import Foundation
import Observation
import PaperclipKit

/// The LLM provider used to draft tasks from a sentence. The provider, address and model live
/// in UserDefaults; the API key lives in the Keychain.
@MainActor
@Observable
final class AssistantSettings {
    static let shared = AssistantSettings()

    private static let configKey = "paperclip.assistant.provider"
    private static let profilesKey = "paperclip.assistant.profiles"
    private static let migrationKey = "paperclip.assistant.scopedKeysMigrated"
    private static let migrationAccountKey = "paperclip.assistant.legacyKeyAccount"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyStore: any AssistantKeyStoring
    @ObservationIgnored private var loadingKey = false
    @ObservationIgnored private var restoringProfile = false
    private(set) var credentialError: String?

    var config: LLMProviderConfig {
        didSet {
            // Consent belongs to the saved provider origin, never to an arbitrary new URL.
            if oldValue.credentialAccount != config.credentialAccount && !restoringProfile {
                config.allowInsecureHTTP = false
            }
            if let data = try? JSONEncoder().encode(config) {
                defaults.set(data, forKey: Self.configKey)
            }
            if oldValue.credentialAccount != config.credentialAccount {
                loadingKey = true
                defer { loadingKey = false }
                do {
                    apiKey = try keyStore.read(account: config.credentialAccount) ?? ""
                    credentialError = nil
                } catch {
                    apiKey = ""
                    credentialError = error.localizedDescription
                }
            }
        }
    }

    var apiKey: String {
        didSet {
            guard !loadingKey else { return }
            do {
                try keyStore.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: config.credentialAccount)
                credentialError = nil
            } catch { credentialError = error.localizedDescription }
        }
    }

    init(defaults: UserDefaults = .standard, keyStore: any AssistantKeyStoring = KeychainAssistantKeyStore()) {
        self.defaults = defaults
        self.keyStore = keyStore
        var loaded = defaults.data(forKey: Self.configKey)
            .flatMap { try? JSONDecoder().decode(LLMProviderConfig.self, from: $0) } ?? LLMProviderConfig()
        // Upgrade hand-entered integrations while preserving their model and credential.
        if let url = URL(string: loaded.baseURL) {
            if url.host == "opencode.ai", url.path.contains("/go") { loaded.kind = .openCodeGo }
            if url.host == "openrouter.ai" { loaded.kind = .openRouter }
            if loaded.kind.isIntegration { loaded.baseURL = loaded.kind.defaultBaseURL }
        }
        var key = ""
        var storageError: String?
        do {
            if !defaults.bool(forKey: Self.migrationKey) {
                // Keep the original owner even if migration fails and the user switches services.
                let owner = defaults.string(forKey: Self.migrationAccountKey) ?? loaded.credentialAccount
                defaults.set(owner, forKey: Self.migrationAccountKey)
                if let legacy = try keyStore.read(account: "default") {
                    if try keyStore.read(account: owner) == nil {
                        try keyStore.write(legacy, account: owner)
                        guard try keyStore.read(account: owner) == legacy else { throw AssistantKeyError.verificationFailed }
                    }
                    try keyStore.write(nil, account: "default")
                }
                defaults.set(true, forKey: Self.migrationKey)
            } else if let legacy = try keyStore.read(account: "default"),
                      try keyStore.read(account: loaded.credentialAccount) == legacy {
                // Clean up the retained legacy copy from the first integration build.
                try keyStore.write(nil, account: "default")
            }
            key = try keyStore.read(account: loaded.credentialAccount) ?? ""
        } catch {
            storageError = error.localizedDescription
            key = (try? keyStore.read(account: loaded.credentialAccount)) ?? ""
        }
        config = loaded
        apiKey = key
        credentialError = storageError
        if let data = try? JSONEncoder().encode(loaded) { defaults.set(data, forKey: Self.configKey) }
    }

    var isConfigured: Bool {
        config.endpoint != nil
            && !config.model.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func drafter(sessionID: String) -> TaskDrafter? {
        isConfigured ? TaskDrafter(config: config, apiKey: apiKey, sessionID: sessionID) : nil
    }

    func selectProvider(_ kind: LLMProviderKind) {
        guard kind != config.kind else { return }
        var profiles = defaults.data(forKey: Self.profilesKey)
            .flatMap { try? JSONDecoder().decode([String: LLMProviderConfig].self, from: $0) } ?? [:]
        profiles[config.kind.rawValue] = config
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Self.profilesKey) }
        restoringProfile = true
        defer { restoringProfile = false }
        config = profiles[kind.rawValue] ?? LLMProviderConfig(kind: kind)
    }

    /// "Anthropic · claude-opus-5-5", or nil when nothing is set up yet.
    var summary: String? {
        guard isConfigured else { return nil }
        return "\(config.kind.label) · \(config.model)"
    }

    func reset() {
        do {
            try keyStore.write(nil, account: config.credentialAccount)
            loadingKey = true
            defer { loadingKey = false }
            apiKey = ""
            config.model = ""
            config.supportsStructuredOutputs = nil
            credentialError = nil
        } catch { credentialError = error.localizedDescription }
    }
}

extension LLMProviderKind {
    var label: String {
        switch self {
        case .openCodeGo: return "OpenCode Go"
        case .openRouter: return "OpenRouter"
        case .anthropic: return "Anthropic"
        case .openAICompatible: return AppL10n.text("assistant.openai_compatible", "OpenAI-compatible")
        }
    }
}

extension TaskDraftContext {
    /// The company's agents and names, as the model should see them.
    @MainActor
    static func make(agents: [Agent], app: AppModel, parent: Issue? = nil) -> TaskDraftContext {
        TaskDraftContext(
            agents: agents.filter { $0.status != .terminated }.map {
                AgentChoice(id: $0.id, name: $0.name, role: $0.roleLabel, title: $0.title, capabilities: $0.capabilities)
            },
            companyName: app.company?.name,
            parentTitle: parent?.title)
    }
}
