import Foundation
import PaperclipKit

enum StatsRange: Int, CaseIterable, Identifiable {
    case week = 7, twoWeeks = 14
    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { AppL10n.text("stats.recent_days", "Last \(days) days") }
}

enum StatsScope: String, CaseIterable, Identifiable {
    case main, all
    var id: String { rawValue }
    var label: String { self == .main ? AppL10n.text("stats.main_tasks", "Main tasks") : AppL10n.text("stats.all_tasks", "All tasks") }
}

/// Task throughput and wall-clock cycle times. Runs are intentionally a separate dataset.
struct CompanyStats {
    enum FlowKind: String, CaseIterable {
        case created, completed
        var label: String {
            switch self {
            case .created: return AppL10n.text("stats.created", "Created")
            case .completed: return AppL10n.text("stats.completed", "Completed")
            }
        }
    }
    struct FlowPoint: Identifiable {
        let date: Date
        let kind: FlowKind
        let count: Int
        var id: String { "\(date.timeIntervalSince1970)-\(kind.rawValue)" }
    }
    struct TimedIssue: Identifiable {
        let issue: Issue
        let duration: TimeInterval
        var id: String { issue.id }
    }
    struct Contribution: Identifiable {
        let id: String
        let agent: Agent?
        let name: String
        let count: Int
        let median: TimeInterval?
    }
    let range: StatsRange
    let scope: StatsScope
    let start: Date
    let now: Date
    let previousStart: Date
    let previousEnd: Date
    let days: [Date]
    let domain: ClosedRange<Date>
    let completed: [Issue]
    let created: Int
    let previousCompleted: Int
    let completedSubtasks: Int
    let missingCompletionDates: Int
    let timed: [TimedIssue]
    let median: TimeInterval?
    let previousMedian: TimeInterval?
    let p90: TimeInterval?
    let flow: [FlowPoint]
    let contributions: [Contribution]

    init(issues: [Issue], agents: [Agent], range: StatsRange, scope: StatsScope,
         now: Date = .now, calendar: Calendar = .current) {
        self.range = range
        self.scope = scope
        self.now = now
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 1 - range.days, to: today)!
        let previousStart = calendar.date(byAdding: .day, value: -range.days, to: start)!
        let previousEnd = calendar.date(byAdding: .day, value: -range.days, to: now)!
        self.start = start
        self.previousStart = previousStart
        self.previousEnd = previousEnd
        days = (0..<range.days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        domain = start...calendar.date(byAdding: .day, value: 1, to: today)!
        var seen = Set<String>()
        let unique = issues.filter { seen.insert($0.id).inserted }
        let scoped = unique.filter { scope == .all || $0.parentId == nil }
        func inWindow(_ date: Date?, _ from: Date, _ until: Date) -> Bool {
            guard let date else { return false }
            return date >= from && date <= until
        }
        let completed = scoped.filter { $0.status == .done && inWindow($0.completedAt, start, now) }
        self.completed = completed
        let previous = scoped.filter { $0.status == .done && inWindow($0.completedAt, previousStart, previousEnd) }
        previousCompleted = previous.count
        created = scoped.filter { inWindow($0.createdAt, start, now) }.count
        completedSubtasks = unique.filter { $0.parentId != nil && $0.status == .done && inWindow($0.completedAt, start, now) }.count
        missingCompletionDates = scoped.filter { $0.status == .done && $0.completedAt == nil }.count
        timed = Self.timedIssues(completed)
        median = Self.median(timed.map(\.duration))
        previousMedian = Self.median(Self.timedIssues(previous).map(\.duration))
        let sorted = timed.map(\.duration).sorted()
        p90 = sorted.count >= 10 ? sorted[Int(ceil(Double(sorted.count) * 0.9)) - 1] : nil
        flow = days.flatMap { day in
            [FlowPoint(date: day, kind: .created, count: scoped.filter {
                inWindow($0.createdAt, start, now) && calendar.isDate($0.createdAt!, inSameDayAs: day)
            }.count),
             FlowPoint(date: day, kind: .completed, count: completed.filter {
                 calendar.isDate($0.completedAt!, inSameDayAs: day)
             }.count)]
        }
        let grouped = Dictionary(grouping: completed) { issue in
            if let id = issue.assigneeAgentId { return "agent:\(id)" }
            if let id = issue.assigneeUserId { return "user:\(id)" }
            return "unassigned"
        }
        contributions = grouped.compactMap { key, tasks -> Contribution? in
            let agent = tasks.first?.assigneeAgentId.flatMap { id in agents.first { $0.id == id } }
            guard !key.hasPrefix("agent:") || agent != nil else { return nil }
            let name = agent?.name ?? (key.hasPrefix("user:") ? AppL10n.text("stats.board_member", "Board member") : AppL10n.text("stats.unassigned", "Unassigned"))
            return Contribution(id: key, agent: agent, name: name, count: tasks.count,
                                median: Self.median(Self.timedIssues(tasks).map(\.duration)))
        }.sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }

