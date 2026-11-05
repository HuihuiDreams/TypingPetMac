import AppKit
import CryptoKit
import XCTest
@testable import TypingPet

final class ShareExchangeTests: XCTestCase {
    @MainActor private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackExchange-\(UUID())")
        let defaults: UserDefaults
        let suite = "PackExchange-\(UUID())"
        let store: PetPackStore
        let templates: ShareTemplateStore
        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let library = PetImageLibrary(defaults: defaults, imagesDirectory: directory.appendingPathComponent("Images"))
            store = PetPackStore(library: library, keyStore: KeyReactionStore(defaults: defaults, directory: directory.appendingPathComponent("Keys")))
            templates = ShareTemplateStore(directory: directory.appendingPathComponent("Templates"))
        }
        func clean() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        func snapshot(message: String) throws -> Data {
            try LocalShareAPI.package(configuration: store.activeConfiguration, set: store.library.activeSet, store: store, message: message)
        }
        func preview(_ data: Data, version: Int) throws -> LocalSharePreview {
            let (root, manifest) = try LocalShareAPI.extract(data)
            defer { try? FileManager.default.removeItem(at: root) }
            return LocalSharePreview(code: "AB12CD", status: "active", latestVersion: version, manifest: manifest,
                packageSize: data.count, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), publishedAt: 1)
        }
    }

    @MainActor func testTemplateUpdateNeverChangesEditedLocalCopyOrActivePet() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let active = fixture.store.library.activeSetID
        let v1 = try fixture.snapshot(message: "hello")
        let preview1 = try fixture.preview(v1, version: 1)
        let originalCount = fixture.store.library.imageSets.count
        try fixture.templates.install(v1, preview: preview1)
        XCTAssertEqual(fixture.store.library.imageSets.count, originalCount, "Receiving is not a local pack import")
        var template = try XCTUnwrap(fixture.templates.templates.first)
        let copy = try fixture.templates.copy(template, into: fixture.store)
        var edited = fixture.store.configuration(for: copy)
        edited.name = "My edited copy"
        edited.presets[0].name = "My expression"
        try fixture.store.save(edited, for: copy)
        let imageURL = try XCTUnwrap(fixture.store.imageURL(for: edited.presets[0], in: copy))
        let imageBytes = try Data(contentsOf: imageURL)
        let v2 = try fixture.snapshot(message: "updated")
        try fixture.templates.install(v2, preview: fixture.preview(v2, version: 2))
        XCTAssertEqual(fixture.templates.templates.count, 1)
        template = try XCTUnwrap(fixture.templates.templates.first)
        XCTAssertEqual(template.preview.latestVersion, 2)
        XCTAssertEqual(template.preview.manifest.creatorMessage, "updated")
        XCTAssertEqual(fixture.store.configuration(for: copy), edited)
        XCTAssertEqual(try Data(contentsOf: imageURL), imageBytes)
        XCTAssertEqual(fixture.store.library.activeSetID, active)
        let fresh = try fixture.templates.copy(template, into: fixture.store)
        XCTAssertNotEqual(fresh.id, copy.id)
        XCTAssertNotEqual(fixture.store.configuration(for: fresh).name, edited.name)
        let restored = ShareTemplateStore(directory: fixture.templates.directory)
        XCTAssertNil(restored.loadError)
        XCTAssertEqual(restored.templates.first?.preview.latestVersion, 2)
        try restored.remove(try XCTUnwrap(restored.templates.first))
        XCTAssertEqual(fixture.store.configuration(for: copy), edited)
    }

    @MainActor func testFailedTemplateReplacementAndBrokenIndexPreserveData() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let bytes = try fixture.snapshot(message: "original")
        let preview = try fixture.preview(bytes, version: 1)
        try fixture.templates.install(bytes, preview: preview)
        XCTAssertThrowsError(try fixture.templates.install(Data("broken".utf8), preview: preview))
        XCTAssertEqual(fixture.templates.templates.first?.preview.latestVersion, 1)
        let index = fixture.templates.directory.appendingPathComponent("index.json")
        let broken = Data("do not overwrite".utf8)
        try broken.write(to: index)
        let restored = ShareTemplateStore(directory: fixture.templates.directory)
        XCTAssertNotNil(restored.loadError)
        XCTAssertThrowsError(try restored.install(bytes, preview: preview))
        XCTAssertEqual(try Data(contentsOf: index), broken)
    }

    @MainActor func testArchiveRejectsSymlinkTraversalAndDeclaredExpansionBeforeExtracting() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let valid = try fixture.snapshot(message: "test")
        XCTAssertNoThrow(try ShareArchiveValidator.validate(valid))
        func centralOffset(_ data: Data) throws -> Int {
            let signature = Data([0x50, 0x4b, 0x01, 0x02])
            return try XCTUnwrap(data.range(of: signature)?.lowerBound)
        }
        var symlink = valid
        let central = try centralOffset(valid)
        // Unix external attributes high word: S_IFLNK.
        symlink[central + 40] = 0xff; symlink[central + 41] = 0xa1
        XCTAssertThrowsError(try ShareArchiveValidator.validate(symlink))
        var bomb = valid
        for i in 24..<28 { bomb[central + i] = 0xff }
        XCTAssertThrowsError(try ShareArchiveValidator.validate(bomb))
        var traversal = valid
        if let range = traversal.range(of: Data("images/".utf8)) {
            traversal.replaceSubrange(range, with: Data("../bad/".utf8))
        }
        XCTAssertThrowsError(try ShareArchiveValidator.validate(traversal))
        XCTAssertThrowsError(try LocalShareAPI.unpack(symlink, into: fixture.store))
    }

    @MainActor func testRealHTTPExchangeLifecycle() async throws {
        guard ProcessInfo.processInfo.environment["TYPINGPET_TEST_SHARE_HTTP"] == "1" else {
            throw XCTSkip("Set TYPINGPET_TEST_SHARE_HTTP=1 with an isolated share API")
        }
        let fixture = try Fixture(); defer { fixture.clean() }
        let source = fixture.store.library.activeSet
        let created = try await LocalShareAPI.create(archive: fixture.snapshot(message: "hello from creator"), set: source,
            requestID: UUID().uuidString, secret: UUID().uuidString + UUID().uuidString, password: "한글네자")
        let password = try XCTUnwrap(created.managementPassword)
        try await LocalShareAPI.authorize(code: created.code, password: password)
        do {
            try await LocalShareAPI.authorize(code: created.code, password: "incorrect")
            XCTFail("Wrong passwords must not unlock management")
        } catch LocalShareError.server("invalid_password") {}
        let preview1 = try await LocalShareAPI.preview(code: created.code)
        try await fixture.templates.receive(preview1)
        let local = try fixture.templates.copy(try XCTUnwrap(fixture.templates.templates.first), into: fixture.store)
        let before = fixture.store.configuration(for: local)
        let version = try await LocalShareAPI.update(code: created.code, configuration: fixture.store.configuration(for: source),
            set: source, store: fixture.store, password: password, message: "v2", baseVersion: 1)
        XCTAssertEqual(version, 2)
        let history = try await LocalShareAPI.versions(code: created.code)
        XCTAssertEqual(history.map(\.version), [2, 1])
        let historical = try await LocalShareAPI.version(code: created.code, revision: 1)
        XCTAssertEqual(historical.manifest.creatorMessage, "hello from creator")
        let oldCopy = try await fixture.templates.copyVersion(code: created.code, revision: 1, into: fixture.store)
        XCTAssertTrue(fixture.store.configuration(for: oldCopy).name.contains("v1"))
        XCTAssertEqual(fixture.templates.templates.first?.preview.latestVersion, 1)
        try await fixture.templates.check(try XCTUnwrap(fixture.templates.templates.first))
        XCTAssertEqual(fixture.templates.templates.first?.latestVersion, 2)
        try await fixture.templates.update(try XCTUnwrap(fixture.templates.templates.first))
        XCTAssertEqual(fixture.templates.templates.first?.preview.manifest.creatorMessage, "v2")
        try await LocalShareAPI.stop(code: created.code, password: password)
        do {
            try await fixture.templates.check(try XCTUnwrap(fixture.templates.templates.first))
            XCTFail("Deleted shares must be unavailable")
        } catch {}
        XCTAssertEqual(fixture.store.configuration(for: local), before)
        XCTAssertNoThrow(try fixture.templates.copy(try XCTUnwrap(fixture.templates.templates.first), into: fixture.store))
    }
}
