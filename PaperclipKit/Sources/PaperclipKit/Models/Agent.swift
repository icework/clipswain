import Foundation

public enum AgentStatus: String, OpenEnum {
    case active, idle, running, paused, error
    case pendingApproval = "pending_approval"
    case terminated
    case unknown

    public static var fallback: AgentStatus { .unknown }

    /// Matches the server's `characterStateForAgent` so avatars use the web UI's poses.
    public var avatarPose: String {
        switch self {
        case .running: return "working"
        case .error: return "confused"
        case .paused, .terminated, .pendingApproval: return "rest"
        default: return "idle"
        }
    }

    public var canPause: Bool { self == .active || self == .idle || self == .running || self == .error }
    public var canResume: Bool { self == .paused }
}

public struct AgentAppearance: Codable, Hashable, Sendable {
    public var schemaVersion: Int?
    public var characterVersion: String?
    public var paletteId: String?
    public var customAvatarAssetId: String?

    public init(paletteId: String, characterVersion: String = "cap-v1") {
        self.schemaVersion = 1
        self.characterVersion = characterVersion
        self.paletteId = paletteId
    }

    public static let paletteIds = [
        "bubblegum-sky", "pink-lemonade", "orchid-peach", "coral-mint", "lime-lagoon",
        "arctic-blue", "solar-flare", "violet-ember", "deep-tide", "coral-current",
        "golden-hour", "tangerine-cobalt", "electric-grove", "flamingo-jade", "cherry-pop",
        "turquoise-cherry", "ultraviolet-tide",
    ]

    /// Mirrors the server's `legacyAgentAppearance`: rolling base-31 hash modulo 17.
    public static func legacy(for agentId: String) -> AgentAppearance {
        var hash = 0
        for unit in agentId.utf16 {
            hash = (hash * 31 + Int(unit)) % paletteIds.count
        }
        return AgentAppearance(paletteId: paletteIds[hash])
    }
}

public struct AgentChainEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: String?
    public var title: String?
}

public struct AgentPermissions: Codable, Hashable, Sendable {
    public var canCreateAgents: Bool?
    public var canCreateSkills: Bool?
    public var trustPreset: String?
}

public struct Agent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var companyId: String
    public var name: String
    public var urlKey: String?
    public var role: String
    public var title: String?
    public var icon: String?
    public var appearance: AgentAppearance?
    public var avatarUrl: String?
    public var status: AgentStatus
    public var reportsTo: String?
    public var capabilities: String?
    public var adapterType: String
    public var adapterConfig: [String: JSONValue]?
    public var runtimeConfig: [String: JSONValue]?
    public var budgetMonthlyCents: Int?
    public var spentMonthlyCents: Int?
    public var pauseReason: String?
    public var pausedAt: Date?
    public var errorReason: String?
    public var lastHeartbeatAt: Date?
    public var permissions: AgentPermissions?
    public var createdAt: Date?
    public var updatedAt: Date?
    /// Present on `GET /api/agents/:id`.
    public var chainOfCommand: [AgentChainEntry]?

    public init(
        id: String, companyId: String, name: String, role: String, status: AgentStatus,
        adapterType: String, title: String? = nil, reportsTo: String? = nil,
        capabilities: String? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.role = role
        self.status = status
        self.adapterType = adapterType
        self.title = title
        self.reportsTo = reportsTo
        self.capabilities = capabilities
    }

    public var resolvedAppearance: AgentAppearance {
        if let appearance, appearance.paletteId != nil { return appearance }
        return .legacy(for: id)
    }

    /// Server-relative path of the avatar image, posed to match the agent's status.
    public func avatarPath(size: Int = 128, scale: Int = 2) -> String {
        let appearance = resolvedAppearance
        if let assetId = appearance.customAvatarAssetId {
            return "/api/assets/\(assetId)/content"
        }
        let version = appearance.characterVersion ?? "cap-v1"
        let palette = status == .terminated ? "muted-dream" : (appearance.paletteId ?? "arctic-blue")
        return "/api/agent-avatars/\(version)/\(palette)/\(status.avatarPose).png?size=\(size)&scale=\(scale)"
    }

    /// The model configured on the adapter, when the adapter exposes one.
    public var modelName: String? {
        adapterConfig?["model"]?.stringValue
    }

    public var roleLabel: String { AgentRole.label(for: role) }
    public var adapterLabel: String { AgentAdapter.label(for: adapterType) }
}

