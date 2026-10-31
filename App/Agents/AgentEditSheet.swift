import PaperclipKit
import SwiftUI

struct AgentEditSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let agent: Agent
    let onSave: (Agent) -> Void

    @State private var name: String
    @State private var title: String
    @State private var role: String
    @State private var capabilities: String
    @State private var budgetDollars: String
    @State private var paletteId: String
    @State private var runner = ActionRunner()

    init(agent: Agent, onSave: @escaping (Agent) -> Void) {
        self.agent = agent
        self.onSave = onSave
        _name = State(initialValue: agent.name)
        _title = State(initialValue: agent.title ?? "")
        _role = State(initialValue: agent.role)
        _capabilities = State(initialValue: agent.capabilities ?? "")
        _budgetDollars = State(initialValue: AgentBudget.dollarsText(cents: agent.budgetMonthlyCents))
        _paletteId = State(initialValue: agent.resolvedAppearance.paletteId ?? AgentAppearance.paletteIds[0])
    }

    private var preview: Agent {
        var copy = agent
        copy.appearance = AgentAppearance(paletteId: paletteId)
        return copy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        AgentAvatar(agent: preview, size: 96)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(AgentAppearance.paletteIds, id: \.self) { palette in
                                    PaletteSwatch(agent: agent, paletteId: palette, selected: palette == paletteId)
                                        .onTapGesture { paletteId = palette }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text(AgentsL10n.text("appearance.title", "Appearance"))
                } footer: {
                    if agent.resolvedAppearance.customAvatarAssetId != nil {
                        Text(AgentsL10n.text("appearance.custom_avatar_note", "This agent uses a custom avatar. Choosing a palette will not replace it."))
                    }
                }

                Section(AgentsL10n.text("identity.title", "Identity")) {
                    TextField(AgentsL10n.text("identity.name", "Name"), text: $name)
                    TextField(AgentsL10n.text("identity.job_title", "Title"), text: $title)
                    Picker(AgentsL10n.text("identity.role", "Role"), selection: $role) {
                        ForEach(AgentRole.all, id: \.self) { Text(AgentRole.label(for: $0)).tag($0) }
                        if !AgentRole.all.contains(role) { Text(role).tag(role) }
                    }
                }
                Section(AgentsL10n.text("capabilities.title", "Capabilities")) {
                    TextField(AgentsL10n.text("capabilities.placeholder", "Areas of expertise"), text: $capabilities, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    HStack {
                        Text("$")
                        TextField("0", text: $budgetDollars).keyboardType(.decimalPad)
                    }
                } header: {
                    Text(AgentsL10n.text("budget.monthly", "Monthly budget (USD)"))
                } footer: {
                    Text(AgentsL10n.text("budget.pause_note", "Enter 0 for no limit. The agent pauses automatically when it exceeds its budget."))
                }
            }
            .navigationTitle(AgentsL10n.text("edit.title", "Edit \(agent.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AgentsL10n.text("action.cancel", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AgentsL10n.text("action.save", "Save")) { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || runner.isBusy)
                }
            }
            .errorAlert(runner)
        }
    }

    private func save() async {
        guard let client = app.client else { return }
        var update = AgentUpdate()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName != agent.name { update.name = trimmedName }
        if title != (agent.title ?? "") { update.title = title }
        if role != agent.role { update.role = role }
        if capabilities != (agent.capabilities ?? "") { update.capabilities = capabilities }
        if budgetDollars != AgentBudget.dollarsText(cents: agent.budgetMonthlyCents) {
            guard let cents = AgentBudget.cents(fromDollars: budgetDollars) else {
                runner.errorMessage = AgentsL10n.text("budget.invalid", "Enter a valid budget amount, such as 12 or 12.50.")
                return
            }
            if cents != (agent.budgetMonthlyCents ?? 0) { update.budgetMonthlyCents = cents }
        }
        if paletteId != agent.resolvedAppearance.paletteId {
            var appearance = AgentAppearance(paletteId: paletteId)
            appearance.customAvatarAssetId = agent.appearance?.customAvatarAssetId
            update.appearance = appearance
        }
        await runner.run {
            let saved = try await client.updateAgent(id: agent.id, update)
            onSave(saved)
            dismiss()
        }
    }
}

private struct PaletteSwatch: View {
    let agent: Agent
    let paletteId: String
    let selected: Bool

    private var sample: Agent {
        var copy = agent
        copy.appearance = AgentAppearance(paletteId: paletteId)
        return copy
    }

    var body: some View {
        AgentAvatar(agent: sample, size: 44)
            .padding(4)
            .background {
                Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
            }
            .accessibilityLabel(paletteId)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
