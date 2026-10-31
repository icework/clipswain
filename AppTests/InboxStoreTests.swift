import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class InboxStoreTests: XCTestCase {
    private var directory: URL!
    private let server = URL(string: "https://inbox.test")!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    private func store(server: URL? = nil, account: String = "user", company: String = "company") -> InboxStore {
        InboxStore(serverURL: server ?? self.server, accountID: account, companyId: company, directory: directory,
                   now: Date(timeIntervalSinceReferenceDate: 0))
    }
    private func issue(_ status: IssueStatus = .done, title: String = "Title") -> Issue {
        var issue = Issue(id: "task", companyId: "company", title: title, status: status, priority: .medium)
        issue.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        return issue
    }
    private func activity(_ id: String, from: String, to: String, at: Int) throws -> IssueActivity {
        try JSONDecoder().decode(IssueActivity.self, from: Data("{\"id\":\"\(id)\",\"action\":\"issue.updated\",\"createdAt\":\(at),\"details\":{\"status\":\"\(to)\",\"_previous\":{\"status\":\"\(from)\"}}}".utf8))
    }
    private func history() throws -> [IssueActivity] {
        [try activity("block-1", from: "in_progress", to: "blocked", at: 10),
         try activity("unblock", from: "blocked", to: "in_progress", at: 20),
         try activity("block-2", from: "in_progress", to: "blocked", at: 30),
         try activity("done", from: "blocked", to: "done", at: 40)]
    }

    func testRepeatedBlockEventsSurviveResolutionRefreshAndRelaunch() throws {
        let inbox = store()
        let history = try history()
        inbox.ingest(history, for: issue())
        inbox.setRead(true, ids: ["block-1"])
        inbox.ingest(history, for: issue(title: "Renamed"))
        inbox.setReadFilter(.all)
        XCTAssertEqual(inbox.events.map(\.id), ["done", "block-2", "unblock", "block-1"])
        XCTAssertEqual(inbox.events.last?.title, "Title")
        let restored = store()
        XCTAssertEqual(restored.events.count, 4)
        XCTAssertTrue(restored.isRead(restored.events.last!))
        XCTAssertEqual(restored.unreadCount, 3)
        XCTAssertFalse(restored.needsHistory(issue()))
    }

    func testFiltersPreserveReadFlagsAndHistoryAndScopeUnreadBadge() throws {
        let inbox = store()
        inbox.ingest(try history(), for: issue())
        inbox.setRead(true, ids: ["block-1"])
        inbox.setEnabled(false, kind: .completed)
        inbox.setReadFilter(.unread)
        XCTAssertEqual(inbox.visibleEvents.map(\.id), ["block-2", "unblock"])
        XCTAssertEqual(inbox.unreadCount, 2)
        XCTAssertFalse(inbox.notificationCandidates.contains { $0.kind == .completed })
        let restored = store()
        XCTAssertEqual(restored.readFilter, .unread)
        XCTAssertFalse(restored.isEnabled(.completed))
        restored.setEnabled(true, kind: .completed)
        XCTAssertEqual(restored.visibleEvents.map(\.id), ["done", "block-2", "unblock"])
        restored.setReadFilter(.read)
        XCTAssertEqual(restored.visibleEvents.map(\.id), ["block-1"])
        XCTAssertEqual(restored.unreadCount, 3) // Reading filter never changes the tab badge.
        restored.setRead(false, ids: ["block-1"])
        XCTAssertTrue(restored.visibleEvents.isEmpty)
    }

    func testDeliveredNotificationDoesNotMarkEventReadOrDeliverItTwice() throws {
        let inbox = store()
        inbox.ingest(try history(), for: issue())
        inbox.markNotified(["done"])
        XCTAssertFalse(inbox.isRead(inbox.events.first!))
        XCTAssertFalse(store().notificationCandidates.contains { $0.id == "done" })
        inbox.setRead(true, ids: ["block-2"])
        XCTAssertFalse(inbox.notificationCandidates.contains { $0.id == "block-2" })
    }

    func testArchivesAreIsolatedByServerAccountAndCompany() throws {
        let inbox = store()
        inbox.ingest(try history(), for: issue())
        inbox.setRead(true, ids: ["done"])
        XCTAssertTrue(store(server: URL(string: "https://other.test")!).events.isEmpty)
        XCTAssertTrue(store(account: "other").events.isEmpty)
        XCTAssertTrue(store(company: "other").events.isEmpty)
        let wrongCompany = store(company: "other")
        wrongCompany.ingest(try history(), for: issue())
        XCTAssertTrue(wrongCompany.events.isEmpty)
    }

    func testCorruptArchiveIsReportedAndNeverOverwritten() throws {
        store().setReadFilter(.unread)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let bytes = Data("invalid archive".utf8)
        try bytes.write(to: file)
        let inbox = store()
        XCTAssertNotNil(inbox.persistenceError)
        inbox.setReadFilter(.read)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testLocalTrustedIdentityMatchesBackgroundScopeAndSharedWriter() throws {
        let identity = try JSONDecoder().decode(BoardIdentity.self, from: Data(#"{"userId":"local-board"}"#.utf8))
        let client = PaperclipClient(serverURL: server, token: nil)
        XCTAssertEqual(InboxStore.accountID(client: client, identity: identity), InboxStore.accountID(client: client, identity: nil))
        let uniqueCompany = UUID().uuidString
        let first = InboxStore.open(serverURL: server, accountID: "test", companyId: uniqueCompany)
        XCTAssertTrue(first === InboxStore.open(serverURL: server, accountID: "test", companyId: uniqueCompany))
    }

    func testBuild12ArchiveKeepsHistoryReadFlagsAndDefaultsAttentionRemindersOn() throws {
        let inbox = store()
        inbox.ingest(try history(), for: issue())
        inbox.setRead(true, ids: ["done"])
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        archive.removeValue(forKey: "attentionNotifiedIDs")
        archive.removeValue(forKey: "attentionNotificationsEnabled")
        try JSONSerialization.data(withJSONObject: archive).write(to: file)
        let restored = store()
        XCTAssertNil(restored.persistenceError)
        XCTAssertEqual(restored.events.count, 4)
        XCTAssertTrue(restored.isRead(restored.events.first!))
        XCTAssertTrue(restored.attentionNotificationsEnabled)
    }
}