public enum AgentRole {
    public static var labels: [String: String] { [
        "ceo": "CEO", "cto": "CTO", "cmo": "CMO", "cfo": "CFO", "security": KitL10n.string("agent.role.security", defaultValue: "Security"),
        "engineer": KitL10n.string("agent.role.engineer", defaultValue: "Engineer"), "designer": KitL10n.string("agent.role.designer", defaultValue: "Designer"), "pm": "PM", "qa": "QA",
        "devops": "DevOps", "researcher": KitL10n.string("agent.role.researcher", defaultValue: "Researcher"), "general": KitL10n.string("agent.role.general", defaultValue: "General"),
    ] }
    public static let all = [
        "ceo", "cto", "cmo", "cfo", "security", "engineer", "designer", "pm", "qa",
        "devops", "researcher", "general",
    ]

    public static func label(for role: String) -> String {
        labels[role] ?? role.capitalized
    }
}

public enum AgentAdapter {
    public static var labels: [String: String] { [
        "claude_local": "Claude Code", "codex_local": "Codex", "cursor": "Cursor",
        "cursor_cloud": "Cursor Cloud", "gemini_local": "Gemini CLI", "grok_local": "Grok Build",
        "hermes_gateway": "Hermes Gateway", "hermes_local": "Hermes", "kimi_local": "Kimi Code",
        "opencode_local": "OpenCode", "pi_local": "Pi", "openclaw_gateway": "OpenClaw",
        "paperclip_runner": "Paperclip Runner", "process": KitL10n.string("agent.adapter.process", defaultValue: "Process"), "http": "HTTP",
    ] }

    public static func label(for adapterType: String) -> String {
        labels[adapterType] ?? adapterType
    }
}

/// Converts between budget cents and the dollar text the user edits, without dropping cents.
public enum AgentBudget {
    /// 1250 → "12.50", 1200 → "12", nil → "0".
    public static func dollarsText(cents: Int?) -> String {
        let cents = cents ?? 0
        return cents % 100 == 0
            ? String(cents / 100)
            : String(format: "%d.%02d", cents / 100, cents % 100)
    }

    /// "12.5" → 1250, "12" → 1200, "" → 0. Nil for anything that is not a non-negative amount
    /// with at most two decimals.
    public static func cents(fromDollars text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty { return 0 }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = Int(parts[0].isEmpty ? "0" : parts[0]), whole >= 0 else { return nil }
        var fraction = 0
        if parts.count == 2 {
            let digits = parts[1]
            guard digits.count <= 2, digits.allSatisfy(\.isNumber) else { return nil }
            fraction = Int(digits.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        }
        return whole * 100 + fraction
    }
}

/// Fields a board user can change on an agent.
public struct AgentUpdate: Encodable, Sendable {
    public var name: String?
    public var title: String?
    public var role: String?
    public var capabilities: String?
    public var budgetMonthlyCents: Int?
    public var appearance: AgentAppearance?

    public init(
        name: String? = nil, title: String? = nil, role: String? = nil,
        capabilities: String? = nil, budgetMonthlyCents: Int? = nil,
        appearance: AgentAppearance? = nil
    ) {
        self.name = name
        self.title = title
        self.role = role
        self.capabilities = capabilities
        self.budgetMonthlyCents = budgetMonthlyCents
        self.appearance = appearance
    }
}

// MARK: - Instructions

public struct AgentInstructionsFileSummary: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var contentHash: String?
    public var binary: Bool?
    public var size: Int
    public var language: String?
    public var markdown: Bool?
    public var isEntryFile: Bool
    public var editable: Bool
    public var deprecated: Bool?
    public var virtual: Bool?

    public var id: String { path }
}

