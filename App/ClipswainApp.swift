import AppIntents
import PaperclipKit
import SwiftUI
import UserNotifications

@main
struct ClipswainApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppModel()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        ClipswainShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.locale, AppL10n.locale)
                .task {
                    NotificationRouter.shared.onOpen = { [app] destination in app.pendingNotification = destination }
                    await app.restore()
                    await app.openPendingNotification()
                }
                .onChange(of: app.pendingNotification) { _, _ in Task { await app.openPendingNotification() } }
                .onOpenURL { app.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AttentionNotifier.scheduleRefresh() }
        }
        .backgroundTask(.appRefresh(AttentionNotifier.taskIdentifier)) {
            await AttentionNotifier.checkInBackground()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = Tab.inbox

    enum Tab: Hashable { case inbox, tasks, agents, settings }

    var body: some View {
        Group {
            if app.isRestoring {
                ProgressView(AppL10n.text("common.connecting", "Connecting…"))
            } else if !app.isConnected {
                ConnectView()
            } else if app.company == nil {
                NoCompanyView()
            } else {
                TabView(selection: $tab) {
                    InboxView()
                        .tabItem { Label(AppL10n.text("common.inbox", "Inbox"), systemImage: "tray.full") }
                        .badge(app.inbox?.unreadCount ?? 0)
                        .tag(Tab.inbox)
                    TaskListView()
                        .tabItem { Label(AppL10n.text("common.tasks", "Tasks"), systemImage: "checklist") }
                        .tag(Tab.tasks)
                    AgentListView()
                        .tabItem { Label(AppL10n.text("app.agents", "Agents"), systemImage: "person.3") }
                        .tag(Tab.agents)
                    SettingsView()
                        .tabItem { Label(AppL10n.text("common.settings", "Settings"), systemImage: "gearshape") }
                        .tag(Tab.settings)
                }
                // Recreate per company so every tab reloads from scratch.
                .id(app.selectedCompanyId)
                .onChange(of: app.pendingRoute) { _, route in
                    if route != nil { tab = .inbox }
                }
            }
        }
    }
}

struct NoCompanyView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label(AppL10n.text("common.no_company", "No company yet"), systemImage: "building.2")
        } description: {
            Text(AppL10n.text("common.no_company_help", "You do not have access to a company on this Paperclip server yet. Create one on the web, then refresh."))
        } actions: {
            Button(AppL10n.text("common.refresh", "Refresh")) { Task { await app.reloadCompanies() } }
            Button(AppL10n.text("common.disconnect", "Disconnect"), role: .destructive) { Task { await app.signOut() } }
        }
    }
}
