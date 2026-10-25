import Foundation
import Testing
@testable import TypingPet

@Suite struct AppEnvironmentTests {
    @Test func rawRuntimeAndUnknownBundlesDefaultToDevelopment() {
        #expect(AppProfile.resolve(channel: nil, bundleIdentifier: nil) == .development)
        #expect(AppProfile.resolve(channel: "production", bundleIdentifier: "unknown") == .development)
        #expect(AppProfile.resolve(channel: "production", bundleIdentifier: "ing.miel.typingpet") == .production)
    }

    @Test func allDevelopmentNamespacesDifferFromProduction() {
        let dev = AppProfile.development
        let prod = AppProfile.production
        let base = URL(fileURLWithPath: "/tmp/profile-tests")
        #expect(dev.bundleIdentifier != prod.bundleIdentifier)
        #expect(dev.preferencesDomain != prod.preferencesDomain)
        #expect(dev.preferencesDomain != dev.bundleIdentifier)
        #expect(dev.supportDirectory(in: base) != prod.supportDirectory(in: base))
        #expect(dev.frameAutosaveName != prod.frameAutosaveName)
        #expect(dev.displayName == "TypingPet Dev")
    }

    @Test func duplicateDevelopmentRuntimeIsBlockedAndExitReleasesLock() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".runtime.lock")
        var first: DevelopmentRunLock? = DevelopmentRunLock()
        let firstAcquired = try first?.acquire(at: file) == true
        #expect(firstAcquired)
        let second = DevelopmentRunLock()
        let secondBlocked = try second.acquire(at: file)
        #expect(!secondBlocked)
        first = nil
        let secondAcquired = try second.acquire(at: file)
        #expect(secondAcquired)
    }
}
