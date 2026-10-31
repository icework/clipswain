import XCTest
@testable import PaperclipKit

final class LLMIntegrationTests: XCTestCase {
    let context = TaskDraftContext(agents: [])

    func testLegacyConfigurationDecodesWithoutNewFields() throws {
        let old = Data(#"{"kind":"openai_compatible","baseURL":"https://proxy.example/v1","model":"old-model"}"#.utf8)
        let config = try JSONDecoder().decode(LLMProviderConfig.self, from: old)
        XCTAssertEqual(config.model, "old-model")
        XCTAssertNil(config.supportsStructuredOutputs)
        XCTAssertEqual(config.endpoint?.host, "proxy.example")
    }

    func testPresetsPinDestinationAndSeparateCredentials() throws {
        let go = LLMProviderConfig(kind: .openCodeGo, baseURL: "https://wrong.example", model: "kimi-k3")
        let router = LLMProviderConfig(kind: .openRouter, baseURL: "https://wrong.example", model: "openai/gpt-5")
        XCTAssertEqual(go.endpoint?.host, "opencode.ai")
        XCTAssertEqual(router.endpoint?.host, "openrouter.ai")
        XCTAssertNotEqual(go.credentialAccount, router.credentialAccount)
        let a = LLMProviderConfig(kind: .openAICompatible, baseURL: "https://a.example/v1")
        let b = LLMProviderConfig(kind: .openAICompatible, baseURL: "https://b.example/v1")
        XCTAssertNotEqual(a.credentialAccount, b.credentialAccount)
        XCTAssertNotEqual(a.credentialAccount, LLMProviderConfig(kind: .openAICompatible, baseURL: "http://a.example/v1").credentialAccount)
    }

    func testGoRoutesAndSessionHeaderOnEveryProtocol() throws {
        let routes: [(String, String, String)] = [
            ("kimi-k3", "/openai/v1/chat/completions", "Authorization"),
            ("minimax-m3.1-flash-free", "/openai/v1/chat/completions", "Authorization"),
            ("minimax-m3", "/anthropic/v1/messages", "x-api-key"),
            ("qwen3.8-max", "/anthropic/v1/messages", "x-api-key"),
            ("claude-haiku-5-5", "/anthropic/v1/messages", "x-api-key"),
            ("gpt-6-luna", "/openai/v1/responses", "Authorization"),
            ("grok-4.7", "/openai/v1/responses", "Authorization"),
            ("muse-spark-1.3-contributor", "/openai/v1/responses", "Authorization"),
            ("gemini-4-argon-contributor", "/google/v1beta/models/gemini-4-argon-contributor:generateContent", "x-goog-api-key"),
        ]
        for (model, path, auth) in routes {
            let config = LLMProviderConfig(kind: .openCodeGo, model: model)
            let drafter = TaskDrafter(config: config, apiKey: "test-only", sessionID: "draft-conversation")
            for text in ["Create a task", "Revise the task"] {
                let request = try drafter.makeRequest(text: text, context: context)
                XCTAssertEqual(request.url?.path, "/inference/go" + path)
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-opencode-session"), "draft-conversation")
                XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), TaskDrafter.userAgent)
                XCTAssertTrue(TaskDrafter.userAgent.hasPrefix("Clipswain"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only", auth)
                let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
                XCTAssertNil(body["output_config"])
                XCTAssertNil(body["fallbacks"])
            }
        }
        let first = TaskDrafter(config: .init(kind: .openCodeGo, model: "kimi-k3"), apiKey: "k")
        let second = TaskDrafter(config: first.config, apiKey: "k")
        XCTAssertNotEqual(first.sessionID, second.sessionID)
    }

    func testRouterUsesCapabilityAndDoesNotSendGoHeader() throws {
        var config = LLMProviderConfig(kind: .openRouter, model: "provider/model")
        var request = try TaskDrafter(config: config, apiKey: "test-only").makeRequest(text: "x", context: context)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-opencode-session"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Clipswain")
        var body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertNil(body["response_format"])
        XCTAssertNil(body["max_tokens"])
        XCTAssertTrue(body["messages"]?.arrayValue?.first?["content"]?.stringValue?.contains("assigneeAgentId") == true)
        config.supportsStructuredOutputs = true
        request = try TaskDrafter(config: config, apiKey: "test-only").makeRequest(text: "x", context: context)
        body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["response_format"]?["type"], .string("json_schema"))
    }

    func testCatalogFilteringSearchAndDeduplication() throws {
        let fixture = Data(#"""
        {"data":[
          {"id":"vendor/alpha","name":"Vendor Alpha","context_length":128000,"supported_parameters":["structured_outputs"],"architecture":{"output_modalities":["text"]}},
          {"id":"kimi-k3"},
          {"id":"vendor/alpha","name":"duplicate"},
          {"id":"image-only","architecture":{"output_modalities":["image"]}},
          {"id":"vendor/alpha:batch","architecture":{"output_modalities":["text"]}},
          {"id":" "}, {"name":"missing id"}
        ]}
        """#.utf8)
        let models = try LLMModelCatalog.parse(fixture)
        XCTAssertEqual(models.count, 2)
        let alpha = try XCTUnwrap(models.first { $0.id == "vendor/alpha" })
        XCTAssertEqual(alpha.contextLength, 128000)
        XCTAssertTrue(alpha.supportsStructuredOutputs)
        XCTAssertTrue(alpha.matches("  VENDOR alpha  "))
        XCTAssertFalse(alpha.matches("vendor beta"))
        XCTAssertTrue(models.allSatisfy { $0.matches("") })
        XCTAssertThrowsError(try LLMModelCatalog.parse(Data(#"{"error":"bad"}"#.utf8)))
        XCTAssertTrue(try LLMModelCatalog.parse(Data(#"{"data":[]}"#.utf8)).isEmpty)
    }

    func testCatalogRequestUsesOwnEndpointAndHeaders() throws {
        let catalog = LLMModelCatalog()
        let go = try catalog.makeRequest(kind: .openCodeGo, apiKey: " key ", sessionID: "catalog-session")
        XCTAssertEqual(go.url?.absoluteString, "https://opencode.ai/inference/go/v1/models")
        XCTAssertEqual(go.value(forHTTPHeaderField: "x-opencode-session"), "catalog-session")
        XCTAssertEqual(go.value(forHTTPHeaderField: "Authorization"), "Bearer key")
        let router = try catalog.makeRequest(kind: .openRouter, apiKey: "", sessionID: "s")
        XCTAssertEqual(router.url?.absoluteString, "https://openrouter.ai/api/v1/models")
        XCTAssertNil(router.value(forHTTPHeaderField: "x-opencode-session"))
        XCTAssertNil(router.value(forHTTPHeaderField: "Authorization"))
    }

    func testResponsesAndGoogleParsing() throws {
        let output = #"{"title":"Fix login","description":null,"assigneeAgentId":null,"priority":"high"}"#
        let responses: [String: Any] = ["status": "completed", "output": [
            ["type": "reasoning"],
            ["type": "message", "content": [["type": "output_text", "text": output]]]
        ]]
        XCTAssertEqual(try TaskDrafter.parse(JSONSerialization.data(withJSONObject: responses), wireProtocol: .responses, context: context).title, "Fix login")
        let google: [String: Any] = ["candidates": [[
            "finishReason": "STOP",
            "content": ["parts": [
                ["thought": true, "text": "internal reasoning"],
                ["text": output]
            ]]
        ]]]
        XCTAssertEqual(try TaskDrafter.parse(JSONSerialization.data(withJSONObject: google), wireProtocol: .google, context: context).priority, .high)
        XCTAssertThrowsError(try TaskDrafter.parse(Data(#"{"status":"incomplete"}"#.utf8), wireProtocol: .responses, context: context)) {
            XCTAssertEqual($0 as? TaskDraftError, .truncated)
        }
        XCTAssertThrowsError(try TaskDrafter.parse(Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8), wireProtocol: .google, context: context)) {
            XCTAssertEqual($0 as? TaskDraftError, .refused)
        }
    }

    // Opt-in, read-only real-catalog validation. No secret or generation spend is needed.
    func testLiveCatalogs() async throws {
        guard ProcessInfo.processInfo.environment["PAPERCLIP_TEST_MODEL_CATALOGS"] == "1" else {
            throw XCTSkip("Set PAPERCLIP_TEST_MODEL_CATALOGS=1 to check live model catalogs")
        }
        for kind in [LLMProviderKind.openCodeGo, .openRouter] {
            let models = try await LLMModelCatalog().fetch(kind: kind, apiKey: "", sessionID: UUID().uuidString)
            XCTAssertFalse(models.isEmpty)
            XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        }
    }
}
