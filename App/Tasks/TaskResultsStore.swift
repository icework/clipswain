import Foundation
import Observation
import PaperclipKit

enum DeliverableList<Item> {
    case loading
    case loaded([Item])
    case failed(String)
}

enum TaskResultError: LocalizedError {
    case wrongScope
    var errorDescription: String? {
        TasksL10n.text("results.scope_error", "The server returned a result from another task. Refresh and try again.")
    }
}

@MainActor @Observable
final class TaskResultsStore {
    private(set) var documents: DeliverableList<IssueDocumentSummary> = .loading
    private(set) var attachments: DeliverableList<IssueAttachment> = .loading
    private(set) var products: DeliverableList<IssueWorkProduct> = .loading
    private var loadID = UUID()

    func load(client: PaperclipClient, issueID: String, companyID: String,
              isCurrent: () -> Bool = { true }) async {
        let requestID = UUID()
        loadID = requestID
        async let docs = capture { try await client.issueDocuments(issueId: issueID) }
        async let files = capture { try await client.issueAttachments(issueId: issueID) }
        async let links = capture { try await client.issueWorkProducts(issueId: issueID) }
        let values = await (docs, files, links)
        guard !Task.isCancelled, loadID == requestID, isCurrent() else { return }
        documents = scoped(values.0, valid: { $0.issueId == issueID && $0.companyId == companyID }) { items in
            items.sorted {
                let rank: (IssueDocumentSummary) -> Int = { ["report", "summary", "final", "result"].firstIndex(of: $0.key.lowercased()) ?? 4 }
                if rank($0) != rank($1) { return rank($0) < rank($1) }
                return $0.updatedAt > $1.updatedAt
            }
        }
        attachments = scoped(values.1, valid: { $0.issueId == issueID && $0.companyId == companyID }) {
            $0.sorted { $0.createdAt > $1.createdAt }
        }
        products = scoped(values.2, valid: { $0.issueId == issueID && $0.companyId == companyID }) {
            $0.sorted {
                if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }

    private func capture<T>(_ operation: () async throws -> [T]) async -> Result<[T], Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    private func scoped<T>(_ result: Result<[T], Error>, valid: (T) -> Bool,
                           sorted: ([T]) -> [T]) -> DeliverableList<T> {
        switch result {
        case .success(let items):
            guard items.allSatisfy(valid) else { return .failed(TaskResultError.wrongScope.localizedDescription) }
            return .loaded(sorted(items))
        case .failure(let error): return .failed(error.localizedDescription)
        }
    }
}
