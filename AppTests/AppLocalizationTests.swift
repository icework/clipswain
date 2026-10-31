import XCTest
import PaperclipKit
@testable import Clipswain

final class AppLocalizationTests: XCTestCase {
    let en = Locale(identifier: "en_US")
    let zh = Locale(identifier: "zh_Hans_CN")

    func testLanguagePickerHasOneEntryPerPackagedLanguage() {
        let expected = Set(Bundle.main.localizations.filter { $0 != "Base" })
        XCTAssertEqual(Set(AppL10n.availableLanguages), expected)
        XCTAssertEqual(AppL10n.availableLanguages.count, expected.count)
        XCTAssertEqual(AppL10n.availableLanguages.filter { $0 == "en" }.count, 1)
        XCTAssertEqual(AppL10n.availableLanguages.filter { $0 == "zh-Hans" }.count, 1)
        XCTAssertEqual(AppL10n.availableLanguages, AppL10n.availableLanguages.sorted())
    }

    func testInAppPreferenceUpdatesAllTablesAndPackageWithoutRelaunch() {
        let settings = PaperclipLocalization.shared
        let previous = settings.languageOverride
        defer { settings.languageOverride = previous }
        settings.languageOverride = "zh-Hans"
        XCTAssertEqual(AppL10n.text("common.tasks", "Tasks"), "任务")
        XCTAssertEqual(TasksL10n.text("common.untitled", "Untitled"), "未命名")
        XCTAssertEqual(TaskTiming.text(0.5), "不足1秒")
        XCTAssertEqual(AppL10n.locale.language.languageCode?.identifier, "zh")
        XCTAssertEqual(AppL10n.text("common.tasks", "Tasks", locale: en), "Tasks")
        settings.languageOverride = "en"
        XCTAssertEqual(AppL10n.text("common.tasks", "Tasks"), "Tasks")
        XCTAssertEqual(TaskTiming.text(0.5), "Less than 1 second")
        settings.languageOverride = nil
        XCTAssertEqual(AppL10n.bundle(for: nil), Bundle.main)
    }

    func testLanguagePreferencePersistsAndRejectsUnavailableResources() {
        let name = "localization-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = PaperclipLocalization(defaults: defaults)
        settings.languageOverride = "zh-Hans"
        XCTAssertEqual(PaperclipLocalization(defaults: defaults).languageOverride, "zh-Hans")
        settings.languageOverride = "not-a-supported-language"
        XCTAssertNil(settings.languageOverride)
        settings.languageOverride = "en"
        settings.languageOverride = nil
        XCTAssertNil(PaperclipLocalization(defaults: defaults).languageOverride)
    }

    func testBothAppLanguagesAndEnglishFallbackArePackaged() {
        XCTAssertTrue(Bundle.main.localizations.contains("en"))
        XCTAssertTrue(Bundle.main.localizations.contains("zh-Hans"))
        XCTAssertEqual(AppL10n.text("common.tasks", "Tasks", locale: en), "Tasks")
        XCTAssertEqual(AppL10n.text("common.tasks", "Tasks", locale: zh), "任务")
        XCTAssertEqual(AppL10n.text("common.tasks", "Tasks", locale: Locale(identifier: "fr_FR")), "Tasks")
    }

    func testAppLanguageKeepsTheSelectedRegion() {
        let locale = AppL10n.formattingLocale(language: "en", regionalLocale: Locale(identifier: "zh_CN"))
        XCTAssertEqual(locale.language.languageCode?.identifier, "en")
        XCTAssertEqual(locale.region?.identifier, "CN")
    }

    func testNativePluralSelectionAndMixedTypedInterpolation() {
        for count in [0, 1, 2, 1000] {
            let text = AppL10n.text("stats.increase", "Up by \(count) tasks", locale: en)
            XCTAssertTrue(text.hasSuffix(count == 1 ? " task" : " tasks"), text)
            let dynamic = "Grace 中文 50% %@"
            let comparison = AppL10n.text("stats.previous_comparison", "Previous period: \(count) tasks · \(dynamic)", locale: en)
            XCTAssertTrue(comparison.contains(dynamic), comparison)
            XCTAssertTrue(comparison.contains(count == 1 ? " task · " : " tasks · "), comparison)
        }
        XCTAssertEqual(AppL10n.text("a11y.completed_percent", "\(25)% complete", locale: zh), "完成 25%")
    }

    func testFeatureTablesAndPermissionPromptResolveInBothLanguages() {
        for locale in [en, zh] {
            let bundle = AppL10n.bundle(for: locale)
            let count = 1
            let tasks = String(localized: "summary.open_count", defaultValue: "\(count) unfinished tasks", table: "Tasks", bundle: bundle, locale: locale)
            XCTAssertEqual(tasks, locale == en ? "1 unfinished task" : "1 项未结束")
            let skills = String(localized: "skills.count", defaultValue: "\(count) skills", table: "Agents", bundle: bundle, locale: locale)
            XCTAssertEqual(skills, locale == en ? "1 skill" : "1 个")
            let permission = bundle.localizedString(forKey: "NSLocalNetworkUsageDescription", value: nil, table: "InfoPlist")
            XCTAssertNotEqual(permission, "NSLocalNetworkUsageDescription")
            XCTAssertTrue(permission.contains("Paperclip"))
        }
    }

    func testFeaturePluralsAndOngoingDurationInMixedLanguageRegion() {
        let locale = AppL10n.formattingLocale(language: "en", regionalLocale: Locale(identifier: "zh_CN"))
        let count = 1
        XCTAssertEqual(AgentsL10n.text("skills.count", "\(count) skills", locale: locale), "1 skill")
        XCTAssertEqual(TasksL10n.text("summary.open_count", "\(count) unfinished tasks", locale: locale), "1 unfinished task")
        let duration = "2m"
        XCTAssertEqual(TasksL10n.text("history.ongoing_duration", "Ongoing for \(duration)", locale: locale), "Ongoing for 2m")
        XCTAssertEqual(TasksL10n.text("history.finished_duration", "Lasted \(duration)", locale: zh), "持续 2m")
    }

    func testNotificationsAndErrorsPreserveDynamicText() {
        let name = "研究 Agent 100%"
        XCTAssertEqual(AppL10n.text("notification.from_agent", "From \(name)", locale: en), "From \(name)")
        XCTAssertEqual(AppL10n.text("notification.from_agent", "From \(name)", locale: zh), "来自 \(name)")
        let status: Int32 = -25308
        let error = AppL10n.text("keychain.unavailable", "Keychain is temporarily unavailable (\(String(status))). Unlock your device and try again.", locale: zh)
        XCTAssertTrue(error.contains("-25308"), error)
    }
}
