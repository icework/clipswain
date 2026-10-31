import Foundation
import PaperclipKit

/// A task list is an ongoing queue, not a project with a fixed completion target.
/// The overview and every filter count use the same assignee/search scope.
enum TaskListFilter: String, Identifiable, CaseIterable {
    case current, inProgress, inReview, blocked, waiting, done, cancelled, all, other
    var id: String { rawValue }

    static let primary: [Self] = [.current, .done, .cancelled, .all]
    static let work: [Self] = [.blocked, .inReview, .inProgress, .waiting]

    var label: String {
        switch self {
        case .current: return TasksL10n.text("filter.current", "Current")
        case .inProgress: return TasksL10n.text("filter.in_progress", "In progress")
        case .inReview: return TasksL10n.text("filter.in_review", "In review")
        case .blocked: return TasksL10n.text("filter.blocked", "Blocked")
        case .waiting: return TasksL10n.text("filter.waiting", "Not started")
        case .done: return TasksL10n.text("filter.done", "Completed")
        case .cancelled: return TasksL10n.text("common.cancelled", "Cancelled")
        case .all: return TasksL10n.text("filter.all", "All")
        case .other: return TasksL10n.text("filter.other", "Other statuses")
        }
    }

    var isCurrent: Bool { self == .current || Self.work.contains(self) }

    func includes(_ status: IssueStatus) -> Bool {
        switch self {
        case .current: return status.isOpen
        case .inProgress: return status == .inProgress
        case .inReview: return status == .inReview
        case .blocked: return status == .blocked
        case .waiting: return status == .todo || status == .backlog
        case .done: return status == .done
        case .cancelled: return status == .cancelled
        case .all: return true
        case .other: return status == .unknown
        }
    }
}

struct TaskListSnapshot {
    let scoped: [Issue]

    init(issues: [Issue], assigneeID: String? = nil, search: String = "") {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        scoped = issues.filter { issue in
            (assigneeID == nil || issue.assigneeAgentId == assigneeID)
                && (query.isEmpty || issue.title.localizedCaseInsensitiveContains(query)
                    || issue.displayKey.localizedCaseInsensitiveContains(query))
        }
    }

    func count(_ filter: TaskListFilter) -> Int { matching(filter).count }
    func count(status: IssueStatus) -> Int { scoped.filter { $0.status == status }.count }
    func matching(_ filter: TaskListFilter) -> [Issue] { scoped.filter { filter.includes($0.status) } }

    func sections(for filter: TaskListFilter) -> [(IssueStatus, [Issue])] {
        let order: [IssueStatus] = [.blocked, .inReview, .inProgress, .todo, .backlog, .done, .cancelled, .unknown]
        let grouped = Dictionary(grouping: matching(filter), by: \.status)
        return order.compactMap { status in
            guard let items = grouped[status], !items.isEmpty else { return nil }
            return (status, items.sorted { lhs, rhs in
                if !status.isTerminal, lhs.priority.rank != rhs.priority.rank {
                    return lhs.priority.rank < rhs.priority.rank
                }
                let left = Self.sortDate(lhs), right = Self.sortDate(rhs)
                if left != right { return left > right }
                return lhs.id < rhs.id
            })
        }
    }

    private static func sortDate(_ issue: Issue) -> Date {
        let ended: Date? = issue.status == .done ? issue.completedAt : issue.status == .cancelled ? issue.cancelledAt : nil
        return ended ?? issue.updatedAt ?? issue.createdAt ?? .distantPast
    }
}
