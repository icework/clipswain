import Foundation
import PaperclipKit

struct TaskHistoryEntry: Identifiable {
    enum Kind {
        case milestone(String, String)
        case status(IssueStatus, IssueStatus)
        case run(IssueRun, Int)
        case interaction(IssueInteraction, resolved: Bool)
    }
    var id: String
    var date: Date?
    var kind: Kind
    var end: Date?
    var ongoing = false
}

struct TaskHistorySnapshot {
    let runs: [IssueRun]
    let entries: [TaskHistoryEntry]

    init(issue: Issue, activities: [IssueActivity], runs: [IssueRun], interactions: [IssueInteraction]) {
        self.runs = TaskTiming.uniqueRuns(runs)
        var seen = Set<String>()
        let activities = activities.filter { seen.insert($0.id).inserted }.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
        let changes = activities.filter { $0.statusChange != nil }
        var items: [TaskHistoryEntry] = []
        if let date = issue.createdAt {
            items.append(.init(id: "created", date: date, kind: .milestone(TasksL10n.text("history.task_created", "Task created"), "plus.circle")))
        }
        for (index, activity) in changes.enumerated() {
            guard let change = activity.statusChange else { continue }
            let next = changes.dropFirst(index + 1).first
            // Some servers do not log automatic checkout transitions. Never bridge those gaps.
            let end = next?.statusChange?.from == change.to ? next?.createdAt : nil
            let ongoing = next == nil && issue.status == change.to && !issue.status.isTerminal
            items.append(.init(id: "activity-" + activity.id, date: activity.createdAt,
                               kind: .status(change.from, change.to), end: end, ongoing: ongoing))
        }
        let terminalDate = issue.status == .done ? issue.completedAt : issue.cancelledAt
        if issue.status.isTerminal, let date = terminalDate,
           !changes.contains(where: { $0.statusChange?.to == issue.status && abs($0.createdAt.timeIntervalSince(date)) < 2 }) {
            items.append(.init(id: "terminal", date: date,
                               kind: .milestone(issue.status == .done ? TasksL10n.text("history.task_completed", "Task completed") : TasksL10n.text("history.task_cancelled", "Task cancelled"), issue.status.symbol)))
        }
        for (index, run) in self.runs.enumerated() {
            items.append(.init(id: "run-" + run.id, date: run.createdAt ?? run.startedAt,
                               kind: .run(run, index + 1)))
        }
        for interaction in interactions {
            if let date = interaction.createdAt {
                items.append(.init(id: "request-" + interaction.id, date: date,
                                   kind: .interaction(interaction, resolved: false)))
            }
            if !interaction.isPending, let date = interaction.resolvedAt {
                items.append(.init(id: "resolved-" + interaction.id, date: date,
                                   kind: .interaction(interaction, resolved: true)))
            }
        }
        // A compact entry per document; never flood the timeline with automatic saves.
        let documents = activities.filter { ["issue.document_created", "issue.document_updated"].contains($0.action) }
        let groups = Dictionary(grouping: documents) {
            $0.details?["key"]?.stringValue ?? $0.details?["documentId"]?.stringValue ?? $0.id
        }
        for group in groups.values {
            guard let latest = group.last else { continue }
            let title = latest.details?["title"]?.stringValue ?? latest.details?["key"]?.stringValue ?? TasksL10n.text("history.task_document", "Task document")
            let suffix = group.count > 1 ? TasksL10n.text("history.document_record_count", " · \(group.count) records") : ""
            items.append(.init(id: "document-" + latest.id, date: latest.createdAt,
                               kind: .milestone(TasksL10n.text("history.document", "Document: \(title)\(suffix)"), "doc.text")))
        }
        for activity in activities where activity.action == "issue.blockers_updated" {
            items.append(.init(id: "dependency-" + activity.id, date: activity.createdAt,
                               kind: .milestone(TasksL10n.text("history.dependencies_updated", "Dependencies updated"), "link")))
        }
        entries = items.sorted {
            let a = $0.date ?? .distantPast, b = $1.date ?? .distantPast
            return a == b ? $0.id < $1.id : a < b
        }
    }
}
