import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class AssistantModelCatalogTests: XCTestCase {
    private func result(_ id: String) throws -> [LLMModel] {
        try LLMModelCatalog.parse(JSONSerialization.data(withJSONObject: ["data": [["id": id]]]))
    }

    func testOlderFailureCannotOverwriteNewSuccess() async throws {
        let catalog = AssistantModelCatalog()
        let pending = PendingModels()
        let first = Task { await catalog.load { try await pending.wait() } }
        await fulfillment(of: [pending.started], timeout: 2)
        let models = try result("new-model")
        await catalog.load { models }
        pending.finish(.failure(URLError(.timedOut)))
        await first.value
        XCTAssertEqual(catalog.models.map(\.id), ["new-model"])
        XCTAssertNil(catalog.error)
        XCTAssertFalse(catalog.isLoading)
    }

    func testOlderCompletionCannotClearNewLoadingState() async throws {
        let catalog = AssistantModelCatalog()
        let old = PendingModels(), new = PendingModels()
        let first = Task { await catalog.load { try await old.wait() } }
        await fulfillment(of: [old.started], timeout: 2)
        let second = Task { await catalog.load { try await new.wait() } }
        await fulfillment(of: [new.started], timeout: 2)
        old.finish(.success(try result("old-model")))
        await first.value
        XCTAssertTrue(catalog.isLoading)
        XCTAssertTrue(catalog.models.isEmpty)
        new.finish(.success(try result("new-model")))
        await second.value
        XCTAssertFalse(catalog.isLoading)
        XCTAssertEqual(catalog.models.map(\.id), ["new-model"])
    }

    func testSwitchingProviderInvalidatesInFlightResult() async throws {
        let catalog = AssistantModelCatalog()
        let pending = PendingModels()
        let task = Task { await catalog.load { try await pending.wait() } }
        await fulfillment(of: [pending.started], timeout: 2)
        catalog.clear()
        pending.finish(.success(try result("old-provider-model")))
        await task.value
        XCTAssertTrue(catalog.models.isEmpty)
        XCTAssertFalse(catalog.isLoading)
        XCTAssertNil(catalog.error)
    }

    func testCancellationRestoresIdleAndAllowsRetry() async throws {
        let catalog = AssistantModelCatalog()
        let pending = PendingModels()
        let task = Task { await catalog.load { try await pending.wait() } }
        await fulfillment(of: [pending.started], timeout: 2)
        task.cancel()
        pending.finish(.failure(CancellationError()))
        await task.value
        XCTAssertFalse(catalog.isLoading)
        XCTAssertNil(catalog.error)
        let models = try result("retry-model")
        await catalog.load { models }
        XCTAssertEqual(catalog.models.map(\.id), ["retry-model"])
    }
}

@MainActor
private final class PendingModels {
    let started = XCTestExpectation(description: "request started")
    var continuation: CheckedContinuation<[LLMModel], Error>?
    func wait() async throws -> [LLMModel] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func finish(_ result: Result<[LLMModel], Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
