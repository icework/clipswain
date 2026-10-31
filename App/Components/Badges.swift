import PaperclipKit
import SwiftUI

extension IssueStatus {
    var label: String {
        switch self {
        case .backlog: return AppL10n.text("status.backlog", "Backlog")
        case .todo: return AppL10n.text("status.todo", "To do")
        case .inProgress: return AppL10n.text("status.in_progress", "In progress")
        case .inReview: return AppL10n.text("status.in_review", "In review")
        case .blocked: return AppL10n.text("status.blocked", "Blocked")
        case .done: return AppL10n.text("status.done", "Done")
        case .cancelled: return AppL10n.text("status.cancelled", "Cancelled")
        case .unknown: return AppL10n.text("status.unknown", "Unknown")
        }
    }

    var symbol: String {
        switch self {
        case .backlog: return "circle.dashed"
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .inReview: return "eye.circle"
        case .blocked: return "exclamationmark.octagon.fill"
        case .done: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .backlog: return .gray
        case .todo: return .secondary
        case .inProgress: return .blue
        case .inReview: return .purple
        case .blocked: return .red
        case .done: return .green
        case .cancelled: return .gray
        case .unknown: return .gray
        }
    }

    /// Rough share of the lifecycle completed, for progress bars.
    var progress: Double {
        switch self {
        case .backlog: return 0
        case .todo: return 0.1
        case .inProgress, .blocked: return 0.5
        case .inReview: return 0.8
        case .done: return 1
        case .cancelled, .unknown: return 0
        }
    }
}

extension IssuePriority {
    var label: String {
        switch self {
        case .critical: return AppL10n.text("priority.critical", "Critical")
        case .high: return AppL10n.text("priority.high", "High")
        case .medium: return AppL10n.text("priority.medium", "Medium")
        case .low: return AppL10n.text("priority.low", "Low")
        case .unknown: return "—"
        }
    }

    var symbol: String {
        switch self {
        case .critical: return "exclamationmark.3"
        case .high: return "chevron.up.2"
        case .medium: return "equal"
        case .low: return "chevron.down"
        case .unknown: return "minus"
        }
    }

    var tint: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .gray
        case .unknown: return .gray
        }
    }
}

extension AgentStatus {
    var label: String {
        switch self {
        case .active: return AppL10n.text("agent.active", "Active")
        case .idle: return AppL10n.text("agent.idle", "Idle")
        case .running: return AppL10n.text("agent.running", "Running")
        case .paused: return AppL10n.text("agent.paused", "Paused")
        case .error: return AppL10n.text("agent.error", "Error")
        case .pendingApproval: return AppL10n.text("agent.pending_approval", "Pending approval")
        case .terminated: return AppL10n.text("agent.terminated", "Terminated")
        case .unknown: return AppL10n.text("status.unknown", "Unknown")
        }
    }

    var tint: Color {
        switch self {
        case .running: return .blue
        case .active, .idle: return .green
        case .paused: return .orange
        case .error: return .red
        case .pendingApproval: return .purple
        case .terminated, .unknown: return .gray
        }
    }
}

struct StatusBadge: View {
    let status: IssueStatus
    var compact = false

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            .font(.caption.weight(.medium))
            .foregroundStyle(status.tint)
            .padding(.horizontal, compact ? 0 : 8)
            .padding(.vertical, compact ? 0 : 3)
            .background {
                if !compact { Capsule().fill(status.tint.opacity(0.12)) }
            }
    }
}

struct PriorityBadge: View {
    let priority: IssuePriority

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: priority.symbol).imageScale(.small)
            Text(priority.label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(priority.tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppL10n.text("a11y.priority", "Priority: \(priority.label)"))
    }
}

struct AgentStatusDot: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(status.tint).frame(width: 7, height: 7)
            Text(status.label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
