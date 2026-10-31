import XCTest
@testable import PaperclipKit

/// Exercises the client against a running server. Skipped unless `PAPERCLIP_TEST_URL` is set,
/// For HTTP, also set `PAPERCLIP_TEST_ALLOW_HTTP=1`. Writes go to the first company,
/// so point it at a disposable instance.
final class LiveServerTests: XCTestCase {
    private var client: PaperclipClient!

    override func setUpWithError() throws {
        guard let raw = ProcessInfo.processInfo.environment["PAPERCLIP_TEST_URL"], let url = URL(string: raw) else {
            throw XCTSkip("PAPERCLIP_TEST_URL not set")
        }
        client = PaperclipClient(serverURL: url, token: ProcessInfo.processInfo.environment["PAPERCLIP_TEST_TOKEN"],
                                 allowInsecureHTTP: ProcessInfo.processInfo.environment["PAPERCLIP_TEST_ALLOW_HTTP"] == "1")
    }

    func testReadEverything() async throws {
        let health = try await client.health()
        XCTAssertEqual(health.status, "ok")
        _ = try await client.me()
        let company = try await XCTUnwrapAsync(try await client.companies().first)
        _ = try await client.dashboard(companyId: company.id)
        _ = try await client.attention(companyId: company.id)
        _ = try await client.approvals(companyId: company.id)
        let issues = try await client.issues(companyId: company.id)
        for issue in issues.prefix(5) {
            _ = try await client.issue(id: issue.id)
            _ = try await client.comments(issueId: issue.id)
            _ = try await client.interactions(issueId: issue.id)
        }
        let agents = try await client.agents(companyId: company.id)
        _ = try await client.orgChart(companyId: company.id)
        _ = try await client.runs(companyId: company.id)
        for agent in agents.prefix(5) {
            _ = try await client.agent(id: agent.id)
            _ = try await client.skills(agentId: agent.id)
            let bundle = try await client.instructionsBundle(agentId: agent.id)
            for file in bundle.files.prefix(2) {
                _ = try await client.instructionsFile(agentId: agent.id, path: file.path)
            }
        }
    }

    func testCreateCommentAndUpdateIssue() async throws {
        let company = try await XCTUnwrapAsync(try await client.companies().first)
        let created = try await client.createIssue(
            companyId: company.id, NewIssue(title: "Live test \(UUID().uuidString.prefix(6))", priority: .low))
        XCTAssertEqual(created.status, .todo)
        let comment = try await client.addComment(issueId: created.id, NewComment(body: "From the iOS client test"))
        XCTAssertEqual(comment.body, "From the iOS client test")
        let updated = try await client.updateIssue(id: created.id, IssueUpdate(status: .cancelled, priority: .high))
        XCTAssertEqual(updated.status, .cancelled)
        XCTAssertEqual(updated.priority, .high)
    }

    func testIssueListFollowsPages() async throws {
        let company = try await XCTUnwrapAsync(try await client.companies().first)
        let onePage = try await client.issues(companyId: company.id, pageSize: 1000)
        let paged = try await client.issues(companyId: company.id, pageSize: 2)
        XCTAssertGreaterThan(onePage.count, 2, "need more than one page of demo data")
        XCTAssertEqual(Set(paged.map(\.id)), Set(onePage.map(\.id)))
    }

    func testAttentionFeedFollowsCursor() async throws {
        let company = try await XCTUnwrapAsync(try await client.companies().first)
        let whole = try await client.attention(companyId: company.id, pageSize: 100)
        let paged = try await client.attention(companyId: company.id, pageSize: 2)
        XCTAssertEqual(Set(paged.items.map(\.id)), Set(whole.items.map(\.id)))
        XCTAssertNil(paged.nextCursor)
    }

    func testSignInChallengeIsCreated() async throws {
        let challenge = try await client.createSignInChallenge(clientName: "PaperclipKit tests")
        XCTAssertFalse(challenge.boardApiToken.isEmpty)
        XCTAssertNotNil(client.approvalURL(for: challenge))
        let state = try await client.challengeState(id: challenge.id, token: challenge.token)
        XCTAssertEqual(state.status, "pending")
    }
}

private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let result = try await value()
    return try XCTUnwrap(result, file: file, line: line)
}
