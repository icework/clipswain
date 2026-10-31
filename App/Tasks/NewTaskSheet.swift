import PaperclipKit
import SwiftUI

struct NewTaskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var parent: Issue?
    var onCreate: (Issue) -> Void

    init(parent: Issue? = nil, initialAssigneeId: String? = nil, onCreate: @escaping (Issue) -> Void) {
        self.parent = parent
        self.onCreate = onCreate
        _assigneeId = State(initialValue: initialAssigneeId ?? parent?.assigneeAgentId)
    }

    @State private var title = ""
    @State private var description = ""
    @State private var priority = IssuePriority.medium
    @State private var status = IssueStatus.todo
    @State private var assigneeId: String?
    @State private var runner = ActionRunner()
    /// Agents of the parent's company when it differs from the selected company.
    @State private var parentCompanyAgents: [Agent]?
    @State private var showingComposer = false
    /// What the user last typed in the composer, so "重新描述" starts from it.
    @State private var prompt = ""
    @State private var assistantSessionID = UUID().uuidString
    /// The fields below hold an AI draft; the preview card replaces the entry card.
    @State private var drafted = false
    /// Whether the draft named a priority, or the form kept its default.
    @State private var draftHadPriority = false

    private var agents: [Agent] { parentCompanyAgents ?? app.activeAgents }
    private var canCreate: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !runner.isBusy }

    /// A subtask must live in its parent's company, whatever company is selected.
    private var companyId: String? { parent?.companyId ?? app.selectedCompanyId }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if drafted {
                        DraftPreviewCard(
                            title: title, description: description, status: status, priority: priority,
                            priorityIsDefault: !draftHadPriority,
                            assignee: agents.first { $0.id == assigneeId },
                            canCreate: canCreate, isCreating: runner.isBusy,
                            onRedo: { showingComposer = true },
                            onCreate: { Task { await create() } })
                    } else {
                        assistantEntry
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let parent {
                    Section(TasksL10n.text("task.parent", "Parent task")) {
                        Text("\(parent.displayKey) · \(parent.title)").foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField(TasksL10n.text("task.title", "Title"), text: $title, axis: .vertical)
                        .font(.headline)
                    TextField(TasksL10n.text("task.description_markdown", "Description (Markdown supported)"), text: $description, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text(drafted ? TasksL10n.text("task.edit_draft", "You can keep editing") : TasksL10n.text("task.manual_entry", "Or fill in the details manually"))
                }
                Section {
                    AssigneePicker(selection: $assigneeId, agents: parentCompanyAgents)
                    Picker(TasksL10n.text("task.priority", "Priority"), selection: $priority) {
                        ForEach(IssuePriority.selectable, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    Picker(TasksL10n.text("common.status", "Status"), selection: $status) {
                        ForEach([IssueStatus.backlog, .todo], id: \.self) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text(TasksL10n.text("task.assignment_hint", "An assigned agent will pick up the task on its next heartbeat."))
                }
            }
            .navigationTitle(parent == nil ? TasksL10n.text("task.new", "New task") : TasksL10n.text("task.new_subtask", "New subtask"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(TasksL10n.text("common.cancel", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(TasksL10n.text("common.create", "Create")) { Task { await create() } }
                        .disabled(!canCreate)
                }
            }
            .errorAlert(runner)
            .task { await loadParentCompanyAgents() }
            .sheet(isPresented: $showingComposer) {
                TaskComposerSheet(text: $prompt, parent: parent, agents: agents, sessionID: assistantSessionID) { apply($0) }
            }
        }
    }

    /// The "一句话创建" option, shown above the manual fields until a draft is applied.
    private var assistantEntry: some View {
        Button {
            showingComposer = true
        } label: {
            HStack(spacing: 14) {
                AssistantIcon(size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(TasksL10n.text("composer.quick_create", "Create with AI")).font(.headline).foregroundStyle(.primary)
                    Text(TasksL10n.text("composer.quick_description", "Describe it in your own words. AI fills in the title, assignee, priority, and description."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AssistantStyle.gradient.opacity(0.55), lineWidth: 1.2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(TasksL10n.text("composer.open_hint", "Open the editor to describe your task"))
    }

    private func apply(_ draft: TaskDraft) {
        withAnimation(.snappy) {
            title = draft.title
            description = draft.description ?? ""
            // Keep what the form already had (e.g. the agent this sheet was opened from)
            // when the sentence did not say.
            if let id = draft.assigneeAgentId { assigneeId = id }
            if let draftPriority = draft.priority { priority = draftPriority }
            draftHadPriority = draft.priority != nil
            drafted = true
        }
    }

    private func loadParentCompanyAgents() async {
        guard let client = app.client, let parent, parent.companyId != app.selectedCompanyId else { return }
        parentCompanyAgents = try? await client.agents(companyId: parent.companyId)
        // An assignee carried over from the parent must exist in that company.
        if let id = assigneeId, parentCompanyAgents?.contains(where: { $0.id == id }) == false { assigneeId = nil }
    }

    private func create() async {
        guard let client = app.client, let companyId else { return }
        await runner.run {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = try await client.createIssue(
                companyId: companyId,
                NewIssue(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: trimmed.isEmpty ? nil : trimmed,
                    status: status, priority: priority, assigneeAgentId: assigneeId, parentId: parent?.id))
            onCreate(created)
            app.didMutate()
            dismiss()
        }
    }
}

/// Picker listing the company's agents with avatars.
struct AssigneePicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: String?
    /// Overrides the selected company's agents (e.g. for another company's subtask).
    var agents: [Agent]? = nil

    private var choices: [Agent] {
        (agents ?? app.activeAgents).filter { $0.status != .terminated }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Picker(TasksL10n.text("task.assignee", "Assignee"), selection: $selection) {
            Text(TasksL10n.text("task.unassigned", "Unassigned")).tag(String?.none)
            ForEach(choices) { agent in
                Text("\(agent.name) · \(agent.roleLabel)").tag(Optional(agent.id))
            }
        }
    }
}

/// What the task will look like once created, built from the form's current values so edits
/// below show up immediately.
private struct DraftPreviewCard: View {
    let title: String
    let description: String
    let status: IssueStatus
    let priority: IssuePriority
    let priorityIsDefault: Bool
    let assignee: Agent?
    let canCreate: Bool
    let isCreating: Bool
    var onRedo: () -> Void
    var onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(TasksL10n.text("composer.preview", "AI-generated preview"))
                Spacer(minLength: 0)
                Button(TasksL10n.text("composer.redescribe", "Describe again"), action: onRedo)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AssistantStyle.gradient)

            Text(title.isEmpty ? TasksL10n.text("task.no_title", "(No title)") : title)
                .font(.title3.weight(.bold))
                .foregroundStyle(title.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }

            if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownText(source: description, font: .subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button(action: onCreate) {
                HStack(spacing: 8) {
                    if isCreating { ProgressView().tint(.white) } else { Image(systemName: "paperplane.fill") }
                    Text(TasksL10n.text("task.create", "Create task"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .prominentButton()
            .disabled(!canCreate)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AssistantStyle.gradient.opacity(0.6), lineWidth: 1.2)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    @ViewBuilder
    private var chips: some View {
        StatusBadge(status: status)
        HStack(spacing: 4) {
            PriorityBadge(priority: priority)
            if priorityIsDefault {
                Text(TasksL10n.text("common.default", "Default")).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(priority.tint.opacity(0.12), in: Capsule())
        HStack(spacing: 5) {
            if let assignee {
                AgentAvatar(agent: assignee, size: 18)
                Text(assignee.name)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                Text(TasksL10n.text("task.unassigned", "Unassigned"))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(assignee == nil ? .secondary : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
