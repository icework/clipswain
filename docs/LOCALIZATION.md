# Localization

The app supports English (`en`) and Simplified Chinese (`zh-Hans`). Settings → Language provides an in-app picker: Follow system, English, and 简体中文 (language names use their native spelling). The optional override is persisted by `PaperclipLocalization` in UserDefaults and observed by both App and package helpers. Changes apply immediately without rebuilding the navigation tree. Follow system removes the override and uses native iOS per-app language negotiation; English remains the fallback.

## Resource layout

| Scope | Resource | Lookup |
| --- | --- | --- |
| Shared App UI, settings, statistics, notifications | `App/Localization/Localizable.xcstrings` | `AppL10n.text` |
| Tasks and inbox | `App/Tasks/Tasks.xcstrings` | `TasksL10n.text` |
| Agents and connection | `App/Agents/Agents.xcstrings` | `AgentsL10n.text` |
| iOS permission prompt | `App/Localization/InfoPlist.xcstrings` | iOS |
| Package labels, errors, durations | `PaperclipKit/Sources/PaperclipKit/Resources/<locale>.lproj/Localizable.strings` | `KitL10n.string`, `Bundle.module` |

Catalogs use stable semantic keys, English default values, and manual extraction state. Helpers are thin wrappers around Foundation `String(localized:defaultValue:table:bundle:)`; interpolation and plural selection remain native. The package uses native `.strings` resources so both Xcode and command-line `swift test` process them correctly.

## Adding text

1. Choose the owning table and a semantic key, such as `stats.median`. Distinguish meanings even when source wording matches (Inbox versus Pending).
2. Add an English default with typed Swift interpolation and matching English/Chinese catalog entries. Use `%lld` for `Int`, `%d` for `Int32`, `%@` for strings. Preserve placeholder types and escape literal percent signs in formatted values.
3. For count-dependent English nouns, add native `plural` variations. Do not concatenate a count with a singular/plural suffix in business code.
4. Never localize user/server content: task titles and descriptions, comments, agent/company names, instructions, logs, model IDs or remote error details. Localize only the surrounding application text. Avoid converting arbitrary `Text(dynamic)` to `LocalizedStringKey`.
5. Keep enum IDs, chart grouping IDs, API values, preferences, URLs, keychain identifiers, and payload schemas language-independent. Translate their presentation labels.

Example:

```swift
Text(AppL10n.text("stats.increase", "Up by \(count) tasks"))
```

The resource provides `Up by %lld task` for English `one`, `Up by %lld tasks` for `other`, and `增加 %lld 项` for Simplified Chinese.

## Formatting and fallback

- `AppL10n.locale` and the package formatting locale combine the selected app language with the user’s region. An English app in a Chinese region must not accidentally show Chinese duration units.
- App date formatting uses `AppL10n.date`; currency stays explicitly USD and uses localized formatting. Server timestamps and protocol parsing keep their fixed POSIX/UTC semantics.
- `TaskTiming.text(_:locale:)` provides deterministic formatting in tests; production uses the package’s selected language. Foundation supplies abbreviated duration units and grammatical plurals.
- Native language negotiation handles regional variants. Explicit locale arguments take precedence for tests and previews; otherwise helpers resolve the in-app override, then native OS preferences.
- In-app changes preserve navigation, server connections, keys, task data and notification settings. System-owned permission dialogs still follow iOS language settings; changing language in iOS can restart the app.

## Adding a third language

1. Add the localization in all App catalogs through Xcode’s String Catalog editor. Translate every key and its applicable plural categories.
2. Add the matching package `<locale>.lproj/Localizable.strings` (and `.stringsdict` if needed). Do not add locale switches to model/view code.
3. Add the locale to `CFBundleLocalizations` in `project.yml`. Keep `developmentLanguage: en` and the package’s `defaultLocalization: "en"`.
4. Run `xcodegen generate`, the validation script, package tests, and App tests.
5. Launch the simulator in that language and verify main pages, long text, errors, empty states, notifications, date/number formatting and accessibility sizes. For RTL languages, include layout direction checks.

## Validation

```sh
python3 scripts/check-localizations.py
swift test --package-path PaperclipKit
xcodegen generate
xcodebuild -project Clipswain.xcodeproj -scheme Clipswain \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:ClipswainAppTests test
```

The script checks all declared locales, key coverage, typed placeholders, call-site interpolation counts (including nested localized strings), hard-coded Chinese UI prose, and bare English UI prose (with a narrow technical/brand allowlist). App and package tests exercise compiled-resource lookup, English singular/plural selection, raw dynamic text, region/language combinations, permission text and duration boundaries.

To check a language without altering stored simulator or device preferences, terminate and launch the simulator app with process arguments:

```sh
xcrun simctl launch booted space.icework.clipswain \
  -AppleLanguages '(en)' -AppleLocale en_US
```

Use `(zh-Hans)` and `zh_CN` for Simplified Chinese, and test mismatched language/region combinations too. These launch arguments are only for verification; set the in-app picker to Follow system when testing these native preferences.
