import CryptoKit
import Foundation

// MARK: - Configuration

/// Which wire protocol the configured LLM provider speaks.
public enum LLMProviderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case openCodeGo = "opencode_go"
    case openRouter = "openrouter"
    /// Anthropic Messages API (`POST /v1/messages`).
    case anthropic
    /// Any provider exposing OpenAI-style `POST /chat/completions`.
    case openAICompatible = "openai_compatible"

    public var defaultBaseURL: String {
        switch self {
        case .openCodeGo: return "https://opencode.ai/inference/go"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .openAICompatible: return "https://api.openai.com/v1"
        }
    }

    /// Model filled in when the user picks this provider; empty means the user must type one.
    public var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-5-5"
        case .openAICompatible, .openCodeGo, .openRouter: return ""
        }
    }

    public var isIntegration: Bool { self == .openCodeGo || self == .openRouter }

    public var modelsEndpoint: URL? {
        switch self {
        case .openCodeGo: return URL(string: defaultBaseURL + "/v1/models")
        case .openRouter: return URL(string: defaultBaseURL + "/models")
        default: return nil
        }
    }
}

enum LLMWireProtocol { case anthropic, chatCompletions, responses, google }

/// The LLM endpoint used to turn a sentence into a task. The API key is stored separately
/// (Keychain) and passed to `TaskDrafter` directly.
public struct LLMProviderConfig: Codable, Hashable, Sendable {
    public var kind: LLMProviderKind
    public var baseURL: String
    public var model: String
    public var supportsStructuredOutputs: Bool?
    public var allowInsecureHTTP: Bool

    public init(kind: LLMProviderKind = .anthropic, baseURL: String? = nil, model: String? = nil,
                allowInsecureHTTP: Bool = false) {
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.model = model ?? kind.defaultModel
        self.allowInsecureHTTP = allowInsecureHTTP
    }

    private enum CodingKeys: String, CodingKey {
        case kind, baseURL, model, supportsStructuredOutputs, allowInsecureHTTP
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(LLMProviderKind.self, forKey: .kind)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        supportsStructuredOutputs = try values.decodeIfPresent(Bool.self, forKey: .supportsStructuredOutputs)
        allowInsecureHTTP = try values.decodeIfPresent(Bool.self, forKey: .allowInsecureHTTP) ?? false
    }

    /// The endpoint URL, tolerating a trailing slash or a base that already ends in the path.
    public var endpoint: URL? {
        if kind == .openRouter { return URL(string: kind.defaultBaseURL + "/chat/completions") }
        if kind == .openCodeGo {
            let root = kind.defaultBaseURL
            switch wireProtocol {
            case .anthropic: return URL(string: root + "/anthropic/v1/messages")
            case .chatCompletions: return URL(string: root + "/openai/v1/chat/completions")
            case .responses: return URL(string: root + "/openai/v1/responses")
            case .google:
                guard let id = model.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) else { return nil }
                return URL(string: root + "/google/v1beta/models/" + id + ":generateContent")
            }
        }
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        switch kind {
        case .anthropic:
            if base.hasSuffix("/v1/messages") { return URL(string: base) }
            return URL(string: base.hasSuffix("/v1") ? base + "/messages" : base + "/v1/messages")
        case .openAICompatible:
            if base.hasSuffix("/chat/completions") { return URL(string: base) }
            return URL(string: base + "/chat/completions")
        case .openCodeGo, .openRouter: return nil
        }
    }

    var wireProtocol: LLMWireProtocol {
        if kind == .anthropic { return .anthropic }
        guard kind == .openCodeGo else { return .chatCompletions }
        let id = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("gemini-") { return .google }
        if id.hasPrefix("gpt-"), !id.hasPrefix("gpt-oss") { return .responses }
        if id.hasPrefix("grok-"), !id.hasPrefix("grok-code") { return .responses }
        if id.hasPrefix("muse-") { return .responses }
        if id.hasPrefix("claude-") || id.hasPrefix("qwen") ||
            (id.hasPrefix("minimax-") && !id.hasPrefix("minimax-m3.1")) { return .anthropic }
        return .chatCompletions
    }

    /// Custom endpoints keep separate credentials for each origin. Presets never send a key
    /// to a user-edited base URL.
    public var credentialAccount: String {
        if kind.isIntegration { return kind.rawValue }
        // The key and HTTP consent must follow the same normalized destination as the
        // request. Parsing raw baseURL here would group leading-whitespace URLs together.
        guard let url = endpoint,
              (try? TransportSecurityPolicy.validate(url, allowInsecureHTTP: true)) != nil,
              let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            // Never reuse the old shared invalid-address key slot. Hash invalid input so
            // another invalid address cannot inherit its key, without storing URL passwords.
            let fingerprint = SHA256.hash(data: Data(baseURL.utf8)).map { String(format: "%02x", $0) }.joined()
            return kind.rawValue + ":invalid:" + fingerprint
        }
        let origin = "\(scheme)://\(host):\(url.port ?? (scheme == "http" ? 80 : 443))"
        return kind.rawValue + ":" + origin
    }
}

