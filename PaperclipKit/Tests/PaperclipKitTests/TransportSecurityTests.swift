import XCTest
@testable import PaperclipKit

final class TransportSecurityTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SecurityFixtureProtocol.self]
        session = URLSession(configuration: configuration)
        SecurityFixtureProtocol.requests = []
    }

    override func tearDown() { session.invalidateAndCancel() }

    func testURLPolicyRequiresExplicitHTTPConsentAndRejectsEmbeddedCredentials() throws {
        try TransportSecurityPolicy.validate(URL(string: "https://example.test")!)
        for address in ["http://127.0.0.1:3100", "http://100.64.0.1:3100", "http://example.test"] {
            let url = URL(string: address)!
            XCTAssertThrowsError(try TransportSecurityPolicy.validate(url)) {
                XCTAssertEqual($0 as? TransportSecurityError, .insecureHTTP)
            }
            XCTAssertNoThrow(try TransportSecurityPolicy.validate(url, allowInsecureHTTP: true))
        }
        for address in ["ftp://example.test", "http+custom://example.test", "file:///tmp/example"] {
            XCTAssertThrowsError(try TransportSecurityPolicy.validate(URL(string: address)!, allowInsecureHTTP: true)) {
                XCTAssertEqual($0 as? TransportSecurityError, .unsupportedScheme)
            }
        }
        for address in ["https://user:password@example.test", "https://user@example.test", "http://user@example.test"] {
            XCTAssertThrowsError(try TransportSecurityPolicy.validate(URL(string: address)!, allowInsecureHTTP: true)) {
                XCTAssertEqual($0 as? TransportSecurityError, .embeddedCredentials)
            }
        }
        XCTAssertThrowsError(try TransportSecurityPolicy.validate(URL(string: "https:/missing-host")!)) {
            XCTAssertEqual($0 as? TransportSecurityError, .missingHost)
        }
    }

    func testBoardHTTPAndAttachmentAreBlockedBeforeSessionReceivesAnything() async throws {
        let client = PaperclipClient(serverURL: URL(string: "http://fixture.test")!, token: "fixture-board-key", session: session)
        do { _ = try await client.health(); XCTFail("Expected HTTP rejection") }
        catch { XCTAssertEqual(error as? TransportSecurityError, .insecureHTTP) }
        do { _ = try await client.downloadIssueAttachment(id: "fixture"); XCTFail("Expected HTTP rejection") }
        catch { XCTAssertEqual(error as? TransportSecurityError, .insecureHTTP) }
        XCTAssertTrue(SecurityFixtureProtocol.requests.isEmpty)
    }

    func testBoardExplicitHTTPConsentPreservesInjectedSession() async throws {
        let client = PaperclipClient(serverURL: URL(string: "http://fixture.test")!, token: "fixture-board-key",
                                    allowInsecureHTTP: true, session: session)
        let health = try await client.health()
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(SecurityFixtureProtocol.requests.count, 1)
        XCTAssertEqual(SecurityFixtureProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-board-key")
    }

    func testAuthenticatedDataRejectsDifferentOriginBeforeSending() async throws {
        let client = PaperclipClient(serverURL: URL(string: "https://fixture.test")!, token: "fixture-board-key", session: session)
        for address in ["https://other.test/avatar", "https://fixture.test:444/avatar", "http://fixture.test/avatar"] {
            do { _ = try await client.data(for: URL(string: address)!); XCTFail("Expected origin rejection") }
            catch { XCTAssertTrue(error is TransportSecurityError) }
        }
        XCTAssertTrue(SecurityFixtureProtocol.requests.isEmpty)
        _ = try await client.data(for: URL(string: "https://FIXTURE.test:443/avatar")!)
        XCTAssertEqual(SecurityFixtureProtocol.requests.count, 1)
    }

    func testBoardRejectsCredentialsAndUnsupportedSchemesBeforeSending() async throws {
        for address in ["https://user:password@fixture.test", "ftp://fixture.test", "http+custom://fixture.test"] {
            let client = PaperclipClient(serverURL: URL(string: address)!, token: "fixture-board-key",
                                        allowInsecureHTTP: true, session: session)
            do { _ = try await client.health(); XCTFail("Expected invalid destination rejection") }
            catch { XCTAssertTrue(error is TransportSecurityError) }
        }
        XCTAssertTrue(SecurityFixtureProtocol.requests.isEmpty)
    }

    func testLLMInvalidDestinationsAreRejectedBeforeSessionReceivesAnything() async throws {
        for address in ["http://fixture.test", "https://user:password@fixture.test", "ftp://fixture.test"] {
            let config = LLMProviderConfig(kind: .anthropic, baseURL: address)
            let drafter = TaskDrafter(config: config, apiKey: "fixture-llm-key", session: session)
            do { _ = try await drafter.draft(from: "Synthetic task", context: .init(agents: [])); XCTFail("Expected rejection") }
            catch { XCTAssertTrue(error is TransportSecurityError) }
        }
        XCTAssertTrue(SecurityFixtureProtocol.requests.isEmpty)
    }

    func testLegacyLLMConfigurationRequiresNewHTTPConsentAndRoundTripsConsent() throws {
        let old = Data(#"{"kind":"anthropic","baseURL":"http://fixture.test","model":"fixture-model"}"#.utf8)
        var config = try JSONDecoder().decode(LLMProviderConfig.self, from: old)
        XCTAssertFalse(config.allowInsecureHTTP)
        XCTAssertThrowsError(try TaskDrafter(config: config, apiKey: "fixture-llm-key").makeRequest(text: "Synthetic task", context: .init(agents: []))) {
            XCTAssertEqual($0 as? TransportSecurityError, .insecureHTTP)
        }
        config.allowInsecureHTTP = true
        let saved = try JSONDecoder().decode(LLMProviderConfig.self, from: JSONEncoder().encode(config))
        XCTAssertTrue(saved.allowInsecureHTTP)
        XCTAssertNoThrow(try TaskDrafter(config: saved, apiKey: "fixture-llm-key").makeRequest(text: "Synthetic task", context: .init(agents: [])))
    }

    func testLLMCredentialScopeMatchesNormalizedRequestDestination() {
        func scope(_ base: String) -> String { LLMProviderConfig(kind: .anthropic, baseURL: base).credentialAccount }
        XCTAssertEqual(scope(" \nhttps://FIRST.test/v1 \t"), scope("https://first.test:443/v1/messages"))
        XCTAssertNotEqual(scope(" https://first.test/v1"), scope(" https://second.test/v1"))
        XCTAssertNotEqual(scope(" http://first.test/v1"), scope(" http://second.test/v1"))
        XCTAssertEqual(scope(" HTTP://first.test/v1 "), scope("http://FIRST.test:80/v1/messages"))
        XCTAssertEqual(scope("HTTPS://first.test"), scope("https://first.test:443"))
        XCTAssertNotEqual(scope("HTTP://first.test"), scope("http://first.test:443"))
        XCTAssertNotEqual(scope("http://first.test:443"), scope("https://first.test:443"))
    }

    func testInvalidLLMURLsCannotSelectValidOrSharedLegacyCredentials() {
        func scope(_ base: String) -> String { LLMProviderConfig(kind: .anthropic, baseURL: base).credentialAccount }
        let valid = scope("https://first.test")
        for address in ["https://user:fake-password@first.test", "ftp://first.test", "", "not a URL"] {
            let invalid = scope(address)
            XCTAssertNotEqual(invalid, valid)
            XCTAssertNotEqual(invalid, "anthropic:invalid")
            XCTAssertFalse(invalid.contains("fake-password"))
            XCTAssertEqual(invalid, scope(address))
        }
        XCTAssertNotEqual(scope("ftp://first.test"), scope("ftp://second.test"))
    }

    func testModelCatalogStillUsesInjectedSessionAtPinnedHTTPSOrigin() async throws {
        let models = try await LLMModelCatalog(session: session).fetch(kind: .openRouter, apiKey: "fixture-catalog-key", sessionID: "fixture-session")
        XCTAssertEqual(models.map(\.id), ["fixture-model"])
        XCTAssertEqual(SecurityFixtureProtocol.requests.first?.url?.scheme, "https")
        XCTAssertEqual(SecurityFixtureProtocol.requests.first?.url?.host, "openrouter.ai")
    }

    func testDelegateRefusesSameAndCrossOriginRedirects() {
        let source = URL(string: "https://fixture.test/source")!
        for status in [301, 302, 303, 307, 308] {
            for target in ["https://fixture.test/destination", "https://other.test/destination"] {
                let request = URLRequest(url: URL(string: target)!)
                let response = HTTPURLResponse(url: source, statusCode: status, httpVersion: nil, headerFields: ["Location": target])!
                var called = false
                RedirectBlockingDelegate().urlSession(session, task: session.dataTask(with: request),
                    willPerformHTTPRedirection: response, newRequest: request) { next in
                    called = true
                    XCTAssertNil(next)
                }
                XCTAssertTrue(called)
            }
        }
    }

    /// A real socket fixture proves headers and POST bodies never reach the redirect target.
    /// Run scripts/verify-network-security.py; no live service or credential is used.
    func testRealTransportRejectsRedirects() async throws {
        guard let value = ProcessInfo.processInfo.environment["PAPERCLIP_NETWORK_TEST_ORIGIN"],
              let origin = URL(string: value), origin.host == "127.0.0.1" else {
            throw XCTSkip("Run scripts/verify-network-security.py for the loopback redirect fixture")
        }
        let liveSession = URLSession(configuration: .ephemeral)
        defer { liveSession.invalidateAndCancel() }
        let client = PaperclipClient(serverURL: origin, token: "fixture-board-key", allowInsecureHTTP: true, session: liveSession)
        do { _ = try await client.health(); XCTFail("Must reject redirected board GET") }
        catch { XCTAssertEqual((error as? PaperclipAPIError)?.status, 307) }
        do { _ = try await client.createIssue(companyId: "fixture-company", .init(title: "Synthetic task")); XCTFail("Must reject redirected board POST") }
        catch { XCTAssertEqual((error as? PaperclipAPIError)?.status, 307) }
        do { _ = try await client.data(for: origin.appendingPathComponent("avatar")); XCTFail("Must reject redirected authenticated content") }
        catch { XCTAssertEqual((error as? PaperclipAPIError)?.status, 307) }
        let signIn = PaperclipClient(serverURL: origin, token: nil, allowInsecureHTTP: true, session: liveSession)
        do { _ = try await signIn.createSignInChallenge(clientName: "Fixture"); XCTFail("Must reject redirected authentication") }
        catch { XCTAssertEqual((error as? PaperclipAPIError)?.status, 307) }
        for kind in [LLMProviderKind.anthropic, .openAICompatible] {
            let config = LLMProviderConfig(kind: kind, baseURL: origin.absoluteString, model: "fixture-model", allowInsecureHTTP: true)
            let drafter = TaskDrafter(config: config, apiKey: "fixture-llm-key", session: liveSession)
            do { _ = try await drafter.draft(from: "Synthetic task", context: .init(agents: [])); XCTFail("Must reject redirected LLM POST") }
            catch {
                guard case TaskDraftError.http(let status, _) = error else { return XCTFail("Expected redirect HTTP status, received \(error)") }
                XCTAssertEqual(status, 307)
            }
        }
    }
}

private final class SecurityFixtureProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"status":"ok","data":[{"id":"fixture-model","name":"Fixture"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
