import Foundation

public struct AttentionSubject: Codable, Hashable, Sendable {
    public var kind: String
    public var id: String
    public var title: String?
    public var identifier: String?
    public var status: String?
    public var href: String?
}

public struct AttentionDetail: Codable, Hashable, Sendable {
    public var kind: String
    public var summaryExcerpt: String?
    public var promptExcerpt: String?
    public var firstQuestionText: String?
    public var firstTaskTitle: String?
    public var failureReasonExcerpt: String?
    public var agentName: String?
    public var questionCount: Int?
    public var taskCount: Int?

    /// The most useful one-line excerpt for this detail kind.
    public var excerpt: String? {
        promptExcerpt ?? firstQuestionText ?? summaryExcerpt ?? failureReasonExcerpt ?? firstTaskTitle
    }
}

public struct AttentionDecisionVerb: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?
}

/// One row of the board's "needs you" feed (`GET /companies/:id/attention`).
public struct AttentionItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sourceKind: String
    public var subject: AttentionSubject
    public var whyNow: String?
    public var severity: String?
    public var activityAt: Date?
    public var relatedIssue: AttentionSubject?
    public var originAgentName: String?
    public var detail: AttentionDetail?
    public var decisionVerbs: [AttentionDecisionVerb]?

    /// The issue to open for this item, if any.
    public var issueId: String? {
        if subject.kind == "issue" { return subject.id }
        return relatedIssue?.id
    }

    /// The approval to open for this item, if any.
    public var approvalId: String? {
        subject.kind == "approval" ? subject.id : nil
    }

    public var sourceLabel: String {
        switch sourceKind {
        case "approval": return KitL10n.string("attention.kind.approval", defaultValue: "Approval")
        case "decision": return KitL10n.string("attention.kind.decision", defaultValue: "Decision")
        case "issue_thread_interaction": return KitL10n.string("attention.kind.reply", defaultValue: "Awaiting Reply")
        case "join_request": return KitL10n.string("attention.kind.join", defaultValue: "Join Request")
        case "recovery_action": return KitL10n.string("attention.kind.recovery", defaultValue: "Recovery")
        case "productivity_review": return KitL10n.string("attention.kind.productivity", defaultValue: "Productivity Review")
        case "blocker_attention": return KitL10n.string("attention.kind.blocked", defaultValue: "Blocked")
        case "review": return KitL10n.string("attention.kind.review", defaultValue: "Review")
        case "failed_run": return KitL10n.string("attention.kind.failed_run", defaultValue: "Failed Run")
        case "budget_alert": return KitL10n.string("attention.kind.budget", defaultValue: "Budget")
        case "agent_error_alert": return KitL10n.string("attention.kind.agent_error", defaultValue: "Agent Error")
        default: return sourceKind
        }
    }

    public var severityRank: Int {
        switch severity {
        case "critical": return 0
        case "high": return 1
        case "medium": return 2
        default: return 3
        }
    }
}

public struct AttentionFeed: Codable, Hashable, Sendable {
    public var totalCount: Int?
    public var nextCursor: String?
    public var items: [AttentionItem]
}

// MARK: - Board sign-in

/// Response of `POST /api/cli-auth/challenges`: a pending board key that becomes valid once a
/// signed-in user approves it in the browser.
public struct CLIAuthChallenge: Codable, Hashable, Sendable {
    public var id: String
    public var token: String
    public var boardApiToken: String
    public var approvalPath: String
    public var approvalUrl: String?
    public var expiresAt: Date?
    public var suggestedPollIntervalMs: Int?
}

public struct CLIAuthChallengeState: Codable, Hashable, Sendable {
    public var status: String

    public var isApproved: Bool { status == "approved" }
    public var isFinal: Bool { status == "approved" || status == "cancelled" || status == "expired" }
}
