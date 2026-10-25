import Foundation
import Testing
@testable import TypingPet

@Suite struct LocalizationTests {
    @Test func systemUsesFirstLanguageAndFallsBackToChinese() {
        for language in ["ko", "ko-KR", "ko_KR"] {
            #expect(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language]) == "ko")
        }
        #expect(AppLanguageMode.system.resolvedLanguage(preferredLanguages: ["en-US", "ko-KR"]) == "en")
        for languages in [["fr"], [], ["kok-IN"], ["jaq"]] {
            #expect(AppLanguageMode.system.resolvedLanguage(preferredLanguages: languages) == "zh-Hans")
        }
        for language in ["ja", "ja-JP", "ja_JP"] {
            #expect(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language, "ko"]) == "ja")
        }
        for language in ["zh", "zh-CN", "zh-SG", "zh-Hans", "zh_Hans_CN", "zh-Hans-HK"] {
            #expect(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language]) == "zh-Hans")
        }
        for language in ["zh-TW", "zh-HK", "zh-MO", "zh-Hant", "zh_Hant_TW", "zh-Hant-CN"] {
            #expect(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language]) == "zh-Hant")
        }
        #expect(AppLanguageMode.korean.resolvedLanguage(preferredLanguages: ["ja"]) == "ko")
        #expect(AppLanguageMode.english.resolvedLanguage(preferredLanguages: ["ko"]) == "en")
        #expect(AppLanguageMode.japanese.resolvedLanguage(preferredLanguages: ["en"]) == "ja")
        #expect(AppLanguageMode.simplifiedChinese.resolvedLanguage(preferredLanguages: ["zh-TW"]) == "zh-Hans")
        #expect(AppLanguageMode.traditionalChinese.resolvedLanguage(preferredLanguages: ["zh-CN"]) == "zh-Hant")
    }

    @Test func preferencePersistsAndInvalidPreferenceUsesDefault() throws {
        let suite = "TypingPetLocalizationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppLanguageMode.load(from: defaults) == .simplifiedChinese)
        let localization = AppLocalization(defaults: defaults)
        localization.setMode(.english)
        #expect(localization.language == "en")
        #expect(AppLocalization(defaults: defaults).mode == .english)
        localization.setMode(.korean)
        #expect(localization.language == "ko")
        for mode in [AppLanguageMode.japanese, .simplifiedChinese, .traditionalChinese] {
            localization.setMode(mode)
            #expect(AppLocalization(defaults: defaults).mode == mode)
            #expect(localization.language == mode.resolvedLanguage())
            #expect(localization.locale.language.languageCode?.identifier == (mode == .japanese ? "ja" : "zh"))
        }
        defaults.set("unknown", forKey: AppLanguageMode.defaultsKey)
        #expect(AppLanguageMode.load(from: defaults) == .simplifiedChinese)
    }

    @Test func allResourcesHaveIdenticalKeysAndPlaceholders() throws {
        func strings(_ language: String) throws -> [String: String] {
            let bundle = try #require(AppLocalization.bundle(for: language))
            let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
            return try #require(NSDictionary(contentsOf: url) as? [String: String])
        }
        let english = try strings("en")
        #expect(english.count > 300)
        let regex = try NSRegularExpression(pattern: #"%[1-9][0-9]*\$@|%0?\d*d"#)
        func placeholders(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for language in AppLanguageMode.supportedLanguages {
            let translated = try strings(language)
            #expect(Set(translated.keys) == Set(english.keys))
            for key in english.keys {
                let value = try #require(translated[key])
                #expect(placeholders(value) == placeholders(english[key]!))
                if !key.hasPrefix("object.particle.") { #expect(!value.isEmpty) }
            }
        }
        #expect(AppLocalization.string("General", language: "ko") == "일반")
        #expect(AppLocalization.string("General", language: "en") == "General")
        #expect(AppLocalization.string("General", language: "ja") == "一般")
        #expect(AppLocalization.string("General", language: "zh-Hans") == "通用")
        #expect(AppLocalization.string("General", language: "zh-Hant") == "一般")
        #expect(AppLocalization.string("General", language: "fr") == "通用")
        #expect(AppLocalization.string("object.particle.vowel", language: "en") == "")
    }

    @Test func argumentsReorderAndUserTextStaysVerbatim() {
        #expect(AppLocalization.string("%2$@ of %1$@ characters", language: "en", arguments: ["100", "3"]) == "3 of 100 characters")
        let title = "我的待办 %@ %2$@ 🐈"
        #expect(AppLocalization.string("Complete %1$@", language: "en", arguments: [title]) == "Complete " + title)
        #expect(AppLocalization.string("%1$@\nClick to edit title", language: "en", arguments: [title]) == title + "\nClick to edit title")
        #expect(AppLocalization.string("Complete %1$@", language: "ja", arguments: [title]) == title + "を完了にする")
        #expect(AppLocalization.string("Complete %1$@", language: "zh-Hant", arguments: [title]) == "完成 " + title)
    }
}