public struct AgentInstructionRevision: Codable, Hashable, Sendable {
    public var id: String
    public var entryFile: String?
    public var contentHash: String?
    public var byteLength: Int?
    public var source: String?
    public var createdAt: Date?
}

public struct AgentInstructionsFile: Codable, Hashable, Sendable {
    public var path: String
    public var contentHash: String?
    public var size: Int?
    public var language: String?
    public var markdown: Bool?
    public var isEntryFile: Bool?
    public var editable: Bool?
    public var content: String
    public var revision: AgentInstructionRevision?

    public init(path: String, content: String, isEntryFile: Bool? = nil, editable: Bool? = nil) {
        self.path = path
        self.content = content
        self.isEntryFile = isEntryFile
        self.editable = editable
    }

    /// Whether the server will accept a write. The entry file of an external bundle goes
    /// through revision write-back, which the server refuses for external bundles.
    public func isWritable(bundleMode: String?) -> Bool {
        if editable == false { return false }
        if bundleMode == "external" && isEntryFile == true { return false }
        return true
    }
}

public struct AgentInstructionsBundle: Codable, Hashable, Sendable {
    public var agentId: String
    public var mode: String?
    public var rootPath: String?
    public var entryFile: String
    public var editable: Bool
    public var warnings: [String]?
    public var legacyPromptTemplateActive: Bool?
    public var files: [AgentInstructionsFileSummary]

    /// Entry file first, then the rest alphabetically.
    public var orderedFiles: [AgentInstructionsFileSummary] {
        files.sorted { lhs, rhs in
            if lhs.isEntryFile != rhs.isEntryFile { return lhs.isEntryFile }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }
}

/// Body for `PUT /api/agents/:id/instructions-bundle/file`. The server needs the base the
/// edit was made from: `baseRevisionId` for the managed entry file, `baseHash` for other
/// managed files, neither for external bundles.
public struct AgentInstructionsFileWrite: Encodable, Sendable {
    public var path: String
    public var content: String
    public var baseRevisionId: String?
    public var baseHash: String?

    public init(path: String, content: String, baseRevisionId: String? = nil, baseHash: String? = nil) {
        self.path = path
        self.content = content
        self.baseRevisionId = baseRevisionId
        self.baseHash = baseHash
    }

    /// Picks the base fields from the version that was read.
    public static func editing(
        _ file: AgentInstructionsFile, content: String, bundleMode: String?
    ) -> AgentInstructionsFileWrite {
        var write = AgentInstructionsFileWrite(path: file.path, content: content)
        guard bundleMode != "external" else { return write }
        if file.isEntryFile == true || file.revision != nil {
            write.baseRevisionId = file.revision?.id
        } else {
            write.baseHash = file.contentHash
        }
        return write
    }

    enum CodingKeys: String, CodingKey { case path, content, baseRevisionId, baseHash }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(content, forKey: .content)
        // The entry file requires baseRevisionId to be present (null for a brand-new entry).
        if baseRevisionId != nil || baseHash == nil {
            try container.encode(baseRevisionId, forKey: .baseRevisionId)
        }
        try container.encodeIfPresent(baseHash, forKey: .baseHash)
    }
}

// MARK: - Skills

public struct AgentSkillEntry: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var runtimeName: String?
    public var desired: Bool
    public var managed: Bool?
    public var state: String?
    public var origin: String?
    public var originLabel: String?
    public var locationLabel: String?
    public var readOnly: Bool?
    public var detail: String?

    public var id: String { key }
    public var displayName: String { runtimeName ?? key }
}

public struct AgentSkillSnapshot: Codable, Hashable, Sendable {
    public var adapterType: String?
    public var supported: Bool
    public var mode: String?
    public var desiredSkills: [String]?
    public var entries: [AgentSkillEntry]
    public var warnings: [String]?
}

// MARK: - Org chart

