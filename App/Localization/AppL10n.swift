import Foundation
import PaperclipKit

/// Native localization with stable keys and typed interpolation. Content supplied by users
/// or the server is displayed verbatim and must never be passed here as a lookup key.
enum AppL10n {
    /// Bundle can report the same language from both Info.plist and .lproj resources.
    static var availableLanguages: [String] {
        Array(Set(Bundle.main.localizations.filter { $0 != "Base" })).sorted()
    }

    static var locale: Locale {
        formattingLocale(language: PaperclipLocalization.shared.languageOverride ?? Bundle.main.preferredLocalizations.first ?? "en", regionalLocale: .current)
    }

    static func formattingLocale(language: String, regionalLocale: Locale) -> Locale {
        var components = Locale.Components(identifier: regionalLocale.identifier)
        components.languageComponents = Locale.Language.Components(identifier: language)
        components.region = regionalLocale.region
        return Locale(components: components)
    }

    static func text(_ key: StaticString, _ value: String.LocalizationValue, table: String = "Localizable", locale explicitLocale: Locale? = nil) -> String {
        String(localized: key, defaultValue: value, table: table, bundle: bundle(for: explicitLocale), locale: explicitLocale ?? locale)
    }

    /// Explicit locales take precedence over the optional in-app language preference.
    /// Adding a locale requires resources, not another language branch here.
    static func bundle(for explicitLocale: Locale?) -> Bundle {
        guard let explicitLocale = explicitLocale ?? PaperclipLocalization.shared.languageOverride.map(Locale.init(identifier:)) else { return .main }
        let language = Bundle.preferredLocalizations(from: Bundle.main.localizations,
                                                     forPreferences: [explicitLocale.identifier, "en"]).first ?? "en"
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    static func date(_ date: Date, style: Date.FormatStyle) -> String {
        date.formatted(style.locale(locale))
    }
}
