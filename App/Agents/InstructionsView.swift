import PaperclipKit
import SwiftUI

/// The agent's instruction bundle (AGENTS.md and friends).
struct InstructionsView: View {
    @Environment(AppModel.self) private var app
    let agent: Agent

    @State private var bundle: AgentInstructionsBundle?
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                Section { ErrorBanner(message: loadError) { Task { await load() } } }
            }
            if let bundle {
                Section {
                    LabeledContent(AgentsL10n.text("mode.title", "Mode"), value: modeLabel(bundle.mode))
                    LabeledContent(AgentsL10n.text("instructions.entry_file", "Entry file"), value: bundle.entryFile)
                    if let root = bundle.rootPath {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AgentsL10n.text("instructions.location", "Location")).font(.caption).foregroundStyle(.secondary)
                            Text(root).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                if bundle.legacyPromptTemplateActive == true {
                    Section {
                        Label(AgentsL10n.text("instructions.legacy_note", "This agent still uses a legacy prompt template. Migrate it in the web app."), systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
                Section(AgentsL10n.text("instructions.files", "Files")) {
                    if bundle.files.isEmpty {
                        Text(AgentsL10n.text("instructions.empty", "No instruction files yet.")).foregroundStyle(.secondary)
                        if bundle.mode != "external" && (bundle.editable || bundle.mode == nil) {
                            NavigationLink {
                                InstructionFileView(agent: agent, path: bundle.entryFile, bundleMode: bundle.mode, isNew: true)
                            } label: {
                                Label(AgentsL10n.text("instructions.create", "Create \(bundle.entryFile)"), systemImage: "plus")
                            }
                        }
                    }
                    ForEach(bundle.orderedFiles) { file in
                        NavigationLink {
                            InstructionFileView(agent: agent, path: file.path, bundleMode: bundle.mode, isNew: false)
                        } label: {
                            HStack {
                                Image(systemName: file.markdown == true ? "doc.richtext" : "doc.plaintext")
                                    .foregroundStyle(file.isEntryFile ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.path).font(.body.monospaced())
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
                                         + (file.isEntryFile ? AgentsL10n.text("instructions.entry_suffix", " · Entry") : "")
                                         + (file.editable ? "" : AgentsL10n.text("instructions.read_only_suffix", " · Read-only")))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(file.binary == true)
                    }
                }
                if let warnings = bundle.warnings, !warnings.isEmpty {
                    Section(AgentsL10n.text("notices.title", "Notices")) {
                        ForEach(warnings, id: \.self) { Text($0).font(.footnote) }
                    }
                }
            } else if loadError == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .readableWidth()
        .navigationTitle(AgentsL10n.text("instructions.title", "Instructions for \(agent.name)"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func modeLabel(_ mode: String?) -> String {
        switch mode {
        case "managed": return AgentsL10n.text("instructions.mode.managed", "Managed by Paperclip")
        case "external": return AgentsL10n.text("instructions.mode.external", "External directory")
        default: return AgentsL10n.text("instructions.mode.unset", "Not configured")
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            bundle = try await client.instructionsBundle(agentId: agent.id)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Reads one instruction file as rendered Markdown, with an editor for editable files.
struct InstructionFileView: View {
    @Environment(AppModel.self) private var app
    let agent: Agent
    let path: String
    let bundleMode: String?

    /// True until the new file has been saved once; later saves edit it with a base.
    @State private var creating: Bool
    @State private var file: AgentInstructionsFile?
    @State private var draft = ""
    @State private var editing = false
    @State private var showRaw = false
    @State private var loadError: String?
    @State private var runner = ActionRunner()

    init(agent: Agent, path: String, bundleMode: String?, isNew: Bool) {
        self.agent = agent
        self.path = path
        self.bundleMode = bundleMode
        _creating = State(initialValue: isNew)
    }

    private var isDirty: Bool { draft != (file?.content ?? "") }

    private var canEdit: Bool { file?.isWritable(bundleMode: bundleMode) ?? false }

    var body: some View {
        Group {
            if editing {
                TextEditor(text: $draft)
                    .font(.system(.callout, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 8)
            } else if let file {
                ScrollView {
                    if bundleMode == "external" && file.isEntryFile == true {
                        Label(AgentsL10n.text("instructions.external_note", "This instruction file is in an external directory and is read-only. To edit it on your phone, first migrate it to Paperclip-managed storage in the web app."), systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .top])
                    }
                    Group {
                        if showRaw || file.markdown == false {
                            Text(file.content)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MarkdownText(source: file.content)
                        }
                    }
                    .padding()
                }
            } else if let loadError {
                ContentUnavailableView(AgentsL10n.text("instructions.load_failed", "Unable to read file"), systemImage: "doc.questionmark", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(path)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AgentsL10n.text("action.cancel", "Cancel")) {
                        draft = file?.content ?? ""
                        editing = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AgentsL10n.text("action.save", "Save")) { Task { await save() } }
                        .disabled(!isDirty || runner.isBusy)
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    if file != nil {
                        Button {
                            showRaw.toggle()
                        } label: {
                            Image(systemName: showRaw ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                        }
                        .accessibilityLabel(showRaw ? AgentsL10n.text("instructions.show_formatted", "Show formatted text") : AgentsL10n.text("instructions.show_source", "Show source"))
                    }
                    if canEdit {
                        Button(AgentsL10n.text("action.edit", "Edit")) {
                            draft = file?.content ?? ""
                            editing = true
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(editing && isDirty)
        .errorAlert(runner)
        .task { await load() }
    }

    private func load() async {
        guard let client = app.client, file == nil else { return }
        if creating {
            file = AgentInstructionsFile(path: path, content: "", isEntryFile: true, editable: true)
            draft = ""
            editing = true
            return
        }
        do {
            file = try await client.instructionsFile(agentId: agent.id, path: path)
            draft = file?.content ?? ""
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        guard let client = app.client, let file else { return }
        await runner.run {
            let write = creating
                ? AgentInstructionsFileWrite(path: path, content: draft)
                : AgentInstructionsFileWrite.editing(file, content: draft, bundleMode: bundleMode)
            _ = try await client.writeInstructionsFile(agentId: agent.id, write)
            // Re-read: the next edit needs the new revision id / hash as its base.
            let saved = try await client.instructionsFile(agentId: agent.id, path: path)
            self.file = saved
            draft = saved.content
            creating = false
            editing = false
        }
    }
}
