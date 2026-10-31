import Foundation

public struct PaperclipAPIError: LocalizedError, Hashable, Sendable {
    public var status: Int
    public var message: String
    public var code: String?

    public init(status: Int, message: String, code: String? = nil) {
        self.status = status
        self.message = message
        self.code = code
    }

    public var errorDescription: String? { localizedDescription(locale: nil) }

    public func localizedDescription(locale: Locale?) -> String {
        switch status {
        case 401: return KitL10n.string("api.error.unauthorized", defaultValue: "Sign-in required or credentials expired (401): \(message)", locale: locale)
        case 403: return KitL10n.string("api.error.forbidden", defaultValue: "Permission denied (403): \(message)", locale: locale)
        case 404: return KitL10n.string("api.error.not_found", defaultValue: "Resource not found (404): \(message)", locale: locale)
        case 409: return KitL10n.string("api.error.conflict", defaultValue: "Conflict (409): \(message)", locale: locale)
        case 422: return KitL10n.string("api.error.invalid_state", defaultValue: "Action unavailable in this state (422): \(message)", locale: locale)
        default: return KitL10n.string("api.error.server", defaultValue: "Server error (\(status)): \(message)", locale: locale)
        }
    }

    /// Parses `{"error": "..."}` or `{"error": {"code": ..., "message": ...}}`.
    static func from(status: Int, data: Data) -> PaperclipAPIError {
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            if let text = json["error"]?.stringValue {
                return PaperclipAPIError(status: status, message: text, code: json["code"]?.stringValue)
            }
            if let error = json["error"], let text = error["message"]?.stringValue {
                return PaperclipAPIError(status: status, message: text, code: error["code"]?.stringValue)
            }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self)
        return PaperclipAPIError(status: status, message: text.isEmpty ? KitL10n.string("api.error.empty", defaultValue: "No response content") : text)
    }
}

/// Body for `POST .../interactions/:id/verdicts`; reasons are trimmed and omitted when empty.
struct VerdictsBody: Encodable {
    struct Entry: Encodable {
        var id: String
        var verdict: String
        var reason: String?
    }

    var verdicts: [Entry]

    init(verdicts: [String: ItemVerdict], reasons: [String: String]) {
        self.verdicts = verdicts.sorted { $0.key < $1.key }.map { id, verdict in
            let reason = reasons[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Entry(id: id, verdict: verdict.rawValue, reason: reason?.isEmpty == false ? reason : nil)
        }
    }
}

private struct WrappedList<T: Decodable>: Decodable {
    var items: [T]?
    var data: [T]?
    var issues: [T]?
}

public struct ServerHealth: Codable, Hashable, Sendable {
    public var status: String
    public var version: String?
    public var deploymentMode: String?
    public var deploymentExposure: String?
    public var authReady: Bool?

    /// Local trusted servers accept requests without any credential.
    public var isLocalTrusted: Bool { deploymentMode == "local_trusted" }
}

/// Thin async client for the Paperclip REST API, acting as a board (human) user.
public final class PaperclipClient: Sendable {
    public let serverURL: URL
    public let token: String?
    public let allowInsecureHTTP: Bool
    private let session: URLSession

    /// - Parameters:
    ///   - serverURL: The server origin, e.g. `http://192.168.1.10:3100`. A trailing `/api` is tolerated.
    ///   - token: A board API key; nil for local trusted servers.
    ///   - allowInsecureHTTP: Explicit consent to unencrypted transport for this connection.
    public init(serverURL: URL, token: String?, allowInsecureHTTP: Bool = false, session: URLSession = .shared) {
        self.serverURL = PaperclipClient.normalize(serverURL)
        self.token = token?.isEmpty == true ? nil : token
        self.allowInsecureHTTP = allowInsecureHTTP
        self.session = session
    }

    public static func normalize(_ url: URL) -> URL {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/api") { text.removeLast(4) }
        return URL(string: text) ?? url
    }

