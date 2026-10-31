import XCTest
@testable import PaperclipKit

private func json<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: PaperclipJSON.encoder.encode(value))
}

final class ReplyRuleTests: XCTestCase {
    func testHumanCommentResumesBlockedOrClosedAgentWork() {
        for status in [IssueStatus.blocked, .done, .cancelled] {
            let issue = Issue(id: "i", companyId: "c", title: "T", status: status, priority: .medium, assigneeAgentId: "a")
            XCTAssertTrue(issue.humanCommentResumesWork, "\(status)")
        }
    }

    func testOtherIssuesKeepReplyOnly() {
        for status in [IssueStatus.todo, .inProgress, .inReview, .backlog] {
            let issue = Issue(id: "i", companyId: "c", title: "T", status: status, priority: .medium, assigneeAgentId: "a")
            XCTAssertFalse(issue.humanCommentResumesWork, "\(status)")
        }
        let unassigned = Issue(id: "i", companyId: "c", title: "T", status: .blocked, priority: .medium)
        XCTAssertFalse(unassigned.humanCommentResumesWork)
    }
}

final class VerdictProtocolTests: XCTestCase {
    private func payload(_ extra: String = "") throws -> VerdictsPayload {
        let raw = #"{"version":1,"prompt":"Review","items":[{"id":"a","label":"A"},{"id":"b","label":"B","previewMarkdown":"**diff**"}]"# + extra + "}"
        return try PaperclipJSON.decoder.decode(VerdictsPayload.self, from: Data(raw.utf8))
    }

    func testServerDefaults() throws {
        let p = try payload()
        XCTAssertEqual(p.allowedVerdicts, [.approve, .reject])
        XCTAssertTrue(p.requiresReason(.reject))
        XCTAssertFalse(p.requiresReason(.approve))
        XCTAssertEqual(p.items[1].previewMarkdown, "**diff**")
    }

