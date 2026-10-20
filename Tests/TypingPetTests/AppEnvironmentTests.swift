import Foundation
import XCTest
@testable import TypingPet

final class AppEnvironmentTests: XCTestCase {
    func testRawRuntimeAndUnknownBundlesDefaultToDevelopment() {
        XCTAssertEqual(AppProfile.resolve(channel: nil, bundleIdentifier: nil), .development)
        XCTAssertEqual(AppProfile.resolve(channel: "production", bundleIdentifier: "unknown"), .development)
        XCTAssertEqual(AppProfile.resolve(channel: "production", bundleIdentifier: "ing.miel.typingpet"), .production)
    }

    func testAllDevelopmentNamespacesDifferFromProduction() {
        let dev = AppProfile.development
        let prod = AppProfile.production
        let base = URL(fileURLWithPath: "/tmp/profile-tests")
        XCTAssertNotEqual(dev.bundleIdentifier, prod.bundleIdentifier)
        XCTAssertNotEqual(dev.preferencesDomain, prod.preferencesDomain)
        XCTAssertNotEqual(dev.preferencesDomain, dev.bundleIdentifier)
        XCTAssertNotEqual(dev.supportDirectory(in: base), prod.supportDirectory(in: base))
        XCTAssertNotEqual(dev.frameAutosaveName, prod.frameAutosaveName)
        XCTAssertEqual(dev.displayName, "TypingPet Dev")
    }

    func testDuplicateDevelopmentRuntimeIsBlockedAndExitReleasesLock() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".runtime.lock")
        var first: DevelopmentRunLock? = DevelopmentRunLock()
        XCTAssertTrue(try first!.acquire(at: file))
        let second = DevelopmentRunLock()
        XCTAssertFalse(try second.acquire(at: file))
        first = nil
        XCTAssertTrue(try second.acquire(at: file))
    }
}