// MARK: - Input / output

/// What the model may pick from, plus the facts it needs to resolve relative wording.
public struct TaskDraftContext: Sendable {
    public struct AgentChoice: Hashable, Sendable {
        public var id: String
        public var name: String
        public var role: String?
        public var title: String?
        public var capabilities: String?

        public init(id: String, name: String, role: String? = nil, title: String? = nil, capabilities: String? = nil) {
            self.id = id
            self.name = name
            self.role = role
            self.title = title
            self.capabilities = capabilities
        }
    }

    public var agents: [AgentChoice]
    public var companyName: String?
    public var parentTitle: String?
    public var now: Date
    public var timeZone: TimeZone

    public init(
        agents: [AgentChoice], companyName: String? = nil, parentTitle: String? = nil,
        now: Date = .now, timeZone: TimeZone = .current
    ) {
        self.agents = agents
        self.companyName = companyName
        self.parentTitle = parentTitle
        self.now = now
        self.timeZone = timeZone
    }
}

/// Fields extracted from the user's sentence. `nil` means "the request did not say".
public struct TaskDraft: Hashable, Sendable {
    public var title: String
    public var description: String?
    public var assigneeAgentId: String?
    public var priority: IssuePriority?

    public init(title: String, description: String? = nil, assigneeAgentId: String? = nil, priority: IssuePriority? = nil) {
        self.title = title
        self.description = description
        self.assigneeAgentId = assigneeAgentId
        self.priority = priority
    }
}

public enum TaskDraftError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case http(status: Int, message: String)
    case refused
    case truncated
    case unreadable

    public var errorDescription: String? { localizedDescription(locale: nil) }

    public func localizedDescription(locale: Locale?) -> String {
        switch self {
        case .notConfigured: return KitL10n.string("draft.error.not_configured", defaultValue: "No AI model is configured. Add an API provider in Settings.", locale: locale)
        case .http(let status, let message):
            switch status {
            case 401, 403: return KitL10n.string("draft.error.unauthorized", defaultValue: "Invalid API key or permission denied (\(status)): \(message)", locale: locale)
            case 404: return KitL10n.string("draft.error.not_found", defaultValue: "Endpoint or model not found (404). Check the URL and model name: \(message)", locale: locale)
            case 429: return KitL10n.string("draft.error.rate_limited", defaultValue: "Rate limit or usage limit reached (429): \(message)", locale: locale)
            default: return KitL10n.string("draft.error.http", defaultValue: "Model request failed (\(status)): \(message)", locale: locale)
            }
        case .refused: return KitL10n.string("draft.error.refused", defaultValue: "The model declined this request. Try rephrasing it.", locale: locale)
        case .truncated: return KitL10n.string("draft.error.truncated", defaultValue: "The model response was cut off. Try a shorter description.", locale: locale)
        case .unreadable: return KitL10n.string("draft.error.unreadable", defaultValue: "Could not extract a task from the model response. Try again.", locale: locale)
        }
    }
}

// MARK: - Drafter

/// Turns one natural-language request into a `TaskDraft` with a single LLM call that is
/// constrained to a JSON schema.
public struct TaskDrafter: Sendable {
    public var config: LLMProviderConfig
    public var apiKey: String
    private let session: URLSession
    public let sessionID: String

    public init(config: LLMProviderConfig, apiKey: String, session: URLSession = .shared, sessionID: String = UUID().uuidString) {
        self.config = config
        self.apiKey = apiKey
        self.session = session
        self.sessionID = sessionID
    }

