import PaperclipKit
import SwiftUI

/// The server's recovery prompt for a task whose last run ended without a clean outcome.
struct RecoveryCard: View {
    @Environment(AppModel.self) private var app
    let action: IssueRecoveryAction
    let onDecide: (RecoveryDecision) async -> Void

    @State private var busy = false
    @State private var confirmingFalsePositive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(TasksL10n.text("recovery.required", "Recovery needed"), systemImage: "lifepreserver")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            Text(causeText).font(.subheadline.weight(.medium))
            if let next = action.nextAction, !next.isEmpty {
                Text(next).font(.footnote).foregroundStyle(.secondary)
            }
            if let attempts = action.attemptCount {
                Text(TasksL10n.text("recovery.attempts", "Attempts: \(attempts)\(action.maxAttempts.map { "/\($0)" } ?? "")"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if action.isBoardOwned {
                HStack {
                    button(TasksL10n.text("common.retry", "Retry"), "arrow.clockwise", .retry)
                        .prominentButton()
                    button(TasksL10n.text("task.mark_done", "Mark complete"), "checkmark", .markDone)
                        .secondaryButton()
                    Menu {
                        Button(TasksL10n.text("recovery.false_positive", "False alarm: the task is already complete"), role: .destructive) { confirmingFalsePositive = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
                .disabled(busy)
            } else if let owner = app.agent(action.ownerAgentId) {
                Text(TasksL10n.text("recovery.owner", "Handled by \(owner.name)")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(TasksL10n.text("recovery.confirm_false_positive", "Confirm this is a false alarm?"), isPresented: $confirmingFalsePositive, titleVisibility: .visible) {
            Button(TasksL10n.text("recovery.close_done", "Close recovery and mark task complete"), role: .destructive) { decide(.falsePositiveDone) }
        }
    }

    private var causeText: String {
        switch action.cause ?? action.kind {
        case "deliberate_wait_without_target": return TasksL10n.text("recovery.wait_without_target", "The agent paused without saying who it is waiting for")
        case "missing_disposition", "successful_run_missing_handoff": return TasksL10n.text("recovery.missing_outcome", "The run ended without the agent reporting a result")
        case "process_lost": return TasksL10n.text("recovery.process_lost", "The agent process exited unexpectedly")
        default: return (action.cause ?? action.kind).replacingOccurrences(of: "_", with: " ")
        }
    }

    private func button(_ title: String, _ symbol: String, _ decision: RecoveryDecision) -> some View {
        Button {
            decide(decision)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 4)
        }
    }

    private func decide(_ decision: RecoveryDecision) {
        busy = true
        Task {
            await onDecide(decision)
            busy = false
        }
    }
}
