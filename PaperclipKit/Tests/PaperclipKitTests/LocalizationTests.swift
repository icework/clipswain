import XCTest
@testable import PaperclipKit

final class LocalizationTests: XCTestCase {
    private let english = Locale(identifier: "en-US")
    private let chinese = Locale(identifier: "zh-Hans-CN")

    private func strings(_ locale: Locale) throws -> [String: String] {
        let url = try XCTUnwrap(KitL10n.bundle(for: locale).url(forResource: "Localizable", withExtension: "strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    func testEveryTranslationHasMatchingKeysAndFormatArguments() throws {
        let en = try strings(english), zh = try strings(chinese)
        XCTAssertFalse(en.isEmpty)
        XCTAssertEqual(Set(en.keys), Set(zh.keys))
        let placeholder = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|@|d|f)"#)
        func arguments(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }
        }
        for (key, value) in en {
            let translation = try XCTUnwrap(zh[key])
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertEqual(arguments(value), arguments(translation), key)
        }
    }

    func testNativeLanguageNegotiationAndEnglishFallback() {
        XCTAssertEqual(KitL10n.string("interaction.kind.questions", defaultValue: "Questions", locale: chinese), "提问")
        XCTAssertEqual(KitL10n.string("interaction.kind.questions", defaultValue: "Questions", locale: english), "Questions")
        XCTAssertEqual(KitL10n.string("interaction.kind.questions", defaultValue: "Questions", locale: Locale(identifier: "fr-FR")), "Questions")
        XCTAssertEqual(KitL10n.string("missing.translation.for.test", defaultValue: "Readable fallback", locale: chinese), "Readable fallback")
    }

    func testAppLanguageControlsUnitsWhileRegionAndExplicitPreferencesArePreserved() {
        let englishInChina = KitL10n.formattingLocale(
            language: "en", regionalLocale: Locale(identifier: "zh_CN@calendar=buddhist;hours=h23"))
        XCTAssertEqual(englishInChina.language.languageCode?.identifier, "en")
        XCTAssertEqual(englishInChina.region?.identifier, "CN")
        XCTAssertEqual(englishInChina.calendar.identifier, .buddhist)
        XCTAssertEqual(englishInChina.hourCycle, .zeroToTwentyThree)
        XCTAssertEqual(TaskTiming.text(193, locale: englishInChina), "3m 13s")
        XCTAssertEqual(KitL10n.string("timing.incomplete", defaultValue: "Timing unavailable", locale: englishInChina), "Timing unavailable")

        let chineseInUS = KitL10n.formattingLocale(language: "zh-Hans", regionalLocale: english)
        XCTAssertEqual(chineseInUS.language.script?.identifier, "Hans")
        XCTAssertEqual(chineseInUS.region?.identifier, "US")
        XCTAssertEqual(TaskTiming.text(193, locale: chineseInUS), "3分钟13秒")
        // An explicit locale still wins over the app-language default in both directions.
        XCTAssertEqual(TaskTiming.text(193, locale: english), "3m 13s")
        XCTAssertEqual(TaskTiming.text(193, locale: chinese), "3分钟13秒")
        XCTAssertEqual(TaskTiming.text(193), TaskTiming.text(193, locale: KitL10n.formattingLocale))
    }

    func testAPIErrorInterpolatesStatusAndPreservesServerContent() {
        let message = "capacity 100%: 原始服务端消息 %@"
        let error = PaperclipAPIError(status: 503, message: message)
        XCTAssertEqual(error.localizedDescription(locale: english), "Server error (503): \(message)")
        XCTAssertEqual(error.localizedDescription(locale: chinese), "服务器错误（503）：\(message)")
        let forbidden = PaperclipAPIError(status: 403, message: message)
        XCTAssertEqual(forbidden.localizedDescription(locale: english), "Permission denied (403): \(message)")
        XCTAssertEqual(forbidden.localizedDescription(locale: chinese), "没有权限（403）：\(message)")
    }

    func testModelErrorsAreLocalizedWithoutTranslatingProviderMessages() {
        let error = TaskDraftError.http(status: 401, message: "invalid_api_key")
        XCTAssertEqual(error.localizedDescription(locale: english), "Invalid API key or permission denied (401): invalid_api_key")
        XCTAssertEqual(error.localizedDescription(locale: chinese), "API Key 无效或没有权限（401）：invalid_api_key")
        XCTAssertEqual(TaskDraftError.notConfigured.localizedDescription(locale: english), "No AI model is configured. Add an API provider in Settings.")
        XCTAssertEqual(TaskDraftError.notConfigured.localizedDescription(locale: chinese), "还没有配置 AI 模型，请先在设置中填写 API Provider。")
    }

    func testDurationUsesNativeUnitsInEachLanguageAndHandlesBoundaryValues() {
        XCTAssertEqual(TaskTiming.text(nil, locale: english), "Timing unavailable")
        XCTAssertEqual(TaskTiming.text(.nan, locale: english), "Timing unavailable")
        XCTAssertEqual(TaskTiming.text(Double(Int.max), locale: chinese), "时间记录不完整")
        XCTAssertEqual(TaskTiming.text(0.1, locale: english), "Less than 1 second")
        XCTAssertEqual(TaskTiming.text(193, locale: english), "3m 13s")
        XCTAssertEqual(TaskTiming.text(90000, locale: english), "1d 1h")
        XCTAssertEqual(TaskTiming.text(90000, locale: chinese), "1天1小时")
        XCTAssertEqual(TaskTiming.text(172800, locale: english), "2d")
        XCTAssertEqual(TaskTiming.text(172800, locale: chinese), "2天")
        // Keep source compatibility with Optional.map; localization does not change missing data.
        let seconds: TimeInterval? = 193
        XCTAssertNotNil(seconds.map(TaskTiming.text))
    }
}
