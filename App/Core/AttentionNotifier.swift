import BackgroundTasks
import Foundation
import PaperclipKit
import UserNotifications

/// Checks task history in the background and delivers selected event types without marking mail read.
enum AttentionNotifier {
    static let taskIdentifier = "space.icework.clipswain.refresh"
    private static let enabledKey = "paperclip.notificationsEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Asks for permission; returns whether notifications can be shown.
    static func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isEnabled = granted
        if granted { scheduleRefresh() }
        return granted
    }

    static func scheduleRefresh() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Background deliveries use the same event archive and filters as the inbox.
    @MainActor
    static func checkInBackground() async {
        scheduleRefresh()
        guard isEnabled, AppModel.hasActiveSession,
              let raw = AppModel.savedServerURL, let url = URL(string: raw),
              let companyId = UserDefaults.standard.string(forKey: "paperclip.companyId") else { return }
        let token: String?
        do { token = try Keychain.token(for: raw) } catch { return }
        let client = PaperclipClient(serverURL: url, token: token,
                                    allowInsecureHTTP: AppModel.allowsInsecureHTTP(for: url))
        let identity: BoardIdentity?
        if client.token != nil {
            guard let current = try? await client.me() else { return }
            identity = current
        } else { identity = nil }
        let store = InboxStore.open(serverURL: client.serverURL,
                               accountID: InboxStore.accountID(client: client, identity: identity), companyId: companyId)
        let attentionObservedAt = Date()
        async let attention = try? client.attention(companyId: companyId)
        await store.sync(client: client, companyId: companyId, foreground: false)
        let items = await attention?.items ?? []
        guard !store.isSyncing, isEnabled, AppModel.hasActiveSession,
              AppModel.savedServerURL == raw,
              UserDefaults.standard.string(forKey: "paperclip.companyId") == companyId else { return }
        await notifyNew(store, attention: items, shouldContinue: {
            guard isEnabled, AppModel.hasActiveSession, AppModel.savedServerURL == raw,
                  UserDefaults.standard.string(forKey: "paperclip.companyId") == companyId,
                  AppModel.allowsInsecureHTTP(for: url) == client.allowInsecureHTTP else { return false }
            do { return try Keychain.token(for: raw) == client.token } catch { return false }
        }, now: { attentionObservedAt })
    }

    @MainActor
    static func notifyNew(
        _ store: InboxStore, attention: [AttentionItem] = [], limit: Int = 5,
        deliver: (UNNotificationRequest) async throws -> Void = { try await UNUserNotificationCenter.current().add($0) },
        updateBadge: (Int) async -> Void = { try? await UNUserNotificationCenter.current().setBadgeCount($0) },
        shouldContinue: () -> Bool = { true }, now: () -> Date = { .now }
    ) async {
        guard store.beginNotificationDelivery() else { return }
        defer { store.endNotificationDelivery() }
        let observedAt = now()
        var knownAttention = Set<String>()
        let eventNotices: [Notice] = store.notificationCandidates.map { Notice.event($0) }
        let attentionItems = attention.filter { knownAttention.insert($0.id).inserted && store.shouldNotifyAttention($0) }
        let attentionNotices: [Notice] = attentionItems.map { Notice.attention($0) }
        let candidates: [Notice] = (eventNotices + attentionNotices).sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
        }
        for notice in candidates.prefix(max(limit, 0)) {
            guard shouldContinue(), !Task.isCancelled else { return }
            switch notice {
            case .event(let event):
                guard store.notificationCandidates.contains(where: { $0.id == event.id }) else { continue }
            case .attention(let item):
                guard store.shouldNotifyAttention(item) else { continue }
            }
            do {
                try await deliver(notice.request(scope: store.scope))
                switch notice {
                case .event(let event): store.markNotified([event.id])
                case .attention(let item): store.markAttentionDelivered(item, observedAt: observedAt)
                }
            } catch { continue } // Failed deliveries remain eligible for the next check.
        }
        if shouldContinue() { await updateBadge(store.unreadCount) }
    }

    private enum Notice {
        case event(InboxEvent)
        case attention(AttentionItem)

        var id: String {
            switch self {
            case .event(let event): return "inbox." + event.id
            case .attention(let item): return "attention." + item.id
            }
        }
        var date: Date {
            switch self {
            case .event(let event): return event.date
            case .attention(let item): return item.activityAt ?? .distantPast
            }
        }
        func request(scope: InboxScope) -> UNNotificationRequest {
            let content = UNMutableNotificationContent()
            let destination: NotificationDestination
            switch self {
            case .event(let event):
                content.title = event.kind.label
                content.body = [event.identifier, event.title].compactMap { $0 }.joined(separator: " · ")
                content.threadIdentifier = event.issueId
                destination = NotificationDestination(scope: scope, issueId: event.issueId, eventId: event.id)
            case .attention(let item):
                let title = item.subject.title ?? item.relatedIssue?.title ?? AppL10n.text("notification.needs_attention", "Needs your attention")
                content.title = AppL10n.text("notification.title", "\(item.sourceLabel): \(title)")
                content.body = item.detail?.excerpt ?? item.whyNow ?? ""
                if let agent = item.originAgentName { content.subtitle = AppL10n.text("notification.from_agent", "From \(agent)") }
                content.threadIdentifier = item.issueId ?? item.sourceKind
                destination = NotificationDestination(scope: scope, issueId: item.issueId, approvalId: item.approvalId,
                    agentId: item.subject.kind == "agent" ? item.subject.id : nil,
                    runId: ["run", "heartbeat_run"].contains(item.subject.kind) ? item.subject.id : nil)
            }
            content.sound = .default
            content.userInfo = destination.userInfo
            return UNNotificationRequest(identifier: id, content: content, trigger: nil)
        }
    }

}

/// Routes notification taps into the app.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// A tap that arrived before the app installed its handler (launch from a notification).
    private var pending: NotificationDestination?

    var onOpen: ((NotificationDestination) -> Void)? {
        didSet {
            guard let onOpen, let tap = pending else { return }
            pending = nil
            onOpen(tap)
        }
    }

    @MainActor
    func receive(userInfo: [AnyHashable: Any]) {
        guard let destination = NotificationDestination(userInfo: userInfo) else { return }
        if let onOpen { onOpen(destination) }
        else { pending = destination }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await receive(userInfo: response.notification.request.content.userInfo)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
