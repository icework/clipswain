import Foundation

public enum ApprovalStatus: String, OpenEnum {
    case pending
    case revisionRequested = "revision_requested"
    case approved, rejected, cancelled
    case unknown
    public static var fallback: ApprovalStatus { .unknown }

    public var isOpen: Bool { self == .pending || self == .revisionRequested }
}

public struct Approval: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var companyId: String
    public var type: String
    public var requestedByAgentId: String?
    public var requestedByUserId: String?
    public var status: ApprovalStatus
    public var payload: [String: JSONValue]?
    public var decisionNote: String?
    public var decidedAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: String, companyId: String, type: String, status: ApprovalStatus, payload: [String: JSONValue]? = nil) {
        self.id = id
        self.companyId = companyId
        self.type = type
        self.status = status
        self.payload = payload
    }

    public var typeLabel: String {
        switch type {
        case "hire_agent": return KitL10n.string("approval.type.hire", defaultValue: "Hire Agent")
        case "approve_ceo_strategy": return KitL10n.string("approval.type.strategy", defaultValue: "CEO Strategy")
        case "budget_override_required": return KitL10n.string("approval.type.budget", defaultValue: "Budget Exceeded")
        case "request_board_approval": return KitL10n.string("approval.type.board", defaultValue: "Board Approval")
        default: return type
        }
    }

    /// Best-effort human summary pulled from common payload fields.
    public var summary: String? {
        guard let payload else { return nil }
        for key in ["title", "summary", "plan", "reason", "name", "description"] {
            if let text = payload[key]?.stringValue, !text.isEmpty { return text }
        }
        return nil
    }
}

public struct ApprovalComment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var approvalId: String
    public var authorAgentId: String?
    public var authorUserId: String?
    public var body: String
    public var createdAt: Date
}

public enum ApprovalDecision: String, Sendable {
    case approve
    case reject
    case requestRevision = "request-revision"
}
