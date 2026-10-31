import XCTest
@testable import PaperclipKit

final class TaskDrafterTests: XCTestCase {
    private let context = TaskDraftContext(
        agents: [
            .init(id: "a-grace", name: "Grace", role: "engineer", title: "iOS Engineer"),
            .init(id: "a-ada", name: "Ada", role: "ceo"),
        ],
        companyName: "Northwind Labs",
        now: Date(timeIntervalSince1970: 1_792_540_800),
        timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    private func body(_ request: URLRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
    }

    // MARK: Endpoint

    func testEndpointNormalization() {
        XCTAssertEqual(LLMProviderConfig(kind: .anthropic).endpoint?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(LLMProviderConfig(kind: .anthropic, baseURL: "https://proxy.example/v1/").endpoint?.absoluteString,
                       "https://proxy.example/v1/messages")
        XCTAssertEqual(LLMProviderConfig(kind: .openAICompatible, baseURL: "https://api.deepseek.com/").endpoint?.absoluteString,
                       "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(LLMProviderConfig(kind: .openAICompatible, baseURL: "http://10.0.0.2:11434/v1/chat/completions").endpoint?.absoluteString,
                       "http://10.0.0.2:11434/v1/chat/completions")
        XCTAssertNil(LLMProviderConfig(kind: .anthropic, baseURL: "  ").endpoint)
    }

    func testMissingKeyOrModelIsNotConfigured() {
        let noKey = TaskDrafter(config: LLMProviderConfig(), apiKey: " ")
        XCTAssertThrowsError(try noKey.makeRequest(text: "x", context: context)) {
            XCTAssertEqual($0 as? TaskDraftError, .notConfigured)
        }
        let noModel = TaskDrafter(config: LLMProviderConfig(kind: .openAICompatible), apiKey: "k")
        XCTAssertThrowsError(try noModel.makeRequest(text: "x", context: context)) {
            XCTAssertEqual($0 as? TaskDraftError, .notConfigured)
        }
    }

    // MARK: Requests

    func testAnthropicRequest() throws {
        let request = try TaskDrafter(config: LLMProviderConfig(), apiKey: "sk-test")
            .makeRequest(text: "让 Grace 修登录崩溃", context: context)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")

        let json = try body(request)
        XCTAssertEqual(json["model"], .string("claude-opus-5-5"))
        XCTAssertEqual(json["fallbacks"], .string("default"))
        XCTAssertNil(json["thinking"])
        XCTAssertEqual(json["output_config"]?["effort"], .string("low"))
        let schema = try XCTUnwrap(json["output_config"]?["format"]?["schema"])
        XCTAssertEqual(json["output_config"]?["format"]?["type"], .string("json_schema"))
        XCTAssertEqual(schema["additionalProperties"], .bool(false))
        let assigneeEnum = schema["properties"]?["assigneeAgentId"]?["anyOf"]?.arrayValue?.first?["enum"]
        XCTAssertEqual(assigneeEnum, .array([.string("a-grace"), .string("a-ada")]))

        let message = try XCTUnwrap(json["messages"]?.arrayValue?.first?["content"]?.stringValue)
        XCTAssertTrue(message.contains("Today: 2026-10-20 Tuesday"))
        XCTAssertTrue(message.contains("\"name\":\"Grace\""))
        XCTAssertTrue(message.contains("<request>\n让 Grace 修登录崩溃\n</request>"))
    }

    func testAnthropicProxySkipsFallbacks() throws {
        let config = LLMProviderConfig(kind: .anthropic, baseURL: "https://gateway.example.com")
        let request = try TaskDrafter(config: config, apiKey: "k").makeRequest(text: "x", context: context)
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))
        XCTAssertNil(try body(request)["fallbacks"])
    }

    func testOpenAICompatibleRequest() throws {
        let config = LLMProviderConfig(kind: .openAICompatible, baseURL: "https://api.example.com/v1", model: "some-model")
        let request = try TaskDrafter(config: config, apiKey: "k").makeRequest(text: "x", context: context)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let json = try body(request)
        XCTAssertEqual(json["messages"]?.arrayValue?.first?["role"], .string("system"))
        XCTAssertEqual(json["response_format"]?["json_schema"]?["strict"], .bool(true))
    }

    func testNoAgentsMakesAssigneeNullOnly() {
        let schema = TaskDrafter.schema(for: TaskDraftContext(agents: []))
        XCTAssertEqual(schema["properties"]?["assigneeAgentId"], .object(["type": .string("null")]))
    }

    // MARK: Responses

    func testParsesAnthropicResponseAfterThinking() throws {
        let data = Data(#"""
        {"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},
         {"type":"text","text":"{\"title\":\"修复登录页崩溃\",\"description\":\"- 截止 2026-10-21\",\"assigneeAgentId\":\"a-grace\",\"priority\":\"critical\"}"}]}
        """#.utf8)
        let draft = try TaskDrafter.parse(data, kind: .anthropic, context: context)
        XCTAssertEqual(draft, TaskDraft(title: "修复登录页崩溃", description: "- 截止 2026-10-21", assigneeAgentId: "a-grace", priority: .critical))
    }

    func testAnthropicRefusalAndTruncation() {
        XCTAssertThrowsError(try TaskDrafter.parse(Data(#"{"stop_reason":"refusal","content":[]}"#.utf8), kind: .anthropic, context: context)) {
            XCTAssertEqual($0 as? TaskDraftError, .refused)
        }
        XCTAssertThrowsError(try TaskDrafter.parse(Data(#"{"stop_reason":"max_tokens","content":[]}"#.utf8), kind: .anthropic, context: context)) {
            XCTAssertEqual($0 as? TaskDraftError, .truncated)
        }
    }

    func testParsesOpenAIResponseWithFence() throws {
        let data = Data(#"""
        {"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"```json\n{\"title\":\"Write release notes\",\"description\":null,\"assigneeAgentId\":null,\"priority\":null}\n```"}}]}
        """#.utf8)
        let draft = try TaskDrafter.parse(data, kind: .openAICompatible, context: context)
        XCTAssertEqual(draft, TaskDraft(title: "Write release notes"))
    }

    func testDropsUnknownAssigneeAndPriority() {
        let draft = TaskDrafter.draft(
            fromJSONText: #"{"title":"T","description":"  ","assigneeAgentId":"someone-else","priority":"urgent"}"#,
            context: context)
        XCTAssertEqual(draft, TaskDraft(title: "T"))
    }

    func testEmptyTitleIsUnreadable() {
        XCTAssertNil(TaskDrafter.draft(fromJSONText: #"{"title":"  "}"#, context: context))
        XCTAssertNil(TaskDrafter.draft(fromJSONText: "no json here", context: context))
    }

    func testErrorMessageExtraction() {
        XCTAssertEqual(TaskDrafter.errorMessage(from: Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)),
                       "invalid x-api-key")
        XCTAssertEqual(TaskDrafter.errorMessage(from: Data("Bad Gateway".utf8)), "Bad Gateway")
    }
}
