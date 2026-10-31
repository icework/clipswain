import PaperclipKit
import SwiftUI

struct TaskHistoryView: View {
    @Environment(AppModel.self) private var app
    let snapshot: TaskHistorySnapshot
    let onInteraction: (Bool) -> Void
    @State private var visibleCount = 40

    var body: some View {
        let entries = Array(snapshot.entries.suffix(visibleCount))
        Section {
            if snapshot.entries.count > visibleCount {
                Button(TasksL10n.text("history.load_earlier", "Load earlier records (\(snapshot.entries.count - visibleCount) more)")) { visibleCount += 40 }
            }
            if entries.isEmpty { Text(TasksL10n.text("history.empty", "No time records yet")).foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 6) {
                        Image(systemName: symbol(entry)).font(.caption.weight(.semibold))
                            .foregroundStyle(tint(entry)).frame(width: 26, height: 26)
                            .background(tint(entry).opacity(0.12), in: Circle())
                        Rectangle().fill(Color.secondary.opacity(0.16)).frame(width: 1).frame(minHeight: 24)
                    }.frame(width: 26)
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = entry.date {
                            Text(AppL10n.date(date, style: .dateTime.month().day().hour().minute().second()))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        } else {
                            Text(TasksL10n.text("history.time_missing", "Time not recorded")).font(.caption).foregroundStyle(.secondary)
                        }
                        entryContent(entry)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
                .id(entry.id)
            }
            // Keep a static anchor outside the lazy ForEach: off-screen row IDs are not
            // registered until SwiftUI materializes their conditional content.
            Color.clear.frame(height: 1)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id("history-latest")
        } footer: {
            Text(TasksL10n.text("history.footer", "Oldest first · Records shown: \(entries.count)/\(snapshot.entries.count). Durations are not estimated for unrecorded status changes."))
        }
    }

    @ViewBuilder private func entryContent(_ entry: TaskHistoryEntry) -> some View {
        switch entry.kind {
        case .milestone(let title, _):
            Text(title).font(.subheadline.weight(.medium))
        case .status(let from, let to):
            Text("\(from.label) → \(to.label)").font(.subheadline.weight(.medium))
            if (to == .blocked || to == .inReview || to == .todo), entry.end != nil || entry.ongoing {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let duration = TaskTiming.text(TaskTiming.interval(from: entry.date, to: entry.end ?? context.date))
                    Text(entry.ongoing
                         ? TasksL10n.text("history.ongoing_duration", "Ongoing for \(duration)")
                         : TasksL10n.text("history.finished_duration", "Lasted \(duration)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .run(let run, let number):
            NavigationLink(value: RunRoute(id: run.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TasksL10n.text("history.run_number", "\(app.agent(run.agentId)?.name ?? TasksL10n.text("common.agent", "Agent")) · Run \(number)"))
                        .font(.subheadline.weight(.semibold))
                    TimelineView(.periodic(from: .now, by: run.status == "running" ? 1 : 60)) { context in
                        Text(run.status == "queued" ? TasksL10n.text("history.queued", "Queued, not started yet") : "\(runLabel(run.status)) · \(TaskTiming.text(run.duration(at: context.date)))")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(tint(entry))
                    }
                    if let start = run.startedAt {
                        Text(TasksL10n.text("history.started", "Started \(AppL10n.date(start, style: .dateTime.month().day().hour().minute().second()))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let end = run.finishedAt {
                        Text(TasksL10n.text("history.finished", "Finished \(AppL10n.date(end, style: .dateTime.month().day().hour().minute().second()))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if run.retryOfRunId != nil {
                        Label(TasksL10n.text("history.retry", "Retry run"), systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(TasksL10n.text("history.view_logs", "View run log")).font(.caption).foregroundStyle(Color.accentColor)
                }
            }
        case .interaction(let interaction, let resolved):
            Button { onInteraction(interaction.isPending) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(resolved ? "\(interaction.kind.label) · \(interactionStatus(interaction.status))" : TasksL10n.text("history.interaction_started", "Started: \(interaction.kind.label)"))
                        .font(.subheadline.weight(.medium))
                    if let title = interaction.title { Text(title).font(.caption).lineLimit(2) }
                    Text(interaction.isPending ? TasksL10n.text("history.view_pending", "View pending request") : TasksL10n.text("history.view_discussion", "View discussion")).font(.caption)
                }
            }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
    }

    private func interactionStatus(_ status: InteractionStatus) -> String {
        switch status {
        case .accepted: return TasksL10n.text("interaction.accepted", "Accepted")
        case .rejected: return TasksL10n.text("common.rejected", "Rejected")
        case .answered: return TasksL10n.text("interaction.answered", "Answered")
        case .cancelled: return TasksL10n.text("interaction.withdrawn", "Withdrawn")
        case .expired: return TasksL10n.text("interaction.expired", "Expired")
        case .failed: return TasksL10n.text("common.failed", "Failed")
        case .pending: return TasksL10n.text("interaction.pending", "Pending")
        case .unknown: return TasksL10n.text("history.unknown_status", "Unknown status")
        }
    }

    private func runLabel(_ status: String) -> String {
        switch status {
        case "running": return TasksL10n.text("run.running", "Running")
        case "succeeded": return TasksL10n.text("run.finished", "Run ended")
        case "failed": return TasksL10n.text("run.failed", "Run failed")
        case "cancelled": return TasksL10n.text("run.cancelled", "Run cancelled")
        case "timed_out": return TasksL10n.text("run.timed_out", "Run timed out")
        default: return TasksL10n.text("run.status", "Run status: \(status)")
        }
    }

    private func symbol(_ entry: TaskHistoryEntry) -> String {
        switch entry.kind {
        case .milestone(_, let symbol): return symbol
        case .status(_, let status): return status.symbol
        case .run: return "play.fill"
        case .interaction(_, let resolved): return resolved ? "checkmark.bubble" : "questionmark.bubble"
        }
    }

    private func tint(_ entry: TaskHistoryEntry) -> Color {
        switch entry.kind {
        case .status(_, let status): return status.tint
        case .run(let run, _): return run.status == "failed" ? .orange : run.status == "running" ? .blue : .secondary
        case .interaction: return .purple
        case .milestone: return .secondary
        }
    }
}
