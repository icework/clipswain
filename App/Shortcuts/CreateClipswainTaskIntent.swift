import AppIntents
import PaperclipKit

struct CreateClipswainTaskIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("shortcut.create_title", defaultValue: "Publish task")
    static var description = IntentDescription(LocalizedStringResource("shortcut.create_description", defaultValue: "Publish a task to the company selected in Clipswain. Runs in the background, including while locked. Uses your AI assistant when configured; otherwise saves your words directly."))
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    static var openAppWhenRun: Bool { false }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: LocalizedStringResource("shortcut.task_text", defaultValue: "Task description"),
               requestValueDialog: IntentDialog(LocalizedStringResource("shortcut.ask_text", defaultValue: "What task would you like to publish?")))
    var taskDescription: String

    @Parameter(title: LocalizedStringResource("shortcut.use_ai", defaultValue: "Use AI assistant"), default: true)
    var useAI: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Publish \(\.$taskDescription)") { \.$useAI }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = try ShortcutTaskService.live(useAI: useAI)
        let created = try await service.publish(taskDescription)
        let message: String
        if created.assigneeAgentId == nil {
            message = AppL10n.text("shortcut.created_unassigned", "Published \(created.displayKey): \(created.title). Unassigned.")
        } else {
            message = AppL10n.text("shortcut.created", "Published \(created.displayKey): \(created.title).")
        }
        return .result(value: created.displayKey, dialog: IntentDialog(stringLiteral: message))
    }
}

struct ClipswainShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateClipswainTaskIntent(), phrases: [
            "Publish a task in \(.applicationName)",
            "Create a task in \(.applicationName)"
        ], shortTitle: LocalizedStringResource("shortcut.create_title", defaultValue: "Publish task"),
                    systemImageName: "plus.bubble.fill")
    }
}
