import PaperclipKit
import SwiftUI

/// Settings → AI 助手: the LLM provider that turns a sentence into a task.
struct AssistantSettingsView: View {
    @Bindable private var settings = AssistantSettings.shared

    @State private var testState = TestState.idle
    @State private var confirmingReset = false
    @State private var showingModels = false
    @State private var catalog = AssistantModelCatalog()
    @State private var sessionID = UUID().uuidString
    @State private var testTask: Task<Void, Never>?

    private struct CatalogIdentity: Equatable, Hashable {
        let kind: LLMProviderKind
        let key: String
    }
    private var catalogIdentity: CatalogIdentity {
        CatalogIdentity(kind: settings.config.kind, key: settings.apiKey)
    }

    private enum TestState: Equatable {
        case idle, running
        case passed(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AssistantIcon(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppL10n.text("assistant.sentence_title", "Create a task in one sentence")).font(.headline)
                        Text(AppL10n.text("assistant.sentence_help", "Describe what you want to do. The model drafts a title, assignee, priority, and description for you to review before submitting."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(AppL10n.text("assistant.integration", "Integration"), selection: kindBinding) {
                    ForEach(LLMProviderKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            } header: {
                Text(AppL10n.text("assistant.service", "Service"))
            } footer: {
                Text(settings.config.kind.isIntegration
                     ? AppL10n.text("assistant.preset_help", "Enter an API key, then choose a model.")
                     : AppL10n.text("assistant.custom_help", "Use your own service URL and model ID."))
            }

            Section(AppL10n.text("assistant.connection", "Connection")) {
                if !settings.config.kind.isIntegration {
                    LabeledContent(AppL10n.text("common.address", "Address")) {
                        TextField(settings.config.kind.defaultBaseURL, text: $settings.config.baseURL)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if settings.config.endpoint?.scheme?.lowercased() == "http" {
                        Toggle(AppL10n.text("assistant.allow_http", "Allow HTTP for this AI service"), isOn: $settings.config.allowInsecureHTTP)
                        Text(AppL10n.text("assistant.http_warning", "HTTP sends your API key, task text, and agent information without HTTPS protection. Enable only when you trust the network protecting this connection."))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                LabeledContent(AppL10n.text("assistant.api_key", "API key")) {
                    SecureField(AppL10n.text("common.required", "Required"), text: $settings.apiKey)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let message = settings.credentialError {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
                if settings.config.kind.isIntegration {
                    Button { showingModels = true } label: {
                        HStack {
                            Text(AppL10n.text("assistant.model", "Model")).foregroundStyle(.primary)
                            Spacer()
                            Text(settings.config.model.isEmpty ? AppL10n.text("assistant.select_model", "Choose a model") : settings.config.model)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if catalog.isLoading {
                        HStack(spacing: 10) { ProgressView(); Text(AppL10n.text("assistant.fetching_models", "Fetching models…")).foregroundStyle(.secondary) }
                    } else if let modelError = catalog.error {
                        Text(AppL10n.text("assistant.fetch_error", "Could not fetch models: \(modelError)")).font(.footnote).foregroundStyle(.orange)
                    } else if !catalog.models.isEmpty {
                        Text(AppL10n.text("assistant.models_loaded", "\(catalog.models.count) models loaded. Search by name."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent(AppL10n.text("assistant.model", "Model")) {
                        TextField(AppL10n.text("assistant.model_id", "Model ID"), text: $settings.config.model)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }

            Section {
                Button {
                    testTask = Task { await test() }
                } label: {
                    HStack {
                        Label(AppL10n.text("assistant.test_connection", "Test connection"), systemImage: "bolt.horizontal")
                        Spacer()
                        if testState == .running { ProgressView() }
                    }
                }
                .disabled(!settings.isConfigured || testState == .running)
                switch testState {
                case .passed(let title):
                    Label(AppL10n.text("assistant.test_success", "Connected. Sample task title: \(title)"), systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                default:
                    EmptyView()
                }
            } footer: {
                Text(AppL10n.text("assistant.privacy", "To draft a task, your text, company name, and agent list (names, roles, and responsibilities) are sent to this provider. Your API key is stored only in this device’s Keychain."))
            }

            if settings.isConfigured || !settings.apiKey.isEmpty {
                Section {
                    Button(AppL10n.text("assistant.clear_config", "Clear configuration"), role: .destructive) { confirmingReset = true }
                }
            }
        }
        .readableWidth()
        .navigationTitle(AppL10n.text("assistant.title", "AI assistant"))
        .navigationBarTitleDisplayMode(.inline)
        .dismissableKeyboard()
        .onChange(of: settings.config) { _, _ in testTask?.cancel(); testState = .idle }
        .onChange(of: settings.apiKey) { _, _ in testTask?.cancel(); testState = .idle }
        .onDisappear { testTask?.cancel(); testState = .idle }
        .task(id: catalogIdentity) {
            catalog.clear()
            guard settings.config.kind.isIntegration else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await fetchModels()
        }
        .sheet(isPresented: $showingModels) {
            NavigationStack {
                ModelPickerView(models: catalog.models, selectedID: settings.config.model,
                                isLoading: catalog.isLoading, error: catalog.error,
                                refresh: { await fetchModels() }) { model in
                    settings.config.model = model.id
                    settings.config.supportsStructuredOutputs = model.supportsStructuredOutputs
                }
            }
        }
        .confirmationDialog(AppL10n.text("assistant.clear_confirmation", "Clear the AI assistant configuration and API key?"), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(AppL10n.text("common.clear", "Clear"), role: .destructive) { settings.reset() }
        }
    }

    private var kindBinding: Binding<LLMProviderKind> {
        Binding { settings.config.kind } set: { settings.selectProvider($0) }
    }

    @MainActor
    private func fetchModels() async {
        let identity = catalogIdentity
        guard identity.kind.isIntegration else { return }
        await catalog.load {
            try await LLMModelCatalog().fetch(kind: identity.kind, apiKey: identity.key, sessionID: sessionID)
        }
    }

    private func test() async {
        guard !Task.isCancelled else { return }
        guard let drafter = settings.drafter(sessionID: sessionID) else { return }
        testState = .running
        let sample = AppL10n.text("assistant.test_prompt", "Fix the sign-in page crash and add unit tests by this Friday. Low priority.")
        do {
            let draft = try await drafter.draft(from: sample, context: TaskDraftContext(agents: []))
            guard !Task.isCancelled else { return }
            testState = .passed(draft.title)
        } catch {
            guard !Task.isCancelled else { return }
            testState = .failed(error.localizedDescription)
        }
    }
}

private struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let models: [LLMModel]
    let selectedID: String
    let isLoading: Bool
    let error: String?
    var refresh: () async -> Void
    var select: (LLMModel) -> Void
    @State private var search = ""

    private var filtered: [LLMModel] { models.filter { $0.matches(search) } }

    var body: some View {
        List {
            if isLoading && models.isEmpty {
                HStack(spacing: 10) { ProgressView(); Text(AppL10n.text("assistant.fetching_models", "Fetching models…")) }
            } else if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button(AppL10n.text("common.retry", "Retry")) { Task { await refresh() } }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView(models.isEmpty ? AppL10n.text("assistant.no_models", "No models available") : AppL10n.text("assistant.no_matching_models", "No matching models"),
                                       systemImage: "magnifyingglass",
                                       description: Text(models.isEmpty ? AppL10n.text("assistant.no_models_help", "Pull to refresh, or check your API key and try again.") : AppL10n.text("assistant.no_matches_help", "Try a model or provider name.")))
            }
            ForEach(filtered) { model in
                Button {
                    select(model)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name).foregroundStyle(.primary)
                            if model.name != model.id {
                                Text(model.id).font(.caption).foregroundStyle(.secondary)
                            }
                            if let length = model.contextLength {
                                Text(AppL10n.text("assistant.context_tokens", "Context: \(length.formatted(.number.locale(AppL10n.locale))) tokens")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                        if model.id == selectedID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(AppL10n.text("assistant.select_model", "Choose a model"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: AppL10n.text("assistant.search_models", "Search by name or model ID"))
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(AppL10n.text("common.cancel", "Cancel")) { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(AppL10n.text("assistant.refresh_models", "Refresh models")).disabled(isLoading)
            }
        }
    }
}
