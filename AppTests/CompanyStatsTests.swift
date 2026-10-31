import XCTest
import PaperclipKit
@testable import Clipswain

final class CompanyStatsTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    func date(_ value: String) -> Date { PaperclipJSON.parseDate(value)! }
    var now: Date { date("2026-10-21T05:00:00Z") } // Oct 20, 22:00 local
    func issue(_ id: String, parent: String? = nil, start: Date? = nil, end: Date? = nil,
               status: IssueStatus = .done, agent: String? = nil) -> Issue {
        var issue = Issue(id: id, companyId: "c", title: id, status: status, priority: .medium,
                          assigneeAgentId: agent, parentId: parent)
        issue.createdAt = start ?? date("2026-10-20T07:00:00Z")
        issue.completedAt = end
        return issue
    }
    func stats(_ issues: [Issue], scope: StatsScope = .main) -> CompanyStats {
        CompanyStats(issues: issues, agents: [], range: .week, scope: scope, now: now, calendar: calendar)
    }
    func testParentAndChildScopesDoNotDoubleCountDelivery() {
        let parent = issue("parent", end: now)
        let child = issue("child", parent: parent.id, end: now)
        XCTAssertEqual(stats([parent, child, parent]).completed.count, 1)
        XCTAssertEqual(stats([parent, child]).completedSubtasks, 1)
        XCTAssertEqual(stats([parent, child], scope: .all).completed.count, 2)
        XCTAssertEqual(stats([parent, child]).created, 1)
    }
    func testMissingFutureAndReopenedCompletionsAreExcluded() {
        let items = [issue("valid", end: now), issue("missing"), issue("future", end: now.addingTimeInterval(1)),
                     issue("reopened", end: now, status: .todo), issue("cancelled", end: now, status: .cancelled)]
        let result = stats(items)
        XCTAssertEqual(result.completed.map(\.id), ["valid"])
        XCTAssertEqual(result.missingCompletionDates, 1)
    }
    func testElapsedUsesCreationNotStartAndRejectsBadDates() {
        var task = issue("waiting", start: now.addingTimeInterval(-3600), end: now)
        task.startedAt = now.addingTimeInterval(-30)
        let bad = issue("bad", start: now.addingTimeInterval(10), end: now)
        let result = stats([task, bad])
        XCTAssertEqual(result.completed.count, 2)
        XCTAssertEqual(result.timed.count, 1)
        XCTAssertEqual(result.median, 3600)
        XCTAssertNil(result.p90)
    }
    func testP90AndEvenMedianUseValidSamplesOnly() {
        let tasks = (1...10).map { issue("\($0)", start: now.addingTimeInterval(-Double($0 * 60)), end: now) }
        let result = stats(tasks)
        XCTAssertEqual(result.median, 330)
        XCTAssertEqual(result.p90, 540)
        XCTAssertEqual(result.timed.prefix(3).map(\.id), ["10", "9", "8"])
    }
    func testPreviousPeriodEndsAtCorrespondingLocalTime() {
        let end = calendar.date(byAdding: .day, value: -7, to: now)!
        let onBoundary = issue("boundary", start: end.addingTimeInterval(-60), end: end)
        let tooLate = issue("later", start: end, end: end.addingTimeInterval(1))
        let result = stats([onBoundary, tooLate])
        XCTAssertEqual(result.previousCompleted, 1)
        XCTAssertEqual(result.previousMedian, 60)
        XCTAssertEqual(result.days.count, 7)
        XCTAssertEqual(calendar.component(.hour, from: result.start), 0)
        XCTAssertEqual(calendar.component(.hour, from: result.previousEnd), 22)
    }
    func testContributionHidesMissingAgentWithoutDroppingTaskMetrics() {
        var human = issue("human", end: now)
        human.assigneeUserId = "person"
        let paused = Agent(id: "paused", companyId: "c", name: "Paused Agent", role: "engineer", status: .paused, adapterType: "test")
        let result = CompanyStats(issues: [issue("unknown", end: now, agent: "removed"), human,
                                          issue("unassigned", end: now), issue("known", end: now, agent: paused.id)],
                                  agents: [paused], range: .week, scope: .main, now: now, calendar: calendar)
        XCTAssertEqual(result.contributions.reduce(0) { $0 + $1.count }, 3)
        XCTAssertEqual(Set(result.contributions.map(\.id)), ["agent:paused", "user:person", "unassigned"])
        XCTAssertEqual(result.completed.count, 4)
        XCTAssertEqual(result.timed.count, 4)
        XCTAssertEqual(result.median, 79200)
    }
    func testRunBucketsKeepRecoveredSeparateAndUseUTCDate() throws {
        let json = #"[{"date":"2026-10-21","succeeded":7,"failed":5,"recovered":2,"other":1,"total":15,"failedByErrorCode":{"timeout":5}},{"date":"2026-10-22","succeeded":99,"failed":0,"total":99}]"#
        let rows = try JSONDecoder().decode([DashboardSummary.RunActivityDay].self, from: Data(json.utf8))
        let runs = RunStatistics(activity: rows + [rows[0]], range: .week, now: now)
        XCTAssertEqual(runs.succeeded, 7)
        XCTAssertEqual(runs.recovered, 2)
        XCTAssertEqual(runs.failed, 5)
        XCTAssertEqual(runs.total, 15)
        XCTAssertEqual(runs.days.count, 1)
        XCTAssertEqual(runs.days.first?.date, date("2026-10-21T00:00:00Z"))
        XCTAssertEqual(RunStatistics.dayLabel(runs.days.first!.date, locale: Locale(identifier: "en_US")), "10/21")
        XCTAssertEqual(runs.failureReasons.first?.count, 5)
        XCTAssertFalse(RunStatistics(activity: nil, range: .week, now: now).supplied)
    }
    func testDSTRangeStillUsesCalendarDays() {
        let result = CompanyStats(issues: [], agents: [], range: .week, scope: .main,
                                  now: date("2026-11-03T06:00:00Z"), calendar: calendar)
        XCTAssertEqual(result.days.count, 7)
        XCTAssertTrue(result.days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        XCTAssertEqual(calendar.component(.hour, from: result.previousEnd), 22)
    }
}