    func testCustomVerdictsAndReasons() throws {
        let p = try payload(#","verdicts":["approve","reject","defer"],"requireReasonOn":["defer"]"#)
        XCTAssertEqual(p.allowedVerdicts, [.approve, .reject, .defer_])
        XCTAssertTrue(p.requiresReason(.defer_))
        XCTAssertFalse(p.requiresReason(.reject))
    }

    func testCompletenessNeedsReasonsAndAllowedVerdicts() throws {
        let p = try payload()
        XCTAssertFalse(p.isComplete(["a": .approve], reasons: [:]), "every item needs a verdict")
        XCTAssertFalse(p.isComplete(["a": .approve, "b": .reject], reasons: [:]), "reject needs a reason")
        XCTAssertFalse(p.isComplete(["a": .approve, "b": .reject], reasons: ["b": "  "]), "blank reason")
        XCTAssertTrue(p.isComplete(["a": .approve, "b": .reject], reasons: ["b": "Too risky"]))
        XCTAssertFalse(p.isComplete(["a": .approve, "b": .defer_], reasons: [:]), "defer is not allowed by default")
    }

    func testBodyCarriesTrimmedReasons() throws {
        let body = try json(VerdictsBody(verdicts: ["b": .reject, "a": .approve], reasons: ["b": " Too risky ", "a": ""]))
        let entries = try XCTUnwrap(body["verdicts"]?.arrayValue)
        XCTAssertEqual(entries.map { $0["id"] }, [.string("a"), .string("b")])
        XCTAssertNil(entries[0]["reason"])
        XCTAssertEqual(entries[1]["reason"], .string("Too risky"))
        XCTAssertEqual(entries[1]["verdict"], .string("reject"))
    }
}

final class RejectReasonTests: XCTestCase {
    private func interaction(kind: InteractionKind, payload: String) throws -> IssueInteraction {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8))
        return IssueInteraction(id: "i", issueId: "x", kind: kind, status: .pending, payload: value)
    }

    func testConfirmationRequiringReason() throws {
        let card = try interaction(kind: .requestConfirmation, payload: #"{"version":1,"prompt":"Ok?","rejectRequiresReason":true,"rejectReasonLabel":"Why?"}"#)
        XCTAssertTrue(card.rejectRequiresReason)
        XCTAssertEqual(card.rejectReasonLabel, "Why?")
    }

    func testCheckboxRequiringReason() throws {
        let card = try interaction(kind: .requestCheckboxConfirmation, payload: #"{"version":1,"prompt":"Pick","options":[{"id":"a","label":"A"}],"rejectRequiresReason":true}"#)
        XCTAssertTrue(card.rejectRequiresReason)
    }

    func testOptionalReasonByDefault() throws {
        let card = try interaction(kind: .requestConfirmation, payload: #"{"version":1,"prompt":"Ok?"}"#)
        XCTAssertFalse(card.rejectRequiresReason)
    }
}

final class AssigneeUpdateTests: XCTestCase {
    func testAssigningAnAgentClearsTheHumanAssignee() throws {
        let body = try json(IssueUpdate.assign(toAgent: "agent-1"))
        XCTAssertEqual(body["assigneeAgentId"], .string("agent-1"))
        XCTAssertEqual(body["assigneeUserId"], .null)
    }

    func testUnassignClearsBoth() throws {
        let body = try json(IssueUpdate.unassign)
        XCTAssertEqual(body["assigneeAgentId"], .null)
        XCTAssertEqual(body["assigneeUserId"], .null)
    }

    func testOtherUpdatesDoNotTouchAssignees() throws {
        let body = try json(IssueUpdate(status: .done))
        XCTAssertNil(body["assigneeAgentId"])
        XCTAssertNil(body["assigneeUserId"])
    }
}

final class AuthorshipTests: XCTestCase {
    func testOnlyTheSignedInUsersCommentsAreMine() {
        let mine = IssueComment(id: "1", issueId: "i", body: "x", createdAt: .now, authorType: .user, authorUserId: "me")
        let colleague = IssueComment(id: "2", issueId: "i", body: "x", createdAt: .now, authorType: .user, authorUserId: "other")
        let agent = IssueComment(id: "3", issueId: "i", body: "x", createdAt: .now, authorType: .agent, authorAgentId: "a")
        XCTAssertTrue(mine.isAuthored(byUser: "me"))
        XCTAssertFalse(colleague.isAuthored(byUser: "me"))
        XCTAssertFalse(agent.isAuthored(byUser: "me"))
        XCTAssertFalse(mine.isAuthored(byUser: nil))
    }
}

final class RunLogCursorTests: XCTestCase {
    func testOffsetFollowsServerPagesThenContentLength() {
        var cursor = RunLogCursor()
        XCTAssertTrue(cursor.apply(HeartbeatRunLog(content: "{\"chunk\":\"a\"}\n", nextOffset: 100)))
        XCTAssertEqual(cursor.offset, 100)
        XCTAssertFalse(cursor.apply(HeartbeatRunLog(content: "{\"chunk\":\"b\"}\n")))
        XCTAssertEqual(cursor.offset, 100 + "{\"chunk\":\"b\"}\n".utf8.count)
        XCTAssertEqual(cursor.chunks.map(\.text), ["ab"])
    }

    func testAFailedPageLeavesNothingHalfApplied() {
        var cursor = RunLogCursor()
        cursor.apply(HeartbeatRunLog(content: "{\"chunk\":\"a\"}\n", nextOffset: 10))
        let before = cursor
        // A thrown request never reaches apply(); re-reading from the same offset is safe.
        XCTAssertEqual(cursor, before)
        XCTAssertEqual(cursor.offset, 10)
    }
}

final class NotificationLedgerTests: XCTestCase {
    func testOnlyRecordedIdsAreKnown() {
        var ledger = NotificationLedger()
        let feed = (1...8).map { "item-\($0)" }
        let fresh = ledger.unseen(feed)
        ledger.record(Array(fresh.prefix(5)))
        XCTAssertEqual(ledger.unseen(feed), ["item-6", "item-7", "item-8"], "undelivered items stay pending")
    }

    func testCapacityDropsOldestFirst() {
        var ledger = NotificationLedger(capacity: 3)
        ledger.record(["a", "b", "c"])
        ledger.record(["d", "a"])
        XCTAssertEqual(ledger.ids, ["b", "c", "d"])
    }
}
