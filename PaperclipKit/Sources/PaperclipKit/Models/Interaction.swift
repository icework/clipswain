import Foundation

public enum InteractionKind: String, OpenEnum {
    case suggestTasks = "suggest_tasks"
    case askUserQuestions = "ask_user_questions"
    case requestConfirmation = "request_confirmation"
    case requestCheckboxConfirmation = "request_checkbox_confirmation"
    case requestItemVerdicts = "request_item_verdicts"
    case connectionIntent = "connection_intent"
    case unknown
    public static var fallback: InteractionKind { .unknown }

    public var label: String {
        switch self {
        case .suggestTasks: return KitL10n.string("interaction.kind.suggest", defaultValue: "Suggested Tasks")
        case .askUserQuestions: return KitL10n.string("interaction.kind.questions", defaultValue: "Questions")
        case .requestConfirmation: return KitL10n.string("interaction.kind.confirm", defaultValue: "Confirmation")
        case .requestCheckboxConfirmation: return KitL10n.string("interaction.kind.checkbox", defaultValue: "Checklist Confirmation")
        case .requestItemVerdicts: return KitL10n.string("interaction.kind.verdicts", defaultValue: "Item Review")
        case .connectionIntent: return KitL10n.string("interaction.kind.connect", defaultValue: "Connection Authorization")
        case .unknown: return KitL10n.string("interaction.kind.unknown", defaultValue: "Interaction")
        }
    }
}

public enum InteractionStatus: String, OpenEnum {
    case pending, accepted, rejected, answered, cancelled, expired, failed
    case unknown
    public static var fallback: InteractionStatus { .unknown }
}

/// A structured card an agent posted in an issue thread, waiting for a decision.
public struct IssueInteraction: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var issueId: String
    public var kind: InteractionKind
    public var title: String?
    public var summary: String?
    public var status: InteractionStatus
    public var effectiveResolverPolicy: String?
    public var createdByAgentId: String?
    public var addresseeAgentId: String?
    public var payload: JSONValue?
    public var result: JSONValue?
    public var createdAt: Date?
    public var resolvedAt: Date?

    public init(
        id: String, issueId: String, kind: InteractionKind, status: InteractionStatus,
        title: String? = nil, payload: JSONValue? = nil
    ) {
        self.id = id
        self.issueId = issueId
        self.kind = kind
        self.status = status
        self.title = title
        self.payload = payload
    }

    public var isPending: Bool { status == .pending }

    public var confirmation: ConfirmationPayload? {
        guard kind == .requestConfirmation else { return nil }
        return try? payload?.decode(ConfirmationPayload.self)
    }

    public var questions: QuestionsPayload? {
        guard kind == .askUserQuestions else { return nil }
        return try? payload?.decode(QuestionsPayload.self)
    }

    public var suggestedTasks: SuggestedTasksPayload? {
        guard kind == .suggestTasks else { return nil }
        return try? payload?.decode(SuggestedTasksPayload.self)
    }

    public var checkboxOptions: CheckboxPayload? {
        guard kind == .requestCheckboxConfirmation else { return nil }
        return try? payload?.decode(CheckboxPayload.self)
    }

    public var verdictItems: VerdictsPayload? {
        guard kind == .requestItemVerdicts else { return nil }
        return try? payload?.decode(VerdictsPayload.self)
    }

    /// The server rejects a decline without a reason when the payload asks for one.
    public var rejectRequiresReason: Bool {
        confirmation?.rejectRequiresReason == true || checkboxOptions?.rejectRequiresReason == true
    }

    public var rejectReasonLabel: String? {
        confirmation?.rejectReasonLabel ?? checkboxOptions?.rejectReasonLabel
    }
}

public struct ConfirmationPayload: Codable, Hashable, Sendable {
    public var prompt: String
    public var acceptLabel: String?
    public var rejectLabel: String?
    public var rejectRequiresReason: Bool?
    public var rejectReasonLabel: String?
    public var detailsMarkdown: String?
}

