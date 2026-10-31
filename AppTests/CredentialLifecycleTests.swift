import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class CredentialLifecycleTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var keys: MemoryBoardKeys!
    private var fixture: CredentialFixture!
    private var session: URLSession!
    private var inboxDirectory: URL!
    private var notificationsWereEnabled = false
    private let server = URL(string: "https://credential.test")!

    override func setUp() {
        super.setUp()
        suite = "PaperclipCredentialTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        keys = MemoryBoardKeys()
        fixture = CredentialFixture()
        CredentialProtocol.fixture = fixture
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CredentialProtocol.self]
        session = URLSession(configuration: configuration)
        inboxDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        notificationsWereEnabled = AttentionNotifier.isEnabled
    }

    override func tearDown() {
        session.invalidateAndCancel()
        CredentialProtocol.fixture = nil
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: inboxDirectory)
        AttentionNotifier.isEnabled = notificationsWereEnabled
        super.tearDown()
    }

    private func makeApp() -> AppModel {
        AppModel(inboxDirectory: inboxDirectory, defaults: defaults, keyStore: keys)
    }

    func testFailedReplacementPreservesWorkingSessionAndOldCredential() async throws {
        defaults.set("company-b", forKey: "paperclip.companyId")
        let app = makeApp()
        try await app.connect(serverURL: server, token: "old-test-key", session: session)
        let previousClient = app.client
        keys.failWrites = true

        do {
            try await app.connect(serverURL: server, token: "replacement-test-key", session: session)
            XCTFail("A failed credential write must fail the connection attempt")
        } catch {}

        XCTAssertTrue(app.client === previousClient)
        XCTAssertEqual(keys.values[server.absoluteString], "old-test-key")
        XCTAssertEqual(defaults.string(forKey: "paperclip.serverURL"), server.absoluteString)
        XCTAssertTrue(defaults.bool(forKey: "paperclip.connected"))
        XCTAssertEqual(app.selectedCompanyId, "company-b")
        XCTAssertEqual(defaults.string(forKey: "paperclip.companyId"), "company-b")
    }

    func testFailedNewSaveDoesNotPersistConnectionOrHTTPConsent() async throws {
        defaults.set(server.absoluteString, forKey: "paperclip.serverURL")
        defaults.set(false, forKey: "paperclip.connected")
        defaults.set("company-b", forKey: "paperclip.companyId")
        keys.failWrites = true
        let app = makeApp()
        let httpServer = URL(string: "http://credential.test:3100")!

        do {
            try await app.connect(serverURL: httpServer, token: "new-test-key",
                                  allowInsecureHTTP: true, session: session)
            XCTFail("A failed credential write must fail the connection attempt")
        } catch {}

        XCTAssertFalse(app.isConnected)
        XCTAssertTrue(keys.values.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: "paperclip.connected"))
        XCTAssertEqual(defaults.string(forKey: "paperclip.serverURL"), server.absoluteString)
        XCTAssertEqual(defaults.string(forKey: "paperclip.companyId"), "company-b")
        XCTAssertFalse(AppModel.allowsInsecureHTTP(for: httpServer, defaults: defaults))
    }

    func testHTTPConsentIsScopedAndRestorePreservesSelectedCompany() async throws {
        let httpServer = URL(string: "http://credential.test:80/api")!
        defaults.set("company-b", forKey: "paperclip.companyId")
        let app = makeApp()
        try await app.connect(serverURL: httpServer, token: "http-test-key",
                              allowInsecureHTTP: true, session: session)

        XCTAssertTrue(AppModel.allowsInsecureHTTP(for: URL(string: "http://CREDENTIAL.test/")!, defaults: defaults))
        for other in ["http://credential.test:3100", "http://other.test", "https://credential.test",
                      "http://user:password@credential.test"] {
            XCTAssertFalse(AppModel.allowsInsecureHTTP(for: URL(string: other)!, defaults: defaults), other)
        }
        let restored = makeApp()
        await restored.restore(session: session)
        XCTAssertTrue(restored.isConnected)
        XCTAssertEqual(restored.client?.token, "http-test-key")
        XCTAssertEqual(restored.selectedCompanyId, "company-b")
        XCTAssertNil(restored.lastError)
    }

    func testRestoreKeychainFailureDoesNotFallBackToUnauthenticatedSession() async {
        defaults.set(server.absoluteString, forKey: "paperclip.serverURL")
        defaults.set(true, forKey: "paperclip.connected")
        keys.values[server.absoluteString] = "saved-test-key"
        keys.failReads = true
        let app = makeApp()

        await app.restore(session: session)

        XCTAssertFalse(app.isConnected)
        XCTAssertNotNil(app.lastError)
        XCTAssertEqual(fixture.requestCount, 0)
        XCTAssertEqual(keys.values[server.absoluteString], "saved-test-key")
        XCTAssertTrue(defaults.bool(forKey: "paperclip.connected"))
    }

    func testRevocationFailureAllowsLocalSignOutWithActionableSafeNotice() async throws {
        let app = makeApp()
        try await app.connect(serverURL: server, token: "active-test-key", session: session)
        fixture.revocationStatus = 503

        await app.signOut()

        XCTAssertFalse(app.isConnected)
        XCTAssertFalse(defaults.bool(forKey: "paperclip.connected"))
        XCTAssertNil(keys.values[server.absoluteString])
        XCTAssertEqual(defaults.string(forKey: "paperclip.serverURL"), server.absoluteString)
        XCTAssertEqual(app.lastError, AppL10n.text("connection.revoke_failed", "Disconnected on this device, but server key revocation could not be confirmed. The key may still be active. Open the server in your browser and revoke this device’s Board API key."))
        XCTAssertFalse(app.lastError?.contains("fixture-private-response") ?? true)
        XCTAssertEqual(fixture.revocationCount, 1)
    }

    func testKeyRemovalFailureKeepsConnectionAndReportsFailure() async throws {
        let app = makeApp()
        try await app.connect(serverURL: server, token: "active-test-key", session: session)
        let previousClient = app.client
        keys.failWrites = true

        await app.signOut()

        XCTAssertTrue(app.client === previousClient)
        XCTAssertTrue(defaults.bool(forKey: "paperclip.connected"))
        XCTAssertEqual(keys.values[server.absoluteString], "active-test-key")
        XCTAssertNotNil(app.lastError)
        XCTAssertFalse(app.isSigningOut)
        XCTAssertEqual(fixture.revocationCount, 1)
    }

    func testSuccessfulSignOutRemovesKeyAndEndsSessionWithoutWarning() async throws {
        let app = makeApp()
        try await app.connect(serverURL: server, token: "active-test-key", session: session)

        await app.signOut()

        XCTAssertFalse(app.isConnected)
        XCTAssertFalse(defaults.bool(forKey: "paperclip.connected"))
        XCTAssertNil(keys.values[server.absoluteString])
        XCTAssertNil(app.lastError)
        XCTAssertEqual(fixture.revocationCount, 1)
    }
}

