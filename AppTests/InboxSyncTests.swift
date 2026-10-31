import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class InboxSyncTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!
    private var fixture: InboxSyncFixture!
    private var client: PaperclipClient!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fixture = InboxSyncFixture()
        InboxSyncProtocol.fixture = fixture
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InboxSyncProtocol.self]
        session = URLSession(configuration: config)
        client = PaperclipClient(serverURL: URL(string: "https://inbox-sync.test")!, token: nil, session: session)
    }
    override func tearDown() async throws {
        session.invalidateAndCancel()
        InboxSyncProtocol.fixture = nil
        try? FileManager.default.removeItem(at: directory)
    }
    private func store(now: Date = .distantPast) -> InboxStore {
        InboxStore(serverURL: client.serverURL, accountID: "user", companyId: "company", directory: directory, now: now)
    }

    func testOfflineTransitionsCatchUpExactlyOnceAndReadStateSurvives() async throws {
        let first = store()
        await first.sync(client: client, companyId: "company", foreground: true)
        XCTAssertEqual(first.events.map(\.id), ["blocked"])
        first.setRead(true, ids: ["blocked"])
        fixture.advanceToCompleted()
        let relaunched = store()
        await relaunched.sync(client: client, companyId: "company", foreground: false)
        XCTAssertEqual(relaunched.events.map(\.id), ["completed", "started", "blocked"])
        XCTAssertTrue(relaunched.isRead(relaunched.events.last!))
        XCTAssertEqual(relaunched.notificationCandidates.map(\.id), ["completed", "started"])
        await relaunched.sync(client: client, companyId: "company", foreground: false)
        XCTAssertEqual(relaunched.events.count, 3)
        XCTAssertEqual(fixture.historyRequests, 2) // An unchanged task is not fetched again.
        XCTAssertEqual(store().events.count, 3)
    }

    func testFailedHistoryIsRetriedAndDoesNotErasePreviouslySavedEvents() async throws {
        let inbox = store()
        await inbox.sync(client: client, companyId: "company", foreground: true)
        fixture.advanceToCompleted()
        fixture.failHistory(true)
        await inbox.sync(client: client, companyId: "company", foreground: false)
        XCTAssertNotNil(inbox.syncError)
        XCTAssertEqual(inbox.events.map(\.id), ["blocked"])
        fixture.failHistory(false)
        await inbox.sync(client: client, companyId: "company", foreground: false)
        XCTAssertNil(inbox.syncError)
        XCTAssertEqual(inbox.events.count, 3)
        XCTAssertEqual(fixture.historyRequests, 3)
    }

    func testFirstImportShowsHistoryWithoutNotifyingAboutOldEvents() async throws {
        fixture.advanceToCompleted()
        let inbox = store(now: .now)
        await inbox.sync(client: client, companyId: "company", foreground: false)
        XCTAssertEqual(inbox.events.count, 3)
        XCTAssertEqual(inbox.unreadCount, 3)
        XCTAssertTrue(inbox.notificationCandidates.isEmpty)
    }
}

private final class InboxSyncProtocol: URLProtocol, @unchecked Sendable {
    static var fixture: InboxSyncFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "inbox-sync.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.fixture!.response(for: request.url!.path)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                              headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class InboxSyncFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var fails = false
    private var requests = 0
    var historyRequests: Int { lock.withLock { requests } }
    func advanceToCompleted() { lock.withLock { completed = true } }
    func failHistory(_ fail: Bool) { lock.withLock { fails = fail } }
    func response(for path: String) -> (Int, String) {
        lock.withLock {
            if path == "/api/companies/company/issues" {
                return (200, #"[{"id":"task","companyId":"company","title":"Offline task","status":"\#(completed ? "done" : "blocked")","priority":"medium","updatedAt":"2026-10-21T10:\#(completed ? "30" : "00"):00Z"}]"#)
            }
            if path == "/api/issues/task/activity" {
                requests += 1
                if fails { return (503, #"{"error":"temporary history failure"}"#) }
                let blocked = #"{"id":"blocked","action":"issue.updated","createdAt":"2026-10-21T10:00:00Z","details":{"status":"blocked","_previous":{"status":"in_progress"}}}"#
                let started = #"{"id":"started","action":"issue.updated","createdAt":"2026-10-21T10:20:00Z","details":{"status":"in_progress","_previous":{"status":"blocked"}}}"#
                let done = #"{"id":"completed","action":"issue.updated","createdAt":"2026-10-21T10:30:00Z","details":{"status":"done","_previous":{"status":"in_progress"}}}"#
                return (200, completed ? "[\(done),\(started),\(blocked)]" : "[\(blocked)]")
            }
            return (404, #"{"error":"unexpected test request"}"#)
        }
    }
}
