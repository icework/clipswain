import Foundation
import Observation

/// One persisted preference shared by App UI and package presentation strings.
/// Nil follows native per-app/system language negotiation. Language identifiers are
/// resource-driven so adding a translation does not require new business-code cases.
@Observable public final class PaperclipLocalization {
    public static let shared = PaperclipLocalization()
    private let defaults: UserDefaults
    private let preferenceKey = "paperclip.languageOverride"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var languageOverride: String? {
        get {
            access(keyPath: \.languageOverride)
            guard let value = defaults.string(forKey: preferenceKey),
                  Bundle.module.localizations.contains(value) else { return nil }
            return value
        }
        set {
            withMutation(keyPath: \.languageOverride) {
                if let newValue, Bundle.module.localizations.contains(newValue) {
                    defaults.set(newValue, forKey: preferenceKey)
                } else {
                    defaults.removeObject(forKey: preferenceKey)
                }
            }
        }
    }
}
