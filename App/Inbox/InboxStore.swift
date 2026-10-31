import CryptoKit
import Foundation
import Observation
import PaperclipKit

/// Device-local mail state. Separate files isolate servers, accounts, and companies.
@MainActor
@Observable
final class InboxStore {
    enum ReadFilter: String, Codable, CaseIterable { case all, unread, read }
    private static var openStores: [String: InboxStore] = [:]

    private struct Archive: Codable {
        var version = 1
        var events: [InboxEvent] = []
        var readIDs: Set<String> = []
        var notifiedIDs: Set<String> = []
        var enabledKinds = Set(InboxEventKind.allCases)
        var readFilter = ReadFilter.all
        var checkpoints: [String: Date] = [:]
        var notificationStartAt: Date?
        var attentionNotifiedIDs: Set<String>?
        var attentionNotificationsEnabled: Bool?
        var attentionStatusReceipts: [AttentionStatusReceipt]?
    }

    private struct AttentionStatusReceipt: Codable {
        var issueId: String
        var kind: InboxEventKind
        var knownThrough: Date
        var existingEventIDs: Set<String>
    }

    private var archive = Archive()
    private let fileURL: URL
    private let companyId: String
    let scope: InboxScope
    private var isDeliveringNotifications = false
    private var canSave = true
    private(set) var persistenceError: String?
    private(set) var syncError: String?
    private(set) var isSyncing = false
    private(set) var hasSynced = false

