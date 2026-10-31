import XCTest
import PaperclipKit
@testable import Clipswain

final class TaskListSnapshotTests: XCTestCase {
    private func issue(_ id: String, _ status: IssueStatus, assignee: String? = nil,
                       title: String = "Task", priority: IssuePriority = .medium, updated: TimeInterval = 0) -> Issue {
        Issue(id: id, companyId: "company", title: title, status: status, priority: priority,
              identifier: "NOR-\(id)", assigneeAgentId: assignee, updatedAt: Date(timeIntervalSince1970: updated))
    }

    func testHistoricalVolumeDoesNotChangeCurrentWork() {
        let active = [issue("a", .blocked), issue("b", .inProgress), issue("c", .inReview),
                      issue("d", .todo), issue("e", .backlog)]
        let history = (0..<200).map { issue("history-\($0)", .done) } + [issue("cancelled", .cancelled)]
        let before = TaskListSnapshot(issues: active)
        let after = TaskListSnapshot(issues: active + history)
        for bucket in TaskListFilter.work + [.current] {
            XCTAssertEqual(before.count(bucket), after.count(bucket))
        }
        XCTAssertEqual(after.count(.current), 5)
        XCTAssertEqual(after.count(.done), 200)
        XCTAssertEqual(after.count(.cancelled), 1)
        XCTAssertEqual(after.count(.all), 206)
    }

    func testDefaultQueueIncludesBlockedAndWaitingIsTodoPlusBacklog() {
        let snapshot = TaskListSnapshot(issues: [issue("1", .blocked), issue("2", .todo), issue("3", .backlog)])
        XCTAssertEqual(snapshot.matching(.current).map(\.id), ["1", "2", "3"])
        XCTAssertEqual(snapshot.matching(.waiting).map(\.id), ["2", "3"])
        XCTAssertEqual(snapshot.sections(for: .current).map(\.0), [.blocked, .todo, .backlog])
    }

    func testOverviewAndListUseSameAssigneeAndSearchScope() {
        let snapshot = TaskListSnapshot(issues: [
            issue("1", .blocked, assignee: "a", title: "Fix login"),
            issue("2", .done, assignee: "a", title: "Login tests"),
            issue("3", .blocked, assignee: "b", title: "Fix login"),
            issue("4", .todo, assignee: "a", title: "Write documentation"),
        ], assigneeID: "a", search: "  LOGIN \n")
        XCTAssertEqual(snapshot.scoped.map(\.id), ["1", "2"])
        XCTAssertEqual(snapshot.count(.current), 1)
        XCTAssertEqual(snapshot.count(.blocked), 1)
        XCTAssertEqual(snapshot.count(.done), 1)
        XCTAssertEqual(snapshot.matching(.blocked).map(\.id), ["1"])
        XCTAssertEqual(snapshot.count(.all), 2)
    }

    func testSearchByIdentifierAndWhitespace() {
        let issues = [issue("42", .todo), issue("24", .done)]
        XCTAssertEqual(TaskListSnapshot(issues: issues, search: "nor-42").scoped.map(\.id), ["42"])
        XCTAssertEqual(TaskListSnapshot(issues: issues, search: " \n ").count(.all), 2)
    }

    func testUnknownStatusIsVisibleWithoutPretendingItIsOpenOrCompleted() {
        let snapshot = TaskListSnapshot(issues: [issue("unknown", .unknown), issue("cancelled", .cancelled)])
        XCTAssertEqual(snapshot.count(.current), 0)
        XCTAssertEqual(snapshot.count(.done), 0)
        XCTAssertEqual(snapshot.matching(.other).map(\.id), ["unknown"])
        XCTAssertEqual(snapshot.sections(for: .all).map(\.0), [.cancelled, .unknown])
    }

    func testHistorySortUsesCompletionDateBeforePriorityAndLaterEdits() {
        var old = issue("old", .done, priority: .critical, updated: 900)
        old.completedAt = Date(timeIntervalSince1970: 100)
        var recent = issue("recent", .done, priority: .low, updated: 400)
        recent.completedAt = Date(timeIntervalSince1970: 400)
        let snapshot = TaskListSnapshot(issues: [old, recent])
        XCTAssertEqual(snapshot.sections(for: .done).first?.1.map(\.id), ["recent", "old"])
    }

    func testActiveSortUsesPriorityThenRecencyAndStableTieBreak() {
        let snapshot = TaskListSnapshot(issues: [
            issue("low", .todo, priority: .low, updated: 1000),
            issue("old", .todo, priority: .high, updated: 100),
            issue("b", .todo, priority: .high, updated: 300),
            issue("a", .todo, priority: .high, updated: 300),
        ])
        XCTAssertEqual(snapshot.sections(for: .current).first?.1.map(\.id), ["a", "b", "old", "low"])
        XCTAssertTrue(TaskListSnapshot(issues: []).sections(for: .current).isEmpty)
    }
}
