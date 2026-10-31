import PaperclipKit
import SwiftUI

/// "一句话创建": the user describes a task in their own words and the configured LLM turns it
/// into a `TaskDraft`, which the new-task form then shows as a preview.
struct TaskComposerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// Kept by the caller so "重新描述" reopens with the previous wording.
    @Binding var text: String
    var parent: Issue?
    var agents: [Agent]
    var sessionID: String
    var onDraft: (TaskDraft) -> Void

    @State private var isWorking = false
    @State private var error: String?
    @State private var glow = false
    /// The in-flight request, cancelled when the sheet closes so a late draft never
    /// overwrites what the user typed in the form meanwhile.
    @State private var generation: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var settings: AssistantSettings { .shared }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    editor
                    if !settings.isConfigured {
                        setupCard
                    } else if trimmed.isEmpty {
                        examples
                    }
                    if let error {
                        ErrorBanner(message: error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(parent == nil ? TasksL10n.text("composer.quick_create", "Create with AI") : TasksL10n.text("composer.quick_subtask", "Create subtask with AI"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(TasksL10n.text("common.cancel", "Cancel")) { generation?.cancel(); dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { generateButton }
            .onAppear { focused = settings.isConfigured }
        }
        .interactiveDismissDisabled(isWorking)
        .onDisappear { generation?.cancel() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 14) {
            AssistantIcon(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(TasksL10n.text("composer.prompt_heading", "What needs to be done?")).font(.title3.weight(.bold))
                Text(TasksL10n.text("composer.prompt_description", "Include who should do it, when it is due, and how urgent it is. AI will prepare a task for you to review."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .disabled(isWorking)
        }
        .font(.body)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            // While the model works, a slowly shifting assistant-gradient border.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: AssistantStyle.colors + [AssistantStyle.colors[0]], center: .center),
                    lineWidth: isWorking ? 2.5 : 1)
                .hueRotation(.degrees(glow ? 360 : 0))
                .opacity(isWorking ? 1 : (focused ? 0.55 : 0.2))
                .animation(.easeInOut(duration: 0.25), value: focused)
        }
        .onChange(of: isWorking) { _, working in
            if working {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { glow = true }
            } else {
                withAnimation(.default) { glow = false }
            }
        }
    }

    private var placeholder: String {
        if let agent = agents.first {
            return TasksL10n.text("composer.example_assigned", "For example: Ask \(agent.name) to fix the login screen crash by Friday. It is urgent; add unit tests afterward.")
        }
        return TasksL10n.text("composer.example_unassigned", "For example: Fix the login screen crash by Friday. It is urgent; add unit tests afterward.")
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TasksL10n.text("composer.examples_heading", "Try saying")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(exampleTexts, id: \.self) { example in
                Button {
                    text = example
                    focused = true
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "text.bubble").foregroundStyle(AssistantStyle.colors[0])
                        Text(example).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var exampleTexts: [String] {
        let names = agents.map(\.name)
        let first = names.first ?? "Grace"
        let second = names.dropFirst().first ?? first
        return [
            TasksL10n.text("composer.example_logs", "\(first), organize the iOS crash logs by tomorrow. This is urgent."),
            TasksL10n.text("composer.example_research", "Ask \(second) to compare pricing plans for three competitors by next Monday. No rush."),
        ]
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(TasksL10n.text("composer.setup_heading", "No AI model configured"), systemImage: "key.horizontal.fill")
                .font(.subheadline.weight(.semibold))
            Text(TasksL10n.text("composer.setup_description", "Choose OpenCode Go, OpenRouter, or a custom service, enter an API key, and select a model."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            NavigationLink {
                AssistantSettingsView()
            } label: {
                Label(TasksL10n.text("composer.configure", "Configure"), systemImage: "gearshape")
                    .font(.subheadline.weight(.semibold))
            }
            .secondaryButton()
        }
        .card(cornerRadius: 18)
    }

    private var generateButton: some View {
        Button {
            generation = Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().tint(.white)
                    Text(TasksL10n.text("composer.generating", "Preparing…"))
                } else {
                    Image(systemName: "sparkles")
                    Text(TasksL10n.text("composer.generate", "Generate task"))
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                // Solid when disabled so the button never looks washed out over the content.
                if canGenerate || isWorking {
                    Capsule().fill(AssistantStyle.gradient)
                } else {
                    Capsule().fill(Color(.systemGray3))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .sensoryFeedback(.success, trigger: isWorking) { old, new in old && !new && error == nil }
    }

    private var canGenerate: Bool { !trimmed.isEmpty && !isWorking && settings.isConfigured }

    // MARK: Action

    private func generate() async {
        guard let drafter = settings.drafter(sessionID: sessionID) else { return }
        focused = false
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let draft = try await drafter.draft(from: trimmed, context: .make(agents: agents, app: app, parent: parent))
            guard !Task.isCancelled else { return }
            onDraft(draft)
            dismiss()
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
