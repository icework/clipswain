import PaperclipKit
import SwiftUI

/// Current work is a set of queues. Finished tasks have their own list filters and
/// never change the size or visual weight of these current-state counts.
struct TaskWorkSummary: View {
    let snapshot: TaskListSnapshot
    let scope: String
    @Binding var selection: TaskListFilter
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconWidth = 24.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(TasksL10n.text("summary.current_work", "Current work")).font(.headline)
                    Spacer()
                    total
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(TasksL10n.text("summary.current_work", "Current work")).font(.headline)
                    total
                }
            }
            Text(scope).font(.caption).foregroundStyle(.secondary)

            if snapshot.count(.current) > 0 {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        ForEach(TaskListFilter.work) { bucketButton($0) }
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            bucketButton(.blocked)
                            bucketButton(.inReview)
                        }
                        HStack(spacing: 10) {
                            bucketButton(.inProgress)
                            bucketButton(.waiting)
                        }
                    }
                }
                if snapshot.count(.waiting) > 0 {
                    Text(TasksL10n.text("summary.waiting", "Not started: To do \(snapshot.count(status: .todo)) · Backlog \(snapshot.count(status: .backlog))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(snapshot.scoped.isEmpty ? TasksL10n.text("summary.empty_scope", "No tasks in this scope") : TasksL10n.text("summary.no_open_tasks", "No unfinished tasks in this scope"), systemImage: "tray")
                        .font(.subheadline)
                    Text(TasksL10n.text("summary.history_hint", "Choose a status below to view history, or tap + to create a task."))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }

            if snapshot.count(.other) > 0 {
                Button { selection = .other } label: {
                    Label(TasksL10n.text("summary.other_count", "Other statuses: \(snapshot.count(.other))"), systemImage: "questionmark.circle")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var total: some View {
        Text(TasksL10n.text("summary.open_count", "\(snapshot.count(.current)) unfinished tasks"))
            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }

    private func bucketButton(_ bucket: TaskListFilter) -> some View {
        let selected = selection == bucket
        let count = snapshot.count(bucket)
        let tint = bucket.tint
        return Button {
            withAnimation(.snappy) { selection = selected ? .current : bucket }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: bucket.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(count > 0 ? tint : .secondary)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(bucket.label).font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(count)").font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(count > 0 ? .primary : .secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(selected ? tint.opacity(0.13) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? tint.opacity(0.65) : .clear, lineWidth: 1.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TasksL10n.text("summary.bucket_accessibility", "\(bucket.label), tasks: \(count)"))
        .accessibilityHint(selected ? TasksL10n.text("summary.selected_hint", "Tap again to show all current tasks") : TasksL10n.text("summary.filter_hint", "Tap to filter the list"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension TaskListFilter {
    var tint: Color {
        switch self {
        case .blocked: return .red
        case .inReview: return .purple
        case .inProgress: return .blue
        default: return .orange
        }
    }
    var symbol: String {
        switch self {
        case .blocked: return "exclamationmark.octagon"
        case .inReview: return "eye"
        case .inProgress: return "arrow.triangle.2.circlepath"
        default: return "tray.full"
        }
    }
}
