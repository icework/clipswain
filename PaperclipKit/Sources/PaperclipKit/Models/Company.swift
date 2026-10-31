import Foundation

public struct Company: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    public var status: String?
    public var issuePrefix: String?
    public var budgetMonthlyCents: Int?
    public var spentMonthlyCents: Int?
    public var logoUrl: String?

    public init(id: String, name: String, issuePrefix: String? = nil) {
        self.id = id
        self.name = name
        self.issuePrefix = issuePrefix
    }
}

public struct DashboardSummary: Codable, Hashable, Sendable {
    public struct AgentCounts: Codable, Hashable, Sendable {
        public var active: Int
        public var running: Int
        public var paused: Int
        public var error: Int
    }

    public struct TaskCounts: Codable, Hashable, Sendable {
        public var open: Int
        public var inProgress: Int
        public var blocked: Int
        public var done: Int
    }

    public struct Costs: Codable, Hashable, Sendable {
        public var monthSpendCents: Int
        public var monthBudgetCents: Int
        public var monthUtilizationPercent: Double
    }

    public struct RunActivityDay: Codable, Hashable, Sendable {
        public var date: String
        public var succeeded: Int
        public var failed: Int
        public var recovered: Int?
        public var other: Int?
        public var total: Int
        /// Failed runs that day keyed by error code, e.g. `["timeout": 2]`.
        public var failedByErrorCode: [String: Int]?
    }

    public var companyId: String
    public var agents: AgentCounts
    public var tasks: TaskCounts
    public var costs: Costs
    public var pendingApprovals: Int
    public var runActivity: [RunActivityDay]?
}

/// Response of `GET /api/cli-auth/me`: the signed-in board user.
public struct BoardIdentity: Codable, Hashable, Sendable {
    public struct User: Codable, Hashable, Sendable {
        public var id: String?
        public var name: String?
        public var email: String?
    }

    public var user: User?
    public var userId: String
    public var isInstanceAdmin: Bool?
    public var companyIds: [String]?
    public var source: String?
}
