import PaperclipKit
import SwiftUI

/// A pending decision card an agent posted on a task. Resolving it is how the board
/// answers an agent's structured question and lets it continue.
struct InteractionCardView: View {
    @Environment(AppModel.self) private var app
    let interaction: IssueInteraction
    let onResolve: (InteractionResolution) async -> Void

    @State private var busy = false
    @State private var rejecting = false
    @State private var rejectReason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let agent = app.agent(interaction.createdByAgentId) {
                    AgentAvatar(agent: agent, size: 26)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(interaction.kind.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                    if let title = interaction.title, !title.isEmpty {
                        Text(title).font(.headline)
                    }
                }
            }
            if let summary = interaction.summary, !summary.isEmpty {
                Text(summary).font(.footnote).foregroundStyle(.secondary)
            }
            content
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
        .padding(.vertical, 6)
        .disabled(busy)
        .alert(rejectTitle, isPresented: $rejecting) {
            TextField(TasksL10n.text("interaction.reason", "Reason"), text: $rejectReason)
            Button(TasksL10n.text("common.submit", "Submit"), role: .destructive) {
                let reason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
                resolve(.reject(reason: reason.isEmpty ? nil : reason))
            }
            .disabled(interaction.rejectRequiresReason
                      && rejectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(TasksL10n.text("common.cancel", "Cancel"), role: .cancel) {}
        } message: {
            if interaction.rejectRequiresReason { Text(TasksL10n.text("interaction.reason_required", "Enter a reason before submitting.")) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch interaction.kind {
        case .askUserQuestions:
            if let payload = interaction.questions {
                QuestionsForm(payload: payload) { answers in resolve(.respond(answers: answers)) }
            } else {
                unsupported
            }
        case .requestConfirmation:
            if let payload = interaction.confirmation {
                MarkdownText(source: payload.prompt, font: .callout)
                if let details = payload.detailsMarkdown, !details.isEmpty {
                    DisclosureGroup(TasksL10n.text("common.details", "Details")) { MarkdownText(source: details, font: .footnote) }
                        .font(.footnote)
                }
                decisionButtons(accept: payload.acceptLabel ?? TasksL10n.text("common.accept", "Accept"), reject: payload.rejectLabel ?? TasksL10n.text("common.reject", "Reject")) {
                    resolve(.accept())
                }
            } else {
                unsupported
            }
        case .suggestTasks:
            if let payload = interaction.suggestedTasks {
                SuggestedTasksForm(payload: payload) { keys in
                    resolve(.accept(selectedClientKeys: keys))
                } onReject: {
                    rejecting = true
                }
            } else {
                unsupported
            }
        case .requestCheckboxConfirmation:
            if let payload = interaction.checkboxOptions {
                CheckboxForm(payload: payload) { ids in
                    resolve(.accept(selectedOptionIds: ids))
                } onReject: {
                    rejecting = true
                }
            } else {
                unsupported
            }
        case .requestItemVerdicts:
            if let payload = interaction.verdictItems {
                VerdictsForm(payload: payload) { verdicts, reasons in resolve(.verdicts(verdicts, reasons: reasons)) }
            } else {
                unsupported
            }
        case .connectionIntent, .unknown:
            unsupported
        }
    }

    private var unsupported: some View {
        Text(TasksL10n.text("interaction.web_required", "Handle this interaction in the web app."))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var rejectTitle: String {
        interaction.rejectReasonLabel ?? (interaction.rejectRequiresReason ? TasksL10n.text("interaction.explain_reason", "Explain why") : TasksL10n.text("interaction.reason_optional", "Reason (optional)"))
    }

    private func decisionButtons(
        accept: String, reject: String, onAccept: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(role: .destructive) {
                rejectReason = ""
                rejecting = true
            } label: {
                Text(reject).frame(maxWidth: .infinity)
            }
            .secondaryButton()
            Button(action: onAccept) {
                Text(accept).frame(maxWidth: .infinity)
            }
            .prominentButton()
        }
    }

    private func resolve(_ resolution: InteractionResolution) {
        busy = true
        Task {
            await onResolve(resolution)
            busy = false
        }
    }
}

private struct QuestionsForm: View {
    let payload: QuestionsPayload
    let onSubmit: ([QuestionAnswer]) -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var otherText: [String: String] = [:]

    private var canSubmit: Bool {
        payload.questions.allSatisfy { question in
            question.required == false
                || !(selections[question.id] ?? []).isEmpty
                || !(otherText[question.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = payload.title, !title.isEmpty {
                Text(title).font(.subheadline.weight(.semibold))
            }
            ForEach(payload.questions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.prompt).font(.callout.weight(.medium))
                    if let help = question.helpText, !help.isEmpty {
                        Text(help).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(question.isMulti ? TasksL10n.text("interaction.multiple_choice", "Select multiple") : TasksL10n.text("interaction.single_choice", "Select one")).font(.caption2).foregroundStyle(.tertiary)
                    ForEach(question.options) { option in
                        OptionRow(
                            label: option.label, detail: option.description,
                            selected: selections[question.id]?.contains(option.id) == true,
                            multi: question.isMulti
                        ) {
                            toggle(option.id, in: question)
                        }
                    }
                    if question.allowOther != false {
                        TextField(TasksL10n.text("interaction.other_optional", "Other (optional)"), text: Binding(
                            get: { otherText[question.id] ?? "" },
                            set: { otherText[question.id] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    }
                }
            }
            Button {
                onSubmit(payload.questions.map { question in
                    let other = otherText[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return QuestionAnswer(
                        questionId: question.id,
                        optionIds: Array(selections[question.id] ?? []).sorted(),
                        otherText: other?.isEmpty == false ? other : nil)
                })
            } label: {
                Text(payload.submitLabel ?? TasksL10n.text("interaction.submit_answers", "Submit answers")).frame(maxWidth: .infinity)
            }
            .prominentButton()
            .disabled(!canSubmit)
        }
    }

    private func toggle(_ optionId: String, in question: Question) {
        var current = selections[question.id] ?? []
        if question.isMulti {
            if current.contains(optionId) { current.remove(optionId) } else { current.insert(optionId) }
        } else {
            current = current.contains(optionId) ? [] : [optionId]
        }
        selections[question.id] = current
    }
}

private struct OptionRow: View {
    let label: String
    let detail: String?
    let selected: Bool
    let multi: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected
                      ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (multi ? "square" : "circle"))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(.primary)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SuggestedTasksForm: View {
    @Environment(AppModel.self) private var app
    let payload: SuggestedTasksPayload
    let onAccept: ([String]) -> Void
    let onReject: () -> Void

    @State private var selected: Set<String> = []

    private var visibleTasks: [SuggestedTask] { payload.tasks.filter { $0.hiddenInPreview != true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleTasks) { task in
                OptionRow(
                    label: task.title,
                    detail: [task.priority?.label, app.agent(task.assigneeAgentId)?.name].compactMap { $0 }.joined(separator: " · "),
                    selected: selected.contains(task.clientKey), multi: true
                ) {
                    if selected.contains(task.clientKey) { selected.remove(task.clientKey) } else { selected.insert(task.clientKey) }
                }
            }
            HStack {
                Button(TasksL10n.text("interaction.reject_all", "Reject all"), role: .destructive, action: onReject)
                    .secondaryButton()
                Button {
                    onAccept(Array(selected).sorted())
                } label: {
                    Text(TasksL10n.text("interaction.create_tasks", "Create \(selected.count) tasks")).frame(maxWidth: .infinity)
                }
                .prominentButton()
                .disabled(selected.isEmpty)
            }
        }
        .onAppear { selected = Set(visibleTasks.map(\.clientKey)) }
    }
}

private struct CheckboxForm: View {
    let payload: CheckboxPayload
    let onAccept: ([String]) -> Void
    let onReject: () -> Void

    @State private var selected: Set<String> = []

    private var isValid: Bool {
        selected.count >= (payload.minSelected ?? 0)
            && (payload.maxSelected.map { selected.count <= $0 } ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prompt = payload.prompt { MarkdownText(source: prompt, font: .callout) }
            ForEach(payload.options) { option in
                OptionRow(label: option.label, detail: option.description, selected: selected.contains(option.id), multi: true) {
                    if selected.contains(option.id) { selected.remove(option.id) } else { selected.insert(option.id) }
                }
            }
            HStack {
                Button(payload.rejectLabel ?? TasksL10n.text("common.reject", "Reject"), role: .destructive, action: onReject)
                    .secondaryButton()
                Button {
                    onAccept(Array(selected).sorted())
                } label: {
                    Text(payload.acceptLabel ?? TasksL10n.text("common.confirm", "Confirm")).frame(maxWidth: .infinity)
                }
                .prominentButton()
                .disabled(!isValid)
            }
        }
        .onAppear { selected = Set(payload.defaultSelectedOptionIds ?? []) }
    }
}

private struct VerdictsForm: View {
    let payload: VerdictsPayload
    let onSubmit: ([String: ItemVerdict], [String: String]) -> Void

    @State private var verdicts: [String: ItemVerdict] = [:]
    @State private var reasons: [String: String] = [:]
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt = payload.prompt { MarkdownText(source: prompt, font: .callout) }
            if let details = payload.detailsMarkdown, !details.isEmpty {
                DisclosureGroup(TasksL10n.text("common.details", "Details")) { MarkdownText(source: details, font: .footnote) }
                    .font(.footnote)
            }
            ForEach(payload.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayLabel).font(.callout.weight(.medium))
                    if let description = item.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                    if let preview = item.previewMarkdown, !preview.isEmpty {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expanded.contains(item.id) },
                            set: { if $0 { expanded.insert(item.id) } else { expanded.remove(item.id) } })
                        ) {
                            MarkdownText(source: preview, font: .footnote)
                                .padding(10)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } label: {
                            Label(TasksL10n.text("interaction.review_content", "View content for review"), systemImage: "doc.text.magnifyingglass").font(.footnote)
                        }
                    }
                    Picker(item.displayLabel, selection: Binding(
                        get: { verdicts[item.id] },
                        set: { verdicts[item.id] = $0 })
                    ) {
                        ForEach(payload.allowedVerdicts, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if let verdict = verdicts[item.id], payload.requiresReason(verdict) {
                        TextField(payload.reasonLabel ?? TasksL10n.text("interaction.reason_mandatory", "Reason (required)"), text: Binding(
                            get: { reasons[item.id] ?? "" },
                            set: { reasons[item.id] = $0 }), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    }
                }
            }
            if payload.allowBulkApprove == true && payload.allowedVerdicts.contains(.approve) {
                Button(TasksL10n.text("interaction.approve_all", "Approve all")) {
                    for item in payload.items { verdicts[item.id] = .approve }
                }
                .font(.footnote)
            }
            Button {
                // Only reasons for verdicts that ask for one are sent.
                let needed = reasons.filter { id, _ in verdicts[id].map(payload.requiresReason) ?? false }
                onSubmit(verdicts, needed)
            } label: {
                Text(TasksL10n.text("interaction.submit_review", "Submit review")).frame(maxWidth: .infinity)
            }
            .prominentButton()
            .disabled(!payload.isComplete(verdicts, reasons: reasons))
        }
    }
}
