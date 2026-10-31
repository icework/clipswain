import XCTest
@testable import PaperclipKit

final class IssueDeliverablesTests: XCTestCase {
    private var session: URLSession!
    private var client: PaperclipClient!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliverablesProtocol.self]
        session = URLSession(configuration: configuration)
        client = PaperclipClient(serverURL: URL(string: "https://results.test/api/")!, token: "fixture-token", session: session)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        DeliverablesProtocol.respond = nil
    }

    static let summary = """
    {"id":"doc","companyId":"company","issueId":"issue","key":"report","title":null,
     "latestRevisionNumber":3,"updatedAt":"2026-10-22T10:00:00Z"}
    """
    static let attachment = """
    {"id":"file","companyId":"company","issueId":"issue","originalFilename":"报告.pdf",
     "contentType":"application/pdf","byteSize":1234,"createdAt":"2026-10-22T10:00:00Z"}
    """
    static func product(url: String) -> String {
        """
        {"id":"product","companyId":"company","issueId":"issue","type":"future_type",
         "title":"Result","url":\(String(data: try! JSONEncoder().encode(url), encoding: .utf8)!),
         "status":"future_status","isPrimary":true,"summary":null,"metadata":{"attachmentId":"file"},
         "updatedAt":"2026-10-22T10:00:00Z"}
        """
    }

    func testReadRoutesDecodeProductionShapesAndUseAuthentication() async throws {
        var paths: [String] = []
        DeliverablesProtocol.respond = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            XCTAssertEqual(request.httpMethod, "GET")
            paths.append(request.url!.path)
            switch request.url!.lastPathComponent {
            case "documents": return (200, "[\(Self.summary)]")
            case "attachments": return (200, "{\"items\":[\(Self.attachment)]}")
            case "work-products": return (200, "[\(Self.product(url: "https://example.com/result"))]")
            default: return (404, "{}")
            }
        }
        let documents = try await client.issueDocuments(issueId: "issue")
        XCTAssertEqual(documents.first?.displayTitle, "report")
        let files = try await client.issueAttachments(issueId: "issue")
        XCTAssertEqual(files.first?.displayName, "报告.pdf")
        let products = try await client.issueWorkProducts(issueId: "issue")
        XCTAssertEqual(products.first?.type, "future_type")
        XCTAssertEqual(products.first?.metadata?["attachmentId"]?.stringValue, "file")
        XCTAssertEqual(paths, ["/api/issues/issue/documents", "/api/issues/issue/attachments", "/api/issues/issue/work-products"])
    }

    func testDocumentKeyIsEncodedAsOneSegmentAndBodyIsRequired() async throws {
        DeliverablesProtocol.respond = { request in
            let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.percentEncodedPath
            XCTAssertEqual(path, "/api/issues/issue/documents/%E6%8A%A5%E5%91%8A%2F%3F%23%25")
            return (200, Self.summary.dropLast() + ",\"body\":\"# Final report\\nSuccess\"}")
        }
        let document = try await client.issueDocument(issueId: "issue", key: "报告/?#%")
        XCTAssertEqual(document.body, "# Final report\nSuccess")
        XCTAssertThrowsError(try PaperclipJSON.decoder.decode(IssueDocument.self, from: Data(Self.summary.utf8)))
    }

    func testMissingEndpointIsAnErrorRatherThanAnEmptyList() async throws {
        DeliverablesProtocol.respond = { _ in (404, "{\"error\":\"Unavailable\"}") }
        do { _ = try await client.issueDocuments(issueId: "issue"); XCTFail("Must surface the failure") }
        catch { XCTAssertEqual((error as? PaperclipAPIError)?.status, 404) }
    }

    func testWorkProductWebLinksRejectLocalAndExecutableSchemes() throws {
        for value in ["/Users/example/report.md", "file:///tmp/result", "javascript:alert(1)", "https://user:secret@example.com/result", "../report"] {
            let product = try PaperclipJSON.decoder.decode(IssueWorkProduct.self, from: Data(Self.product(url: value).utf8))
            XCTAssertNil(product.webURL, value)
        }
        let product = try PaperclipJSON.decoder.decode(IssueWorkProduct.self, from: Data(Self.product(url: "https://example.com/result").utf8))
        XCTAssertEqual(product.webURL?.host, "example.com")
    }

    func testAttachmentRedirectCannotForwardCredentialToStorageHost() {
        let url = URL(string: "https://storage.test/result")!
        let response = HTTPURLResponse(url: URL(string: "https://results.test/api/attachments/id/content")!, statusCode: 302, httpVersion: nil, headerFields: ["Location": url.absoluteString])!
        var redirected = URLRequest(url: url)
        redirected.setValue("Bearer fixture-token", forHTTPHeaderField: "Authorization")
        var called = false
        AttachmentDownloadDelegate().urlSession(session, task: session.dataTask(with: redirected),
            willPerformHTTPRedirection: response, newRequest: redirected) { next in
                called = true
                XCTAssertNil(next)
            }
        XCTAssertTrue(called)
    }

    // URLProtocol does not exercise URLSession's real download-to-disk/redirect behavior.
    // scripts/verify-task-result-downloads.py supplies an isolated loopback HTTP fixture.
    private func downloadFixtureClient() throws -> PaperclipClient {
        guard let origin = ProcessInfo.processInfo.environment["PAPERCLIP_ATTACHMENT_TEST_ORIGIN"],
              let url = URL(string: origin), url.host == "127.0.0.1" else {
            throw XCTSkip("Run scripts/verify-task-result-downloads.py for the local download fixture")
        }
        return PaperclipClient(serverURL: url, token: "fixture-download-token",
                               allowInsecureHTTP: true,
                               session: URLSession(configuration: .ephemeral))
    }

    func testRealAttachmentDownloadWritesExpectedFileToDisk() async throws {
        let fixture = try downloadFixtureClient()
        let url = try await fixture.downloadIssueAttachment(id: "file")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Fixture attachment: 中文 report\n")
    }

    func testRealAttachmentDownloadRejectsRedirectAndJSONError() async throws {
        let fixture = try downloadFixtureClient()
        for (id, expected) in [("redirect", 302), ("missing", 404)] {
            do { _ = try await fixture.downloadIssueAttachment(id: id); XCTFail("Must reject \(id)") }
            catch { XCTAssertEqual((error as? PaperclipAPIError)?.status, expected) }
        }
    }
}

private final class DeliverablesProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.respond!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
