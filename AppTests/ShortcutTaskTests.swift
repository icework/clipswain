import XCTest
import AppIntents
import PaperclipKit
@testable import Clipswain

@MainActor
final class ShortcutTaskTests: XCTestCase {
    private var session: URLSession!
    private var requests: [URLRequest] = []
    private var posted: [String: Any]?
    private var companies = "[{\"id\":\"company\",\"name\":\"Test company\"}]"
    private var postStatus = 201

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ShortcutProtocol.self]
        session = URLSession(configuration: config)
        ShortcutProtocol.respond = { [unowned self] request in
            self.requests.append(request)
            switch request.url!.path {
            case "/api/companies": return (200, self.companies)
            case "/api/companies/company/agents":
                return (200, "[{\"id\":\"engineer\",\"companyId\":\"company\",\"name\":\"Engineer\",\"role\":\"engineer\",\"status\":\"idle\",\"adapterType\":\"process\"}]")
            case "/api/companies/company/issues":
                let data = request.httpBody ?? request.httpBodyStream.map { stream in
                    stream.open(); defer { stream.close() }
                    var data = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        data.append(buffer, count: count)
                    }
                    return data
                } ?? Data()
                self.posted = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (self.postStatus, "{\"id\":\"created\",\"companyId\":\"company\",\"identifier\":\"TEST-42\",\"title\":\"Created task\",\"status\":\"todo\",\"priority\":\"medium\"}")
            default: throw URLError(.unsupportedURL)
            }
        }
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        ShortcutProtocol.respond = nil
    }

    private func service(draft: ShortcutTaskService.Draft? = nil,
                         current: @escaping () -> Bool = { true }) -> ShortcutTaskService {
        ShortcutTaskService(client: PaperclipClient(serverURL: URL(string: "https://shortcut.test")!, token: "fixture-token", session: session),
                            companyID: "company", draft: draft, isCurrentSession: current)
    }

    func testDirectCaptureUsesSavedCompanyAndReturnsRealResponseIdentifier() async throws {
        let created = try await service().publish("  Fix the inbox\nKeep the original detail.  ")
        XCTAssertEqual(created.displayKey, "TEST-42")
        XCTAssertEqual(posted?["title"] as? String, "Fix the inbox\nKeep the original detail.")
        XCTAssertEqual(posted?["description"] as? String, "Fix the inbox\nKeep the original detail.")
        XCTAssertEqual(posted?["status"] as? String, "todo")
        XCTAssertNil(posted?["assigneeAgentId"])
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
    }

    func testAIDraftPreservesOriginalSpeechAndResolvesOnlyCompanyAgents() async throws {
        let created = try await service { text, context in
            XCTAssertEqual(context.companyName, "Test company")
            XCTAssertEqual(context.agents.map(\.id), ["engineer"])
            return TaskDraft(title: "Fix inbox", description: "Investigate stale data", assigneeAgentId: "engineer", priority: .high)
        }.publish("Ask engineer to fix inbox; high priority")
        XCTAssertEqual(created.displayKey, "TEST-42")
        XCTAssertEqual(posted?["title"] as? String, "Fix inbox")
        XCTAssertEqual(posted?["assigneeAgentId"] as? String, "engineer")
        XCTAssertEqual(posted?["priority"] as? String, "high")
        XCTAssertTrue((posted?["description"] as? String)?.contains("Ask engineer to fix inbox; high priority") == true)
    }

    func testMissingCompanyDoesNotFallBackOrPublish() async throws {
        companies = "[{\"id\":\"other\",\"name\":\"Other company\"}]"
        do { _ = try await service().publish("Task"); XCTFail("Must reject missing company") }
        catch { XCTAssertTrue(error is ShortcutTaskError) }
        XCTAssertNil(posted)
    }

    func testEmptySpeechDoesNotContactServer() async throws {
        do { _ = try await service().publish(" \n "); XCTFail("Must reject empty input") }
        catch { XCTAssertTrue(error is ShortcutTaskError) }
        XCTAssertTrue(requests.isEmpty)
    }

    func testSessionChangedDuringDraftDoesNotPublish() async throws {
        do { _ = try await service(current: { false }).publish("Task"); XCTFail("Must reject changed session") }
        catch { XCTAssertTrue(error is ShortcutTaskError) }
        XCTAssertNil(posted)
    }

    func testUnknownAssigneeAndEmptyTitleNeverPublish() async throws {
        for draft in [TaskDraft(title: "Task", assigneeAgentId: "other-company-agent"), TaskDraft(title: " \n ")] {
            do { _ = try await service(draft: { _, _ in draft }).publish("Task"); XCTFail("Must reject bad draft") }
            catch { XCTAssertTrue(error is ShortcutTaskError) }
            XCTAssertNil(posted)
        }
    }

    func testAIFailureDoesNotSilentlyPublishAnUnassignedTask() async throws {
        do { _ = try await service(draft: { _, _ in throw TaskDraftError.unreadable }).publish("Task"); XCTFail("Must stop on AI failure") }
        catch { XCTAssertTrue(error is TaskDraftError) }
        XCTAssertNil(posted)
    }

    func testAmbiguousServerFailureIsNotRetried() async throws {
        postStatus = 500
        do { _ = try await service().publish("Task"); XCTFail("Must report uncertain result") }
        catch { XCTAssertTrue(error is ShortcutTaskError) }
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testBackgroundShortcutRejectsHTTPWithoutConsentAndPropagatesKeychainFailure() throws {
        let name = "ShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("http://shortcut.test", forKey: "paperclip.serverURL")
        defaults.set("company", forKey: "paperclip.companyId")
        XCTAssertThrowsError(try ShortcutSession.load(defaults: defaults, token: { _ in "fixture" })) {
            XCTAssertEqual($0 as? TransportSecurityError, .insecureHTTP)
        }
        defaults.set("https://shortcut.test", forKey: "paperclip.serverURL")
        XCTAssertThrowsError(try ShortcutSession.load(defaults: defaults, token: { _ in throw AssistantKeyError.verificationFailed }))
    }

    func testSignedOutAndUnselectedSessionsCannotLoad() throws {
        let name = "ShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://shortcut.test", forKey: "paperclip.serverURL")
        XCTAssertThrowsError(try ShortcutSession.load(defaults: defaults, token: { _ in nil }))
        defaults.set("company", forKey: "paperclip.companyId")
        XCTAssertEqual(try ShortcutSession.load(defaults: defaults, token: { _ in "test" }).companyID, "company")
        defaults.set(false, forKey: "paperclip.connected")
        XCTAssertThrowsError(try ShortcutSession.load(defaults: defaults, token: { _ in nil }))
    }
}

private final class ShortcutProtocol: URLProtocol, @unchecked Sendable {
    static var respond: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "shortcut.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
