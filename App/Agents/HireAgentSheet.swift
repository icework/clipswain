import PaperclipKit
import SwiftUI

/// Hire a new agent: identity, manager, runtime (adapter + model), budget and character.
struct HireAgentSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onHire: (Agent) -> Void

    @State private var name = ""
    @State private var title = ""
    @State private var role = "engineer"
    @State private var reportsTo: String?
    @State private var capabilities = ""
    @State private var adapters: [AdapterInfo] = []
    @State private var adapterType = "claude_local"
    @State private var models: [AdapterModel] = []
    @State private var model: String?
    @State private var budgetDollars = "0"
    @State private var paletteId = AgentAppearance.paletteIds.randomElement() ?? "arctic-blue"
    @State private var runner = ActionRunner()

    /// Coding-agent CLIs first; raw process/http adapters last since they need manual config.
    private var sortedAdapters: [AdapterInfo] {
        adapters.filter { $0.disabled != true }.sorted { lhs, rhs in
            let rank: (String) -> Int = { ["claude_local": 0, "codex_local": 1, "cursor": 2, "gemini_local": 3][$0] ?? ($0 == "process" || $0 == "http" ? 9 : 5) }
            return (rank(lhs.type), lhs.displayName) < (rank(rhs.type), rhs.displayName)
        }
    }

    private var preview: Agent {
        var agent = Agent(id: "preview", companyId: "", name: name, role: role, status: .idle, adapterType: adapterType)
        agent.appearance = AgentAppearance(paletteId: paletteId)
        return agent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AgentAvatar(agent: preview, size: 84)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(AgentAppearance.paletteIds, id: \.self) { palette in
                                    let sample: Agent = {
                                        var copy = preview
                                        copy.appearance = AgentAppearance(paletteId: palette)
                                        return copy
                                    }()
                                    AgentAvatar(agent: sample, size: 36)
                                        .padding(3)
                                        .background {
                                            Circle().strokeBorder(palette == paletteId ? Color.accentColor : .clear, lineWidth: 2)
                                        }
                                        .onTapGesture { paletteId = palette }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Section(AgentsL10n.text("identity.title", "Identity")) {
                    TextField(AgentsL10n.text("hire.name_placeholder", "Name (e.g. Grace)"), text: $name)
                    TextField(AgentsL10n.text("hire.title_placeholder", "Title (e.g. Senior iOS Engineer)"), text: $title)
                    Picker(AgentsL10n.text("identity.role", "Role"), selection: $role) {
                        ForEach(AgentRole.all, id: \.self) { Text(AgentRole.label(for: $0)).tag($0) }
                    }
                    Picker(AgentsL10n.text("hire.reports_to", "Reports to"), selection: $reportsTo) {
                        Text(AgentsL10n.text("hire.reports_to_board", "None (reports directly to the board)")).tag(String?.none)
                        ForEach(app.activeAgents) { Text("\($0.name) · \($0.roleLabel)").tag(Optional($0.id)) }
                    }
                }

                Section(AgentsL10n.text("capabilities.title", "Capabilities")) {
                    TextField(AgentsL10n.text("hire.capabilities_placeholder", "Expertise and responsibilities"), text: $capabilities, axis: .vertical).lineLimit(2...6)
                }

                Section {
                    Picker(AgentsL10n.text("runtime.title", "Runtime"), selection: $adapterType) {
                        ForEach(sortedAdapters) { Text($0.displayName).tag($0.type) }
                    }
                    if !models.isEmpty {
                        Picker(AgentsL10n.text("model.title", "Model"), selection: $model) {
                            Text(AgentsL10n.text("model.default", "Default")).tag(String?.none)
                            ForEach(models) { Text($0.label ?? $0.id).tag(Optional($0.id)) }
                        }
                    }
                } header: {
                    Text(AgentsL10n.text("hire.runtime_section", "Execution"))
                } footer: {
                    Text(AgentsL10n.text("hire.runtime_help", "The runtime must be available on the computer hosting Paperclip (for example, Claude Code installed and signed in). Adjust advanced settings in the web app."))
                }

                Section {
                    HStack {
                        Text("$")
                        TextField("0", text: $budgetDollars).keyboardType(.decimalPad)
                    }
                } header: {
                    Text(AgentsL10n.text("budget.monthly", "Monthly budget (USD)"))
                } footer: {
                    Text(AgentsL10n.text("budget.unlimited_note", "Enter 0 for no limit."))
                }
            }
            .navigationTitle(AgentsL10n.text("hire.title", "Hire agent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AgentsL10n.text("action.cancel", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AgentsL10n.text("hire.submit", "Hire")) { Task { await hire() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || runner.isBusy)
                }
            }
            .errorAlert(runner)
            .task { await loadAdapters() }
            .task(id: adapterType) { await loadModels() }
        }
    }

    private func loadAdapters() async {
        guard let client = app.client else { return }
        adapters = (try? await client.adapters()) ?? [AdapterInfo(type: "claude_local")]
        if !sortedAdapters.contains(where: { $0.type == adapterType }), let first = sortedAdapters.first {
            adapterType = first.type
        }
    }

    private func loadModels() async {
        guard let client = app.client, let companyId = app.selectedCompanyId else { return }
        model = nil
        models = (try? await client.adapterModels(companyId: companyId, adapterType: adapterType)) ?? []
    }

    private func hire() async {
        guard let client = app.client, let companyId = app.selectedCompanyId else { return }
        guard let budgetCents = AgentBudget.cents(fromDollars: budgetDollars) else {
            runner.errorMessage = AgentsL10n.text("budget.invalid", "Enter a valid budget amount, such as 12 or 12.50.")
            return
        }
        await runner.run {
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            let trimmedCapabilities = capabilities.trimmingCharacters(in: .whitespacesAndNewlines)
            let agent = try await client.createAgent(
                companyId: companyId,
                NewAgent(
                    name: name.trimmingCharacters(in: .whitespaces), role: role,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle, reportsTo: reportsTo,
                    capabilities: trimmedCapabilities.isEmpty ? nil : trimmedCapabilities,
                    adapterType: adapterType, model: model,
                    budgetMonthlyCents: budgetCents,
                    appearance: AgentAppearance(paletteId: paletteId)))
            app.upsert(agent)
            app.didMutate()
            onHire(agent)
            dismiss()
        }
    }
}