    public func draft(from text: String, context: TaskDraftContext) async throws -> TaskDraft {
        let request = try makeRequest(text: text, context: context)
        let (data, response) = try await session.data(for: request, delegate: RedirectBlockingDelegate())
        guard let http = response as? HTTPURLResponse else { throw TaskDraftError.unreadable }
        guard (200..<300).contains(http.statusCode) else {
            throw TaskDraftError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.parse(data, wireProtocol: config.wireProtocol, context: context)
    }

    // MARK: Request

    func makeRequest(text: String, context: TaskDraftContext) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = config.endpoint, !key.isEmpty, !model.isEmpty else { throw TaskDraftError.notConfigured }
        try TransportSecurityPolicy.validate(url, allowInsecureHTTP: config.allowInsecureHTTP)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.addIntegrationHeaders(to: &request, kind: config.kind, sessionID: sessionID)
        if config.kind == .openCodeGo { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

        let schema = Self.schema(for: context)
        let userMessage = Self.userMessage(text: text, context: context)
        let instructions = Self.systemPrompt + "\nReturn only one JSON object matching this schema:\n" + schema.prettyPrinted
        let body: JSONValue
        switch config.wireProtocol {
        case .anthropic:
            if config.kind != .openCodeGo { request.setValue(key, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var fields: [String: JSONValue] = [
                "model": .string(model),
                "max_tokens": .number(4096),
                "system": .string(config.kind.isIntegration ? instructions : Self.systemPrompt),
                "messages": .array([.object(["role": .string("user"), "content": .string(userMessage)])]),
                "output_config": .object([
                    // Extraction is simple; low effort keeps the sheet responsive.
                    "effort": .string("low"),
                    "format": .object(["type": .string("json_schema"), "schema": schema]),
                ]),
            ]
            // Go's Anthropic-compatible models do not all support output_config.
            if config.kind.isIntegration { fields.removeValue(forKey: "output_config") }
            // Server-side fallback on a safety decline; only Anthropic's own API accepts it,
            // a proxy or gateway in front of it may reject the parameter.
            if url.host == "api.anthropic.com" {
                request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                fields["fallbacks"] = .string("default")
            }
            body = .object(fields)
        case .chatCompletions:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var fields: [String: JSONValue] = [
                "model": .string(model),
                "messages": .array([
                    .object(["role": .string("system"), "content": .string(instructions)]),
                    .object(["role": .string("user"), "content": .string(userMessage)]),
                ]),
                "response_format": .object([
                    "type": .string("json_schema"),
                    "json_schema": .object([
                        "name": .string("task_draft"),
                        "strict": .bool(true),
                        "schema": schema,
                    ]),
                ]),
            ]
            if config.kind.isIntegration && config.supportsStructuredOutputs != true {
                fields.removeValue(forKey: "response_format")
            }
            // OpenRouter includes small-context models. Let it choose a compatible limit
            // rather than imposing 8192 on a model whose entire context may be smaller.
            if config.kind == .openCodeGo { fields["max_tokens"] = .number(8192) }
            body = .object(fields)
        case .responses:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = .object([
                "model": .string(model), "instructions": .string(instructions),
                "input": .string(userMessage), "store": .bool(false),
                "max_output_tokens": .number(8192),
            ])
        case .google:
            body = .object([
                "systemInstruction": .object(["parts": .array([.object(["text": .string(instructions)])])]),
                "contents": .array([.object(["role": .string("user"), "parts": .array([.object(["text": .string(userMessage)])])])]),
                "generationConfig": .object(["maxOutputTokens": .number(8192)]),
            ])
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Follows the host app's MARKETING_VERSION instead of a hard-coded release number.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Clipswain/\($0)" } ?? "Clipswain"
    }()

    static func addIntegrationHeaders(to request: inout URLRequest, kind: LLMProviderKind, sessionID: String) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if kind == .openCodeGo {
            request.setValue(sessionID, forHTTPHeaderField: "x-opencode-session")
        }
        if kind == .openRouter {
            request.setValue("Clipswain", forHTTPHeaderField: "X-Title")
        }
    }

    static let systemPrompt = """
        You turn a short request from the board of a company run by AI agents into one task for \
        its tracker. Fill every field of the JSON schema:
        - title: a short, specific, imperative title (at most about 60 characters), written in the \
        same language as the request.
        - description: Markdown with the details the request gives — context, scope, deadlines, \
        acceptance criteria — in the request's language. Resolve relative dates such as "tomorrow" \
        or "下周一" to absolute dates using today's date. Do not invent requirements the request \
        does not state or clearly imply. Use null when there is nothing beyond the title.
        - assigneeAgentId: the id of the agent the request names or clearly points to by name, \
        role or title. Use null when no agent is named or implied; never guess.
        - priority: "critical", "high", "medium" or "low" only when the request signals urgency or \
        importance (for example 紧急, ASAP, 尽快, 不急, 有空再做). Use null otherwise.
        """

    static func userMessage(text: String, context: TaskDraftContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "yyyy-MM-dd EEEE"

        let agents = context.agents.map { agent -> JSONValue in
            var fields: [String: JSONValue] = ["id": .string(agent.id), "name": .string(agent.name)]
            if let role = agent.role, !role.isEmpty { fields["role"] = .string(role) }
            if let title = agent.title, !title.isEmpty { fields["title"] = .string(title) }
            if let capabilities = agent.capabilities, !capabilities.isEmpty {
                fields["capabilities"] = .string(String(capabilities.prefix(240)))
            }
            return .object(fields)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let agentsJSON = (try? encoder.encode(JSONValue.array(agents))).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        var lines = ["Today: \(formatter.string(from: context.now)) (\(context.timeZone.identifier))"]
        if let company = context.companyName { lines.append("Company: \(company)") }
        if let parent = context.parentTitle { lines.append("This task is a subtask of: \(parent)") }
        lines.append("Agents: \(agentsJSON)")
        lines.append("")
        lines.append("<request>\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))\n</request>")
        return lines.joined(separator: "\n")
    }

    /// Every field is required and nullable, so the model must state "not given" explicitly.
    /// The assignee is limited to the company's agent ids.
    static func schema(for context: TaskDraftContext) -> JSONValue {
        let ids = context.agents.map { JSONValue.string($0.id) }
        let assignee: JSONValue = ids.isEmpty
            ? .object(["type": .string("null")])
            : .object(["anyOf": .array([
                .object(["type": .string("string"), "enum": .array(ids)]),
                .object(["type": .string("null")]),
            ])])
        let priorities = IssuePriority.selectable.map { JSONValue.string($0.rawValue) }
        return .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "description": .object(["anyOf": .array([
                    .object(["type": .string("string")]),
                    .object(["type": .string("null")]),
                ])]),
                "assigneeAgentId": assignee,
                "priority": .object(["anyOf": .array([
                    .object(["type": .string("string"), "enum": .array(priorities)]),
                    .object(["type": .string("null")]),
                ])]),
            ]),
            "required": .array(["title", "description", "assigneeAgentId", "priority"].map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }

    // MARK: Response

    static func parse(_ data: Data, kind: LLMProviderKind, context: TaskDraftContext) throws -> TaskDraft {
        try parse(data, wireProtocol: kind == .anthropic ? .anthropic : .chatCompletions, context: context)
    }

    static func parse(_ data: Data, wireProtocol: LLMWireProtocol, context: TaskDraftContext) throws -> TaskDraft {
        guard let response = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw TaskDraftError.unreadable }
        let text: String?
        switch wireProtocol {
        case .anthropic:
            switch response["stop_reason"]?.stringValue {
            case "refusal": throw TaskDraftError.refused
            case "max_tokens": throw TaskDraftError.truncated
            default: break
            }
            // Thinking blocks come first; the JSON is in the text block.
            text = response["content"]?.arrayValue?
                .first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue
        case .chatCompletions:
            let choice = response["choices"]?.arrayValue?.first
            if choice?["finish_reason"]?.stringValue == "length" { throw TaskDraftError.truncated }
            if let refusal = choice?["message"]?["refusal"]?.stringValue, !refusal.isEmpty { throw TaskDraftError.refused }
            text = choice?["message"]?["content"]?.stringValue
        case .responses:
            if response["status"]?.stringValue == "incomplete" { throw TaskDraftError.truncated }
            let blocks = response["output"]?.arrayValue?.flatMap { $0["content"]?.arrayValue ?? [] } ?? []
            if blocks.contains(where: { $0["type"]?.stringValue == "refusal" }) { throw TaskDraftError.refused }
            text = blocks.filter { $0["type"]?.stringValue == "output_text" }.compactMap { $0["text"]?.stringValue }.joined()
        case .google:
            let candidate = response["candidates"]?.arrayValue?.first
            if candidate?["finishReason"]?.stringValue == "MAX_TOKENS" { throw TaskDraftError.truncated }
            if response["promptFeedback"]?["blockReason"] != nil || ["SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT"].contains(candidate?["finishReason"]?.stringValue ?? "") {
                throw TaskDraftError.refused
            }
            text = candidate?["content"]?["parts"]?.arrayValue?.filter { $0["thought"] != .bool(true) }.compactMap { $0["text"]?.stringValue }.joined()
        }
        guard let text, let draft = draft(fromJSONText: text, context: context) else { throw TaskDraftError.unreadable }
        return draft
    }

    /// Reads the model's JSON, tolerating a ```json fence or prose around the object, and drops
    /// values outside what the form accepts.
    static func draft(fromJSONText text: String, context: TaskDraftContext) -> TaskDraft? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end {
            body = String(body[start...end])
        }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)),
              let title = json["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }

        let description = json["description"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignee = json["assigneeAgentId"]?.stringValue
        let validIds = Set(context.agents.map(\.id))
        let priority = json["priority"]?.stringValue.flatMap(IssuePriority.init(rawValue:))
        return TaskDraft(
            title: title,
            description: description?.isEmpty == false ? description : nil,
            assigneeAgentId: assignee.flatMap { validIds.contains($0) ? $0 : nil },
            priority: priority.flatMap { $0 == .unknown ? nil : $0 })
    }

    static func errorMessage(from data: Data) -> String {
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            if let message = json["error"]?["message"]?.stringValue { return message }
            if let message = json["error"]?.stringValue ?? json["message"]?.stringValue { return message }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? KitL10n.string("draft.error.no_details", defaultValue: "No details available") : String(raw.prefix(200))
    }
}
