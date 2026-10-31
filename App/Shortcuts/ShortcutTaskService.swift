import Foundation
import PaperclipKit

/// A background invocation must restore its own session; it cannot depend on a visible scene.
struct ShortcutSession: Equatable {
    let server: URL
    let companyID: String
    let token: String?
    let allowInsecureHTTP: Bool

    static func load(defaults: UserDefaults = .standard,
                     token: (String) throws -> String? = Keychain.token(for:)) throws -> Self {
        guard defaults.object(forKey: "paperclip.connected") as? Bool != false,
              let raw = defaults.string(forKey: "paperclip.serverURL"),
              let server = URL(string: raw), ["http", "https"].contains(server.scheme?.lowercased() ?? ""),
              server.host != nil,
              let company = defaults.string(forKey: "paperclip.companyId"), !company.isEmpty else {
            throw ShortcutTaskError.notConnected
        }
        let allowHTTP = AppModel.allowsInsecureHTTP(for: server, defaults: defaults)
        try TransportSecurityPolicy.validate(server, allowInsecureHTTP: allowHTTP)
        return Self(server: server, companyID: company, token: try token(raw), allowInsecureHTTP: allowHTTP)
    }
}

enum ShortcutTaskError: LocalizedError {
    case notConnected, companyUnavailable, emptyText, invalidDraft, sessionChanged, submissionUncertain

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return AppL10n.text("shortcut.not_connected", "Open Clipswain once to connect and select a company, then try again.")
        case .companyUnavailable:
            return AppL10n.text("shortcut.company_unavailable", "The selected company is unavailable. Open Clipswain and select a company again.")
        case .emptyText:
            return AppL10n.text("shortcut.empty_text", "Please describe the task.")
        case .invalidDraft:
            return AppL10n.text("shortcut.invalid_draft", "The task draft is invalid. No task was published.")
        case .sessionChanged:
            return AppL10n.text("shortcut.session_changed", "Your Clipswain connection or company changed. No task was published. Please try again.")
        case .submissionUncertain:
            return AppL10n.text("shortcut.submission_uncertain", "Clipswain could not confirm publication. Check your task list before retrying to avoid creating a duplicate.")
        }
    }
}

/// Shares the existing API and AI drafter without opening the app or changing saved preferences.
@MainActor
struct ShortcutTaskService {
    typealias Draft = (String, TaskDraftContext) async throws -> TaskDraft
    let client: PaperclipClient
    let companyID: String
    var draft: Draft?
    var isCurrentSession: () -> Bool = { true }

    func publish(_ input: String) async throws -> Issue {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ShortcutTaskError.emptyText }
        let companies = try await client.companies()
        // Never silently fall back to another company if the saved company is gone.
        guard let company = companies.first(where: { $0.id == companyID }) else {
            throw ShortcutTaskError.companyUnavailable
        }
        let issue: NewIssue
        if let draft {
            let agents = try await client.agents(companyId: companyID).filter { $0.status != .terminated }
            let context = TaskDraftContext(agents: agents.map {
                .init(id: $0.id, name: $0.name, role: $0.roleLabel, title: $0.title, capabilities: $0.capabilities)
            }, companyName: company.name)
            let result = try await draft(text, context)
            let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty,
                  result.assigneeAgentId.map({ id in agents.contains { $0.id == id } }) ?? true else {
                throw ShortcutTaskError.invalidDraft
            }
            let original = AppL10n.text("shortcut.original_request", "Original request")
            let description = [result.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                               "### \(original)\n\(text)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            issue = NewIssue(title: title, description: description, priority: result.priority ?? .medium,
                             assigneeAgentId: result.assigneeAgentId)
        } else {
            issue = NewIssue(title: String(text.prefix(100)), description: text)
        }
        try Task.checkCancellation()
        guard isCurrentSession() else { throw ShortcutTaskError.sessionChanged }
        do {
            // POST is deliberately never retried: a lost response can still mean a created task.
            return try await client.createIssue(companyId: companyID, issue)
        } catch let error as PaperclipAPIError where error.status >= 400 && error.status < 500 {
            throw error
        } catch {
            throw ShortcutTaskError.submissionUncertain
        }
    }

    static func live(useAI: Bool) throws -> Self {
        let saved = try ShortcutSession.load()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        let client = PaperclipClient(serverURL: saved.server, token: saved.token,
                                    allowInsecureHTTP: saved.allowInsecureHTTP, session: session)
        var draft: Draft?
        if useAI {
            // Fresh settings also retry a previously unavailable Keychain after first unlock.
            let settings = AssistantSettings()
            if let error = settings.credentialError {
                throw PaperclipAPIError(status: 0, message: error)
            }
            if settings.isConfigured {
                let drafter = TaskDrafter(config: settings.config, apiKey: settings.apiKey, session: session)
                draft = { text, context in try await drafter.draft(from: text, context: context) }
            }
        }
        return Self(client: client, companyID: saved.companyID, draft: draft,
                    isCurrentSession: { (try? ShortcutSession.load()) == saved })
    }
}
