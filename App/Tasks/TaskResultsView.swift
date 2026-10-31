import PaperclipKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct TaskResultsView: View {
    @Environment(AppModel.self) private var app
    let issueID: String
    let issueKey: String
    let companyID: String
    @State private var store = TaskResultsStore()
    @State private var previewURL: URL?
    @State private var previewDirectory: URL?
    @State private var downloadingID: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var fileError: String?
    @State private var failedAttachment: IssueAttachment?
    @State private var sourceClient: PaperclipClient?

    var body: some View {
        List {
            if app.selectedCompanyId == companyID, app.client != nil, app.client === sourceClient {
                Section {
                    Text(TasksL10n.text("results.help", "Reports and files saved to this task appear here. Agent replies are in Discussion; execution logs are in Timeline."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(TasksL10n.text("results.documents", "Documents")) {
                    resource(store.documents) { document in
                        NavigationLink {
                            TaskDocumentView(issueID: issueID, issueKey: issueKey, companyID: companyID,
                                             document: document, relatedDocuments: documentList)
                                .id(document.id)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.displayTitle)
                                    Text(document.key).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "doc.text") }
                        }
                    }
                }
                Section(TasksL10n.text("results.attachments", "Attachments")) {
                    resource(store.attachments) { attachment in
                        Button { preview(attachment) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "paperclip")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(attachment.displayName).foregroundStyle(.primary)
                                    Text(ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if downloadingID == attachment.id { ProgressView() }
                                else { Image(systemName: "arrow.down.circle") }
                            }
                        }.disabled(downloadingID != nil)
                    }
                    if let fileError {
                        ErrorBanner(message: fileError) {
                            if let failedAttachment { preview(failedAttachment) }
                        }
                    }
                }
                Section(TasksL10n.text("results.deliverables", "Deliverables")) {
                    resource(store.products) { product in
                        productRow(product)
                    }
                }
            } else {
                Text(TasksL10n.text("results.session_changed", "The connection or company changed. Reopen this task to view its results."))
            }
        }
        .listStyle(.insetGrouped)
        .readableWidth()
        .navigationTitle(TasksL10n.text("results.title", "Results & deliverables"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if sourceClient == nil { sourceClient = app.client }
            await load()
        }
        .refreshable { await load() }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, url in if url == nil { clearPreview() } }
        .onDisappear {
            downloadTask?.cancel()
            if previewURL == nil { clearPreview() }
        }
    }

    private var documentList: [IssueDocumentSummary] {
        if case .loaded(let documents) = store.documents { return documents }
        return []
    }

    @ViewBuilder
    private func resource<Item: Identifiable, Row: View>(_ state: DeliverableList<Item>,
                                                        @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        switch state {
        case .loading: ProgressView()
        case .failed(let message): ErrorBanner(message: message) { Task { await load() } }
        case .loaded(let items):
            if items.isEmpty {
                Text(TasksL10n.text("results.none", "Nothing saved yet")).foregroundStyle(.secondary)
            } else { ForEach(items, content: row) }
        }
    }

    @ViewBuilder
    private func productRow(_ product: IssueWorkProduct) -> some View {
        // An uploaded file is also a work product on recent servers. Reuse its authenticated
        // preview rather than opening an unauthenticated API URL in Safari.
        if let attachmentID = product.metadata?["attachmentId"]?.stringValue,
           case .loaded(let files) = store.attachments,
           let attachment = files.first(where: { $0.id == attachmentID }) {
            Button { preview(attachment) } label: { productLabel(product, symbol: "paperclip") }
                .disabled(downloadingID != nil)
        } else if let url = product.webURL, !isServerAPI(url) {
            Link(destination: url) { productLabel(product, symbol: "arrow.up.right.square") }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                productLabel(product, symbol: "shippingbox")
                if let url = product.url, !url.isEmpty {
                    Text(url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(TasksL10n.text("results.local_path", "This location cannot be opened directly on iPhone. Check Documents or Attachments for a saved copy."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func productLabel(_ product: IssueWorkProduct, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.title).foregroundStyle(.primary)
                if let summary = product.summary, !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(product.status).font(.caption2).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: symbol) }
    }

    private func isServerAPI(_ url: URL) -> Bool {
        guard let server = app.client?.serverURL else { return false }
        return url.host == server.host && url.port == server.port && url.path.hasPrefix("/api/")
    }

    private func load() async {
        guard let client = app.client, client === sourceClient, app.selectedCompanyId == companyID else { return }
        await store.load(client: client, issueID: issueID, companyID: companyID) {
            app.client === client && app.selectedCompanyId == companyID
        }
    }

    private func preview(_ attachment: IssueAttachment) {
        guard downloadingID == nil, let client = app.client, client === sourceClient, app.selectedCompanyId == companyID else { return }
        fileError = nil
        failedAttachment = nil
        downloadingID = attachment.id
        downloadTask = Task { @MainActor in
            defer { downloadingID = nil }
            var temporaryFile: URL?
            var directory: URL?
            do {
                let file = try await client.downloadIssueAttachment(id: attachment.id)
                temporaryFile = file
                try Task.checkCancellation()
                guard app.client === client, app.selectedCompanyId == companyID else { throw CancellationError() }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                directory = folder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = Self.safeFilename(attachment.displayName, contentType: attachment.contentType)
                let destination = folder.appendingPathComponent(name)
                try FileManager.default.moveItem(at: file, to: destination)
                clearPreview()
                previewDirectory = folder
                previewURL = destination
                directory = nil
            } catch {
                if !(error is CancellationError), !Task.isCancelled,
                   app.client === client, app.selectedCompanyId == companyID {
                    fileError = error.localizedDescription
                    failedAttachment = attachment
                }
            }
            if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
            if let directory { try? FileManager.default.removeItem(at: directory) }
        }
    }

    static func safeFilename(_ name: String, contentType: String? = nil) -> String {
        let component = name.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? ""
        let clean = component.components(separatedBy: .controlCharacters).joined()
        let filename = clean.isEmpty || clean == "." || clean == ".." ? "attachment" : String(clean.suffix(180))
        if (filename as NSString).pathExtension.isEmpty,
           let contentType, let ext = UTType(mimeType: contentType)?.preferredFilenameExtension {
            return filename + "." + ext
        }
        return filename
    }

    private func clearPreview() {
        if let previewDirectory { try? FileManager.default.removeItem(at: previewDirectory) }
        previewDirectory = nil
    }
}
