import XCTest
import PaperclipKit
import UserNotifications
@testable import Clipswain

@MainActor
final class NotificationDeliveryTests: XCTestCase {
    private var directory: URL!
    private let server = URL(string: "https://notification-delivery.test")!

    override func setUp() async throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    private func store() -> InboxStore {
        InboxStore(serverURL: server, accountID: "user", companyId: "company", directory: directory,
                   now: Date(timeIntervalSinceReferenceDate: 0))
    }
    private func item(_ id: String, kind: String, issueId: String? = "task", subjectKind: String = "issue") throws -> AttentionItem {
        var object: [String: Any] = ["id": id, "sourceKind": kind, "subject": ["kind": subjectKind, "id": id, "title": "Needs action"],
                                     "activityAt": 50, "whyNow": "Please respond"]
        if let issueId {
            object["relatedIssue"] = ["kind": "issue", "id": issueId, "title": "Task"]
            if subjectKind == "issue" { object["subject"] = ["kind": "issue", "id": issueId, "title": "Needs action"] }
        }
        return try JSONDecoder().decode(AttentionItem.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func seedEvent(_ store: InboxStore, status: String = "blocked", id: String = "event", at: Int = 40) throws {
        let issue = Issue(id: "task", companyId: "company", title: "Task", status: IssueStatus(rawValue: status)!, priority: .medium)
        let activity = try JSONDecoder().decode(IssueActivity.self, from: Data("{\"id\":\"\(id)\",\"action\":\"issue.updated\",\"createdAt\":\(at),\"details\":{\"status\":\"\(status)\",\"_previous\":{\"status\":\"in_progress\"}}}".utf8))
        store.ingest([activity], for: issue)
    }

    func testQuestionsApprovalsAndFailuresDeliverWithoutAnyTaskTransition() async throws {
        let inbox = store()
        let items = [try item("question", kind: "issue_thread_interaction"),
                     try item("approval", kind: "approval", issueId: nil, subjectKind: "approval"),
                     try item("failure", kind: "failed_run", subjectKind: "heartbeat_run")]
        var sent: [UNNotificationRequest] = []
        await AttentionNotifier.notifyNew(inbox, attention: items, deliver: { sent.append($0) }, updateBadge: { _ in })
        XCTAssertEqual(Set(sent.map(\.identifier)), ["attention.question", "attention.approval", "attention.failure"])
        let approval = try XCTUnwrap(sent.first { $0.identifier == "attention.approval" })
        XCTAssertEqual(NotificationDestination(userInfo: approval.content.userInfo)?.approvalId, "approval")
        XCTAssertTrue(sent.allSatisfy { NotificationDestination(userInfo: $0.content.userInfo)?.scope == inbox.scope })
        XCTAssertTrue(inbox.events.isEmpty)
        let restored = store()
        sent = []
        await AttentionNotifier.notifyNew(restored, attention: items, deliver: { sent.append($0) }, updateBadge: { _ in })
        XCTAssertTrue(sent.isEmpty)
    }

    func testBlockedAndReviewStatusDoNotAlsoSendAttentionAlerts() async throws {
        for (status, kind) in [("blocked", "blocker_attention"), ("in_review", "review")] {
            let inbox = store()
            try seedEvent(inbox, status: status)
            let attention = try item("duplicate-" + status, kind: kind)
            var sent: [String] = []
            await AttentionNotifier.notifyNew(inbox, attention: [attention], deliver: { sent.append($0.identifier) }, updateBadge: { _ in })
            XCTAssertEqual(sent, ["inbox.event"])
            sent = []
            await AttentionNotifier.notifyNew(inbox, attention: [attention], deliver: { sent.append($0.identifier) }, updateBadge: { _ in })
            XCTAssertTrue(sent.isEmpty)
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testBlockedFilterAlsoSuppressesAttentionFallbackButNotQuestions() async throws {
        let inbox = store()
        inbox.setEnabled(false, kind: .blocked)
        let items = [try item("blocked", kind: "blocker_attention"), try item("question", kind: "issue_thread_interaction")]
        var sent: [String] = []
        await AttentionNotifier.notifyNew(inbox, attention: items, deliver: { sent.append($0.identifier) }, updateBadge: { _ in })
        XCTAssertEqual(sent, ["attention.question"])
    }

    func testAttentionFallbackStillDeliversWhenHistoryIsUnavailable() async throws {
        let inbox = store()
        let blocked = try item("blocked", kind: "blocker_attention")
        var sent: [String] = []
        await AttentionNotifier.notifyNew(inbox, attention: [blocked, blocked], deliver: { sent.append($0.identifier) }, updateBadge: { _ in })
        XCTAssertEqual(sent, ["attention.blocked"])
    }

    func testFailedDeliveryRetriesAndDoesNotMarkAnythingRead() async throws {
        let inbox = store()
        try seedEvent(inbox)
        let question = try item("question", kind: "issue_thread_interaction")
        await AttentionNotifier.notifyNew(inbox, attention: [question], deliver: { _ in throw CocoaError(.fileWriteUnknown) }, updateBadge: { _ in })
        XCTAssertEqual(inbox.notificationCandidates.count, 1)
        XCTAssertTrue(inbox.shouldNotifyAttention(question))
        var sent: [String] = []
        await AttentionNotifier.notifyNew(inbox, attention: [question], deliver: { sent.append($0.identifier) }, updateBadge: { _ in })
        XCTAssertEqual(Set(sent), ["inbox.event", "attention.question"])
        XCTAssertFalse(inbox.isRead(inbox.events[0]))
        XCTAssertTrue(inbox.notificationCandidates.isEmpty)
    }

    func testFallbackReceiptSurvivesRelaunchAndSuppressesOnlyTheOriginalOccurrence() async throws {
        for (status, kind) in [("blocked", "blocker_attention"), ("in_review", "review")] {
            let inbox = store()
            let fallback = try item("fallback", kind: kind)
            var sent: [String] = []
            await AttentionNotifier.notifyNew(inbox, attention: [fallback], deliver: { sent.append($0.identifier) },
                                             updateBadge: { _ in }, now: { Date(timeIntervalSinceReferenceDate: 60) })
            XCTAssertEqual(sent, ["attention.fallback"])
            let restored = store()
            try seedEvent(restored, status: status)
            // The new transition is after the server snapshot (50) but before delivery (60).
            try seedEvent(restored, status: status, id: "later-occurrence", at: 55)
            sent = []
            await AttentionNotifier.notifyNew(restored, attention: [fallback], deliver: { sent.append($0.identifier) }, updateBadge: { _ in })
            XCTAssertEqual(sent, ["inbox.later-occurrence"])
            XCTAssertEqual(restored.events.count, 2)
            XCTAssertEqual(restored.unreadCount, 2) // Delivery deduplication never changes reading state.
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testBlockedTransitionTimestampHandlesLaterActivityCommitWithoutSuppressingNewBlock() async throws {
        let inbox = store()
        let fallback = try item("fallback", kind: "blocker_attention")
        await AttentionNotifier.notifyNew(inbox, attention: [fallback], deliver: { _ in }, updateBadge: { _ in },
                                         now: { Date(timeIntervalSinceReferenceDate: 60) })
        let activity = try JSONDecoder().decode(IssueActivity.self, from: Data(#"{"id":"original","action":"issue.updated","createdAt":51,"details":{"status":"blocked","_previous":{"status":"in_progress"},"changes":{"blockedTransitionAt":{"to":"2001-01-01T00:00:50Z"}}}}"#.utf8))
        inbox.ingest([activity], for: Issue(id: "task", companyId: "company", title: "Task", status: .blocked, priority: .medium))
        try seedEvent(inbox, id: "new-block", at: 55)
        XCTAssertEqual(inbox.notificationCandidates.map(\.id), ["new-block"])
        XCTAssertEqual(inbox.unreadCount, 2)
    }

    func testAttentionPreferencePersistsAndDoesNotDisableTaskEvents() async throws {
        let inbox = store()
        XCTAssertTrue(inbox.attentionNotificationsEnabled)
        inbox.setAttentionNotificationsEnabled(false)
        let restored = store()
        XCTAssertFalse(restored.attentionNotificationsEnabled)
        try seedEvent(restored, status: "done")
        var sent: [String] = []
        await AttentionNotifier.notifyNew(restored, attention: [try item("question", kind: "issue_thread_interaction")],
                                         deliver: { sent.append($0.identifier) }, updateBadge: { _ in })
        XCTAssertEqual(sent, ["inbox.event"])
    }

    func testConcurrentChecksDoNotDeliverTheSameNotificationTwice() async throws {
        let inbox = store()
        let question = try item("question", kind: "issue_thread_interaction")
        let started = expectation(description: "delivery in flight")
        var resume: CheckedContinuation<Void, Never>?
        var sent = 0
        let first = Task {
            await AttentionNotifier.notifyNew(inbox, attention: [question], deliver: { _ in
                sent += 1
                await withCheckedContinuation { resume = $0; started.fulfill() }
            }, updateBadge: { _ in })
        }
        await fulfillment(of: [started], timeout: 2)
        await AttentionNotifier.notifyNew(inbox, attention: [question], deliver: { _ in sent += 1 }, updateBadge: { _ in })
        resume?.resume()
        await first.value
        XCTAssertEqual(sent, 1)
    }

    func testSessionChangeStopsRemainingNotificationsAndBadgeWrites() async throws {
        let inbox = store()
        let items = [try item("question", kind: "issue_thread_interaction"), try item("failure", kind: "failed_run")]
        var active = true
        var sent = 0
        var badges = 0
        await AttentionNotifier.notifyNew(inbox, attention: items, deliver: { _ in sent += 1; active = false },
                                         updateBadge: { _ in badges += 1 }, shouldContinue: { active })
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(badges, 0)
        XCTAssertEqual(items.filter(inbox.shouldNotifyAttention).count, 1)
    }
}
