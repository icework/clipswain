import Foundation

public enum IssueStatus: String, OpenEnum {
    case backlog, todo
    case inProgress = "in_progress"
    case inReview = "in_review"
    case blocked, done, cancelled
    case unknown

    public static var fallback: IssueStatus { .unknown }

    /// Statuses a board user can pick, in lifecycle order.
    public static var selectable: [IssueStatus] {
        [.backlog, .todo, .inProgress, .inReview, .blocked, .done, .cancelled]
    }

    public var isTerminal: Bool { self == .done || self == .cancelled }
    public var isOpen: Bool { !isTerminal && self != .unknown }
}

public enum IssuePriority: String, OpenEnum {
    case critical, high, medium, low
    case unknown

    public static var fallback: IssuePriority { .unknown }
    public static var selectable: [IssuePriority] { [.critical, .high, .medium, .low] }

    /// Lower sorts first.
    public var rank: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .unknown: return 4
        }
    }
}

public struct IssueRelationSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var identifier: String?
    public var title: String
    public var status: IssueStatus
    public var priority: IssuePriority?
    public var assigneeAgentId: String?
    public var assigneeUserId: String?
}

public struct IssueAncestor: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var identifier: String?
    public var title: String
    public var status: IssueStatus?
}

public struct IssueLabel: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var color: String?
}

public struct IssueActiveRun: Codable, Hashable, Sendable {
    public var id: String
    public var status: String
    public var agentId: String
    public var invocationSource: String?
    public var startedAt: Date?
    public var finishedAt: Date?
}

/// Who the server says must act to unblock an issue.
public struct IssueUnblockDescriptor: Codable, Hashable, Sendable {
    public enum Owner: Hashable, Sendable {
        case agent(String)
        case user(String)
        case board
    }

    public var owner: Owner
    public var action: String

    enum CodingKeys: String, CodingKey { case owner, action }
    enum OwnerKeys: String, CodingKey { case agentId, userId }

    public init(owner: Owner, action: String) {
        self.owner = owner
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        if let nested = try? container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner) {
            if let agentId = try nested.decodeIfPresent(String.self, forKey: .agentId) {
                owner = .agent(agentId)
            } else if let userId = try nested.decodeIfPresent(String.self, forKey: .userId) {
                owner = .user(userId)
            } else {
                owner = .board
            }
        } else {
            owner = .board
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        switch owner {
        case .agent(let id):
            var nested = container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner)
            try nested.encode(id, forKey: .agentId)
        case .user(let id):
            var nested = container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner)
            try nested.encode(id, forKey: .userId)
        case .board:
            try container.encode("board", forKey: .owner)
        }
    }
}

/// Opened by the server when a run ended without a clean outcome (no handoff, crash,
/// workspace trouble). The owner, often the board, decides how the task continues.
public struct IssueRecoveryAction: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var status: String
    public var ownerType: String?
    public var ownerAgentId: String?
    public var cause: String?
    public var nextAction: String?
    public var attemptCount: Int?
    public var maxAttempts: Int?
    public var createdAt: Date?

    public var isBoardOwned: Bool { ownerType == "board" || ownerType == "user" }
}

/// Board decisions on a recovery action, mirroring the web UI's options.
public enum RecoveryDecision: String, CaseIterable, Sendable {
    case retry, markDone, falsePositiveDone

    var outcome: String { self == .falsePositiveDone ? "false_positive" : "restored" }
    var sourceIssueStatus: String { self == .retry ? "todo" : "done" }
}

public struct Issue: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var companyId: String
    public var projectId: String?
    public var goalId: String?
    public var parentId: String?
    public var identifier: String?
    public var issueNumber: Int?
    public var title: String
    public var description: String?
    public var status: IssueStatus
    public var priority: IssuePriority
    public var assigneeAgentId: String?
    public var assigneeUserId: String?
    public var createdByAgentId: String?
    public var createdByUserId: String?
    public var startedAt: Date?
    public var completedAt: Date?
    public var cancelledAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var labels: [IssueLabel]?
    public var blockedBy: [IssueRelationSummary]?
    public var blocks: [IssueRelationSummary]?
    public var ancestors: [IssueAncestor]?
    public var unblockDescriptor: IssueUnblockDescriptor?
    public var activeRecoveryAction: IssueRecoveryAction?
    public var activeRun: IssueActiveRun?
    public var liveDescendantCount: Int?
    public var executionRunId: String?

    public init(
        id: String, companyId: String, title: String, status: IssueStatus,
        priority: IssuePriority, identifier: String? = nil, description: String? = nil,
        assigneeAgentId: String? = nil, parentId: String? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.title = title
        self.status = status
        self.priority = priority
        self.identifier = identifier
        self.description = description
        self.assigneeAgentId = assigneeAgentId
        self.parentId = parentId
        self.updatedAt = updatedAt
    }

    /// "PAP-12" when the server assigned one, otherwise a short id.
    public var displayKey: String { identifier ?? String(id.prefix(8)) }

    /// The server moves a blocked or finished agent-assigned issue back to todo and wakes the
    /// agent on any human comment (`shouldImplicitlyMoveCommentedIssueToTodo`); there is no
    /// "comment only" option for these issues.
    public var humanCommentResumesWork: Bool {
        guard let agent = assigneeAgentId, !agent.isEmpty else { return false }
        return status == .blocked || status.isTerminal
    }

    /// Agent run currently executing this issue, if any.
    public var isRunning: Bool {
        guard let run = activeRun else { return false }
        return run.status == "running" || run.status == "queued"
    }
}