public struct OrgNode: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: String?
    public var title: String?
    public var status: AgentStatus?
    public var reports: [OrgNode]

    enum CodingKeys: String, CodingKey { case id, name, role, title, status, reports, children }

    public init(id: String, name: String, role: String?, title: String?, status: AgentStatus?, reports: [OrgNode]) {
        self.id = id
        self.name = name
        self.role = role
        self.title = title
        self.status = status
        self.reports = reports
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decodeIfPresent(AgentStatus.self, forKey: .status)
        reports = try container.decodeIfPresent([OrgNode].self, forKey: .reports)
            ?? container.decodeIfPresent([OrgNode].self, forKey: .children)
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(reports, forKey: .reports)
    }

    /// Builds the tree locally from `reportsTo`, used when the org endpoint is unavailable.
    public static func tree(from agents: [Agent]) -> [OrgNode] {
        let visible = agents.filter { $0.status != .terminated }
        let ids = Set(visible.map(\.id))
        let byManager = Dictionary(grouping: visible) { agent -> String in
            guard let manager = agent.reportsTo, ids.contains(manager) else { return "" }
            return manager
        }
        func build(_ agent: Agent, depth: Int) -> OrgNode {
            let children = depth > 32 ? [] : (byManager[agent.id] ?? []).map { build($0, depth: depth + 1) }
            return OrgNode(
                id: agent.id, name: agent.name, role: agent.role, title: agent.title,
                status: agent.status, reports: children)
        }
        return (byManager[""] ?? []).map { build($0, depth: 0) }
    }
}

// MARK: - Runs

public struct HeartbeatRun: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var agentId: String?
    public var status: String
    public var invocationSource: String?
    public var triggerDetail: String?
    public var error: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var createdAt: Date?
}

public struct HeartbeatRunEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var seq: Int
    public var eventType: String
    public var stream: String?
    public var level: String?
    public var message: String?
    public var createdAt: Date?
}

/// A slice of a run's NDJSON transcript (`GET /heartbeat-runs/:id/log`).
public struct HeartbeatRunLog: Codable, Hashable, Sendable {
    public var content: String
    public var nextOffset: Int?

    public init(content: String, nextOffset: Int? = nil) {
        self.content = content
        self.nextOffset = nextOffset
    }

    public struct Chunk: Hashable, Sendable {
        public var stream: String
        public var text: String
    }

    /// Decodes the NDJSON lines into output chunks, merging consecutive chunks per stream.
    public var chunks: [Chunk] {
        struct Line: Decodable { var stream: String?; var chunk: String? }
        var result: [Chunk] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let parsed = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)),
                  let text = parsed.chunk else { continue }
            let stream = parsed.stream ?? "stdout"
            if let last = result.last, last.stream == stream {
                result[result.count - 1].text += text
            } else {
                result.append(Chunk(stream: stream, text: text))
            }
        }
        return result
    }
}

// MARK: - Hiring

public struct AdapterInfo: Codable, Hashable, Sendable, Identifiable {
    public var type: String
    public var label: String?
    public var disabled: Bool?
    public var modelsCount: Int?

    public init(type: String, label: String? = nil, disabled: Bool? = nil, modelsCount: Int? = nil) {
        self.type = type
        self.label = label
        self.disabled = disabled
        self.modelsCount = modelsCount
    }

    public var id: String { type }
    public var displayName: String { AgentAdapter.label(for: type) }
}

public struct AdapterModel: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String?
}

/// Body for `POST /api/companies/:id/agents` (board hires directly).
public struct NewAgent: Encodable, Sendable {
    public var name: String
    public var role: String
    public var title: String?
    public var reportsTo: String?
    public var capabilities: String?
    public var adapterType: String
    public var adapterConfig: [String: String]
    public var budgetMonthlyCents: Int
    public var appearance: AgentAppearance?

    public init(
        name: String, role: String, title: String?, reportsTo: String?, capabilities: String?,
        adapterType: String, model: String?, budgetMonthlyCents: Int, appearance: AgentAppearance?
    ) {
        self.name = name
        self.role = role
        self.title = title
        self.reportsTo = reportsTo
        self.capabilities = capabilities
        self.adapterType = adapterType
        self.adapterConfig = model.map { ["model": $0] } ?? [:]
        self.budgetMonthlyCents = budgetMonthlyCents
        self.appearance = appearance
    }
}
