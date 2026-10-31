import Foundation
import Observation
import PaperclipKit

/// Refreshes can overlap (automatic load, pull-to-refresh, retry). Only the newest
/// request may publish results, including errors and loading state.
@MainActor
@Observable
final class AssistantModelCatalog {
    private(set) var models: [LLMModel] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var requestID = UUID()

    func clear() {
        requestID = UUID()
        models = []
        error = nil
        isLoading = false
    }

    func load(_ fetch: () async throws -> [LLMModel]) async {
        guard !Task.isCancelled else { return }
        let id = UUID()
        requestID = id
        isLoading = true
        error = nil
        defer { if requestID == id { isLoading = false } }
        do {
            let result = try await fetch()
            guard !Task.isCancelled, requestID == id else { return }
            models = result
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            self.error = error.localizedDescription
        }
    }
}
