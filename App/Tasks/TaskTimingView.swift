import PaperclipKit
import SwiftUI

struct TaskTimingView: View {
    let issue: Issue
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: issue.activeRun?.status == "running" ? 1 : 60)) { context in
            let elapsed = TaskTiming.elapsed(issue, at: context.date)
            let label = issue.status == .done ? TasksL10n.text("timing.total_elapsed", "Total elapsed") : issue.status == .cancelled ? TasksL10n.text("timing.cancelled_elapsed", "Elapsed before cancellation") : TasksL10n.text("timing.elapsed", "Elapsed")
            VStack(alignment: .leading, spacing: 4) {
                if let run = issue.activeRun, run.status == "running", run.finishedAt == nil {
                    Text(TasksL10n.text("timing.current_run", "Current run: \(TaskTiming.text(TaskTiming.runDuration(status: run.status, start: run.startedAt, finish: run.finishedAt, now: context.date)))"))
                        .foregroundStyle(.blue)
                } else if issue.activeRun?.status == "queued" {
                    Text(TasksL10n.text("run.queued", "Queued")).foregroundStyle(.secondary)
                }
                Text(elapsed == nil ? TasksL10n.text("timing.incomplete", "Time records incomplete") : "\(label) \(TaskTiming.text(elapsed))")
                    .foregroundStyle(.secondary)
            }
            .font(compact ? .caption : .subheadline.weight(.medium))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
