import Foundation

public enum InboxEventKind: String, Codable, CaseIterable, Sendable {
    case blocked, completed, started, review, reopened, cancelled, created, statusChanged
}

/// An immutable occurrence, keyed by the server's activity id rather than by task id.
public struct InboxEvent: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let issueId: String
    public let identifier: String?
    public let title: String
    public let date: Date
    /// Server status timestamp, when provided separately from the activity log's commit time.
    public let transitionAt: Date?
    public let kind: InboxEventKind
    public let previousStatus: IssueStatus?
    public let status: IssueStatus

    public init?(activity: IssueActivity, issue: Issue) {
        let from: IssueStatus?
        let to: IssueStatus
        if activity.action == "issue.created" {
            guard let raw = activity.details?["status"]?.stringValue,
                  let initial = IssueStatus(rawValue: raw), initial != .unknown else { return nil }
            from = nil
            to = initial
        } else if let change = activity.statusChange {
            from = change.from
            to = change.to
        } else if ["issue.checked_out", "issue.released"].contains(activity.action),
                  let old = activity.details?["_previous"]?["status"]?.stringValue,
                  let new = activity.details?["status"]?.stringValue,
                  old != new, let previous = IssueStatus(rawValue: old), let next = IssueStatus(rawValue: new),
                  previous != .unknown, next != .unknown {
            from = previous
            to = next
        } else {
            return nil // Repeated status echoes are not events.
        }
        id = activity.id
        issueId = issue.id
        identifier = activity.details?["identifier"]?.stringValue ?? issue.identifier
        title = activity.details?["issueTitle"]?.stringValue ?? activity.details?["title"]?.stringValue ?? issue.title
        date = activity.createdAt
        transitionAt = (activity.details?["changes"]?["blockedTransitionAt"]?["to"]?.stringValue
            ?? activity.details?["blockedTransitionAt"]?.stringValue).flatMap(PaperclipJSON.parseDate)
        previousStatus = from
        status = to
        if from == nil { kind = .created }
        else if to == .blocked { kind = .blocked }
        else if to == .done { kind = .completed }
        else if to == .cancelled { kind = .cancelled }
        else if from?.isTerminal == true { kind = .reopened }
        else if to == .inProgress { kind = .started }
        else if to == .inReview { kind = .review }
        else { kind = .statusChanged }
    }
}
