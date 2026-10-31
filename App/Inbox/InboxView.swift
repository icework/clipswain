import PaperclipKit
import SwiftUI
import UserNotifications

struct InboxView: View {
    @Environment(AppModel.self) private var app
    @State private var showsActions = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker(TasksL10n.text("inbox.mode", "Inbox view"), selection: $showsActions) {
                    Text(TasksL10n.text("inbox.events", "Events")).tag(false)
                    Text(TasksL10n.text("inbox.actions", "Needs attention")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if showsActions {
                    AttentionInboxContent()
                } else if let store = app.inbox {
                    InboxEventsContent(store: store) { event in
                        store.setRead(true, ids: [event.id])
                        path.append(IssueRoute(id: event.issueId))
                    } refresh: { await refresh() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(TasksL10n.text("inbox.title", "Inbox"))
            .paperclipDestinations()
            .task(id: app.revision) { await refresh() }
            .autoRefresh(every: .seconds(30)) { await refresh() }
            .onChange(of: app.inbox?.unreadCount, initial: true) { _, count in
                Task { try? await UNUserNotificationCenter.current().setBadgeCount(count ?? 0) }
            }
            .onChange(of: app.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                path = NavigationPath()
                switch route {
                case .issue(let id): path.append(IssueRoute(id: id))
                case .approval(let id): path.append(ApprovalRoute(id: id))
                case .agent(let id): path.append(AgentRoute(id: id))
                case .run(let id): path.append(RunRoute(id: id))
                }
                app.pendingRoute = nil
            }
        }
    }

    private func refresh() async {
        guard let client = app.client, let companyId = app.selectedCompanyId, let store = app.inbox else { return }
        await store.sync(client: client, companyId: companyId, foreground: true)
    }
}

private struct InboxEventsContent: View {
    let store: InboxStore
    let open: (InboxEvent) -> Void
    let refresh: () async -> Void
    @State private var filtering = false
    @State private var visibleCount = 100

    var body: some View {
        List {
            if let error = store.persistenceError {
                Section { ErrorBanner(message: TasksL10n.text("inbox.storage_error", "Inbox changes could not be saved: \(error)")) }
            }
            if let error = store.syncError {
                Section { ErrorBanner(message: TasksL10n.text("inbox.sync_error", "Some task history could not be refreshed: \(error)")) { Task { await refresh() } } }
            }
            Section {
                ForEach(store.visibleEvents.prefix(visibleCount)) { event in
                    Button { open(event) } label: {
                        InboxEventRow(event: event, isRead: store.isRead(event))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) { readAction(event) }
                    .contextMenu { readAction(event) }
                }
                if store.visibleEvents.count > visibleCount {
                    Button(TasksL10n.text("inbox.load_earlier", "Load earlier events")) { visibleCount += 100 }
                }
            } header: {
                HStack {
                    Text(TasksL10n.text("inbox.unread_count", "Unread: \(store.unreadCount)"))
                    Spacer()
                    Text(TasksL10n.text("inbox.newest_first", "Newest first"))
                }
                .textCase(nil)
            } footer: {
                Text(TasksL10n.text("inbox.history_help", "Events stay here after a task changes again. Swipe an event to change its read status."))
            }
            if store.hasSynced && store.visibleEvents.isEmpty {
                ContentUnavailableView(
                    TasksL10n.text("inbox.events_empty", "No events to show"), systemImage: "tray",
                    description: Text(TasksL10n.text("inbox.events_empty_help", "Change your filters or pull to refresh task history.")))
                    .listRowBackground(Color.clear)
            }
        }
        .readableWidth()
        .refreshable { await refresh() }
        .overlay {
            if !store.hasSynced && store.events.isEmpty {
                ProgressView(TasksL10n.text("inbox.syncing", "Loading task history…"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { filtering = true } label: {
                    Image(systemName: store.enabledKinds.count == InboxEventKind.allCases.count && store.readFilter == .all
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(TasksL10n.text("inbox.filters", "Inbox filters"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(TasksL10n.text("inbox.mark_filtered_read", "Mark filtered events as read"), systemImage: "envelope.open") {
                        store.setRead(true, ids: store.visibleEvents.map(\.id))
                    }
                    .disabled(!store.visibleEvents.contains { !store.isRead($0) })
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(TasksL10n.text("inbox.event_actions", "Event actions"))
            }
        }
        .sheet(isPresented: $filtering) { InboxFilters(store: store) }
        .onChange(of: store.readFilter) { _, _ in visibleCount = 100 }
        .onChange(of: store.enabledKinds) { _, _ in visibleCount = 100 }
    }

    private func readAction(_ event: InboxEvent) -> some View {
        Button {
            store.setRead(!store.isRead(event), ids: [event.id])
        } label: {
            Label(store.isRead(event) ? TasksL10n.text("inbox.mark_unread", "Mark as unread") : TasksL10n.text("inbox.mark_read", "Mark as read"),
                  systemImage: store.isRead(event) ? "envelope.badge" : "envelope.open")
        }
        .tint(.blue)
    }
}

private struct InboxFilters: View {
    @Environment(\.dismiss) private var dismiss
    let store: InboxStore

    var body: some View {
        NavigationStack {
            Form {
                Section(TasksL10n.text("inbox.read_status", "Read status")) {
                    Picker(TasksL10n.text("inbox.read_status", "Read status"), selection: Binding(get: { store.readFilter }, set: store.setReadFilter)) {
                        ForEach(InboxStore.ReadFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(InboxEventKind.allCases, id: \.self) { kind in
                        Toggle(isOn: Binding(get: { store.isEnabled(kind) }, set: { store.setEnabled($0, kind: kind) })) {
                            Label(kind.label, systemImage: kind.symbol).foregroundStyle(kind.tint)
                        }
                    }
                } header: {
                    Text(TasksL10n.text("inbox.event_types", "Event types"))
                } footer: {
                    Text(TasksL10n.text("inbox.filter_help", "Turn off a type to hide its events and stop its background notifications. History is kept and returns when you turn it back on."))
                }
                Section {
                    Button(TasksL10n.text("inbox.reset_filters", "Show all events")) {
                        for kind in InboxEventKind.allCases { store.setEnabled(true, kind: kind) }
                        store.setReadFilter(.all)
                    }
                } footer: {
                    Text(TasksL10n.text("inbox.local_state", "Filters and read status are saved on this device, separately for each server, account, and company."))
                }
                Section {
                    Toggle(TasksL10n.text("inbox.attention_notifications", "Questions, approvals and failures"), isOn: Binding(
                        get: { store.attentionNotificationsEnabled }, set: store.setAttentionNotificationsEnabled))
                } footer: {
                    Text(TasksL10n.text("inbox.attention_notifications_help", "Keep background reminders for items that need your attention, even without a task status change. Blocked and review reminders follow the event type filters above."))
                }
            }
            .navigationTitle(TasksL10n.text("inbox.filters", "Inbox filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(TasksL10n.text("inbox.filter_done", "Done")) { dismiss() } } }
        }
    }
}

private struct InboxEventRow: View {
    let event: InboxEvent
    let isRead: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.title3)
                .foregroundStyle(event.kind.tint)
                .frame(width: 38, height: 38)
                .background(event.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.identifier ?? "—").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text(AppL10n.date(event.date, style: .dateTime.month().day().hour().minute()))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(event.title).font(.subheadline.weight(isRead ? .regular : .semibold)).lineLimit(2)
                Text(event.kind.label).font(.caption.weight(.medium)).foregroundStyle(event.kind.tint)
                if let previous = event.previousStatus {
                    Text("\(previous.label) → \(event.status.label)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Circle().fill(isRead ? Color.clear : Color.accentColor).frame(width: 7, height: 7).padding(.top, 6)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRead ? TasksL10n.text("inbox.read", "Read") : TasksL10n.text("inbox.unread", "Unread"))
    }
}

extension InboxStore.ReadFilter {
    var label: String {
        switch self {
        case .all: return TasksL10n.text("inbox.all", "All")
        case .unread: return TasksL10n.text("inbox.unread", "Unread")
        case .read: return TasksL10n.text("inbox.read", "Read")
        }
    }
}

extension InboxEventKind {
    var label: String {
        switch self {
        case .blocked: return TasksL10n.text("inbox.event_blocked", "Task blocked")
        case .completed: return TasksL10n.text("inbox.event_completed", "Task completed")
        case .started: return TasksL10n.text("inbox.event_started", "Task started")
        case .review: return TasksL10n.text("inbox.event_review", "Ready for review")
        case .reopened: return TasksL10n.text("inbox.event_reopened", "Task reopened")
        case .cancelled: return TasksL10n.text("inbox.event_cancelled", "Task cancelled")
        case .created: return TasksL10n.text("inbox.event_created", "Task created")
        case .statusChanged: return TasksL10n.text("inbox.event_changed", "Other status changes")
        }
    }
    var symbol: String {
        switch self {
        case .blocked: return "exclamationmark.octagon.fill"
        case .completed: return "checkmark.circle.fill"
        case .started: return "play.circle.fill"
        case .review: return "eye.circle.fill"
        case .reopened: return "arrow.uturn.backward.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .created: return "plus.circle.fill"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        }
    }
    var tint: Color {
        switch self {
        case .blocked: return .red
        case .completed: return .green
        case .started: return .blue
        case .review: return .purple
        case .reopened: return .orange
        case .cancelled: return .secondary
        case .created: return .teal
        case .statusChanged: return .indigo
        }
    }
}