public struct QuestionOption: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?
}

public struct Question: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var prompt: String
    public var helpText: String?
    public var selectionMode: String
    public var required: Bool?
    public var allowOther: Bool?
    public var options: [QuestionOption]

    public var isMulti: Bool { selectionMode == "multi" }
}

public struct QuestionsPayload: Codable, Hashable, Sendable {
    public var title: String?
    public var submitLabel: String?
    public var questions: [Question]
}

public struct QuestionAnswer: Codable, Hashable, Sendable {
    public var questionId: String
    public var optionIds: [String]
    public var otherText: String?

    public init(questionId: String, optionIds: [String], otherText: String? = nil) {
        self.questionId = questionId
        self.optionIds = optionIds
        self.otherText = otherText
    }
}

public struct SuggestedTask: Codable, Hashable, Sendable, Identifiable {
    public var clientKey: String
    public var title: String
    public var description: String?
    public var priority: IssuePriority?
    public var assigneeAgentId: String?
    public var hiddenInPreview: Bool?

    public var id: String { clientKey }
}

public struct SuggestedTasksPayload: Codable, Hashable, Sendable {
    public var tasks: [SuggestedTask]
}

public struct CheckboxOption: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?
}

public struct CheckboxPayload: Codable, Hashable, Sendable {
    public var prompt: String?
    public var detailsMarkdown: String?
    public var options: [CheckboxOption]
    public var defaultSelectedOptionIds: [String]?
    public var minSelected: Int?
    public var maxSelected: Int?
    public var acceptLabel: String?
    public var rejectLabel: String?
    public var rejectRequiresReason: Bool?
    public var rejectReasonLabel: String?
}

public struct VerdictItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String?
    public var title: String?
    public var description: String?
    public var previewMarkdown: String?

    public var displayLabel: String { label ?? title ?? id }
}

public struct VerdictsPayload: Codable, Hashable, Sendable {
    public var prompt: String?
    public var detailsMarkdown: String?
    public var items: [VerdictItem]
    /// Verdicts the agent allows; the server defaults to approve/reject.
    public var verdicts: [String]?
    /// Verdicts that need a reason; the server defaults to reject.
    public var requireReasonOn: [String]?
    public var reasonLabel: String?
    public var allowBulkApprove: Bool?

    public var allowedVerdicts: [ItemVerdict] {
        let raw = verdicts ?? ["approve", "reject"]
        let allowed = ItemVerdict.allCases.filter { raw.contains($0.rawValue) }
        return allowed.isEmpty ? [.approve, .reject] : allowed
    }

    public func requiresReason(_ verdict: ItemVerdict) -> Bool {
        (requireReasonOn ?? ["reject"]).contains(verdict.rawValue)
    }

    /// True when every item has an allowed verdict and every verdict that needs a reason has one.
    public func isComplete(_ verdicts: [String: ItemVerdict], reasons: [String: String]) -> Bool {
        items.allSatisfy { item in
            guard let verdict = verdicts[item.id], allowedVerdicts.contains(verdict) else { return false }
            if requiresReason(verdict) {
                return !(reasons[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
    }
}

public enum ItemVerdict: String, CaseIterable, Sendable {
    case approve, reject, defer_ = "defer"

    public var label: String {
        switch self {
        case .approve: return KitL10n.string("interaction.verdict.approve", defaultValue: "Approve")
        case .reject: return KitL10n.string("interaction.verdict.reject", defaultValue: "Reject")
        case .defer_: return KitL10n.string("interaction.verdict.defer", defaultValue: "Defer")
        }
    }
}

/// How the board resolves an interaction card.
public enum InteractionResolution: Sendable {
    case accept(selectedClientKeys: [String]? = nil, selectedOptionIds: [String]? = nil)
    case reject(reason: String?)
    case respond(answers: [QuestionAnswer], summaryMarkdown: String? = nil)
    case verdicts([String: ItemVerdict], reasons: [String: String] = [:])
}
