import PaperclipKit
import SwiftUI

/// Bottom bar for replying to the agent on a task.
struct CommentComposer: View {
    struct Reply {
        enum Mode { case comment, resume, interrupt }
        var body: String
        var mode: Mode
    }

    @Environment(AppModel.self) private var app
    let issue: Issue
    /// Returns whether the reply was sent; the text is kept when it was not.
    let onSend: (Reply) async -> Bool

    @State private var text = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    /// Blocked or finished tasks need an explicit "continue" to get the agent moving again.
    private var suggestsResume: Bool {
        issue.status == .blocked || issue.status.isTerminal || issue.status == .inReview
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassSurface(cornerRadius: 22)

                Menu {
                    if !issue.humanCommentResumesWork {
                        Button {
                            submit(.comment)
                        } label: {
                            Label(TasksL10n.text("comment.reply_only", "Reply only"), systemImage: "text.bubble")
                        }
                    }
                    Button {
                        submit(.resume)
                    } label: {
                        Label(issue.status.isTerminal ? TasksL10n.text("comment.reply_reopen", "Reply and reopen") : TasksL10n.text("comment.reply_unblock", "Reply and resume (unblock)"), systemImage: "play.circle")
                    }
                    if issue.isRunning {
                        Button {
                            submit(.interrupt)
                        } label: {
                            Label(TasksL10n.text("comment.reply_interrupt", "Reply and interrupt the current run"), systemImage: "bolt.horizontal.circle")
                        }
                    }
                } label: {
                    sendIcon
                } primaryAction: {
                    submit(suggestsResume ? .resume : .comment)
                }
                .disabled(trimmed.isEmpty || sending)
                .accessibilityLabel(suggestsResume ? TasksL10n.text("comment.reply_resume", "Reply and resume") : TasksL10n.text("comment.send_reply", "Send reply"))
            }
            if focused && issue.humanCommentResumesWork {
                Text(issue.status.isTerminal
                     ? TasksL10n.text("comment.reopen_explanation", "Sending will reopen the task and wake \(agentName) to continue working.")
                     : TasksL10n.text("comment.resume_explanation", "Sending will move the task to To do and wake \(agentName) to continue working."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if focused && suggestsResume {
                Text(TasksL10n.text("comment.send_hint", "Tap Send to reply and let the agent continue; press and hold to reply only."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var agentName: String {
        app.agent(issue.assigneeAgentId)?.name ?? TasksL10n.text("common.agent", "Agent")
    }

    private var placeholder: String {
        if issue.status == .blocked { return TasksL10n.text("comment.unblock_placeholder", "Reply to the agent to unblock…") }
        if let _ = issue.assigneeAgentId { return TasksL10n.text("comment.agent_placeholder", "Reply to the agent…") }
        return TasksL10n.text("comment.placeholder", "Add a comment…")
    }

    @ViewBuilder
    private var sendIcon: some View {
        if sending {
            ProgressView().frame(width: 42, height: 42)
        } else {
            Image(systemName: suggestsResume ? "play.fill" : "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(trimmed.isEmpty ? Color.secondary : Color.white)
                .frame(width: 42, height: 42)
                .background(trimmed.isEmpty ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.accentColor), in: Circle())
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy, value: trimmed.isEmpty)
        }
    }

    private func submit(_ mode: Reply.Mode) {
        let body = trimmed
        guard !body.isEmpty else { return }
        sending = true
        Task {
            let sent = await onSend(Reply(body: body, mode: mode))
            sending = false
            guard sent else { return }
            // Keep anything typed while the request was in flight.
            if trimmed == body { text = "" }
            focused = false
        }
    }
}