    init(serverURL: URL, accountID: String, companyId: String, directory: URL? = nil, now: Date = .now) {
        self.companyId = companyId
        self.scope = InboxScope(serverURL: serverURL, accountID: accountID, companyId: companyId)
        archive = Archive(notificationStartAt: now)
        let scope = try! JSONEncoder().encode([PaperclipClient.normalize(serverURL).absoluteString, accountID, companyId])
        let filename = SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined() + ".json"
        let directory = directory ?? URL.applicationSupportDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
        fileURL = directory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                var saved = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
                guard saved.version == 1 else { throw CocoaError(.coderReadCorrupt) }
                if saved.notificationStartAt == nil { saved.notificationStartAt = now }
                archive = saved
            }
        } catch {
            // Preserve unknown/corrupt data for recovery instead of replacing it with an empty archive.
            canSave = false
            persistenceError = error.localizedDescription
        }
    }

    static func accountID(client: PaperclipClient, identity: BoardIdentity?) -> String {
        guard let token = client.token else { return "local-board" }
        if let id = identity?.userId { return "user:" + id }
        return "credential:" + SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Foreground and background work share one writer, including during scene transitions.
    static func open(serverURL: URL, accountID: String, companyId: String) -> InboxStore {
        let key = String(decoding: try! JSONEncoder().encode([PaperclipClient.normalize(serverURL).absoluteString, accountID, companyId]), as: UTF8.self)
        if let store = openStores[key] { return store }
        let store = InboxStore(serverURL: serverURL, accountID: accountID, companyId: companyId)
        openStores[key] = store
        return store
    }

    var events: [InboxEvent] { archive.events }
    var enabledKinds: Set<InboxEventKind> { archive.enabledKinds }
    var readFilter: ReadFilter { archive.readFilter }
    var attentionNotificationsEnabled: Bool { archive.attentionNotificationsEnabled ?? true }
    var unreadCount: Int { archive.events.filter { isEnabled($0.kind) && !isRead($0) }.count }
    var visibleEvents: [InboxEvent] {
        archive.events.filter {
            isEnabled($0.kind) && (readFilter == .all || (readFilter == .read) == isRead($0))
        }
    }
    var notificationCandidates: [InboxEvent] {
        archive.events.filter { $0.date >= (archive.notificationStartAt ?? .distantFuture) && isEnabled($0.kind) && !isRead($0) && !archive.notifiedIDs.contains($0.id) }
    }
    func isRead(_ event: InboxEvent) -> Bool { archive.readIDs.contains(event.id) }
    func isEnabled(_ kind: InboxEventKind) -> Bool { archive.enabledKinds.contains(kind) }

    func setRead(_ read: Bool, ids: [String]) {
        if read { archive.readIDs.formUnion(ids) }
        else { archive.readIDs.subtract(ids) }
        save()
    }
    func setEnabled(_ enabled: Bool, kind: InboxEventKind) {
        if enabled && !isEnabled(kind) {
            // Re-enabling restores old mail without sending a burst of historical alerts.
            archive.notifiedIDs.formUnion(archive.events.filter { $0.kind == kind }.map(\.id))
        }
        if enabled { archive.enabledKinds.insert(kind) }
        else { archive.enabledKinds.remove(kind) }
        save()
    }
    func setReadFilter(_ filter: ReadFilter) { archive.readFilter = filter; save() }
    func markNotified(_ ids: [String]) { archive.notifiedIDs.formUnion(ids); save() }

    func setAttentionNotificationsEnabled(_ enabled: Bool) {
        archive.attentionNotificationsEnabled = enabled
        save()
    }

    func markAttentionSeen(_ ids: [String]) {
        var known = archive.attentionNotifiedIDs ?? []
        known.formUnion(ids)
        archive.attentionNotifiedIDs = known
        save()
    }

    func markAttentionDelivered(_ item: AttentionItem, observedAt: Date) {
        if let kind = statusKind(for: item), let issueId = item.issueId {
            var receipts = archive.attentionStatusReceipts ?? []
            receipts.append(AttentionStatusReceipt(issueId: issueId, kind: kind,
                knownThrough: item.activityAt ?? observedAt,
                existingEventIDs: Set(archive.events.filter { $0.issueId == issueId && $0.kind == kind }.map(\.id))))
            archive.attentionStatusReceipts = receipts
        }
        markAttentionSeen([item.id])
    }

    private func statusKind(for item: AttentionItem) -> InboxEventKind? {
        switch item.sourceKind {
        case "blocker_attention": return .blocked
        case "review": return .review
        default: return nil
        }
    }

    func shouldNotifyAttention(_ item: AttentionItem) -> Bool {
        guard attentionNotificationsEnabled, !(archive.attentionNotifiedIDs ?? []).contains(item.id) else { return false }
        if let eventKind = statusKind(for: item) {
            guard isEnabled(eventKind) else { return false }
            // The status occurrence owns this alert, including after it was read or delivered.
            if let issueId = item.issueId, archive.events.first(where: { $0.issueId == issueId })?.kind == eventKind {
                return false
            }
        }
        return true
    }

    func beginNotificationDelivery() -> Bool {
        guard !isDeliveringNotifications else { return false }
        isDeliveringNotifications = true
        return true
    }
    func endNotificationDelivery() { isDeliveringNotifications = false }

    /// Append only: absent tasks/activities and status reversals never delete earlier mail.
    func ingest(_ activities: [IssueActivity], for issue: Issue) {
        guard issue.companyId == companyId else { return }
        var ids = Set(archive.events.map(\.id))
        for activity in activities {
            if let event = InboxEvent(activity: activity, issue: issue), ids.insert(event.id).inserted {
                archive.events.append(event)
            }
        }
        archive.events.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        // A fallback may arrive before its history. Consume only the latest matching
        // occurrence observed by that delivery, never a later genuine transition.
        if let receipts = archive.attentionStatusReceipts {
            archive.attentionStatusReceipts = receipts.filter { receipt in
                guard receipt.issueId == issue.id,
                      let event = archive.events.first(where: {
                          $0.issueId == issue.id && $0.kind == receipt.kind && ($0.transitionAt ?? $0.date) <= receipt.knownThrough
                              && !receipt.existingEventIDs.contains($0.id)
                      }) else { return true }
                archive.notifiedIDs.insert(event.id)
                return false
            }
        }
        archive.checkpoints[issue.id] = issue.updatedAt
    }

    func needsHistory(_ issue: Issue) -> Bool {
        guard let updated = issue.updatedAt else { return true }
        return archive.checkpoints[issue.id] != updated
    }

    private func save() {
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = error.localizedDescription }
    }

    /// Full per-task history catches transitions that happened while this device was offline.
    /// Only changed tasks are reread; at most four history requests run at a time.
    func sync(client: PaperclipClient, companyId: String, foreground: Bool) async {
        guard !isSyncing, companyId == self.companyId else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let issues = try await client.issues(companyId: companyId)
            try Task.checkCancellation()
            let changed = issues.filter(needsHistory)
            let result = await withTaskGroup(of: HistoryResult.self) { group in
                var iterator = changed.makeIterator()
                func enqueue(_ issue: Issue) {
                    group.addTask {
                        do { return HistoryResult(issue: issue, activities: try await client.issueActivity(issueId: issue.id)) }
                        catch { return HistoryResult(issue: issue, error: error.localizedDescription) }
                    }
                }
                for _ in 0..<4 { if let issue = iterator.next() { enqueue(issue) } }
                var errors: [String] = []
                for await result in group {
                    if !Task.isCancelled {
                        if let activities = result.activities { ingest(activities, for: result.issue) }
                        if let error = result.error { errors.append(error) }
                        if let issue = iterator.next() { enqueue(issue) }
                    }
                }
                return errors
            }
            if foreground { archive.notifiedIDs.formUnion(archive.events.map(\.id)) }
            save()
            syncError = result.first
            hasSynced = true
        } catch is CancellationError {
            save() // Keep completed history reads; never advance failed tasks' checkpoints.
        } catch {
            syncError = error.localizedDescription
            hasSynced = true
        }
    }
}

private struct HistoryResult: Sendable {
    let issue: Issue
    var activities: [IssueActivity]? = nil
    var error: String? = nil
}
