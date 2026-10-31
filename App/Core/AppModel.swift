import Foundation
import Observation
import PaperclipKit

/// App-wide session: which server, which credential, which company, plus shared lookups
/// (agents by id) that every screen needs to render names and avatars.
@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let server = "paperclip.serverURL"
        static let company = "paperclip.companyId"
        /// The saved server is only a prefill; this says whether a session is active.
        static let connected = "paperclip.connected"
    }

    private(set) var client: PaperclipClient?
    private(set) var health: ServerHealth?
    private(set) var identity: BoardIdentity?
    private(set) var companies: [Company] = []
    private(set) var agents: [Agent] = []
    private(set) var inbox: InboxStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyStore: any BoardKeyStoring
    private let inboxDirectory: URL?
    private var agentsLoadID = UUID()
    var selectedCompanyId: String? {
        didSet { defaults.set(selectedCompanyId, forKey: Keys.company) }
    }

    enum PendingRoute: Equatable {
        case issue(String)
        case approval(String)
        case agent(String)
        case run(String)
    }

    /// Set when a notification is tapped; the inbox pushes it and clears it.
    var pendingRoute: PendingRoute?
    var pendingNotification: NotificationDestination?

    init(inboxDirectory: URL? = nil, defaults: UserDefaults = .standard,
         keyStore: any BoardKeyStoring = KeychainBoardKeyStore()) {
        self.inboxDirectory = inboxDirectory
        self.defaults = defaults
        self.keyStore = keyStore
    }

    func openPendingNotification() async {
        guard !isRestoring, client != nil, let destination = pendingNotification else { return }
        pendingNotification = nil
        await openNotification(destination)
    }

    /// Resolve the originating archive before publishing a route; the view never guesses it.
    @discardableResult
    func openNotification(_ destination: NotificationDestination) async -> Bool {
        guard let client,
              destination.issueId != nil || destination.approvalId != nil || destination.agentId != nil || destination.runId != nil,
              destination.eventId == nil || destination.issueId != nil else { return false }
        let accountID = InboxStore.accountID(client: client, identity: identity)
        let companyId: String
        if let scope = destination.scope {
            guard scope.serverURL == client.serverURL, scope.accountID == accountID else { return false }
            companyId = scope.companyId
        } else {
            // Build 12 and older notifications have no scope. Resolve it through the server,
            // and verify an event id before writing a read flag into any archive.
            do {
                if let issueId = destination.issueId {
                    let issue = try await client.issue(id: issueId)
                    companyId = issue.companyId
                    if let eventId = destination.eventId {
                        let activities = try await client.issueActivity(issueId: issueId)
                        guard activities.contains(where: { $0.id == eventId }) else { return false }
                    }
                } else if let approvalId = destination.approvalId {
                    companyId = try await client.approval(id: approvalId).companyId
                } else { return false }
            } catch { return false }
        }
        guard self.client === client, companies.contains(where: { $0.id == companyId }) else { return false }
        if selectedCompanyId != companyId { await selectCompany(companyId) }
        guard self.client === client, selectedCompanyId == companyId,
              InboxStore.accountID(client: client, identity: identity) == accountID else { return false }
        if let eventId = destination.eventId { inbox?.setRead(true, ids: [eventId]) }
        if let id = destination.approvalId { pendingRoute = .approval(id) }
        else if let id = destination.issueId { pendingRoute = .issue(id) }
        else if let id = destination.agentId { pendingRoute = .agent(id) }
        else if let id = destination.runId { pendingRoute = .run(id) }
        else { return false }
        return true
    }

    /// Handles `clipswain://issue/<id>` and `clipswain://approval/<id>`.
    func open(_ url: URL) {
        guard url.scheme == "clipswain", let id = url.pathComponents.dropFirst().first else { return }
        switch url.host {
        case "issue", "task": pendingRoute = .issue(id)
        case "approval": pendingRoute = .approval(id)
        default: break
        }
    }

    /// Current actionable items, separate from the unread event count used by the tab badge.
    var attentionCount = 0

    /// Bumped after a mutation so list screens know to refetch.
    private(set) var revision = 0
    var lastError: String?
    private(set) var isRestoring = true
    private(set) var isSigningOut = false

    var isConnected: Bool { client != nil }
    var company: Company? { companies.first { $0.id == selectedCompanyId } }

    func agent(_ id: String?) -> Agent? {
        guard let id else { return nil }
        return agents.first { $0.id == id }
    }

    var activeAgents: [Agent] {
        agents.filter { $0.status != .terminated }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - Connection

    func restore(session: URLSession = .shared) async {
        defer { isRestoring = false }
        guard defaults.object(forKey: Keys.connected) as? Bool != false,
              let raw = defaults.string(forKey: Keys.server), let url = URL(string: raw) else { return }
        do {
            let token = try keyStore.read(account: raw)
            try await connect(serverURL: url, token: token,
                              allowInsecureHTTP: Self.allowsInsecureHTTP(for: url, defaults: defaults),
                              persist: false, session: session)
        } catch {
            // Keep the saved server so the connect screen can prefill it.
            lastError = error.localizedDescription
        }
    }

    nonisolated static var savedServerURL: String? { UserDefaults.standard.string(forKey: "paperclip.serverURL") }

    /// HTTP consent belongs to an origin, never to a host on another port or to another server.
    nonisolated static func allowsInsecureHTTP(for url: URL, defaults: UserDefaults = .standard) -> Bool {
        guard let key = insecureHTTPConsentKey(for: url) else { return false }
        return defaults.bool(forKey: key)
    }

    private nonisolated static func insecureHTTPConsentKey(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "http",
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        return "paperclip.insecureHTTP.\(host):\(components.port ?? 80)"
    }

    /// Validates the credential by loading the identity and companies before committing.
    func connect(serverURL: URL, token: String?, allowInsecureHTTP: Bool = false,
                 persist: Bool = true, session: URLSession = .shared) async throws {
        let candidate = PaperclipClient(serverURL: serverURL, token: token,
                                        allowInsecureHTTP: allowInsecureHTTP, session: session)
        let health = try await candidate.health()
        if token == nil && !health.isLocalTrusted {
            throw PaperclipAPIError(status: 401, message: AppL10n.text("connection.sign_in_required", "This server requires sign-in. Approve access in your browser or paste an API key."))
        }
        let identity = try? await candidate.me()
        let companies = try await candidate.companies()
        let origin = candidate.serverURL.absoluteString
        if persist {
            // A successful server response does not mean a persistent session exists. Commit
            // preferences and HTTP consent only after the credential write has succeeded.
            try keyStore.write(candidate.token, account: origin)
            defaults.set(origin, forKey: Keys.server)
            defaults.set(true, forKey: Keys.connected)
            if let key = Self.insecureHTTPConsentKey(for: candidate.serverURL) {
                defaults.set(allowInsecureHTTP, forKey: key)
            }
        }
        self.client = candidate
        self.health = health
        self.identity = identity
        self.companies = companies
        let saved = defaults.string(forKey: Keys.company)
        selectedCompanyId = companies.first { $0.id == saved }?.id ?? companies.first?.id
        configureInbox()
        lastError = nil
        await reloadAgents()
        await openPendingNotification()
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        let signingOutClient = client
        var revocationFailed = false
        if let signingOutClient, signingOutClient.token != nil {
            do { try await signingOutClient.revokeCurrentKey() }
            catch { revocationFailed = true }
        }
        // A connection that changed while revocation was pending belongs to a new session.
        guard client === signingOutClient else { return }
        if let origin = signingOutClient?.serverURL.absoluteString {
            do { try keyStore.write(nil, account: origin) }
            catch {
                lastError = AppL10n.text("connection.key_removal_failed", "The saved key could not be removed. Connection settings were kept. Unlock your device and try disconnecting again; server revocation may already have completed.")
                return
            }
        }
        // Keep the address for prefill, but end the session so neither the next launch nor
        // background refresh reconnects on its own.
        defaults.set(false, forKey: Keys.connected)
        AttentionNotifier.isEnabled = false
        attentionCount = 0
        client = nil
        health = nil
        identity = nil
        companies = []
        agents = []
        inbox = nil
        pendingNotification = nil
        pendingRoute = nil
        lastError = revocationFailed
            ? AppL10n.text("connection.revoke_failed", "Disconnected on this device, but server key revocation could not be confirmed. The key may still be active. Open the server in your browser and revoke this device’s Board API key.")
            : nil
    }

    nonisolated static var hasActiveSession: Bool {
        // Sessions saved before this flag existed count as active.
        UserDefaults.standard.object(forKey: "paperclip.connected") as? Bool ?? true
    }

    // MARK: - Shared data

    func selectCompany(_ id: String) async {
        selectedCompanyId = id
        agents = []
        configureInbox()
        await reloadAgents()
        revision += 1
    }

    /// When a link opens a task from another company the user can access, switch to that
    /// company and re-open the task there, so agents, assignees and new subtasks all match it.
    /// Returns true when it switched.
    func alignCompany(with issue: Issue) async -> Bool {
        guard issue.companyId != selectedCompanyId,
              companies.contains(where: { $0.id == issue.companyId }) else { return false }
        pendingRoute = .issue(issue.id)
        await selectCompany(issue.companyId)
        return true
    }

    private func configureInbox() {
        guard let client, let companyId = selectedCompanyId else { inbox = nil; return }
        let accountID = InboxStore.accountID(client: client, identity: identity)
        if let inboxDirectory {
            inbox = InboxStore(serverURL: client.serverURL, accountID: accountID, companyId: companyId, directory: inboxDirectory)
        } else {
            inbox = InboxStore.open(serverURL: client.serverURL, accountID: accountID, companyId: companyId)
        }
    }

    func reloadCompanies() async {
        guard let client else { return }
        guard let companies = try? await client.companies() else { return }
        self.companies = companies
        // The selection may be empty (first connect had no company) or point at a company that
        // is gone; fall back to the first one so the app can leave the empty state.
        if company == nil, let first = companies.first {
            await selectCompany(first.id)
        }
    }

    func reloadAgents() async {
        guard let client, let companyId = selectedCompanyId else { return }
        let loadID = UUID()
        agentsLoadID = loadID
        do {
            let loaded = try await client.agents(companyId: companyId)
            // Drop the result if the user switched company or signed out meanwhile.
            // A newer detail read or mutation also takes precedence over this request.
            guard self.client === client, selectedCompanyId == companyId, agentsLoadID == loadID else { return }
            agents = loaded.map { agent in
                var merged = agent
                merged.chainOfCommand = merged.chainOfCommand ?? self.agent(agent.id)?.chainOfCommand
                return merged
            }
        } catch {
            guard self.client === client, selectedCompanyId == companyId, agentsLoadID == loadID else { return }
            lastError = error.localizedDescription
        }
    }

    /// Detail reads and list reads publish to the same observable cache.
    @discardableResult
    func reloadAgent(_ id: String) async throws -> Agent? {
        guard let client, let companyId = selectedCompanyId else { return nil }
        let loaded = try await client.agent(id: id)
        guard self.client === client, selectedCompanyId == companyId, loaded.companyId == companyId else { return nil }
        upsert(loaded)
        return agent(id)
    }

    /// Replaces one agent after a detail read or mutation returned its new state.
    func upsert(_ agent: Agent) {
        guard agent.companyId == selectedCompanyId else { return }
        agentsLoadID = UUID()
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            var merged = agent
            merged.chainOfCommand = merged.chainOfCommand ?? agents[index].chainOfCommand
            agents[index] = merged
        } else {
            agents.append(agent)
        }
    }

    func didMutate() { revision += 1 }
}
