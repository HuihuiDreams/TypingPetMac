import Foundation
import Darwin

// Unbundled `swift run` and unknown bundles always use the isolated development profile.
enum AppProfile: String {
    case development, production

    static func resolve(channel: String?, bundleIdentifier: String?) -> AppProfile {
        channel == "production" && bundleIdentifier == "ing.miel.typingpet" ? .production : .development
    }
    var bundleIdentifier: String { self == .development ? "ing.miel.typingpet.dev" : "ing.miel.typingpet" }
    var preferencesDomain: String { self == .development ? "ing.miel.typingpet.dev.preferences" : "ing.miel.typingpet" }
    var displayName: String { self == .development ? "TypingPet Dev" : "Typing Pet" }
    var supportFolder: String { self == .development ? "TypingPetDev" : "TypingPet" }
    var frameAutosaveName: String { self == .development ? "TypingPetDevWindow" : "TypingPetWindow" }
    func supportDirectory(in base: URL) -> URL { base.appendingPathComponent(supportFolder, isDirectory: true) }
}

enum AppEnvironment {
    static let profile = AppProfile.resolve(
        channel: Bundle.main.object(forInfoDictionaryKey: "TypingPetBuildChannel") as? String,
        bundleIdentifier: Bundle.main.bundleIdentifier
    )
    static var isDevelopment: Bool { profile == .development }
    static var displayName: String { profile.displayName }
    static var frameAutosaveName: String { profile.frameAutosaveName }
    static let defaults: UserDefaults = {
        guard isDevelopment else { return .standard }
        // macOS rejects a suite name equal to the current bundle identifier.
        guard let store = UserDefaults(suiteName: profile.preferencesDomain) else {
            fatalError("Cannot open isolated development preferences. Production preferences were not loaded.")
        }
        return store
    }()
    static var supportDirectory: URL {
        profile.supportDirectory(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
}

// Acquire before any store loads. A second development runtime must not write the same records.
final class DevelopmentRunLock {
    private var descriptor: Int32 = -1

    func acquire(at file: URL) throws -> Bool {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let candidate = file.path.withCString { Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR) }
        guard candidate >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if flock(candidate, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            Darwin.close(candidate)
            if code == EWOULDBLOCK { return false }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        descriptor = candidate
        return true
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
    }
}
