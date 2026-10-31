import XCTest
import PaperclipKit
@testable import Clipswain

final class TaskHistorySnapshotTests: XCTestCase {
    func activity(_ id: String, from: String, to: String, at: Int) throws -> IssueActivity {
        try JSONDecoder().decode(IssueActivity.self, from: Data("{\"id\":\"\(id)\",\"action\":\"issue.updated\",\"createdAt\":\(at),\"details\":{\"changes\":{\"status\":{\"from\":\"\(from)\",\"to\":\"\(to)\"}}}}".utf8))
    }
    func testMissingCheckoutTransitionDoesNotInventBlockedDuration() throws {
        let issue = Issue(id: "i", companyId: "c", title: "test", status: .blocked, priority: .medium)
        let first = try activity("1", from: "in_progress", to: "blocked", at: 10)
        let second = try activity("2", from: "in_progress", to: "blocked", at: 20)
        let snapshot = TaskHistorySnapshot(issue: issue, activities: [second, first, first], runs: [], interactions: [])
        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertEqual(snapshot.entries.first?.id, "activity-1")
        XCTAssertNil(snapshot.entries.first?.end)
        XCTAssertFalse(snapshot.entries.first!.ongoing)
        XCTAssertTrue(snapshot.entries.last!.ongoing)
    }
    func testContiguousTransitionHasBoundedDuration() throws {
        let issue = Issue(id: "i", companyId: "c", title: "test", status: .todo, priority: .medium)
        let first = try activity("1", from: "in_progress", to: "blocked", at: 10)
        let second = try activity("2", from: "blocked", to: "todo", at: 30)
        let snapshot = TaskHistorySnapshot(issue: issue, activities: [first, second], runs: [], interactions: [])
        XCTAssertEqual(snapshot.entries.first!.end!.timeIntervalSince(snapshot.entries.first!.date!), 20)
    }
    func testCreationAndTerminalFallbackSurviveMissingHistory() {
        var issue = Issue(id: "i", companyId: "c", title: "test", status: .done, priority: .medium)
        issue.createdAt = Date(timeIntervalSince1970: 10)
        issue.completedAt = Date(timeIntervalSince1970: 30)
        let snapshot = TaskHistorySnapshot(issue: issue, activities: [], runs: [], interactions: [])
        XCTAssertEqual(snapshot.entries.map(\.id), ["created", "terminal"])
    }
}
