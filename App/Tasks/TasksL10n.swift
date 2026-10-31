import Foundation

/// Task and inbox copy uses stable keys so additional languages can be added in Tasks.xcstrings.
/// Dynamic server content is displayed verbatim and never used as a localization key.
enum TasksL10n {
    static func text(_ key: StaticString, _ value: String.LocalizationValue, locale: Locale? = nil) -> String {
        AppL10n.text(key, value, table: "Tasks", locale: locale)
    }
}
