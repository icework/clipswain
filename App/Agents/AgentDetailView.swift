import PaperclipKit
import SwiftUI

/// An agent's profile: character, role, model, chain of command, current work, recent runs,
/// skills, and a link to its instructions.
struct AgentDetailView: View {
    @Environment(AppModel.self) private var app
    let agentId: String

    private var agent: Agent? { app.agent(agentId) }
    @State private var tasks: [Issue] = []
    @State private var runs: [HeartbeatRun] = []
    @State private var skills: AgentSkillSnapshot?
    @State private var loadError: String?
    @State private var runner = ActionRunner()
    @State private var editing = false
    @State private var showingNewTask = false
    @State private var confirmingTerminate = false

    private var openTasks: [Issue] { tasks.filter(\.status.isOpen) }

    var body: some View {
        Group {
            if let agent {
                content(agent)
            } else if let loadError {
                ContentUnavailableView(AgentsL10n.text("detail.load_failed", "Unable to load agent"), systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(agent?.name ?? AgentsL10n.text("detail.fallback_name", "Agent"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .autoRefresh(every: agent?.status == .running ? .seconds(8) : .seconds(30)) { await load() }
        .errorAlert(runner)
    }

    private func content(_ agent: Agent) -> some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AgentPalette.gradient(for: agent).opacity(0.25))
                            .frame(width: 150, height: 150)
                            .blur(radius: 18)
                        AgentAvatar(agent: agent, size: 128)
                            .shadow(color: AgentPalette.accent(for: agent).opacity(0.35), radius: 16, y: 8)
                    }
                    VStack(spacing: 4) {
                        Text(agent.name).font(.largeTitle.weight(.bold))
                        Text([agent.title, agent.roleLabel].compactMap { $0 }.removingDuplicates().joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    StatusPill(status: agent.status)
                    if let error = agent.errorReason, agent.status == .error {
                        Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    if let reason = agent.pauseReason, agent.status == .paused {
                        Text(AgentsL10n.text("detail.pause_reason", "Paused: \(pauseReasonText(reason))")).font(.footnote).foregroundStyle(.orange)
                    }
                    HStack(spacing: 0) {
                        stat("\(openTasks.count)", AgentsL10n.text("detail.open_tasks", "Open tasks"))
                        Divider().frame(height: 28)
                        stat("\(runs.count)", AgentsL10n.text("detail.recent_runs", "Recent runs"))
                        Divider().frame(height: 28)
                        stat(agent.lastHeartbeatAt?.relative ?? "—", AgentsL10n.text("detail.last_heartbeat", "Last heartbeat"))
                    }
                    .padding(.vertical, 10)
                    .glassSurface(cornerRadius: 18)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            actionsSection(agent)

            Section(AgentsL10n.text("detail.profile", "Profile")) {
                LabeledContent(AgentsL10n.text("runtime.title", "Runtime"), value: agent.adapterLabel)
                if let model = agent.modelName { LabeledContent(AgentsL10n.text("model.title", "Model"), value: model) }
                if let heartbeat = agent.lastHeartbeatAt { LabeledContent(AgentsL10n.text("detail.last_heartbeat", "Last heartbeat"), value: heartbeat.relative) }
                if let budget = agent.budgetMonthlyCents, budget > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(AgentsL10n.text("budget.current_month", "Monthly budget"), value: "\((agent.spentMonthlyCents ?? 0).dollars) / \(budget.dollars)")
                        ProgressView(value: min(Double(agent.spentMonthlyCents ?? 0) / Double(budget), 1))
                            .tint(Double(agent.spentMonthlyCents ?? 0) / Double(budget) > 0.9 ? .red : .accentColor)
                    }
                } else if let spent = agent.spentMonthlyCents, spent > 0 {
                    LabeledContent(AgentsL10n.text("budget.monthly_spend", "Spent this month"), value: spent.dollars)
                }
                if let capabilities = agent.capabilities, !capabilities.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AgentsL10n.text("capabilities.title", "Capabilities")).font(.caption).foregroundStyle(.secondary)
                        Text(capabilities)
                    }
                }
            }

            Section {
                NavigationLink {
                    InstructionsView(agent: agent)
                } label: {
                    Label(AgentsL10n.text("detail.instructions", "View instructions"), systemImage: "doc.text")
                }
                if let skills {
                    NavigationLink {
                        SkillsView(snapshot: skills)
                    } label: {
                        LabeledContent {
                            Text(skills.supported ? AgentsL10n.text("skills.count", "\(skills.entries.filter(\.desired).count) skills") : AgentsL10n.text("skills.unsupported", "Not supported"))
                        } label: {
                            Label(AgentsL10n.text("detail.skills", "Skills"), systemImage: "wand.and.stars")
                        }
                    }
                }
            }

            if let chain = agent.chainOfCommand, !chain.isEmpty {
                Section(AgentsL10n.text("detail.chain_of_command", "Chain of command")) {
                    ForEach(chain) { manager in
                        NavigationLink(value: AgentRoute(id: manager.id)) {
                            HStack(spacing: 10) {
                                AgentAvatar(agent: app.agent(manager.id), size: 28)
                                VStack(alignment: .leading) {
                                    Text(manager.name)
                                    Text(manager.title ?? AgentRole.label(for: manager.role ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            let reports = app.agents.filter { $0.reportsTo == agent.id && $0.status != .terminated }
            if !reports.isEmpty {
                Section(AgentsL10n.text("detail.reports", "Direct reports")) {
                    ForEach(reports) { report in
                        NavigationLink(value: AgentRoute(id: report.id)) {
                            HStack(spacing: 10) {
                                AgentAvatar(agent: report, size: 28)
                                Text(report.name)
                                Spacer()
                                AgentStatusDot(status: report.status)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(openTasks) { issue in
                    NavigationLink(value: IssueRoute(id: issue.id)) { TaskRow(issue: issue) }
                }
                if openTasks.isEmpty {
                    Text(AgentsL10n.text("detail.no_open_tasks", "No open tasks")).foregroundStyle(.secondary)
                }
                Button {
                    showingNewTask = true
                } label: {
                    Label(AgentsL10n.text("detail.assign_task", "Assign a new task to \(agent.name)"), systemImage: "plus.circle")
                }
            } header: {
                Text(AgentsL10n.text("detail.current_tasks", "Current tasks · \(openTasks.count)"))
            }

            if !runs.isEmpty {
                Section(AgentsL10n.text("detail.recent_runs", "Recent runs")) {
                    ForEach(runs) { run in
                        NavigationLink(value: RunRoute(id: run.id)) { RunRow(run: run) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .readableWidth()
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                AgentPalette.gradient(for: agent)
                    .opacity(0.22)
                    .frame(height: 380)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = true } label: { Label(AgentsL10n.text("detail.edit", "Edit profile"), systemImage: "pencil") }
                    if agent.status != .terminated {
                        Button(role: .destructive) { confirmingTerminate = true } label: {
                            Label(AgentsL10n.text("detail.terminate", "Terminate agent"), systemImage: "person.crop.circle.badge.xmark")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            AgentsL10n.text("detail.terminate.confirmation", "Permanently terminate \(agent.name)?"), isPresented: $confirmingTerminate, titleVisibility: .visible
        ) {
            Button(AgentsL10n.text("action.terminate", "Terminate"), role: .destructive) {
                Task {
                    await runner.run {
                        let updated = try await app.client!.terminateAgent(id: agentId)
                        app.upsert(updated)
                    }
                }
            }
        } message: {
            Text(AgentsL10n.text("detail.terminate.warning", "Termination is permanent. This agent’s tasks will need to be reassigned. Use Pause if you only want to stop it temporarily."))
        }
        .sheet(isPresented: $editing) {
            AgentEditSheet(agent: agent) { updated in
                app.upsert(updated)
            }
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheetPrefilled(assigneeId: agent.id) { created in tasks.insert(created, at: 0) }
        }
    }

    @ViewBuilder
    private func actionsSection(_ agent: Agent) -> some View {
        Section {
            HStack(spacing: 10) {
                if agent.status.canResume {
                    actionButton(AgentsL10n.text("action.resume", "Resume"), "play.fill", .green) { try await app.client!.resumeAgent(id: agentId) }
                } else if agent.status.canPause {
                    actionButton(AgentsL10n.text("action.pause", "Pause"), "pause.fill", .orange) { try await app.client!.pauseAgent(id: agentId) }
                }
                if agent.status != .terminated && agent.status != .paused && agent.status != .pendingApproval {
                    Button {
                        Task { await wake() }
                    } label: {
                        actionLabel(AgentsL10n.text("action.run_now", "Run now"), "bolt.fill", .blue)
                    }
                    .buttonStyle(.plain)
                }
                if agent.status == .error {
                    actionButton(AgentsL10n.text("action.clear_error", "Clear error"), "arrow.counterclockwise", .red) { try await app.client!.clearAgentError(id: agentId) }
                }
            }
            .disabled(runner.isBusy)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func actionButton(
        _ title: String, _ symbol: String, _ tint: Color, perform: @escaping () async throws -> Agent
    ) -> some View {
        Button {
            Task {
                await runner.run {
                    let updated = try await perform()
                    app.upsert(updated)
                }
            }
        } label: {
            actionLabel(title, symbol, tint)
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func pauseReasonText(_ reason: String) -> String {
        switch reason {
        case "budget": return AgentsL10n.text("pause_reason.budget", "Budget exceeded")
        case "manual": return AgentsL10n.text("pause_reason.manual", "Paused manually")
        case "system": return AgentsL10n.text("pause_reason.system", "Paused by system")
        default: return reason
        }
    }

    private func actionLabel(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func wake() async {
        guard let client = app.client else { return }
        await runner.run {
            let run = try await client.invokeHeartbeat(agentId: agentId)
            runs.insert(run, at: 0)
            _ = try? await app.reloadAgent(agentId)
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        do {
            guard let loaded = try await app.reloadAgent(agentId) else { return }
            async let tasksTask = client.issues(companyId: loaded.companyId, assigneeAgentId: agentId)
            async let runsTask = client.runs(companyId: loaded.companyId, agentId: agentId, limit: 10)
            async let skillsTask = client.skills(agentId: agentId)
            tasks = (try? await tasksTask) ?? []
            runs = (try? await runsTask) ?? []
            skills = try? await skillsTask
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct RunRow: View {
    let run: HeartbeatRun

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusLabel).font(.subheadline)
                Text([sourceLabel, run.error].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let date = run.startedAt ?? run.createdAt {
                Text(date.relative).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var statusLabel: String {
        switch run.status {
        case "queued": return AgentsL10n.text("run.status.queued", "Queued")
        case "running": return AgentsL10n.text("run.status.running", "Running")
        case "succeeded": return AgentsL10n.text("run.status.succeeded", "Succeeded")
        case "failed": return AgentsL10n.text("run.status.failed", "Failed")
        case "cancelled": return AgentsL10n.text("run.status.cancelled", "Cancelled")
        case "timed_out": return AgentsL10n.text("run.status.timed_out", "Timed out")
        case "scheduled_retry": return AgentsL10n.text("run.status.scheduled_retry", "Waiting to retry")
        default: return run.status
        }
    }

    private var sourceLabel: String? {
        switch run.invocationSource {
        case "timer": return AgentsL10n.text("run.source.timer", "Scheduled heartbeat")
        case "assignment": return AgentsL10n.text("run.source.assignment", "Task assignment")
        case "on_demand": return AgentsL10n.text("run.source.on_demand", "Manual trigger")
        case "automation": return AgentsL10n.text("run.source.automation", "Automation")
        default: return run.invocationSource
        }
    }

    private var symbol: String {
        switch run.status {
        case "succeeded": return "checkmark.circle.fill"
        case "failed", "timed_out": return "xmark.octagon.fill"
        case "running": return "bolt.circle.fill"
        case "queued", "scheduled_retry": return "clock"
        default: return "minus.circle"
        }
    }

    private var tint: Color {
        switch run.status {
        case "succeeded": return .green
        case "failed", "timed_out": return .red
        case "running": return .blue
        default: return .secondary
        }
    }
}

struct SkillsView: View {
    let snapshot: AgentSkillSnapshot

    var body: some View {
        List {
            if !snapshot.supported {
                Section {
                    Text(AgentsL10n.text("skills.unsupported_help", "This agent’s runtime (\(AgentAdapter.label(for: snapshot.adapterType ?? ""))) does not support skill management."))
                        .foregroundStyle(.secondary)
                }
            }
            if !snapshot.entries.isEmpty {
                Section(AgentsL10n.text("skills.title", "Skills")) {
                    ForEach(snapshot.entries) { entry in
                        HStack {
                            Image(systemName: entry.desired ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(entry.desired ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                if let detail = entry.originLabel ?? entry.detail ?? entry.locationLabel {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let state = entry.state { Text(state).font(.caption2).foregroundStyle(.tertiary) }
                        }
                    }
                }
            }
            if let warnings = snapshot.warnings, !warnings.isEmpty {
                Section(AgentsL10n.text("notices.title", "Notices")) {
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle(AgentsL10n.text("skills.title", "Skills"))
    }
}

/// New-task sheet with the assignee preselected (used from an agent's profile).
struct NewTaskSheetPrefilled: View {
    let assigneeId: String
    let onCreate: (Issue) -> Void

    var body: some View {
        NewTaskSheet(initialAssigneeId: assigneeId, onCreate: onCreate)
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
