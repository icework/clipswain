import XCTest
@testable import PaperclipKit

/// Fixtures were captured from a real Paperclip 0.3.1 server running in local trusted mode.
final class DecodingTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try PaperclipJSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }

    func testCompanies() throws {
        let companies = try fixture("companies", as: [Company].self)
        XCTAssertEqual(companies.first?.name, "Northwind Labs")
        XCTAssertEqual(companies.first?.issuePrefix, "NOR")
    }

    func testIssueListAndDetail() throws {
        let issues = try fixture("issues", as: [Issue].self)
        XCTAssertEqual(issues.count, 5)
        XCTAssertTrue(issues.allSatisfy { $0.identifier?.hasPrefix("NOR-") == true })
        XCTAssertTrue(Set(issues.map(\.status)).isSuperset(of: [.inProgress, .blocked, .backlog, .done]))
        XCTAssertFalse(issues.contains { $0.priority == .unknown })

        let detail = try fixture("issue-detail", as: Issue.self)
        XCTAssertEqual(detail.title, "Implement board sign-in flow")
        XCTAssertEqual(detail.status, .blocked)
        XCTAssertEqual(detail.priority, .critical)
        XCTAssertEqual(detail.ancestors?.first?.title, "Ship the iOS companion MVP")
    }

    func testComments() throws {
        let comments = try fixture("comments", as: [IssueComment].self)
        XCTAssertEqual(comments.count, 1)
        XCTAssertTrue(comments[0].isFromAgent)
        XCTAssertTrue(comments[0].body.contains("blocked"))
    }

    func testQuestionInteraction() throws {
        let interactions = try fixture("interactions-questions", as: [IssueInteraction].self)
        let card = try XCTUnwrap(interactions.first)
        XCTAssertEqual(card.kind, .askUserQuestions)
        XCTAssertTrue(card.isPending)
        let questions = try XCTUnwrap(card.questions)
        XCTAssertEqual(questions.questions.first?.options.map(\.id), ["trusted", "browser", "paste"])
        XCTAssertEqual(questions.questions.first?.isMulti, true)
    }

    func testConfirmationInteraction() throws {
        let interactions = try fixture("interactions-confirm", as: [IssueInteraction].self)
        let confirmation = try XCTUnwrap(interactions.first?.confirmation)
        XCTAssertEqual(confirmation.acceptLabel, "Accept plan")
        XCTAssertEqual(confirmation.rejectRequiresReason, true)
    }

    func testAgents() throws {
        let agents = try fixture("agents", as: [Agent].self)
        XCTAssertEqual(agents.count, 4)
        let linus = try XCTUnwrap(agents.first { $0.name == "Linus" })
        XCTAssertEqual(linus.modelName, "claude-opus-5-5")
        XCTAssertEqual(linus.roleLabel, "CTO")
        XCTAssertNotNil(linus.resolvedAppearance.paletteId)
        XCTAssertTrue(linus.avatarPath().hasPrefix("/api/agent-avatars/cap-v1/"))

        let grace = try fixture("agent-detail", as: Agent.self)
        XCTAssertEqual(grace.chainOfCommand?.map(\.name), ["Linus", "Ada"])
    }

    func testAvatarPoseFollowsStatus() {
        var agent = Agent(id: "a1", companyId: "c", name: "A", role: "engineer", status: .running, adapterType: "process")
        agent.appearance = AgentAppearance(paletteId: "deep-tide")
        XCTAssertEqual(agent.avatarPath(size: 64, scale: 2), "/api/agent-avatars/cap-v1/deep-tide/working.png?size=64&scale=2")
        agent.status = .error
        XCTAssertTrue(agent.avatarPath().contains("/confused.png"))
        agent.status = .terminated
        XCTAssertTrue(agent.avatarPath().contains("/muted-dream/rest.png"))
    }

    func testLegacyAppearanceMatchesServerHash() {
        // Reference value computed with the server's legacyAgentAppearance("agent-42").
        var hash = 0
        for unit in "agent-42".utf16 { hash = (hash * 31 + Int(unit)) % 17 }
        XCTAssertEqual(AgentAppearance.legacy(for: "agent-42").paletteId, AgentAppearance.paletteIds[hash])
    }

    func testOrgChart() throws {
        let roots = try fixture("org", as: [OrgNode].self)
        XCTAssertEqual(roots.map(\.name), ["Ada"])
        XCTAssertEqual(Set(roots[0].reports.map(\.name)), ["Linus", "Dieter"])
        let linus = try XCTUnwrap(roots[0].reports.first { $0.name == "Linus" })
        XCTAssertEqual(linus.reports.map(\.name), ["Grace"])
    }

    func testLocalOrgTreeMatchesServer() throws {
        let agents = try fixture("agents", as: [Agent].self)
        let roots = OrgNode.tree(from: agents)
        XCTAssertEqual(roots.map(\.name), ["Ada"])
        XCTAssertEqual(roots[0].reports.count, 2)
    }

    func testDashboardAttentionApprovals() throws {
        let dashboard = try fixture("dashboard", as: DashboardSummary.self)
        XCTAssertEqual(dashboard.tasks.blocked, 1)
        XCTAssertEqual(dashboard.agents.active, 4)

        let feed = try fixture("attention", as: AttentionFeed.self)
        XCTAssertFalse(feed.items.isEmpty)
        XCTAssertTrue(feed.items.contains { $0.issueId != nil || $0.approvalId != nil })

        let approvals = try fixture("approvals", as: [Approval].self)
        XCTAssertEqual(approvals.first?.status, .pending)
        XCTAssertEqual(approvals.first?.summary, "Buy an Apple Developer membership")
    }

    func testInstructionsAndSkills() throws {
        let bundle = try fixture("instructions-bundle", as: AgentInstructionsBundle.self)
        XCTAssertEqual(bundle.entryFile, "AGENTS.md")
        XCTAssertEqual(bundle.orderedFiles.first?.isEntryFile, true)

        let file = try fixture("instructions-file", as: AgentInstructionsFile.self)
        XCTAssertTrue(file.content.contains("senior iOS engineer"))
        let write = AgentInstructionsFileWrite.editing(file, content: "new", bundleMode: bundle.mode)
        XCTAssertEqual(write.baseRevisionId, file.revision?.id)
        XCTAssertNil(write.baseHash)

        let skills = try fixture("skills", as: AgentSkillSnapshot.self)
        XCTAssertFalse(skills.supported)
    }

    func testUnknownEnumValuesDoNotFail() throws {
        let data = Data(#"{"id":"x","companyId":"c","title":"T","status":"teleported","priority":"urgent"}"#.utf8)
        let issue = try PaperclipJSON.decoder.decode(Issue.self, from: data)
        XCTAssertEqual(issue.status, .unknown)
        XCTAssertEqual(issue.priority, .unknown)
    }

    func testIssueUpdateEncodesUnassignAsNull() throws {
        let data = try PaperclipJSON.encoder.encode(IssueUpdate(status: .todo, assigneeAgentId: .some(nil)))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(json["status"], .string("todo"))
        XCTAssertEqual(json["assigneeAgentId"], .null)
        XCTAssertNil(json["title"])
    }

    func testErrorParsing() {
        let nested = PaperclipAPIError.from(status: 401, data: Data(#"{"error":{"code":"UNAUTHORIZED","message":"need key"}}"#.utf8))
        XCTAssertEqual(nested.message, "need key")
        XCTAssertEqual(nested.code, "UNAUTHORIZED")
        let flat = PaperclipAPIError.from(status: 409, data: Data(#"{"error":"Another agent owns the task"}"#.utf8))
        XCTAssertEqual(flat.message, "Another agent owns the task")
    }

    func testServerURLNormalization() {
        let client = PaperclipClient(serverURL: URL(string: "http://host:3100/api/")!, token: "")
        XCTAssertEqual(client.serverURL.absoluteString, "http://host:3100")
        XCTAssertNil(client.token)
        XCTAssertEqual(client.absoluteURL("/api/x.png")?.absoluteString, "http://host:3100/api/x.png")
    }
}

final class RunLogTests: XCTestCase {
    func testChunksMergePerStream() {
        let log = HeartbeatRunLog(content: """
        {"ts":"2026-10-20T06:22:22.653Z","stream":"stdout","chunk":"hello ","seq":1}
        {"stream":"stdout","chunk":"world\\n","seq":2}
        {"stream":"stderr","chunk":"oops","seq":3}
        not json
        {"stream":"stdout","chunk":"done","seq":4}
        """)
        XCTAssertEqual(log.chunks.map(\.stream), ["stdout", "stderr", "stdout"])
        XCTAssertEqual(log.chunks.first?.text, "hello world\n")
    }
}
