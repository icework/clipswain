import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class AgentStateTests: XCTestCase {
    private var app: AppModel!
    private var fixture: AgentStateFixture!
    private var session: URLSession!
    private var savedCompany: Any?

    override func setUp() async throws {
        savedCompany = UserDefaults.standard.object(forKey: "paperclip.companyId")
        fixture = AgentStateFixture()
        AgentStateProtocol.fixture = fixture
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AgentStateProtocol.self]
        session = URLSession(configuration: config)
        app = AppModel()
        try await app.connect(serverURL: URL(string: "https://agent-state.test")!, token: nil,
                              persist: false, session: session)
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        AgentStateProtocol.fixture = nil
        UserDefaults.standard.set(savedCompany, forKey: "paperclip.companyId")
    }

    func testDetailReadPublishesRunningAndIdleToListCache() async throws {
        XCTAssertEqual(app.agent("agent")?.status, .idle)
        fixture.setStatus("running")
        let detail = try await app.reloadAgent("agent")
        XCTAssertEqual(detail?.status, .running)
        XCTAssertEqual(app.agents.first?.status, .running)
        XCTAssertTrue(app.agent("agent")!.avatarPath().contains("working"))

        fixture.setStatus("idle")
        _ = try await app.reloadAgent("agent")
        XCTAssertEqual(app.agents.first?.status, .idle)
    }

    func testListRefreshUpdatesSharedDetailAndPreservesChainOfCommand() async throws {
        _ = try await app.reloadAgent("agent")
        XCTAssertEqual(app.agent("agent")?.chainOfCommand?.first?.id, "manager")
        fixture.setStatus("running")
        await app.reloadAgents()
        XCTAssertEqual(app.agent("agent")?.status, .running)
        XCTAssertEqual(app.agent("agent")?.chainOfCommand?.first?.id, "manager")

        fixture.setStatus("idle")
        await app.reloadAgents()
        XCTAssertEqual(app.agent("agent")?.status, .idle)
    }

    func testOlderListResponseCannotUndoNewerDetailRead() async throws {
        let pending = expectation(description: "idle list request held")
        fixture.holdNextList(pending)
        let list = Task { await app.reloadAgents() }
        await fulfillment(of: [pending], timeout: 2)
        fixture.setStatus("running")
        _ = try await app.reloadAgent("agent")
        fixture.releaseList()
        await list.value
        XCTAssertEqual(app.agent("agent")?.status, .running)
    }

    func testLateDetailFromPreviousCompanyDoesNotEnterSelectedCompanyCache() async throws {
        let pending = expectation(description: "detail request held")
        fixture.holdNextDetail(pending)
        let detail = Task { try await app.reloadAgent("agent") }
        await fulfillment(of: [pending], timeout: 2)
        await app.selectCompany("other")
        fixture.releaseDetail()
        let result = try await detail.value
        XCTAssertNil(result)
        XCTAssertTrue(app.agents.isEmpty)
    }
}

private final class AgentStateProtocol: URLProtocol, @unchecked Sendable {
    static var fixture: AgentStateFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "agent-state.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.fixture!.handle(self) }
    override func stopLoading() {}

    func respond(_ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class AgentStateFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = "idle"
    private var listExpectation: XCTestExpectation?
    private var detailExpectation: XCTestExpectation?
    private var pendingList: (AgentStateProtocol, String)?
    private var pendingDetail: (AgentStateProtocol, String)?

    func setStatus(_ status: String) { lock.withLock { self.status = status } }
    func holdNextList(_ expectation: XCTestExpectation) { lock.withLock { listExpectation = expectation } }
    func holdNextDetail(_ expectation: XCTestExpectation) { lock.withLock { detailExpectation = expectation } }
    func releaseList() {
        let pending = lock.withLock { let value = pendingList; pendingList = nil; return value }
        if let (request, body) = pending { request.respond(body) }
    }
    func releaseDetail() {
        let pending = lock.withLock { let value = pendingDetail; pendingDetail = nil; return value }
        if let (request, body) = pending { request.respond(body) }
    }

    func handle(_ request: AgentStateProtocol) {
        lock.lock()
        let path = request.request.url!.path
        let agent = #"{"id":"agent","companyId":"company","name":"Status Agent","role":"engineer","status":"\#(status)","adapterType":"process"}"#
        let body: String
        switch path {
        case "/api/health": body = #"{"status":"ok","deploymentMode":"local_trusted"}"#
        case "/api/cli-auth/me": body = #"{"userId":"test-board"}"#
        case "/api/companies": body = #"[{"id":"company","name":"Status Test"}]"#
        case "/api/companies/company/agents": body = "[\(agent)]"
        case "/api/agents/agent":
            body = String(agent.dropLast()) + #", "chainOfCommand":[{"id":"manager","name":"Manager"}]}"#
        default: body = "[]"
        }
        if path == "/api/companies/company/agents", let expectation = listExpectation {
            listExpectation = nil
            pendingList = (request, body)
            lock.unlock()
            expectation.fulfill()
        } else if path == "/api/agents/agent", let expectation = detailExpectation {
            detailExpectation = nil
            pendingDetail = (request, body)
            lock.unlock()
            expectation.fulfill()
        } else {
            lock.unlock()
            request.respond(body)
        }
    }
}
