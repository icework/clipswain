import PaperclipKit
import SwiftUI

struct TaskListView: View {
    @Environment(AppModel.self) private var app

    @State private var issues: [Issue] = []
    @State private var filter = TaskListFilter.current
    @State private var assigneeFilter: String?
    @State private var search = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var showingNewTask = false
    @State private var completedCount = 0
    @State private var runner = ActionRunner()
    @State private var loadID = UUID()

    private var snapshot: TaskListSnapshot {
        TaskListSnapshot(issues: issues, assigneeID: assigneeFilter, search: search)
    }
    private var visible: [Issue] { snapshot.matching(filter) }
    private var sections: [(IssueStatus, [Issue])] { snapshot.sections(for: filter) }
    private var scopeLabel: String {
        let owner = assigneeFilter.flatMap { app.agent($0)?.name } ?? (assigneeFilter == nil ? TasksL10n.text("filter.all_assignees", "All assignees") : TasksL10n.text("filter.selected_assignee", "Selected assignee"))
        return search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? owner : TasksL10n.text("filter.search_scope", "\(owner) · Search results")
    }

    var body: some View {
        NavigationStack {
            List {
                if loaded {
                    Section {
                        TaskWorkSummary(snapshot: snapshot, scope: scopeLabel, selection: $filter)
                    }
                }
                Section {
                    filterChips
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .listSectionSpacing(.compact)
                if let error {
                    Section { ErrorBanner(message: error) { Task { await load() } } }
                }
                ForEach(sections, id: \.0) { status, items in
                    Section {
                        ForEach(items) { issue in
                            NavigationLink(value: IssueRoute(id: issue.id)) {
                                TaskRow(issue: issue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if issue.status.isOpen {
                                    Button { Task { await setStatus(.done, for: issue) } } label: {
                                        Label(TasksL10n.text("task.complete", "Complete"), systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if issue.status != .inProgress && issue.status.isOpen {
                                    Button { Task { await setStatus(.todo, for: issue) } } label: {
                                        Label(TasksL10n.text("task.todo", "To do"), systemImage: "circle")
                                    }
                                    .tint(.gray)
                                }
                            }
                            .contextMenu { quickActions(for: issue) }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: status.symbol).foregroundStyle(status.tint)
                            Text(status.label).foregroundStyle(.primary)
                            Text("\(items.count)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(status.tint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(status.tint.opacity(0.14), in: Capsule())
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                    }
                }
                if loaded && visible.isEmpty && error == nil && filter != .current {
                    ContentUnavailableView(emptyTitle, systemImage: "checklist", description: Text(emptyDescription))
                        .listRowBackground(Color.clear)
                }
            }
            .readableWidth()
            .navigationTitle(TasksL10n.text("task.navigation_title", "Tasks"))
            .paperclipDestinations()
            .searchable(text: $search, prompt: TasksL10n.text("task.search_placeholder", "Search title or ID"))
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    assigneeMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewTask = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(TasksL10n.text("task.new", "New task"))
                }
            }
            .sheet(isPresented: $showingNewTask) {
                NewTaskSheet { created in
                    loadID = UUID()
                    issues.insert(created, at: 0)
                }
            }
            .overlay {
                if !loaded && error == nil { ProgressView() }
            }
            .task(id: app.revision) { await load() }
            .autoRefresh(every: .seconds(30)) { await load() }
            .sensoryFeedback(.success, trigger: completedCount)
            .errorAlert(runner)
            .animation(.snappy, value: visible.map(\.id))
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskListFilter.primary) { option in
                    let selected = option == filter || (option == .current && filter.isCurrent)
                    Button {
                        withAnimation(.snappy) { filter = option }
                    } label: {
                        HStack(spacing: 5) {
                            Text(option.label)
                            if loaded {
                                let count = snapshot.count(option)
                                Text("\(count)")
                                    .monospacedDigit()
                                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule().fill(Color.accentColor)
                            } else {
                                Capsule().fill(Color(.secondarySystemGroupedBackground))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    @ViewBuilder
    private func quickActions(for issue: Issue) -> some View {
        Menu {
            ForEach(IssueStatus.selectable, id: \.self) { status in
                Button { Task { await setStatus(status, for: issue) } } label: {
                    Label(status.label, systemImage: status.symbol)
                }
                .disabled(status == issue.status)
            }
        } label: {
            Label(TasksL10n.text("task.change_status", "Change status"), systemImage: issue.status.symbol)
        }
        Menu {
            ForEach(IssuePriority.selectable, id: \.self) { priority in
                Button { Task { await setPriority(priority, for: issue) } } label: {
                    Label(priority.label, systemImage: priority.symbol)
                }
                .disabled(priority == issue.priority)
            }
        } label: {
            Label(TasksL10n.text("task.change_priority", "Change priority"), systemImage: "flag")
        }
        Button {
            UIPasteboard.general.string = issue.displayKey
        } label: {
            Label(TasksL10n.text("task.copy_identifier", "Copy ID \(issue.displayKey)"), systemImage: "doc.on.doc")
        }
    }

    private func setStatus(_ status: IssueStatus, for issue: Issue) async {
        await mutate(issue, IssueUpdate(status: status))
        if status == .done { completedCount += 1 }
    }

    private func setPriority(_ priority: IssuePriority, for issue: Issue) async {
        await mutate(issue, IssueUpdate(priority: priority))
    }

    private func mutate(_ issue: Issue, _ update: IssueUpdate) async {
        guard let client = app.client else { return }
        await runner.run {
            let updated = try await client.updateIssue(id: issue.id, update)
            loadID = UUID()
            if let index = issues.firstIndex(where: { $0.id == issue.id }) {
                var merged = updated
                merged.activeRun = updated.activeRun ?? issues[index].activeRun
                issues[index] = merged
            }
        }
    }

    private var assigneeMenu: some View {
        Menu {
            Picker(TasksL10n.text("task.assignee", "Assignee"), selection: $assigneeFilter) {
                Text(TasksL10n.text("filter.everyone", "Everyone")).tag(String?.none)
                ForEach(app.activeAgents) { agent in
                    Text(agent.name).tag(Optional(agent.id))
                }
            }
        } label: {
            if let agent = app.agent(assigneeFilter) {
                HStack(spacing: 4) {
                    AgentAvatar(agent: agent, size: 22)
                    Text(agent.name).font(.subheadline)
                }
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        .accessibilityLabel(TasksL10n.text("filter.assignee_hint", "Filter by assignee"))
    }

    private var emptyTitle: String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return TasksL10n.text("task.no_matches", "No matching tasks") }
        switch filter {
        case .current: return TasksL10n.text("task.no_current", "No unfinished tasks")
        case .done: return TasksL10n.text("task.no_completed", "No completed tasks yet")
        case .cancelled: return TasksL10n.text("task.no_cancelled", "No cancelled tasks")
        case .all: return TasksL10n.text("task.empty", "No tasks yet")
        default: return TasksL10n.text("task.empty_status", "No tasks with status: \(filter.label)")
        }
    }

    private var emptyDescription: String {
        if assigneeFilter != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TasksL10n.text("task.search_empty_hint", "Try different keywords or another assignee.")
        }
        return filter == .current ? TasksL10n.text("task.current_empty_hint", "View the history or create a task.") : TasksL10n.text("task.status_empty_hint", "Choose another status or create a task.")
    }

    private func load() async {
        guard let client = app.client, let companyId = app.selectedCompanyId else { return }
        let request = UUID()
        loadID = request
        do {
            let fetched = try await client.issues(companyId: companyId)
            guard !Task.isCancelled, loadID == request else { return }
            issues = fetched
            error = nil
            loaded = true
        } catch {
            guard !Task.isCancelled, loadID == request else { return }
            self.error = error.localizedDescription
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var app
    let issue: Issue

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: issue.status.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(issue.status.tint)
                .frame(width: 32, height: 32)
                .background(issue.status.tint.opacity(0.13), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(issue.status.isTerminal ? .secondary : .primary)
                    .strikethrough(issue.status == .cancelled, color: .secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(issue.displayKey).font(.caption.monospaced()).foregroundStyle(.secondary)
                    PriorityBadge(priority: issue.priority)
                    if issue.isRunning {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill").symbolEffect(.pulse)
                            Text(issue.activeRun?.status == "queued" ? TasksL10n.text("run.queued", "Queued") : TasksL10n.text("run.running", "Running"))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    }
                }
                TaskTimingView(issue: issue, compact: true)
            }
            Spacer(minLength: 4)
            if let agent = app.agent(issue.assigneeAgentId) {
                HaloAvatar(agent: agent, size: 34)
            }
        }
        .padding(.vertical, 3)
    }
}
