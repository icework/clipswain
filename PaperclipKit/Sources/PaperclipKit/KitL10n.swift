import Foundation

/// Native bundle localization shared by PaperclipKit presentation strings.
/// API values and server-provided content must never pass through this helper.
enum KitL10n {
    static func string(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        locale: Locale? = nil
    ) -> String {
        String(localized: key, defaultValue: defaultValue,
               bundle: bundle(for: locale), locale: locale ?? formattingLocale)
    }

    /// Keep unit language aligned with the app while retaining regional formatting choices.
    /// A per-app English preference can coexist with a Chinese system region (`en`, `zh_CN`).
    static var formattingLocale: Locale {
        formattingLocale(language: PaperclipLocalization.shared.languageOverride ?? Bundle.module.preferredLocalizations.first ?? "en", regionalLocale: .current)
    }

    static func formattingLocale(language: String, regionalLocale: Locale) -> Locale {
        var components = Locale.Components(identifier: regionalLocale.identifier)
        components.languageComponents = Locale.Components(identifier: language).languageComponents
        components.region = regionalLocale.region
        return Locale(components: components)
    }

    /// Explicit locales take precedence over the optional in-app language preference.
    /// Foundation negotiates regional variants and the package's development-language fallback.
    static func bundle(for locale: Locale?) -> Bundle {
        guard let locale = locale ?? PaperclipLocalization.shared.languageOverride.map(Locale.init(identifier:)) else { return .module }
        let language = Bundle.preferredLocalizations(
            from: Bundle.module.localizations, forPreferences: [locale.identifier]).first ?? "en"
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .module }
        return bundle
    }
}
