import XCTest
@testable import PaperclipKit

final class InboxEventTests: XCTestCase {
    private let issue = Issue(id: "task", companyId: "company", title: "Current title", status: .done, priority: .medium)

    private func activity(_ details: String, action: String = "issue.updated", id: String = "event") throws -> IssueActivity {
        try JSONDecoder().decode(IssueActivity.self, from: Data("{\"id\":\"\(id)\",\"action\":\"\(action)\",\"createdAt\":10,\"details\":\(details)}".utf8))
    }

    func testBlockedAndCompletedAreHistoricalOccurrencesDespiteCurrentStatus() throws {
        let blocked = try activity(#"{"status":"blocked","_previous":{"status":"in_progress"}}"#)
        let event = try XCTUnwrap(InboxEvent(activity: blocked, issue: issue))
        XCTAssertEqual(event.kind, .blocked)
        XCTAssertEqual(event.status, .blocked)
        XCTAssertEqual(event.previousStatus, .inProgress)
        let completed = try activity(#"{"changes":{"status":{"from":"blocked","to":"done"}}}"#, id: "completed")
        XCTAssertEqual(InboxEvent(activity: completed, issue: issue)?.kind, .completed)
    }

    func testEchoMissingPreviousAndUnknownStatusDoNotInventTransitions() throws {
        for details in [#"{"status":"blocked","_previous":{"status":"blocked"}}"#,
                        #"{"status":"done"}"#,
                        #"{"status":"future_state","_previous":{"status":"todo"}}"#] {
            XCTAssertNil(InboxEvent(activity: try activity(details), issue: issue))
        }
    }

    func testCreatedCheckoutReleaseAndReopenedKinds() throws {
        let cases: [(String, String, InboxEventKind)] = [
            ("issue.created", #"{"title":"Original title","status":"todo"}"#, .created),
            ("issue.checked_out", #"{"status":"in_progress","_previous":{"status":"todo"}}"#, .started),
            ("issue.released", #"{"status":"todo","_previous":{"status":"in_progress"}}"#, .statusChanged),
            ("issue.updated", #"{"status":"todo","_previous":{"status":"done"}}"#, .reopened),
            ("issue.updated", #"{"status":"in_review","_previous":{"status":"in_progress"}}"#, .review),
            ("issue.updated", #"{"status":"cancelled","_previous":{"status":"todo"}}"#, .cancelled),
        ]
        for (action, details, expected) in cases {
            XCTAssertEqual(InboxEvent(activity: try activity(details, action: action), issue: issue)?.kind, expected)
        }
    }

    func testServerEventIdentityTitleAndTimestampSurviveRoundTrip() throws {
        let source = try activity(#"{"status":"todo","title":"Original title","identifier":"ABC-1"}"#, action: "issue.created")
        let event = try XCTUnwrap(InboxEvent(activity: source, issue: issue))
        XCTAssertEqual(event.id, "event")
        XCTAssertEqual(event.title, "Original title")
        XCTAssertEqual(event.identifier, "ABC-1")
        XCTAssertEqual(event.date, source.createdAt)
        XCTAssertEqual(try JSONDecoder().decode(InboxEvent.self, from: JSONEncoder().encode(event)), event)
    }
}