    /// Resolves a server-relative path such as an avatar URL.
    public func absoluteURL(_ path: String) -> URL? {
        if let url = URL(string: path), url.scheme != nil { return url }
        return URL(string: serverURL.absoluteString + (path.hasPrefix("/") ? path : "/" + path))
    }

    private func authorizedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Fetches same-origin server content without forwarding credentials through redirects.
    public func data(for url: URL) async throws -> Data {
        var request = authorizedRequest(for: url)
        request.timeoutInterval = 30
        return try await perform(request)
    }

    // MARK: - Transport

    private func makeURL(_ path: String, query: [String: String?]) throws -> URL {
        guard var components = URLComponents(string: serverURL.absoluteString + "/api" + path) else {
            throw PaperclipAPIError(status: 0, message: KitL10n.string("api.error.invalid_url", defaultValue: "Invalid URL: \(path)"))
        }
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        guard let url = components.url else {
            throw PaperclipAPIError(status: 0, message: KitL10n.string("api.error.invalid_url", defaultValue: "Invalid URL: \(path)"))
        }
        return url
    }

    private func send(
        _ method: String, _ path: String, query: [String: String?] = [:], body: Data? = nil
    ) async throws -> Data {
        var request = authorizedRequest(for: try makeURL(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 30
        return try await perform(request)
    }

    private func validateDestination(_ url: URL) throws {
        try TransportSecurityPolicy.validate(url, allowInsecureHTTP: allowInsecureHTTP)
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        guard url.scheme?.lowercased() == serverURL.scheme?.lowercased(),
              url.host?.lowercased() == serverURL.host?.lowercased(), port(url) == port(serverURL) else {
            throw TransportSecurityError.differentOrigin
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        guard let url = request.url else { throw TransportSecurityError.missingHost }
        try validateDestination(url)
        let (data, response) = try await session.data(for: request, delegate: RedirectBlockingDelegate())
        guard let http = response as? HTTPURLResponse else {
            throw PaperclipAPIError(status: 0, message: KitL10n.string("api.error.invalid_response", defaultValue: "Invalid response"))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PaperclipAPIError.from(status: http.statusCode, data: data)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try PaperclipJSON.decoder.decode(T.self, from: data)
        } catch {
            throw PaperclipAPIError(status: 0, message: KitL10n.string("api.error.decoding", defaultValue: "Could not read response: \(Self.describe(error))"))
        }
    }

    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch decoding {
        case .keyNotFound(let key, let context): return KitL10n.string("api.error.missing_field", defaultValue: "Missing field \(path(context)).\(key.stringValue)")
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return KitL10n.string("api.error.field_details", defaultValue: "\(path(context)): \(context.debugDescription)")
        @unknown default: return String(describing: decoding)
        }
    }

    private func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try decode(T.self, from: try await send("GET", path, query: query))
    }

    private func write<T: Decodable, Body: Encodable>(
        _ method: String, _ path: String, _ body: Body
    ) async throws -> T {
        let data = try PaperclipJSON.encoder.encode(body)
        return try decode(T.self, from: try await send(method, path, body: data))
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        try decode(T.self, from: try await send("POST", path, body: Data("{}".utf8)))
    }

    /// Lists decode leniently: a bare array, or an object wrapping `items`/`data`.
    private func list<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> [T] {
        let data = try await send("GET", path, query: query)
        if let array = try? PaperclipJSON.decoder.decode([T].self, from: data) { return array }
        if let wrapped = try? PaperclipJSON.decoder.decode(WrappedList<T>.self, from: data),
           let items = wrapped.items ?? wrapped.data ?? wrapped.issues {
            return items
        }
        return try decode([T].self, from: data)
    }

    // MARK: - Session

    public func health() async throws -> ServerHealth { try await get("/health") }

    public func me() async throws -> BoardIdentity { try await get("/cli-auth/me") }

    /// Starts a browser-approved sign-in. Open `approvalURL` for the user, then poll
    /// `challengeState` until approved; `boardApiToken` becomes usable afterwards.
    public func createSignInChallenge(clientName: String) async throws -> CLIAuthChallenge {
        struct Body: Encodable { var command: String; var clientName: String; var requestedAccess: String }
        return try await write(
            "POST", "/cli-auth/challenges",
            Body(command: "paperclip ios sign-in", clientName: clientName, requestedAccess: "board"))
    }

    public func challengeState(id: String, token: String) async throws -> CLIAuthChallengeState {
        try await get("/cli-auth/challenges/\(id)", query: ["token": token])
    }

    public func approvalURL(for challenge: CLIAuthChallenge) -> URL? {
        if let text = challenge.approvalUrl, let url = URL(string: text) { return url }
        return absoluteURL(challenge.approvalPath)
    }

    /// Revokes the key this client is using (sign out).
    public func revokeCurrentKey() async throws {
        _ = try await send("POST", "/cli-auth/revoke-current", body: Data("{}".utf8))
    }

    // MARK: - Companies

    public func companies() async throws -> [Company] { try await list("/companies") }

    public func dashboard(companyId: String) async throws -> DashboardSummary {
        try await get("/companies/\(companyId)/dashboard")
    }

    /// The whole attention feed, following `nextCursor` up to `maxPages` pages.
    public func attention(companyId: String, pageSize: Int = 100, maxPages: Int = 20) async throws -> AttentionFeed {
        var feed: AttentionFeed = try await get(
            "/companies/\(companyId)/attention", query: ["limit": String(pageSize)])
        var cursor = feed.nextCursor
        var pages = 1
        while let next = cursor, pages < maxPages {
            let page: AttentionFeed = try await get(
                "/companies/\(companyId)/attention", query: ["limit": String(pageSize), "cursor": next])
            feed.items.append(contentsOf: page.items)
            cursor = page.nextCursor
            pages += 1
        }
        feed.nextCursor = cursor
        return feed
    }

    // MARK: - Issues

    /// Every matching issue, fetched page by page with `offset` so large companies are not
    /// silently truncated. Stops after `maxPages` pages as a safety cap.
    public func issues(
        companyId: String, statuses: [IssueStatus]? = nil, assigneeAgentId: String? = nil,
        query text: String? = nil, pageSize: Int = 500, maxPages: Int = 40
    ) async throws -> [Issue] {
        var all: [Issue] = []
        var seen = Set<String>()
        for page in 0..<maxPages {
            let batch: [Issue] = try await list(
                "/companies/\(companyId)/issues",
                query: [
                    "status": statuses.map { $0.map(\.rawValue).joined(separator: ",") },
                    "assigneeAgentId": assigneeAgentId,
                    "q": text,
                    "limit": String(pageSize),
                    "offset": String(page * pageSize),
                ])
            // Rows can shift between pages while agents work; keep the first copy of each.
            all.append(contentsOf: batch.filter { seen.insert($0.id).inserted })
            if batch.count < pageSize { break }
        }
        return all
    }

    public func issue(id: String) async throws -> Issue { try await get("/issues/\(id)") }

    // MARK: - Task results

    private static func pathSegment(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    public func issueDocuments(issueId: String) async throws -> [IssueDocumentSummary] {
        try await list("/issues/\(Self.pathSegment(issueId))/documents")
    }

    public func issueDocument(issueId: String, key: String) async throws -> IssueDocument {
        try await get("/issues/\(Self.pathSegment(issueId))/documents/\(Self.pathSegment(key))")
    }

    public func issueAttachments(issueId: String) async throws -> [IssueAttachment] {
        try await list("/issues/\(Self.pathSegment(issueId))/attachments")
    }

    public func issueWorkProducts(issueId: String) async throws -> [IssueWorkProduct] {
        try await list("/issues/\(Self.pathSegment(issueId))/work-products")
    }

    /// Downloads to disk. The caller owns the returned temporary file and must move/delete it.
    /// Build the content route from the ID, never attach a board token to a supplied asset URL.
    public func downloadIssueAttachment(id: String) async throws -> URL {
        let url = try makeURL("/attachments/\(Self.pathSegment(id))/content", query: [:])
        var request = authorizedRequest(for: url)
        request.timeoutInterval = 120
        try validateDestination(url)
        let (file, response) = try await session.download(for: request, delegate: AttachmentDownloadDelegate())
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let data = (try? Data(contentsOf: file, options: .mappedIfSafe).prefix(4096)) ?? Data()
            try? FileManager.default.removeItem(at: file)
            throw PaperclipAPIError.from(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: Data(data))
        }
        return file
    }

    public func childIssues(companyId: String, parentId: String) async throws -> [Issue] {
        try await list("/companies/\(companyId)/issues", query: ["parentId": parentId])
    }

    public func createIssue(companyId: String, _ issue: NewIssue) async throws -> Issue {
        try await write("POST", "/companies/\(companyId)/issues", issue)
    }

    public func updateIssue(id: String, _ update: IssueUpdate) async throws -> Issue {
        try await write("PATCH", "/issues/\(id)", update)
    }

    public func resolveRecovery(
        issueId: String, actionId: String, _ decision: RecoveryDecision, note: String? = nil
    ) async throws {
        struct Body: Encodable {
            var actionId: String
            var outcome: String
            var sourceIssueStatus: String
            var resolutionNote: String?
        }
        let body = Body(
            actionId: actionId, outcome: decision.outcome,
            sourceIssueStatus: decision.sourceIssueStatus, resolutionNote: note)
        _ = try await send(
            "POST", "/issues/\(issueId)/recovery-actions/resolve", body: try PaperclipJSON.encoder.encode(body))
    }

    public func issueActivity(issueId: String) async throws -> [IssueActivity] {
        try await list("/issues/\(issueId)/activity")
    }

    public func issueRuns(issueId: String) async throws -> [IssueRun] {
        try await list("/issues/\(issueId)/runs")
    }

    public func comments(issueId: String) async throws -> [IssueComment] {
        try await list("/issues/\(issueId)/comments", query: ["order": "asc"])
    }

    public func addComment(issueId: String, _ comment: NewComment) async throws -> IssueComment {
        try await write("POST", "/issues/\(issueId)/comments", comment)
    }

    public func interactions(issueId: String) async throws -> [IssueInteraction] {
        try await list("/issues/\(issueId)/interactions")
    }

    public func resolve(
        issueId: String, interactionId: String, _ resolution: InteractionResolution
    ) async throws -> IssueInteraction {
        let base = "/issues/\(issueId)/interactions/\(interactionId)"
        switch resolution {
        case .accept(let clientKeys, let optionIds):
            struct Body: Encodable { var selectedClientKeys: [String]?; var selectedOptionIds: [String]? }
            return try await write("POST", base + "/accept", Body(selectedClientKeys: clientKeys, selectedOptionIds: optionIds))
        case .reject(let reason):
            struct Body: Encodable { var reason: String? }
            return try await write("POST", base + "/reject", Body(reason: reason))
        case .respond(let answers, let summary):
            struct Body: Encodable { var answers: [QuestionAnswer]; var summaryMarkdown: String? }
            return try await write("POST", base + "/respond", Body(answers: answers, summaryMarkdown: summary))
        case .verdicts(let verdicts, let reasons):
            return try await write("POST", base + "/verdicts", VerdictsBody(verdicts: verdicts, reasons: reasons))
        }
    }

    // MARK: - Approvals

    public func approvals(companyId: String, status: ApprovalStatus? = nil) async throws -> [Approval] {
        try await list("/companies/\(companyId)/approvals", query: ["status": status?.rawValue])
    }

    public func approval(id: String) async throws -> Approval { try await get("/approvals/\(id)") }

    public func approvalComments(id: String) async throws -> [ApprovalComment] {
        try await list("/approvals/\(id)/comments")
    }

    public func addApprovalComment(id: String, body: String) async throws -> ApprovalComment {
        struct Body: Encodable { var body: String }
        return try await write("POST", "/approvals/\(id)/comments", Body(body: body))
    }

    public func decide(approvalId: String, _ decision: ApprovalDecision, note: String?) async throws -> Approval {
        struct Body: Encodable { var decisionNote: String? }
        return try await write("POST", "/approvals/\(approvalId)/\(decision.rawValue)", Body(decisionNote: note))
    }

    // MARK: - Agents

    public func agents(companyId: String) async throws -> [Agent] {
        try await list("/companies/\(companyId)/agents")
    }

    public func agent(id: String) async throws -> Agent { try await get("/agents/\(id)") }

    public func adapters() async throws -> [AdapterInfo] { try await list("/adapters") }

    public func adapterModels(companyId: String, adapterType: String) async throws -> [AdapterModel] {
        try await list("/companies/\(companyId)/adapters/\(adapterType)/models")
    }

    public func createAgent(companyId: String, _ agent: NewAgent) async throws -> Agent {
        try await write("POST", "/companies/\(companyId)/agents", agent)
    }

    /// Permanently deactivates the agent. Irreversible.
    public func terminateAgent(id: String) async throws -> Agent { try await post("/agents/\(id)/terminate") }

    public func updateAgent(id: String, _ update: AgentUpdate) async throws -> Agent {
        try await write("PATCH", "/agents/\(id)", update)
    }

    public func pauseAgent(id: String) async throws -> Agent { try await post("/agents/\(id)/pause") }
    public func resumeAgent(id: String) async throws -> Agent { try await post("/agents/\(id)/resume") }
    public func clearAgentError(id: String) async throws -> Agent { try await post("/agents/\(id)/clear-error") }

    /// Asks the agent to run a heartbeat now.
    public func invokeHeartbeat(agentId: String) async throws -> HeartbeatRun {
        try await post("/agents/\(agentId)/heartbeat/invoke")
    }

    public func runs(companyId: String, agentId: String? = nil, limit: Int = 20) async throws -> [HeartbeatRun] {
        try await list(
            "/companies/\(companyId)/heartbeat-runs",
            query: ["agentId": agentId, "limit": String(limit), "summary": "true"])
    }

    public func run(id: String) async throws -> HeartbeatRun { try await get("/heartbeat-runs/\(id)") }

    public func runEvents(runId: String, afterSeq: Int = 0) async throws -> [HeartbeatRunEvent] {
        try await list("/heartbeat-runs/\(runId)/events", query: ["afterSeq": String(afterSeq), "limit": "500"])
    }

    public func runLog(runId: String, offset: Int = 0) async throws -> HeartbeatRunLog {
        try await get("/heartbeat-runs/\(runId)/log", query: ["offset": String(offset)])
    }

    public func cancelRun(id: String) async throws {
        _ = try await send("POST", "/heartbeat-runs/\(id)/cancel", body: Data("{}".utf8))
    }

    public func orgChart(companyId: String) async throws -> [OrgNode] {
        try await list("/companies/\(companyId)/org")
    }

    public func skills(agentId: String) async throws -> AgentSkillSnapshot {
        try await get("/agents/\(agentId)/skills")
    }

    public func instructionsBundle(agentId: String) async throws -> AgentInstructionsBundle {
        try await get("/agents/\(agentId)/instructions-bundle")
    }

    public func instructionsFile(agentId: String, path: String) async throws -> AgentInstructionsFile {
        try await get("/agents/\(agentId)/instructions-bundle/file", query: ["path": path])
    }

    public func writeInstructionsFile(
        agentId: String, _ write: AgentInstructionsFileWrite
    ) async throws -> AgentInstructionsFile {
        try await self.write("PUT", "/agents/\(agentId)/instructions-bundle/file", write)
    }
}
