import Foundation
import Combine

enum AppLanguageMode: String, CaseIterable {
    case system, korean, english, japanese, simplifiedChinese, traditionalChinese

    static let defaultsKey = "AppLanguageMode"
    static let supportedLanguages = ["ko", "en", "ja", "zh-Hans", "zh-Hant"]

    static func load(from defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .system
    }

    func resolvedLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .korean: return "ko"
        case .english: return "en"
        case .japanese: return "ja"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .system:
            let first = preferredLanguages.first?.lowercased().replacingOccurrences(of: "_", with: "-") ?? "en"
            let parts = first.split(separator: "-").map(String.init)
            switch parts.first {
            case "ko": return "ko"
            case "ja": return "ja"
            case "zh":
                if parts.contains("hant") { return "zh-Hant" }
                if parts.contains("hans") { return "zh-Hans" }
                return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
            default: return "en"
            }
        }
    }
}

final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    @Published private(set) var mode: AppLanguageMode
    @Published private(set) var language: String
    private let defaults: UserDefaults
    private var localeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = AppEnvironment.defaults) {
        self.defaults = defaults
        let savedMode = AppLanguageMode.load(from: defaults)
        mode = savedMode
        language = savedMode.resolvedLanguage()
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshSystemLanguage() }
    }

    deinit {
        if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
    }

    var locale: Locale {
        let identifiers = ["ko": "ko_KR", "en": "en_US", "ja": "ja_JP", "zh-Hans": "zh_Hans_CN", "zh-Hant": "zh_Hant_TW"]
        return Locale(identifier: identifiers[language] ?? "en_US")
    }

    func setMode(_ value: AppLanguageMode) {
        defaults.set(value.rawValue, forKey: AppLanguageMode.defaultsKey)
        mode = value
        language = value.resolvedLanguage()
    }

    private func refreshSystemLanguage() {
        language = mode.resolvedLanguage()
    }

    private static let bundles: [String: Bundle] = AppLanguageMode.supportedLanguages.reduce(into: [:]) { result, language in
        // The shipped app copies lproj folders directly. SwiftPM keeps them in Localization.
        let root = Bundle.main.resourceURL
        let packaged = root?.appendingPathComponent("\(language).lproj")
        if let packaged, let bundle = Bundle(url: packaged) {
            result[language] = bundle
        } else {
            #if !TYPINGPET_DISTRIBUTION
            result[language] = Bundle(url: Bundle.module.resourceURL!
                .appendingPathComponent("Localization/\(language).lproj"))
            #endif
        }
    }

    static func bundle(for language: String) -> Bundle? {
        bundles[AppLanguageMode.supportedLanguages.contains(language) ? language : "en"]
    }

    static func string(_ key: String, language: String, arguments: [String] = []) -> String {
        let template = bundle(for: language)?.localizedString(forKey: key, value: nil, table: nil) ?? key
        guard !arguments.isEmpty else { return template }
        // Replace positional tokens in the template only. User text is never treated as a format.
        let source = template as NSString
        var result = template
        for match in placeholders.matches(in: template, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let index = Int(source.substring(with: match.range(at: 1))), arguments.indices.contains(index - 1),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index - 1])
        }
        return result
    }

    private static let placeholders = try! NSRegularExpression(pattern: #"%([1-9][0-9]*)\$@"#)
}

func L(_ key: String, _ arguments: Any...) -> String {
    AppLocalization.string(key, language: AppLocalization.shared.language, arguments: arguments.map { String(describing: $0) })
}
