import AppKit
import Foundation
import Testing
@testable import TypingPet

@Suite(.serialized)
struct PetPackArchiveTests {
    @MainActor
    private struct Fixture {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let library: PetImageLibrary
        let keys: KeyReactionStore
        var sampleImage: URL {
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/TypingPet/Resources/basic.png")
        }

        init() throws {
            suite = "PetPackArchiveTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suite))
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            library = PetImageLibrary(defaults: defaults, imagesDirectory: root.appendingPathComponent("Images"))
            keys = KeyReactionStore(defaults: defaults, directory: root.appendingPathComponent("Keys"))
        }

        func store() -> PetPackStore {
            PetPackStore(library: library, keyStore: keys)
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test @MainActor
    func exportAndImportRoundTripRestoresPackConfigurationAndImages() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = f.store()
        let customSet = try f.library.addSet(from: [f.sampleImage], name: "Exportable Cat")
        var config = store.configuration(for: customSet)
        config.name = "My Exported Pack"
        try store.save(config, for: customSet)

        let exportURL = f.root.appendingPathComponent("Exported.petpack")
        try PetPackArchive.exportPack(
            set: customSet,
            config: config,
            library: f.library,
            store: store,
            destinationURL: exportURL
        )

        #expect(FileManager.default.fileExists(atPath: exportURL.path))

        // Pre-inspection verification
        let inspection = try PetPackArchive.inspectAndValidate(url: exportURL)
        #expect(inspection.fileCount >= 2) // pack.json + image
        #expect(inspection.totalUncompressedBytes > 0)
        #expect(inspection.fileNames.contains(where: { $0.hasSuffix("pack.json") }))

        // Import into library
        let importedSet = try PetPackArchive.importPack(from: exportURL, library: f.library, store: store)
        #expect(importedSet.name == "My Exported Pack")
        let importedConfig = store.configuration(for: importedSet)
        #expect(importedConfig.name == "My Exported Pack")
        #expect(!importedConfig.presets.isEmpty)
    }

    @Test
    func invalidMagicHeaderIsRejected() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake-\(UUID().uuidString).petpack")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let fakeData = "NOT_A_ZIP_FILE_AT_ALL_JUST_RANDOM_DATA".data(using: .utf8)!
        try fakeData.write(to: tempFile)

        #expect(throws: PetPackArchiveError.self) {
            _ = try PetPackArchive.inspectAndValidate(url: tempFile)
        }
    }

    @Test
    func fileExceedingMaximumArchiveSizeIsRejected() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("huge-\(UUID().uuidString).petpack")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Create sparse file larger than 25MB (26MB)
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempFile)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(26 * 1024 * 1024))

        #expect(throws: PetPackArchiveError.self) {
            _ = try PetPackArchive.inspectAndValidate(url: tempFile)
        }
    }

    @Test
    func disallowedFileExtensionIsRejected() throws {
        let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent("evil-\(UUID().uuidString).petpack")
        defer { try? FileManager.default.removeItem(at: tempZip) }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("evil-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let script = staging.appendingPathComponent("malicious.sh")
        try "#!/bin/sh\necho 1".data(using: .utf8)?.write(to: script)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--norsrc", staging.path, tempZip.path]
        try p.run()
        p.waitUntilExit()

        #expect(throws: PetPackArchiveError.self) {
            _ = try PetPackArchive.inspectAndValidate(url: tempZip)
        }
    }
}
