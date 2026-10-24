import Foundation
import XCTest
@testable import TypingPet

final class LocalizationTests: XCTestCase {
    func testSystemUsesFirstLanguageAndFallsBackToEnglish() {
        for language in ["ko", "ko-KR", "ko_KR"] {
            XCTAssertEqual(AppLanguageMode.system.resolvedLanguage(preferredLanguages: [language]), "ko")
        }
        for languages in [["en-US", "ko-KR"], ["ja-JP", "ko"], ["fr"], [], ["kok-IN"]] {
            XCTAssertEqual(AppLanguageMode.system.resolvedLanguage(preferredLanguages: languages), "en")
        }
        XCTAssertEqual(AppLanguageMode.korean.resolvedLanguage(preferredLanguages: ["ja"]), "ko")
        XCTAssertEqual(AppLanguageMode.english.resolvedLanguage(preferredLanguages: ["ko"]), "en")
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
        defaults.set("unknown", forKey: AppLanguageMode.defaultsKey)
        XCTAssertEqual(AppLanguageMode.load(from: defaults), .system)
    }

    func testBothResourcesHaveIdenticalKeysAndPlaceholders() throws {
        func strings(_ language: String) throws -> [String: String] {
            let bundle = try XCTUnwrap(AppLocalization.bundle(for: language))
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
            return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        }
        let korean = try strings("ko"), english = try strings("en")
        XCTAssertGreaterThan(english.count, 300)
        XCTAssertEqual(Set(korean.keys), Set(english.keys))
        let regex = try NSRegularExpression(pattern: #"%[1-9][0-9]*\$@|%0?\d*d"#)
        func placeholders(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for key in english.keys {
            XCTAssertEqual(placeholders(korean[key]!), placeholders(english[key]!), key)
        }
        XCTAssertEqual(AppLocalization.string("General", language: "ko"), "일반")
        XCTAssertEqual(AppLocalization.string("General", language: "en"), "General")
        XCTAssertEqual(AppLocalization.string("General", language: "ja"), "General")
        XCTAssertEqual(AppLocalization.string("object.particle.vowel", language: "en"), "")
    }

    func testArgumentsReorderAndUserTextStaysVerbatim() {
        XCTAssertEqual(AppLocalization.string("%2$@ of %1$@ characters", language: "en", arguments: ["100", "3"]), "3 of 100 characters")
        let title = "내 할 일 %@ %2$@ 🐈"
        XCTAssertEqual(AppLocalization.string("Complete %1$@", language: "en", arguments: [title]), "Complete " + title)
        XCTAssertEqual(AppLocalization.string("%1$@\nClick to edit title", language: "en", arguments: [title]), title + "\nClick to edit title")
    }
}
