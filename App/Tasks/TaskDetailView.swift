import PaperclipKit
import SwiftUI

struct TaskDetailView: View {
    @Environment(AppModel.self) private var app
    let issueId: String

    @State private var issue: Issue?
    @State private var comments: [IssueComment] = []
    @State private var interactions: [IssueInteraction] = []
    @State private var children: [Issue] = []
    @State private var loadError: String?
    @State private var historyRuns: [IssueRun] = []
    @State private var activities: [IssueActivity] = []
    @State private var historyLoaded = false
    @State private var historyError: String?
    @State private var showingDiscussion = false
    @State private var showingTimingHelp = false
    @State private var loadID = UUID()
    @State private var replyScrollID: UUID?
    @State private var runner = ActionRunner()
    @State private var showingDescription = false
    @State private var showingNewSubtask = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var profileRoute: AgentRoute?

    private var pendingInteractions: [IssueInteraction] { interactions.filter(\.isPending) }
    private var resolvedInteractions: [IssueInteraction] { interactions.filter { !$0.isPending } }

    var body: some View {
        Group {
            if let issue {
                content(issue)
            } else if let loadError {
                ContentUnavailableView {
                    Label(TasksL10n.text("task.load_error", "Unable to load task"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button(TasksL10n.text("common.retry", "Retry")) { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(issue?.displayKey ?? TasksL10n.text("task.detail_title", "Task"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // Poll faster while an agent is working so new comments and status changes appear.
        .autoRefresh(every: issue?.isRunning == true ? .seconds(6) : .seconds(20)) { await load() }
        .errorAlert(runner)
    }

    // MARK: - Layout

    private func content(_ issue: Issue) -> some View {
        ScrollViewReader { proxy in
            List {
                header(issue)
                attentionSection(issue).id("attention")
                Section {
                    NavigationLink {
                        TaskResultsView(issueID: issue.id, issueKey: issue.displayKey, companyID: issue.companyId).id(issue.id)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TasksL10n.text("results.title", "Results & deliverables")).font(.headline)
                                Text(TasksL10n.text("results.subtitle", "Reports, documents, attachments and links"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "doc.text.magnifyingglass") }
                    }
                }
                historySummary(issue)
                Section {
                    Picker(TasksL10n.text("task.process_view", "Activity view"), selection: $showingDiscussion) {
                        Text(TasksL10n.text("task.timeline", "Timeline")).tag(false)
                        Text(TasksL10n.text("common.discussion", "Discussion")).tag(true)
                    }.pickerStyle(.segmented)
                    if !showingDiscussion {
                        Button(TasksL10n.text("task.latest", "Jump to latest"), systemImage: "arrow.down.to.line") {
                            withAnimation { proxy.scrollTo("history-latest", anchor: .bottom) }
                        }.font(.footnote)
                    }
                }
                .id("process-tabs")
                if showingDiscussion {
                    threadSection
                        .task(id: replyScrollID) {
                            guard replyScrollID != nil else { return }
                            withAnimation { proxy.scrollTo("discussion-end", anchor: .bottom) }
                            replyScrollID = nil
                        }
                } else {
                    TaskHistoryView(snapshot: TaskHistorySnapshot(issue: issue, activities: activities,
                                                                 runs: historyRuns, interactions: interactions)) { pending in
                        if !pending { showingDiscussion = true }
                        withAnimation { proxy.scrollTo(pending ? "attention" : "process-tabs", anchor: .top) }
                    }
                }
                if let description = issue.description, !description.isEmpty {
                    Section(TasksL10n.text("task.description", "Description")) {
                        MarkdownText(source: description, font: .callout)
                            .lineLimit(showingDescription ? nil : 8)
                        if description.count > 400 {
                            Button(showingDescription ? TasksL10n.text("common.collapse", "Collapse") : TasksL10n.text("common.expand_all", "Show all")) { showingDescription.toggle() }
                                .font(.footnote)
                        }
                    }
                }
                subtasksSection(issue)
                relationsSection(issue)
            }
            .listStyle(.insetGrouped)
            .readableWidth()
            .dismissableKeyboard()
            .onChange(of: showingDiscussion) { _, discussion in
                if discussion && replyScrollID == nil { withAnimation { proxy.scrollTo("process-tabs", anchor: .top) } }
            }
            .refreshable { await load() }
            .safeAreaInset(edge: .bottom) {
                CommentComposer(issue: issue) { reply in
                    let sent = await send(reply, issue: issue)
                    if sent {
                        replyScrollID = UUID()
                        showingDiscussion = true
                    }
                    return sent
                }
            }
            .navigationDestination(item: $profileRoute) { AgentDetailView(agentId: $0.id).id($0.id) }
            .sheet(isPresented: $showingNewSubtask) {
                NewTaskSheet(parent: issue) { created in children.append(created) }
            }
            .alert(TasksL10n.text("task.edit_title", "Edit title"), isPresented: $editingTitle) {
                TextField(TasksL10n.text("task.title", "Title"), text: $titleDraft)
                Button(TasksL10n.text("common.save", "Save")) { Task { await update(IssueUpdate(title: titleDraft)) } }
                Button(TasksL10n.text("common.cancel", "Cancel"), role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func header(_ issue: Issue) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if let ancestors = issue.ancestors, !ancestors.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(ancestors.reversed()) { ancestor in
                                NavigationLink(value: IssueRoute(id: ancestor.id)) {
                                    Text(ancestor.identifier ?? ancestor.title).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(issue.displayKey).foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.medium))
                    }
                }
                Text(issue.title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .onLongPressGesture {
                        titleDraft = issue.title
                        editingTitle = true
                    }

                FlowChips {
                    Menu {
                        ForEach(IssueStatus.selectable, id: \.self) { status in
                            Button { Task { await update(IssueUpdate(status: status)) } } label: {
                                Label(status.label, systemImage: status.symbol)
                            }
                            .disabled(status == issue.status)
                        }
                    } label: {
                        Chip(text: issue.status.label, symbol: issue.status.symbol, tint: issue.status.tint)
                    }
                    Menu {
                        ForEach(IssuePriority.selectable, id: \.self) { priority in
                            Button { Task { await update(IssueUpdate(priority: priority)) } } label: {
                                Label(priority.label, systemImage: priority.symbol)
                            }
                        }
                    } label: {
                        Chip(text: TasksL10n.text("task.priority_value", "Priority: \(issue.priority.label)"), symbol: issue.priority.symbol, tint: issue.priority.tint)
                    }
                    Menu {
                        if let agent = app.agent(issue.assigneeAgentId) {
                            Button { profileRoute = AgentRoute(id: agent.id) } label: {
                                Label(TasksL10n.text("task.view_agent", "View \(agent.name)'s profile"), systemImage: "person.crop.circle")
                            }
                            Divider()
                        }
                        Button(TasksL10n.text("task.unassign", "Unassign")) { Task { await update(.unassign) } }
                        ForEach(app.activeAgents) { agent in
                            Button("\(agent.name) · \(agent.roleLabel)") {
                                Task { await update(.assign(toAgent: agent.id)) }
                            }
                        }
                    } label: {
                        assigneeChip(issue)
                    }
                }
                .disabled(runner.isBusy)

                if issue.isRunning, let run = issue.activeRun {
                    NavigationLink(value: RunRoute(id: run.id)) {
                        HStack(spacing: 10) {
                            HaloAvatar(agent: app.agent(run.agentId), size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(TasksL10n.text("task.agent_activity", "\(app.agent(run.agentId)?.name ?? TasksL10n.text("common.agent", "Agent")) \(run.status == "queued" ? TasksL10n.text("run.agent_queued", "is queued") : TasksL10n.text("run.agent_working", "is working"))"))
                                    .font(.subheadline.weight(.semibold))
                                Text(TasksL10n.text("task.live_output", "View live output")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                                .foregroundStyle(.blue)
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func historySummary(_ issue: Issue) -> some View {
        Section {
            TaskTimingView(issue: issue)
            if historyLoaded && historyError == nil {
                TimelineView(.periodic(from: .now, by: historyRuns.contains { $0.status == "running" } ? 1 : 60)) { context in
                    let runs = TaskTiming.uniqueRuns(historyRuns)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(TasksL10n.text("task.cumulative_runs", "Total linked run time: \(TaskTiming.text(TaskTiming.cumulative(runs, at: context.date)))"))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(TasksL10n.text("task.run_count", "\(runs.count) run records · includes retries, excludes subtasks"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let historyError {
                ErrorBanner(message: historyError) { Task { await load() } }
            } else {
                ProgressView(TasksL10n.text("task.loading_runs", "Loading run records…")).font(.caption)
            }
            if let loadError {
                ErrorBanner(message: loadError) { Task { await load() } }
            }
            Button(TasksL10n.text("task.timing_help", "How is time measured?"), systemImage: "info.circle") { showingTimingHelp = true }
                .font(.caption)
                .alert(TasksL10n.text("task.timing_definition", "Time measurements"), isPresented: $showingTimingHelp) {
                    Button(TasksL10n.text("common.got_it", "Got it"), role: .cancel) {}
                } message: {
                    Text(TasksL10n.text("task.timing_explanation", "Elapsed time runs from creation to completion or now, including waiting and blocked periods. Linked run time adds up each run from start to finish, including tool and model waits. A run may involve multiple tasks, and concurrent runs may add up to more than elapsed time; this is not time spent exclusively on this task. Waiting time is not estimated when status records are incomplete."))
                }
        }
    }

    private func assigneeChip(_ issue: Issue) -> some View {
        HStack(spacing: 5) {
            if let agent = app.agent(issue.assigneeAgentId) {
                AgentAvatar(agent: agent, size: 18)
                Text(agent.name)
            } else {
                Image(systemName: "person.crop.circle.badge.plus").imageScale(.small)
                Text(issue.assigneeUserId != nil ? TasksL10n.text("common.board_member", "Board member") : TasksL10n.text("task.unassigned", "Unassigned"))
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(issue.assigneeAgentId == nil ? Color.secondary : AgentPalette.accent(for: app.agent(issue.assigneeAgentId)))
        .padding(.leading, issue.assigneeAgentId == nil ? 10 : 4)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(
            (issue.assigneeAgentId == nil ? Color.secondary : AgentPalette.accent(for: app.agent(issue.assigneeAgentId))).opacity(0.14),
            in: Capsule())
    }

    /// What is holding this task up and what the user can do about it.
    @ViewBuilder
    private func attentionSection(_ issue: Issue) -> some View {
        if !pendingInteractions.isEmpty || issue.status == .blocked || issue.unblockDescriptor != nil
            || issue.activeRecoveryAction != nil {
            Section {
                if let recovery = issue.activeRecoveryAction, recovery.status == "active" {
                    RecoveryCard(action: recovery) { decision in
                        await resolveRecovery(recovery, decision)
                    }
                }
                if let descriptor = issue.unblockDescriptor {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TasksL10n.text("task.unblock_owner", "Needed to unblock: \(ownerText(descriptor.owner))")).font(.subheadline.weight(.medium))
                            if !descriptor.action.isEmpty {
                                Text(descriptor.action).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                    }
                } else if issue.status == .blocked && pendingInteractions.isEmpty && issue.activeRecoveryAction == nil {
                    Label(TasksL10n.text("task.blocked_help", "This task is blocked. Read the latest comments, then reply below and choose “Reply and resume” to wake the agent and continue."), systemImage: "exclamationmark.octagon")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(pendingInteractions) { interaction in
                    InteractionCardView(interaction: interaction) { resolution in
                        await resolve(interaction, resolution)
                    }
                }
            } header: {
                Label(TasksL10n.text("inbox.attention", "Needs your attention"), systemImage: "bell.badge.fill").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func subtasksSection(_ issue: Issue) -> some View {
        Section {
            if !children.isEmpty {
                let done = children.filter { $0.status == .done }.count
                let counted = children.filter { $0.status != .cancelled }.count
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(TasksL10n.text("task.subtask_progress", "Subtask progress")).font(.subheadline)
                        Spacer()
                        Text("\(done)/\(counted)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: counted == 0 ? 0 : Double(done) / Double(counted)).tint(.green)
                }
                ForEach(children) { child in
                    NavigationLink(value: IssueRoute(id: child.id)) { TaskRow(issue: child) }
                }
            }
            Button {
                showingNewSubtask = true
            } label: {
                Label(TasksL10n.text("task.add_subtask", "Add subtask"), systemImage: "plus.circle")
            }
        } header: {
            Text(TasksL10n.text("task.subtasks", "Subtasks"))
        }
    }

    @ViewBuilder
    private func relationsSection(_ issue: Issue) -> some View {
        let blockers = issue.blockedBy ?? []
        let blocking = issue.blocks ?? []
        if !blockers.isEmpty || !blocking.isEmpty {
            Section(TasksL10n.text("task.dependencies", "Dependencies")) {
                ForEach(blockers) { relation in
                    NavigationLink(value: IssueRoute(id: relation.id)) {
                        relationRow(relation, prefix: TasksL10n.text("task.blocked_by", "Blocked by"))
                    }
                }
                ForEach(blocking) { relation in
                    NavigationLink(value: IssueRoute(id: relation.id)) {
                        relationRow(relation, prefix: TasksL10n.text("task.blocks", "Blocks"))
                    }
                }
            }
        }
    }

    private func relationRow(_ relation: IssueRelationSummary, prefix: String) -> some View {
        HStack {
            StatusBadge(status: relation.status, compact: true)
            VStack(alignment: .leading) {
                Text("\(prefix) \(relation.identifier ?? "")").font(.caption).foregroundStyle(.secondary)
                Text(relation.title).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var threadSection: some View {
        Section {
            if comments.isEmpty && resolvedInteractions.isEmpty {
                Text(TasksL10n.text("discussion.empty", "No discussion yet.")).foregroundStyle(.secondary)
            }
            ForEach(timeline, id: \.id) { entry in
                switch entry {
                case .comment(let comment):
                    CommentRow(comment: comment)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                case .interaction(let interaction):
                    ResolvedInteractionRow(interaction: interaction)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            Color.clear.frame(height: 1).listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear).listRowSeparator(.hidden).id("discussion-end")
        } header: {
            Text(TasksL10n.text("discussion.count", "Discussion · \(comments.filter { $0.deletedAt == nil }.count)"))
        }
    }

    private enum TimelineEntry {
        case comment(IssueComment)
        case interaction(IssueInteraction)

        var id: String {
            switch self {
            case .comment(let comment): return "c-" + comment.id
            case .interaction(let interaction): return "i-" + interaction.id
            }
        }

        var date: Date {
            switch self {
            case .comment(let comment): return comment.createdAt
            case .interaction(let interaction): return interaction.resolvedAt ?? interaction.createdAt ?? .distantPast
            }
        }
    }

    private var timeline: [TimelineEntry] {
        (comments.filter { $0.deletedAt == nil }.map(TimelineEntry.comment)
            + resolvedInteractions.map(TimelineEntry.interaction))
            .sorted { $0.date < $1.date }
    }

    private func ownerText(_ owner: IssueUnblockDescriptor.Owner) -> String {
        switch owner {
        case .agent(let id): return app.agent(id)?.name ?? TasksL10n.text("common.some_agent", "An agent")
        case .user(let id): return id == app.identity?.userId ? TasksL10n.text("common.you", "You") : TasksL10n.text("common.a_board_member", "A board member")
        case .board: return TasksL10n.text("common.board_you", "Board (you)")
        }
    }

    // MARK: - Data

    private func fetchHistory(_ client: PaperclipClient) async -> ([IssueRun]?, [IssueActivity]?) {
        async let runs = try? client.issueRuns(issueId: issueId)
        async let events = try? client.issueActivity(issueId: issueId)
        return await (runs, events)
    }

    private func load() async {
        guard let client = app.client else { return }
        let request = UUID()
        loadID = request
        do {
            async let issueTask = client.issue(id: issueId)
            async let commentsTask = try? client.comments(issueId: issueId)
            async let interactionsTask = try? client.interactions(issueId: issueId)
            async let historyTask = fetchHistory(client)
            let loaded = try await issueTask
            guard loadID == request, !Task.isCancelled else { return }
            if await app.alignCompany(with: loaded) { return }
            async let childrenTask = try? client.childIssues(companyId: loaded.companyId, parentId: loaded.id)
            let (newComments, newInteractions, history, newChildren) = await (commentsTask, interactionsTask, historyTask, childrenTask)
            guard loadID == request, !Task.isCancelled else { return }
            issue = loaded
            comments = newComments ?? comments
            interactions = newInteractions ?? interactions
            children = newChildren ?? children
            if let runs = history.0 { historyRuns = runs }
            if let events = history.1 { activities = events }
            if history.0 != nil && history.1 != nil {
                historyLoaded = true
                historyError = nil
            } else {
                historyError = TasksL10n.text("task.history_refresh_error", "The timeline could not fully refresh. Existing records may be out of date. Please try again.")
            }
            loadError = nil
        } catch {
            guard loadID == request else { return }
            loadError = error.localizedDescription
        }
    }

    private func update(_ update: IssueUpdate) async {
        guard let client = app.client else { return }
        await runner.run {
            let updated = try await client.updateIssue(id: issueId, update)
            loadID = UUID()
            merge(updated)
            app.didMutate()
            await load()
        }
    }

    /// Sends a reply. Plain replies post a comment; "reply and continue" uses the same
    /// follow-up intent as the web UI, which reopens/unblocks and wakes the assignee.
    private func send(_ reply: CommentComposer.Reply, issue: Issue) async -> Bool {
        guard let client = app.client else { return false }
        return await runner.run {
            switch reply.mode {
            case .comment:
                let comment = try await client.addComment(issueId: issue.id, NewComment(body: reply.body))
                comments.append(comment)
            case .resume:
                let comment = try await client.addComment(
                    issueId: issue.id, NewComment(body: reply.body, resume: true))
                comments.append(comment)
            case .interrupt:
                let comment = try await client.addComment(
                    issueId: issue.id, NewComment(body: reply.body, interrupt: true))
                comments.append(comment)
            }
            if let refreshed = try? await client.issue(id: issue.id) { merge(refreshed) }
            app.didMutate()
            await load()
        }
    }

    private func resolveRecovery(_ action: IssueRecoveryAction, _ decision: RecoveryDecision) async {
        guard let client = app.client else { return }
        await runner.run {
            try await client.resolveRecovery(issueId: issueId, actionId: action.id, decision)
            await load()
            app.didMutate()
        }
    }

    private func resolve(_ interaction: IssueInteraction, _ resolution: InteractionResolution) async {
        guard let client = app.client else { return }
        await runner.run {
            let resolved = try await client.resolve(issueId: issueId, interactionId: interaction.id, resolution)
            if let index = interactions.firstIndex(where: { $0.id == resolved.id }) {
                interactions[index] = resolved
            }
            if let refreshed = try? await client.issue(id: issueId) { merge(refreshed) }
            comments = (try? await client.comments(issueId: issueId)) ?? comments
            app.didMutate()
            await load()
        }
    }

    /// PATCH responses omit detail-only fields (ancestors, relations); keep the ones we had.
    private func merge(_ updated: Issue) {
        var merged = updated
        if let current = issue {
            merged.ancestors = updated.ancestors ?? current.ancestors
            merged.blockedBy = updated.blockedBy ?? current.blockedBy
            merged.blocks = updated.blocks ?? current.blocks
        }
        issue = merged
    }
}

/// A comment as a chat bubble: agents on the left in their palette, the board on the right.
struct CommentRow: View {
    @Environment(AppModel.self) private var app
    let comment: IssueComment

    private var isMine: Bool { comment.isAuthored(byUser: app.identity?.userId) }
    private var agent: Agent? { app.agent(comment.authorAgentId) }

    var body: some View {
        if comment.authorType == .system {
            SystemNote(body: comment.body, date: comment.createdAt)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if isMine {
                    Spacer(minLength: 40)
                } else if comment.isFromAgent {
                    HaloAvatar(agent: agent, size: 30)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(authorName).font(.caption.weight(.semibold))
                        Text(comment.createdAt.relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(isMine ? Color.secondary : AgentPalette.accent(for: agent))
                    MarkdownText(source: comment.body, font: .callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(bubble, in: BubbleShape(mine: isMine))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 520, alignment: isMine ? .trailing : .leading)
                if !isMine { Spacer(minLength: 24) }
            }
            .padding(.vertical, 2)
        }
    }

    private var bubble: AnyShapeStyle {
        if isMine { return AnyShapeStyle(Color.accentColor.opacity(0.16)) }
        if !comment.isFromAgent { return AnyShapeStyle(Color.secondary.opacity(0.12)) }
        let (a, b) = AgentPalette.colors(for: agent)
        return AnyShapeStyle(LinearGradient(colors: [a.opacity(0.16), b.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var authorName: String {
        if comment.isFromAgent { return agent?.name ?? TasksL10n.text("common.agent", "Agent") }
        if isMine { return TasksL10n.text("common.you", "You") }
        return TasksL10n.text("common.board_member", "Board member")
    }
}

/// Server-written notes (recovery, retries): compact, collapsed to a few lines.
struct SystemNote: View {
    let body_: String
    let date: Date
    @State private var expanded = false

    init(body: String, date: Date) {
        self.body_ = body
        self.date = date
    }

    var body: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Paperclip").font(.caption.weight(.semibold))
                        Text(date.relative).font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(body_)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? TasksL10n.text("common.collapse", "Collapse") : TasksL10n.text("common.expand", "Expand"))
    }
}

/// Rounded bubble with a tighter corner on the speaker's side.
struct BubbleShape: Shape {
    let mine: Bool

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 18, small: CGFloat = 6
        return UnevenRoundedRectangle(
            topLeadingRadius: big,
            bottomLeadingRadius: mine ? big : small,
            bottomTrailingRadius: mine ? small : big,
            topTrailingRadius: big,
            style: .continuous
        ).path(in: rect)
    }
}

/// Lays chips out in rows, wrapping when they run out of width.
struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ResolvedInteractionRow: View {
    let interaction: IssueInteraction

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(TasksL10n.text("interaction.resolved_summary", "\(interaction.kind.label) “\(interaction.title ?? "")” · \(statusText)"))
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private var statusText: String {
        switch interaction.status {
        case .accepted: return TasksL10n.text("interaction.accepted", "Accepted")
        case .rejected: return TasksL10n.text("common.rejected", "Rejected")
        case .answered: return TasksL10n.text("interaction.answered", "Answered")
        case .cancelled: return TasksL10n.text("interaction.withdrawn", "Withdrawn")
        case .expired: return TasksL10n.text("interaction.expired", "Expired")
        case .failed: return TasksL10n.text("common.failed", "Failed")
        default: return interaction.status.rawValue
        }
    }

    private var icon: String {
        switch interaction.status {
        case .accepted, .answered: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal.fill"
        default: return "clock.badge.xmark"
        }
    }

    private var tint: Color {
        switch interaction.status {
        case .accepted, .answered: return .green
        case .rejected: return .red
        default: return .gray
        }
    }
}
