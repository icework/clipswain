import SwiftUI

extension Date {
    /// "3 分钟前"-style relative time.
    var relative: String {
        // Server and device clocks drift a little; never show "in 2 seconds".
        if timeIntervalSinceNow > -45 { return AppL10n.text("common.just_now", "Just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppL10n.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

extension Int {
    /// Cents to a dollar string, e.g. 1250 → "$12.50".
    var dollars: String {
        let formatter = NumberFormatter()
        formatter.locale = AppL10n.locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = self % 100 == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: Double(self) / 100)) ?? "$\(self / 100)"
    }
}

/// Inline error row with a retry action.
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button(AppL10n.text("common.retry", "Retry"), action: retry).font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Runs an async action, tracks busy state and surfaces errors as an alert.
@MainActor
@Observable
final class ActionRunner {
    var isBusy = false
    var errorMessage: String?

    var showsError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    @discardableResult
    func run(_ action: @MainActor () async throws -> Void) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await action()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

extension View {
    func errorAlert(_ runner: ActionRunner) -> some View {
        @Bindable var runner = runner
        return alert(AppL10n.text("common.action_failed", "Action failed"), isPresented: $runner.showsError) {
            Button(AppL10n.text("common.ok", "OK"), role: .cancel) {}
        } message: {
            Text(runner.errorMessage ?? "")
        }
    }
}

/// Re-runs `action` on an interval while the view is on screen, and right away when the app
/// returns to the foreground, so agent progress shows up without pull-to-refresh.
private struct AutoRefresh: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let interval: Duration
    let action: () async -> Void

    private struct Key: Hashable {
        let interval: Duration
        let active: Bool
    }

    func body(content: Content) -> some View {
        content
            // Keyed on the scene phase so the loop restarts with the current value: it stops
            // in the background and starts again on return, instead of reading a stale phase.
            .task(id: Key(interval: interval, active: scenePhase == .active)) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    await action()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await action() } }
            }
    }
}

extension View {
    /// Re-runs `action` periodically; see `AutoRefresh`.
    func autoRefresh(every interval: Duration, _ action: @escaping () async -> Void) -> some View {
        modifier(AutoRefresh(interval: interval, action: action))
    }
}