public enum CommentAuthorType: String, OpenEnum {
    case agent, user, system
    case unknown
    public static var fallback: CommentAuthorType { .unknown }
}

public struct IssueComment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var issueId: String
    public var authorType: CommentAuthorType?
    public var authorAgentId: String?
    public var authorUserId: String?
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date?
    public var deletedAt: Date?

    public init(
        id: String, issueId: String, body: String, createdAt: Date,
        authorType: CommentAuthorType? = nil, authorAgentId: String? = nil, authorUserId: String? = nil
    ) {
        self.id = id
        self.issueId = issueId
        self.body = body
        self.createdAt = createdAt
        self.authorType = authorType
        self.authorAgentId = authorAgentId
        self.authorUserId = authorUserId
    }

    public var isFromAgent: Bool {
        authorType == .agent || (authorType == nil && authorAgentId != nil)
    }

    /// Whether the signed-in board user wrote this comment (not just any human).
    public func isAuthored(byUser userId: String?) -> Bool {
        guard !isFromAgent, authorType != .system, let userId, let author = authorUserId else { return false }
        return author == userId
    }
}

/// Fields a board user can change on an issue. Only non-nil fields are sent.
public struct IssueUpdate: Encodable, Sendable {
    public var title: String?
    public var description: String?
    public var status: IssueStatus?
    public var priority: IssuePriority?
    /// Use `.some(nil)` to unassign.
    public var assigneeAgentId: String??
    /// Use `.some(nil)` to clear a human assignee; the server allows only one assignee.
    public var assigneeUserId: String??
    public var comment: String?
    /// With a comment: move a blocked/closed issue back to todo and wake the assignee.
    public var resume: Bool?

    public init(
        title: String? = nil, description: String? = nil, status: IssueStatus? = nil,
        priority: IssuePriority? = nil, assigneeAgentId: String?? = nil,
        assigneeUserId: String?? = nil, comment: String? = nil, resume: Bool? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assigneeAgentId = assigneeAgentId
        self.assigneeUserId = assigneeUserId
        self.comment = comment
        self.resume = resume
    }

    enum CodingKeys: String, CodingKey {
        case title, description, status, priority, assigneeAgentId, assigneeUserId, comment, resume
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status?.rawValue, forKey: .status)
        try container.encodeIfPresent(priority?.rawValue, forKey: .priority)
        if let assignee = assigneeAgentId {
            if let id = assignee {
                try container.encode(id, forKey: .assigneeAgentId)
            } else {
                try container.encodeNil(forKey: .assigneeAgentId)
            }
        }
        if let user = assigneeUserId {
            if let id = user {
                try container.encode(id, forKey: .assigneeUserId)
            } else {
                try container.encodeNil(forKey: .assigneeUserId)
            }
        }
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(resume, forKey: .resume)
    }

    public var isEmpty: Bool {
        title == nil && description == nil && status == nil && priority == nil
            && assigneeAgentId == nil && assigneeUserId == nil && comment == nil
    }

    /// Assign to an agent, clearing any human assignee so the server's one-assignee rule holds.
    public static func assign(toAgent agentId: String) -> IssueUpdate {
        IssueUpdate(assigneeAgentId: .some(agentId), assigneeUserId: .some(nil))
    }

    /// Remove every assignee, agent or human.
    public static var unassign: IssueUpdate {
        IssueUpdate(assigneeAgentId: .some(nil), assigneeUserId: .some(nil))
    }
}

public struct NewIssue: Encodable, Sendable {
    public var title: String
    public var description: String?
    public var status: String
    public var priority: String
    public var assigneeAgentId: String?
    public var parentId: String?

    public init(
        title: String, description: String? = nil, status: IssueStatus = .todo,
        priority: IssuePriority = .medium, assigneeAgentId: String? = nil, parentId: String? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status.rawValue
        self.priority = priority.rawValue
        self.assigneeAgentId = assigneeAgentId
        self.parentId = parentId
    }
}

public struct NewComment: Encodable, Sendable {
    public var body: String
    public var clientRequestId: String
    /// Reopen a done/cancelled issue when commenting.
    public var reopen: Bool?
    /// Wake the assignee to resume work after this comment.
    public var resume: Bool?
    /// Interrupt the assignee's current run so it picks up the comment now.
    public var interrupt: Bool?

    public init(body: String, reopen: Bool? = nil, resume: Bool? = nil, interrupt: Bool? = nil) {
        self.body = body
        self.clientRequestId = UUID().uuidString.lowercased()
        self.reopen = reopen
        self.resume = resume
        self.interrupt = interrupt
    }
}
