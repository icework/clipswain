import PaperclipKit
import SwiftUI

struct ApprovalDetailView: View {
    @Environment(AppModel.self) private var app
    let approvalId: String

    @State private var approval: Approval?
    @State private var comments: [ApprovalComment] = []
    @State private var loadError: String?
    @State private var note = ""
    @State private var commentText = ""
    @State private var runner = ActionRunner()

    var body: some View {
        Group {
            if let approval {
                form(approval)
            } else if let loadError {
                ContentUnavailableView(TasksL10n.text("approval.load_error", "Unable to load approval"), systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .readableWidth()
        .dismissableKeyboard()
        .navigationTitle(TasksL10n.text("approval.title", "Approval"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .errorAlert(runner)
    }

    private func form(_ approval: Approval) -> some View {
        Form {
            Section {
                LabeledContent(TasksL10n.text("common.type", "Type"), value: approval.typeLabel)
                LabeledContent(TasksL10n.text("common.status", "Status"), value: statusLabel(approval.status))
                if let agent = app.agent(approval.requestedByAgentId) {
                    LabeledContent(TasksL10n.text("approval.requester", "Requested by")) {
                        HStack(spacing: 6) {
                            AgentAvatar(agent: agent, size: 22)
                            Text(agent.name)
                        }
                    }
                }
                if let created = approval.createdAt {
                    LabeledContent(TasksL10n.text("approval.submitted", "Submitted"), value: AppL10n.date(created, style: .dateTime.year().month().day().hour().minute()))
                }
            }

            if let payload = approval.payload, !payload.isEmpty {
                Section(TasksL10n.text("common.content", "Content")) {
                    ForEach(payload.keys.sorted(), id: \.self) { key in
                        if let value = payload[key] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key).font(.caption).foregroundStyle(.secondary)
                                if let text = value.stringValue {
                                    MarkdownText(source: text, font: .callout)
                                } else {
                                    Text(value.prettyPrinted).font(.system(.caption, design: .monospaced))
                                }
                            }
                        }
                    }
                }
            }

            if let decision = approval.decisionNote, !decision.isEmpty {
                Section(TasksL10n.text("approval.decision_note", "Decision note")) { Text(decision) }
            }

            if approval.status.isOpen {
                Section {
                    TextField(TasksL10n.text("approval.note_optional", "Note (optional)"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                    Button {
                        Task { await decide(.approve) }
                    } label: {
                        Label(TasksL10n.text("approval.approve", "Approve"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        Task { await decide(.requestRevision) }
                    } label: {
                        Label(TasksL10n.text("approval.request_revision", "Request changes"), systemImage: "arrow.uturn.backward.circle")
                            .foregroundStyle(.orange)
                    }
                    Button(role: .destructive) {
                        Task { await decide(.reject) }
                    } label: {
                        Label(TasksL10n.text("common.reject", "Reject"), systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(TasksL10n.text("approval.make_decision", "Make a decision"))
                }
                .disabled(runner.isBusy)
            }

            Section(TasksL10n.text("common.discussion", "Discussion")) {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.agent(comment.authorAgentId)?.name ?? TasksL10n.text("common.board", "Board"))
                            .font(.caption.weight(.semibold))
                        MarkdownText(source: comment.body, font: .callout)
                    }
                }
                HStack {
                    TextField(TasksL10n.text("comment.add", "Add a comment"), text: $commentText, axis: .vertical)
                    Button(TasksL10n.text("common.send", "Send")) { Task { await addComment() } }
                        .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func statusLabel(_ status: ApprovalStatus) -> String {
        switch status {
        case .pending: return TasksL10n.text("approval.pending", "Pending approval")
        case .revisionRequested: return TasksL10n.text("approval.revision_requested", "Changes requested")
        case .approved: return TasksL10n.text("approval.approved", "Approved")
        case .rejected: return TasksL10n.text("common.rejected", "Rejected")
        case .cancelled: return TasksL10n.text("common.cancelled", "Cancelled")
        case .unknown: return TasksL10n.text("common.unknown", "Unknown")
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            approval = try await client.approval(id: approvalId)
            comments = (try? await client.approvalComments(id: approvalId)) ?? []
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func decide(_ decision: ApprovalDecision) async {
        guard let client = app.client else { return }
        await runner.run {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            approval = try await client.decide(approvalId: approvalId, decision, note: trimmed.isEmpty ? nil : trimmed)
            note = ""
            app.didMutate()
        }
    }

    private func addComment() async {
        guard let client = app.client else { return }
        await runner.run {
            let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
            comments.append(try await client.addApprovalComment(id: approvalId, body: body))
            commentText = ""
        }
    }
}