private final class MemoryBoardKeys: BoardKeyStoring {
    var values: [String: String] = [:]
    var failReads = false
    var failWrites = false

    func read(account: String) throws -> String? {
        if failReads { throw AssistantKeyError.status(-25308) }
        return values[account]
    }

    func write(_ value: String?, account: String) throws {
        if failWrites { throw AssistantKeyError.status(-25308) }
        values[account] = value
    }
}

private final class CredentialProtocol: URLProtocol, @unchecked Sendable {
    static var fixture: CredentialFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.lowercased() == "credential.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.fixture!.handle(self) }
    override func stopLoading() {}

    func respond(_ body: String, status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class CredentialFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var requests = 0
    private var revocations = 0
    var requestCount: Int { lock.withLock { requests } }
    var revocationCount: Int { lock.withLock { revocations } }
    var revocationStatus: Int {
        get { lock.withLock { status } }
        set { lock.withLock { status = newValue } }
    }

    func handle(_ request: CredentialProtocol) {
        let path = request.request.url!.path
        let status = lock.withLock {
            requests += 1
            if path == "/api/cli-auth/revoke-current" { revocations += 1 }
            return self.status
        }
        switch path {
        case "/api/health": request.respond(#"{"status":"ok","deploymentMode":"authenticated"}"#)
        case "/api/cli-auth/me": request.respond(#"{"userId":"test-board"}"#)
        case "/api/companies": request.respond(#"[{"id":"company-a","name":"First"},{"id":"company-b","name":"Chosen"}]"#)
        case "/api/cli-auth/revoke-current": request.respond(#"{"error":"fixture-private-response"}"#, status: status)
        default: request.respond("[]")
        }
    }
}
