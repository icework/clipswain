import Foundation

/// Agent and connection UI strings. Add translations to Agents.xcstrings for new languages.
/// Keep server-authored names, instructions, and runtime output outside this table.
enum AgentsL10n {
    static func text(_ key: StaticString, _ value: String.LocalizationValue, locale: Locale? = nil) -> String {
        AppL10n.text(key, value, table: "Agents", locale: locale)
    }
}
