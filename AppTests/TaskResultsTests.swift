import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class TaskResultsTests: XCTestCase {
    private var session: URLSession!
    private var client: PaperclipClient!

    override func setUp() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResultsProtocol.self]
        session = URLSession(configuration: configuration)
        client = PaperclipClient(serverURL: URL(string: "https://results.test")!, token: nil, session: session)
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        ResultsProtocol.respond = nil
    }

    private static func document(key: String, company: String = "company") -> String {
        """
        {"id":"\(key)","companyId":"\(company)","issueId":"issue","key":"\(key)","title":null,
        "latestRevisionNumber":1,"updatedAt":"2026-10-22T10:00:00Z"}
        """
    }

    func testUnavailableAttachmentsDoNotHideReportAndEmptyProducts() async {
        ResultsProtocol.respond = { request in
            switch request.url!.lastPathComponent {
            case "documents": return (200, "[\(Self.document(key: "plan")),\(Self.document(key: "report"))]")
            case "attachments": return (403, "{\"error\":\"Access denied\"}")
            default: return (200, "[]")
            }
        }
        let store = TaskResultsStore()
        await store.load(client: client, issueID: "issue", companyID: "company")
        if case .loaded(let documents) = store.documents { XCTAssertEqual(documents.map(\.key), ["report", "plan"]) }
        else { XCTFail("Reports must remain accessible") }
        if case .failed = store.attachments {} else { XCTFail("Permission error must be visible") }
        if case .loaded(let products) = store.products { XCTAssertTrue(products.isEmpty) }
        else { XCTFail("Empty is different from failure") }
    }

    func testWrongCompanyResultsAreRejected() async {
        ResultsProtocol.respond = { request in
            (200, request.url!.lastPathComponent == "documents" ? "[\(Self.document(key: "report", company: "other-company"))]" : "[]")
        }
        let store = TaskResultsStore()
        await store.load(client: client, issueID: "issue", companyID: "company")
        if case .failed = store.documents {} else { XCTFail("Must reject cross-company content") }
    }

    func testChangedSessionAndCancelledLoadDoNotApplyResults() async {
        ResultsProtocol.respond = { _ in (200, "[]") }
        let store = TaskResultsStore()
        await store.load(client: client, issueID: "issue", companyID: "company", isCurrent: { false })
        if case .loading = store.documents {} else { XCTFail("Old session must not update the screen") }
        let cancelled = Task {
            await store.load(client: client, issueID: "issue", companyID: "company")
        }
        cancelled.cancel()
        await cancelled.value
        if case .loading = store.documents {} else { XCTFail("Cancelled request must not update the screen") }
    }

    func testPreviewFilenameCannotEscapeTemporaryDirectory() {
        XCTAssertEqual(TaskResultsView.safeFilename("../../报告.pdf"), "报告.pdf")
        XCTAssertEqual(TaskResultsView.safeFilename("C:\\private\\result.md"), "result.md")
        XCTAssertEqual(TaskResultsView.safeFilename(".."), "attachment")
        XCTAssertEqual(TaskResultsView.safeFilename("\n\u{0}"), "attachment")
        XCTAssertEqual(TaskResultsView.safeFilename("file-id", contentType: "application/pdf"), "file-id.pdf")
    }

    func testDocumentLinksResolveAgainstConnectedServer() {
        let server = URL(string: "https://paperclip.test")!
        XCTAssertEqual(TaskDocumentView.webLink(URL(string: "/NOR/issues/NOR-38#document-publication-draft")!, server: server)?.absoluteString,
                       "https://paperclip.test/NOR/issues/NOR-38#document-publication-draft")
        XCTAssertEqual(TaskDocumentView.webLink(URL(string: "https://example.com/source")!, server: server)?.host, "example.com")
        XCTAssertNil(TaskDocumentView.webLink(URL(string: "file:///tmp/report")!, server: server))
        XCTAssertNil(TaskDocumentView.webLink(URL(string: "javascript:alert(1)")!, server: server))
    }

    func testReportTablesRenderAsRowsAndDoNotConsumeFencedCode() {
        let markdown = """
        # Report
        | Product | Result |
        | :--- | ---: |
        | Phone | Works \\| with app |

        After table.
        ```
        | Product | Result |
        | --- | --- |
        ```
        """
        XCTAssertEqual(MarkdownText.blocks(markdown), [
            .heading(1, "Report"),
            .table(headers: ["Product", "Result"], rows: [["Phone", "Works | with app"]]),
            .paragraph("After table."),
            .code("| Product | Result |\n| --- | --- |")
        ])
    }

    func testSiblingDocumentLinksStayInAppOnlyForCurrentServerAndTask() throws {
        let server = URL(string: "https://paperclip.test")!
        let report = try PaperclipJSON.decoder.decode(IssueDocumentSummary.self, from: Data(Self.document(key: "report").utf8))
        let link = URL(string: "https://paperclip.test/NOR/issues/NOR-38#document-report")!
        XCTAssertEqual(TaskDocumentView.documentLink(link, server: server, issueID: "issue", issueKey: "NOR-38", documents: [report])?.key, "report")
        for value in ["https://other.test/NOR/issues/NOR-38#document-report",
                      "http://paperclip.test/NOR/issues/NOR-38#document-report",
                      "https://paperclip.test/NOR/issues/NOR-39#document-report",
                      "https://paperclip.test/NOR/issues/NOR-38#document-missing"] {
            XCTAssertNil(TaskDocumentView.documentLink(URL(string: value)!, server: server, issueID: "issue", issueKey: "NOR-38", documents: [report]))
        }
    }
}

private final class ResultsProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> (Int, String))?
    static var respond: ((URLRequest) -> (Int, String))? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "results.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // URLSession cancellation can finish after tearDown clears the fixture handler.
        guard let respond = Self.respond else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let (status, body) = respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
