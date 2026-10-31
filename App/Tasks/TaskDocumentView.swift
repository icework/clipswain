import PaperclipKit
import SwiftUI

struct TaskDocumentView: View {
    @Environment(AppModel.self) private var app
    let issueID: String
    let issueKey: String
    let companyID: String
    let document: IssueDocumentSummary
    let relatedDocuments: [IssueDocumentSummary]
    @State private var loaded: IssueDocument?
    @State private var error: String?
    @State private var loadID = UUID()
    @State private var sourceClient: PaperclipClient?
    @State private var linkedDocument: IssueDocumentSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if app.client != nil, app.client === sourceClient, app.selectedCompanyId == companyID {
                    if let error { ErrorBanner(message: error) { Task { await load() } } }
                    if let loaded {
                        Text(loaded.title ?? document.displayTitle).font(.title2.bold())
                        HStack {
                            Text(TasksL10n.text("results.revision", "Revision \(loaded.latestRevisionNumber)"))
                            Text(loaded.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        }.font(.caption).foregroundStyle(.secondary)
                        Divider()
                        if loaded.body.isEmpty {
                            Text(TasksL10n.text("results.empty_document", "This document is empty.")).foregroundStyle(.secondary)
                        } else {
                            MarkdownText(source: loaded.body)
                                .environment(\.openURL, OpenURLAction { url in
                                    guard let server = sourceClient?.serverURL,
                                          let resolved = Self.webLink(url, server: server) else { return .discarded }
                                    if let target = Self.documentLink(resolved, server: server, issueID: issueID,
                                                                      issueKey: issueKey, documents: relatedDocuments) {
                                        linkedDocument = target
                                        return .handled
                                    }
                                    return .systemAction(resolved)
                                })
                        }
                    } else if error == nil { ProgressView().frame(maxWidth: .infinity) }
                } else {
                    Text(TasksL10n.text("results.session_changed", "The connection or company changed. Reopen this task to view its results."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .readableWidth()
        .navigationTitle(document.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let loaded, app.client != nil, app.client === sourceClient, app.selectedCompanyId == companyID {
                ShareLink(item: loaded.body) {
                    Label(TasksL10n.text("results.share", "Share document"), systemImage: "square.and.arrow.up")
                }
            }
        }
        .task {
            if sourceClient == nil { sourceClient = app.client }
            await load()
        }
        .refreshable { await load() }
        .navigationDestination(item: $linkedDocument) { target in
            TaskDocumentView(issueID: issueID, issueKey: issueKey, companyID: companyID,
                             document: target, relatedDocuments: relatedDocuments).id(target.id)
        }
    }

    /// Paperclip reports link to other documents/tasks with server-relative URLs.
    /// Resolve those against this connection rather than handing an unusable relative URL to iOS.
    static func webLink(_ url: URL, server: URL) -> URL? {
        guard let resolved = URL(string: url.relativeString, relativeTo: server)?.absoluteURL,
              ["http", "https"].contains(resolved.scheme?.lowercased() ?? ""),
              resolved.host != nil, resolved.user == nil, resolved.password == nil else { return nil }
        return resolved
    }

    /// Open known sibling documents with the existing app connection, without a second
    /// browser login. Links to another host/task continue to use their normal web destination.
    static func documentLink(_ url: URL, server: URL, issueID: String, issueKey: String,
                             documents: [IssueDocumentSummary]) -> IssueDocumentSummary? {
        func port(_ value: URL) -> Int? { value.port ?? (value.scheme == "https" ? 443 : value.scheme == "http" ? 80 : nil) }
        guard url.scheme?.lowercased() == server.scheme?.lowercased(),
              url.host?.lowercased() == server.host?.lowercased(), port(url) == port(server),
              url.pathComponents.dropLast().last == "issues",
              [issueID, issueKey].contains(url.lastPathComponent),
              let fragment = url.fragment?.removingPercentEncoding, fragment.hasPrefix("document-") else { return nil }
        let key = String(fragment.dropFirst("document-".count))
        return documents.first { $0.key == key && $0.issueId == issueID }
    }

    private func load() async {
        guard let client = app.client, client === sourceClient, app.selectedCompanyId == companyID else { return }
        let requestID = UUID()
        loadID = requestID
        do {
            let result = try await client.issueDocument(issueId: issueID, key: document.key)
            guard !Task.isCancelled, loadID == requestID,
                  app.client === client, app.selectedCompanyId == companyID else { return }
            guard result.companyId == companyID, result.issueId == issueID,
                  result.key == document.key, result.id == document.id else { throw TaskResultError.wrongScope }
            loaded = result
            error = nil
        } catch {
            guard !Task.isCancelled, loadID == requestID,
                  app.client === client, app.selectedCompanyId == companyID else { return }
            self.error = error.localizedDescription
        }
    }
}
