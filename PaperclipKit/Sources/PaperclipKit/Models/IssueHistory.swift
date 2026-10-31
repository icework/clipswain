import Foundation

public struct IssueRun: Codable, Hashable, Sendable, Identifiable {
    public var runId: String
    public var status: String
    public var agentId: String?
    public var createdAt: Date?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var retryOfRunId: String?
    public var contextIssueId: String?
    public var id: String { runId }

    public func duration(at now: Date) -> TimeInterval? {
        TaskTiming.runDuration(status: status, start: startedAt, finish: finishedAt, now: now)
    }
}

public struct IssueActivity: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var action: String
    public var actorType: String?
    public var actorId: String?
    public var runId: String?
    public var details: JSONValue?
    public var createdAt: Date

    /// A status echoed in a PATCH is not evidence of a transition.
    public var statusChange: (from: IssueStatus, to: IssueStatus)? {
        guard action == "issue.updated" else { return nil }
        let old = details?["changes"]?["status"]?["from"]?.stringValue
            ?? details?["_previous"]?["status"]?.stringValue
            ?? details?["reopenedFrom"]?.stringValue
        let new = details?["changes"]?["status"]?["to"]?.stringValue
            ?? details?["status"]?.stringValue
        guard let old, let new, old != new,
              let from = IssueStatus(rawValue: old), let to = IssueStatus(rawValue: new),
              from != .unknown, to != .unknown else { return nil }
        return (from, to)
    }
}

public enum TaskTiming {
    public static func interval(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end, end >= start else { return nil }
        return end.timeIntervalSince(start)
    }

    public static func elapsed(_ issue: Issue, at now: Date) -> TimeInterval? {
        let end: Date?
        switch issue.status {
        case .done: end = issue.completedAt
        case .cancelled: end = issue.cancelledAt
        case .unknown: end = nil
        default: end = now // Ignore stale terminal timestamps after reopening.
        }
        return interval(from: issue.createdAt, to: end)
    }

    public static func runDuration(status: String, start: Date?, finish: Date?, now: Date) -> TimeInterval? {
        guard status != "queued" else { return nil }
        return interval(from: start, to: finish ?? (status == "running" ? now : nil))
    }

    public static func uniqueRuns(_ runs: [IssueRun]) -> [IssueRun] {
        // Prefer the most complete record if a refresh/page repeats a run.
        let grouped = Dictionary(grouping: runs, by: \.id)
        return grouped.values.compactMap { copies in
            copies.sorted {
                if ($0.finishedAt != nil) != ($1.finishedAt != nil) { return $0.finishedAt != nil }
                if ($0.startedAt != nil) != ($1.startedAt != nil) { return $0.startedAt != nil }
                return $0.status < $1.status
            }.first
        }.sorted {
            let a = $0.createdAt ?? $0.startedAt ?? .distantPast
            let b = $1.createdAt ?? $1.startedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a < b
        }
    }

    /// Sum of associated process wall times, not exclusive work on this issue.
    /// Queued runs contribute no execution; incomplete started/ended runs make the total unknown.
    public static func cumulative(_ runs: [IssueRun], at now: Date) -> TimeInterval? {
        var total: TimeInterval = 0
        for run in uniqueRuns(runs) where run.status != "queued" {
            guard let duration = run.duration(at: now) else { return nil }
            total += duration
        }
        return total
    }

    /// Retains the one-argument function shape used by `Optional.map(TaskTiming.text)`.
    public static func text(_ seconds: TimeInterval?) -> String {
        text(seconds, locale: nil)
    }

    public static func text(_ seconds: TimeInterval?, locale: Locale?) -> String {
        let unavailable = KitL10n.string("timing.incomplete", defaultValue: "Timing unavailable", locale: locale)
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return unavailable }
        if seconds > 0 && seconds < 1 {
            return KitL10n.string("timing.less_than_second", defaultValue: "Less than 1 second", locale: locale)
        }
        // Format complete seconds only. Waiting and execution keep their existing timing semantics.
        let value = floor(seconds)
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale ?? KitL10n.formattingLocale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        if value >= 86400 { formatter.allowedUnits = [.day, .hour] }
        else if value >= 3600 { formatter.allowedUnits = [.hour, .minute] }
        else if value >= 60 { formatter.allowedUnits = [.minute, .second] }
        else { formatter.allowedUnits = [.second] }
        return formatter.string(from: value) ?? unavailable
    }
}