    static func timedIssues(_ issues: [Issue]) -> [TimedIssue] {
        issues.compactMap { issue in
            guard let duration = TaskTiming.interval(from: issue.createdAt, to: issue.completedAt) else { return nil }
            return TimedIssue(issue: issue, duration: duration)
        }.sorted { $0.duration == $1.duration ? $0.id < $1.id : $0.duration > $1.duration }
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

struct RunStatistics {
    struct Day: Identifiable {
        let date: Date
        let succeeded: Int
        let recovered: Int
        let failed: Int
        let other: Int
        var id: Date { date }
        var total: Int { succeeded + recovered + failed + other }
    }
    enum Kind: String, CaseIterable {
        case succeeded, recovered, failed, other
        var label: String {
            switch self {
            case .succeeded: return AppL10n.text("stats.run_succeeded", "Succeeded")
            case .recovered: return AppL10n.text("stats.run_recovered", "Recovered by retry")
            case .failed: return AppL10n.text("stats.run_failed", "Unrecovered failures")
            case .other: return AppL10n.text("stats.other", "Other")
            }
        }
    }
    struct Segment: Identifiable {
        let date: Date
        let kind: Kind
        let count: Int
        var id: String { "\(date.timeIntervalSince1970)-\(kind.rawValue)" }
    }
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    static func dayLabel(_ date: Date, locale: Locale = AppL10n.locale) -> String {
        var style = Date.FormatStyle().month(.defaultDigits).day()
        style.locale = locale
        style.timeZone = calendar.timeZone
        style.calendar = calendar
        return date.formatted(style)
    }
    let days: [Day]
    let domain: ClosedRange<Date>
    let failureReasons: [(code: String, count: Int)]
    let requestedDays: Int
    let supplied: Bool
    var succeeded: Int { days.reduce(0) { $0 + $1.succeeded } }
    var recovered: Int { days.reduce(0) { $0 + $1.recovered } }
    var failed: Int { days.reduce(0) { $0 + $1.failed } }
    var total: Int { days.reduce(0) { $0 + $1.total } }
    var segments: [Segment] {
        days.flatMap { day in
            [Segment(date: day.date, kind: .succeeded, count: day.succeeded),
             Segment(date: day.date, kind: .recovered, count: day.recovered),
             Segment(date: day.date, kind: .failed, count: day.failed),
             Segment(date: day.date, kind: .other, count: day.other)]
        }
    }

    init(activity: [DashboardSummary.RunActivityDay]?, range: StatsRange, now: Date = .now) {
        supplied = activity != nil
        requestedDays = range.days
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 1 - range.days, to: today)!
        domain = start...calendar.date(byAdding: .day, value: 1, to: today)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var records: [Date: DashboardSummary.RunActivityDay] = [:]
        for row in activity ?? [] {
            guard let date = formatter.date(from: row.date), formatter.string(from: date) == row.date,
                  date >= start, date <= today else { continue }
            records[date] = row
        }
        days = records.map { date, row in
            Day(date: date, succeeded: row.succeeded, recovered: row.recovered ?? 0, failed: row.failed,
                other: row.other ?? max(0, row.total - row.succeeded - row.failed - (row.recovered ?? 0)))
        }.sorted { $0.date < $1.date }
        var reasons: [String: Int] = [:]
        for row in records.values {
            for (code, count) in row.failedByErrorCode ?? [:] where count > 0 { reasons[code, default: 0] += count }
        }
        failureReasons = reasons.map { (code: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.code < $1.code : $0.count > $1.count
        }
    }
}
