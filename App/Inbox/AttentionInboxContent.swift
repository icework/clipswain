import PaperclipKit
import SwiftUI

/// Live actions remain available separately from the immutable event inbox.
struct AttentionInboxContent: View {
    @Environment(AppModel.self) private var app

    @State private var feed: [AttentionItem] = []
    @State private var blocked: [Issue] = []
    @State private var approvals: [Approval] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var attentionUnavailable = false

    /// Blocked tasks the attention feed did not already surface.
    private var extraBlocked: [Issue] {
        let covered = Set(feed.compactMap(\.issueId))
        return blocked.filter { !covered.contains($0.id) }
    }

    /// Pending approvals the attention feed did not already surface.
    private var extraApprovals: [Approval] {
        let covered = Set(feed.compactMap(\.approvalId))
        return approvals.filter { $0.status.isOpen && !covered.contains($0.id) }
    }

    private var isClear: Bool { feed.isEmpty && extraBlocked.isEmpty && extraApprovals.isEmpty }

    var body: some View {
        List {
            if let error {
                Section { ErrorBanner(message: error) { Task { await load() } } }
            }
            if !feed.isEmpty {
                Section {
                    ForEach(feed) { item in
                        link(for: item)
                    }
                } header: {
                    sectionHeader(TasksL10n.text("inbox.attention", "Needs your attention"), count: feed.count, symbol: "bell.badge.fill", tint: .orange)
                }
            }
            if !extraApprovals.isEmpty {
                Section(TasksL10n.text("approval.pending", "Pending approval")) {
                    ForEach(extraApprovals) { approval in
                        NavigationLink(value: ApprovalRoute(id: approval.id)) {
                            ApprovalRow(approval: approval)
                        }
                    }
                }
            }
            if !extraBlocked.isEmpty {
                Section(TasksL10n.text("inbox.blocked", "Blocked tasks")) {
                    ForEach(extraBlocked) { issue in
                        NavigationLink(value: IssueRoute(id: issue.id)) { TaskRow(issue: issue) }
                    }
                }
            }
            if loaded && isClear && error == nil {
                Section {
                    ContentUnavailableView(
                        TasksL10n.text("inbox.clear", "All clear"), systemImage: "checkmark.seal",
                        description: Text(TasksL10n.text("inbox.clear_description", "No agents are waiting for your reply, and no tasks are blocked.")))
                }
                .listRowBackground(Color.clear)
            }
        }
        .readableWidth()
        .refreshable { await load() }
        .overlay { if !loaded { ProgressView() } }
        .task(id: app.revision) { await load() }
        .autoRefresh(every: .seconds(30)) { await load() }
    }

    private func sectionHeader(_ title: String, count: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint).symbolEffect(.bounce, value: count)
            Text(title).foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .font(.headline)
        .textCase(nil)
    }

    @ViewBuilder
    private func link(for item: AttentionItem) -> some View {
        if let id = item.approvalId {
            NavigationLink(value: ApprovalRoute(id: id)) { AttentionRow(item: item) }
        } else if let id = item.issueId {
            NavigationLink(value: IssueRoute(id: id)) { AttentionRow(item: item) }
        } else if item.subject.kind == "agent" {
            NavigationLink(value: AgentRoute(id: item.subject.id)) { AttentionRow(item: item) }
        } else {
            AttentionRow(item: item)
        }
    }

    private func load() async {
        guard let client = app.client, let companyId = app.selectedCompanyId else { return }
        async let feedTask = client.attention(companyId: companyId)
        async let blockedTask = client.issues(companyId: companyId, statuses: [.blocked])
        async let approvalsTask = client.approvals(companyId: companyId, status: .pending)
        var failures: [String] = []
        do {
            feed = try await feedTask.items.sorted {
                ($0.severityRank, $1.activityAt ?? .distantPast) < ($1.severityRank, $0.activityAt ?? .distantPast)
            }
            attentionUnavailable = false
        } catch let apiError as PaperclipAPIError where [401, 403, 404].contains(apiError.status) {
            // Servers or actors without the attention feed: fall back to blocked tasks + approvals.
            feed = []
            attentionUnavailable = true
        } catch {
            // A timeout or 5xx: keep what was already shown and say the list may be incomplete.
            failures.append(TasksL10n.text("inbox.load_error", "Unable to load inbox: \(error.localizedDescription)"))
        }
        do { blocked = try await blockedTask } catch { failures.append(error.localizedDescription) }
        do { approvals = try await approvalsTask } catch { failures.append(error.localizedDescription) }
        error = failures.first
        loaded = true
        guard app.client === client, app.selectedCompanyId == companyId else { return }
        app.attentionCount = feed.count + extraBlocked.count + extraApprovals.count
        app.inbox?.markAttentionSeen(feed.map(\.id))
    }
}

/// One "needs you" item, led by the agent who raised it.
struct AttentionRow: View {
    @Environment(AppModel.self) private var app
    let item: AttentionItem

    private var agent: Agent? {
        guard let name = item.originAgentName else { return nil }
        return app.agents.first { $0.name == name }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let agent {
                    HaloAvatar(agent: agent, size: 44)
                        .overlay(alignment: .bottomTrailing) { kindBadge.offset(x: 4, y: 4) }
                } else {
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        sourceAndIdentifier
                        Spacer(minLength: 0)
                        activityTime
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) {
                        sourceAndIdentifier
                        activityTime
                    }
                }
                Text(item.subject.title ?? item.relatedIssue?.title ?? TasksL10n.text("common.untitled", "Untitled"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let excerpt = item.detail?.excerpt ?? item.whyNow, !excerpt.isEmpty,
                   excerpt != (item.subject.title ?? item.relatedIssue?.title) {
                    Text(excerpt).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceAndIdentifier: some View {
        HStack(spacing: 6) {
            Chip(text: item.sourceLabel, tint: tint)
            if let key = item.relatedIssue?.identifier ?? item.subject.identifier {
                Text(key).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var activityTime: some View {
        if let date = item.activityAt {
            Text(date.relative).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var kindBadge: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
    }

    private var symbol: String {
        switch item.sourceKind {
        case "issue_thread_interaction": return "questionmark.bubble.fill"
        case "approval", "decision": return "checkmark.shield.fill"
        case "blocker_attention": return "exclamationmark.octagon.fill"
        case "failed_run", "agent_error_alert": return "exclamationmark.triangle.fill"
        case "budget_alert": return "dollarsign.circle.fill"
        case "review": return "eye.fill"
        case "recovery_action": return "lifepreserver.fill"
        default: return "bell.fill"
        }
    }

    private var tint: Color {
        switch item.severity {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .blue
        default: return .indigo
        }
    }
}

struct ApprovalRow: View {
    @Environment(AppModel.self) private var app
    let approval: Approval

    var body: some View {
        HStack(spacing: 12) {
            HaloAvatar(agent: app.agent(approval.requestedByAgentId), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Chip(text: approval.typeLabel, symbol: "checkmark.shield.fill", tint: .purple)
                Text(approval.summary ?? approval.typeLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
