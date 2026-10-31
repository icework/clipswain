import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class NotificationRoutingTests: XCTestCase {
    private var app: AppModel!
    private var directory: URL!
    private var session: URLSession!
    private var savedCompany: Any?
    private let server = URL(string: "https://notification-routing.test")!

    override func setUp() async throws {
        savedCompany = UserDefaults.standard.object(forKey: "paperclip.companyId")
        UserDefaults.standard.set("company-b", forKey: "paperclip.companyId")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotificationRoutingProtocol.self]
        session = URLSession(configuration: config)
        app = AppModel(inboxDirectory: directory)
        try await app.connect(serverURL: server, token: nil, persist: false, session: session)
    }
    override func tearDown() async throws {
        session.invalidateAndCancel()
        UserDefaults.standard.set(savedCompany, forKey: "paperclip.companyId")
        try? FileManager.default.removeItem(at: directory)
    }

    private func seed(company: String, task: String, event: String) async throws -> InboxEvent {
        await app.selectCompany(company)
        let issue = Issue(id: task, companyId: company, title: task, status: .done, priority: .medium)
        let activity = try JSONDecoder().decode(IssueActivity.self, from: Data("{\"id\":\"\(event)\",\"action\":\"issue.updated\",\"createdAt\":40,\"details\":{\"status\":\"done\",\"_previous\":{\"status\":\"blocked\"}}}".utf8))
        app.inbox!.ingest([activity], for: issue)
        app.inbox!.setRead(false, ids: [event])
        return try XCTUnwrap(app.inbox?.events.first)
    }

    func testCrossCompanyEventNotificationMarksOnlyOriginArchiveRead() async throws {
        let eventA = try await seed(company: "company-a", task: "task-a", event: "event-a")
        let scopeA = app.inbox!.scope
        _ = try await seed(company: "company-b", task: "task-b", event: "event-b")
        let storeB = app.inbox!
        let opened = await app.openNotification(.init(scope: scopeA, issueId: "task-a", eventId: "event-a"))
        XCTAssertTrue(opened)
        XCTAssertEqual(app.selectedCompanyId, "company-a")
        XCTAssertEqual(app.pendingRoute, .issue("task-a"))
        XCTAssertTrue(app.inbox!.isRead(eventA))
        XCTAssertEqual(app.inbox!.unreadCount, 0)
        XCTAssertFalse(storeB.isRead(eventA))
        XCTAssertEqual(storeB.unreadCount, 1)
        await app.selectCompany("company-b")
        await app.selectCompany("company-a")
        XCTAssertTrue(app.inbox!.isRead(eventA))
    }

    func testNotificationsFromAnotherServerAccountOrInaccessibleCompanyAreRejected() async throws {
        for scope in [InboxScope(serverURL: URL(string: "https://another.test")!, accountID: "local-board", companyId: "company-a"),
                      InboxScope(serverURL: server, accountID: "another-user", companyId: "company-a"),
                      InboxScope(serverURL: server, accountID: "local-board", companyId: "inaccessible")] {
            let opened = await app.openNotification(.init(scope: scope, issueId: "task-a", eventId: "event-a"))
            XCTAssertFalse(opened)
            XCTAssertEqual(app.selectedCompanyId, "company-b")
            XCTAssertNil(app.pendingRoute)
        }
    }

    func testLegacyNotificationResolvesCompanyAndVerifiesEventBeforeMarkingRead() async throws {
        let event = try await seed(company: "company-a", task: "task-a", event: "event-a")
        await app.selectCompany("company-b")
        let opened = await app.openNotification(.init(issueId: "task-a", eventId: "event-a"))
        XCTAssertTrue(opened)
        XCTAssertEqual(app.selectedCompanyId, "company-a")
        XCTAssertTrue(app.inbox!.isRead(event))
    }

    func testLegacyUnknownEventDoesNotWriteReadStateOrSwitchCompany() async {
        let opened = await app.openNotification(.init(issueId: "task-a", eventId: "not-in-history"))
        XCTAssertFalse(opened)
        XCTAssertEqual(app.selectedCompanyId, "company-b")
        XCTAssertNil(app.pendingRoute)
    }

    func testScopedApprovalSwitchesCompanyAndKeepsApprovalRoute() async {
        let scope = InboxScope(serverURL: server, accountID: "local-board", companyId: "company-a")
        let opened = await app.openNotification(.init(scope: scope, approvalId: "approval-a"))
        XCTAssertTrue(opened)
        XCTAssertEqual(app.selectedCompanyId, "company-a")
        XCTAssertEqual(app.pendingRoute, .approval("approval-a"))
    }

    func testColdStartRouterPreservesScopeUntilHandlerIsInstalled() throws {
        let scope = InboxScope(serverURL: server, accountID: "local-board", companyId: "company-a")
        let destination = NotificationDestination(scope: scope, issueId: "task-a", eventId: "event-a")
        let router = NotificationRouter()
        router.receive(userInfo: destination.userInfo)
        var received: [NotificationDestination] = []
        router.onOpen = { received.append($0) }
        XCTAssertEqual(received, [destination])
        router.onOpen = { received.append($0) }
        XCTAssertEqual(received.count, 1)
    }

    func testPayloadRoundTripAndPartialScopeRejection() {
        let destination = NotificationDestination(scope: .init(serverURL: server, accountID: "local-board", companyId: "company-a"),
                                                 issueId: "task-a", eventId: "event-a")
        XCTAssertEqual(NotificationDestination(userInfo: destination.userInfo), destination)
        XCTAssertNil(NotificationDestination(userInfo: ["serverURL": server.absoluteString, "issueId": "task-a"]))
        XCTAssertNil(NotificationDestination(userInfo: ["serverURL": 42, "issueId": "task-a"]))
        XCTAssertNil(NotificationDestination(userInfo: ["eventId": "event-a"]))
    }
}

private final class NotificationRoutingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "notification-routing.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: String
        switch request.url!.path {
        case "/api/health": body = #"{"status":"ok","deploymentMode":"local_trusted"}"#
        case "/api/cli-auth/me": body = #"{"userId":"local-board"}"#
        case "/api/companies": body = #"[{"id":"company-a","name":"A"},{"id":"company-b","name":"B"}]"#
        case "/api/issues/task-a": body = #"{"id":"task-a","companyId":"company-a","title":"A task","status":"done","priority":"medium"}"#
        case "/api/issues/task-a/activity": body = #"[{"id":"event-a","action":"issue.updated","createdAt":"2026-10-21T10:30:00Z","details":{"status":"done","_previous":{"status":"blocked"}}}]"#
        default: body = "[]"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                              headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
