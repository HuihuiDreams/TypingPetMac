import Foundation
import XCTest
@testable import TypingPet

final class LocalizationTests: XCTestCase {
    func testSystemUsesFirstLanguageAndFallsBackToEnglish() {
        for language in ["ko", "ko-KR", "ko_KR"] {
            XCTAssertEqual(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language]), "ko")
        }
        for languages in [["en-US", "ko-KR"], ["fr"], [], ["kok-IN"], ["jaq"]] {
            XCTAssertEqual(AppLanguageMode.system.resolvedLanguage(preferredLanguages: languages), "en")
        }
        for language in ["ja", "ja-JP", "ja_JP"] {
            XCTAssertEqual(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language, "ko"]), "ja")
        }
        for language in ["zh", "zh-CN", "zh-SG", "zh-Hans", "zh_Hans_CN", "zh-Hans-HK"] {
            XCTAssertEqual(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language]), "zh-Hans")
        }
        for language in ["zh-TW", "zh-HK", "zh-MO", "zh-Hant", "zh_Hant_TW", "zh-Hant-CN"] {
            XCTAssertEqual(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language]), "zh-Hant")
        }
        XCTAssertEqual(AppLanguageMode.korean.resolvedLanguage(preferredLanguages: ["ja"]), "ko")
        XCTAssertEqual(AppLanguageMode.english.resolvedLanguage(preferredLanguages: ["ko"]), "en")
        XCTAssertEqual(AppLanguageMode.japanese.resolvedLanguage(preferredLanguages: ["en"]), "ja")
        XCTAssertEqual(AppLanguageMode.simplifiedChinese.resolvedLanguage(preferredLanguages: ["zh-TW"]), "zh-Hans")
        XCTAssertEqual(AppLanguageMode.traditionalChinese.resolvedLanguage(preferredLanguages: ["zh-CN"]), "zh-Hant")
    }

    func testPreferencePersistsAndInvalidPreferenceUsesSystem() throws {
        let suite = "TypingPetLocalizationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppLanguageMode.load(from: defaults), .system)
        let localization = AppLocalization(defaults: defaults)
        localization.setMode(.english)
        XCTAssertEqual(localization.language, "en")
        XCTAssertEqual(AppLocalization(defaults: defaults).mode, .english)
        localization.setMode(.korean)
        XCTAssertEqual(localization.language, "ko")
        for mode in [AppLanguageMode.japanese, .simplifiedChinese, .traditionalChinese] {
            localization.setMode(mode)
            XCTAssertEqual(AppLocalization(defaults: defaults).mode, mode)
            XCTAssertEqual(localization.language, mode.resolvedLanguage())
            XCTAssertEqual(localization.locale.language.languageCode?.identifier, mode == .japanese ? "ja" : "zh")
        }
        defaults.set("unknown", forKey: AppLanguageMode.defaultsKey)
        XCTAssertEqual(AppLanguageMode.load(from: defaults), .system)
    }

    func testAllResourcesHaveIdenticalKeysAndPlaceholders() throws {
        func strings(_ language: String) throws -> [String: String] {
            let bundle = try XCTUnwrap(AppLocalization.bundle(for: language))
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
            return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        }
        let english = try strings("en")
        XCTAssertGreaterThan(english.count, 300)
        let regex = try NSRegularExpression(pattern: #"%[1-9][0-9]*\$@|%0?\d*d"#)
        func placeholders(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for language in AppLanguageMode.supportedLanguages {
            let translated = try strings(language)
            XCTAssertEqual(Set(translated.keys), Set(english.keys), language)
            for key in english.keys {
                let value = try XCTUnwrap(translated[key], "\(language): \(key)")
                XCTAssertEqual(placeholders(value), placeholders(english[key]!), "\(language): \(key)")
                if !key.hasPrefix("object.particle.") { XCTAssertFalse(value.isEmpty, "\(language): \(key)") }
            }
        }
        XCTAssertEqual(AppLocalization.string("General", language: "ko"), "일반")
        XCTAssertEqual(AppLocalization.string("General", language: "en"), "General")
        XCTAssertEqual(AppLocalization.string("General", language: "ja"), "一般")
        XCTAssertEqual(AppLocalization.string("General", language: "zh-Hans"), "通用")
        XCTAssertEqual(AppLocalization.string("General", language: "zh-Hant"), "一般")
        XCTAssertEqual(AppLocalization.string("General", language: "fr"), "General")
        XCTAssertEqual(AppLocalization.string("object.particle.vowel", language: "en"), "")
    }

    func testArgumentsReorderAndUserTextStaysVerbatim() {
        XCTAssertEqual(AppLocalization.string("%2$@ of %1$@ characters", language: "en", arguments: ["100", "3"]), "3 of 100 characters")
        let title = "我的待办 %@ %2$@ 🐈"
        XCTAssertEqual(AppLocalization.string("Complete %1$@", language: "en", arguments: [title]), "Complete " + title)
        XCTAssertEqual(AppLocalization.string("%1$@\nClick to edit title", language: "en", arguments: [title]), title + "\nClick to edit title")
        XCTAssertEqual(AppLocalization.string("Complete %1$@", language: "ja", arguments: [title]), title + "を完了にする")
        XCTAssertEqual(AppLocalization.string("Complete %1$@", language: "zh-Hant", arguments: [title]), "完成 " + title)
    }
}
