import AppKit
import Foundation

/// Errors that can occur during .petpack archive export or import.
enum PetPackArchiveError: LocalizedError {
    case fileTooLarge(Int64)
    case invalidMagicHeader
    case corruptArchive
    case tooManyFiles(Int)
    case uncompressedSizeExceeded(Int64)
    case singleFileSizeExceeded(String, Int64)
    case suspiciousCompressionRatio(Double)
    case pathTraversalDetected(String)
    case disallowedFileExtension(String)
    case symbolicLinksNotAllowed(String)
    case missingManifest
    case unsupportedSchemaVersion(Int)
    case extractionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            return L("The package is too large (%1$@ MB). Maximum allowed size is 25 MB.", String(format: "%.1f", Double(size) / (1024 * 1024)))
        case .invalidMagicHeader:
            return L("The file is not a valid .petpack archive.")
        case .corruptArchive:
            return L("The package archive structure is damaged or unreadable.")
        case .tooManyFiles(let count):
            return L("The package contains too many files (%1$@). Maximum allowed is 200.", count)
        case .uncompressedSizeExceeded(let size):
            return L("The extracted package size exceeds the 50 MB limit (%1$@ MB).", String(format: "%.1f", Double(size) / (1024 * 1024)))
        case .singleFileSizeExceeded(let name, let size):
            return L("File “%1$@” exceeds the 10 MB limit (%2$@ MB).", name, String(format: "%.1f", Double(size) / (1024 * 1024)))
        case .suspiciousCompressionRatio(let ratio):
            return L("The package compression ratio (%1$@:1) is suspiciously high and was blocked for safety.", String(format: "%.1f", ratio))
        case .pathTraversalDetected(let path):
            return L("Insecure file path detected in package: %1$@", path)
        case .disallowedFileExtension(let ext):
            return L("Unsupported file type in package: .%1$@", ext)
        case .symbolicLinksNotAllowed(let path):
            return L("Symbolic links are not permitted in packages: %1$@", path)
        case .missingManifest:
            return L("The package is missing a valid pack.json specification.")
        case .unsupportedSchemaVersion(let version):
            return L("Unsupported package schema version (%1$@). Please update TypingPet.", version)
        case .extractionFailed(let detail):
            return L("Could not extract package: %1$@", detail)
        case .exportFailed(let detail):
            return L("Could not export package: %1$@", detail)
        }
    }
}

/// Manifest metadata stored inside pack.json in the .petpack ZIP root.
struct PetPackManifest: Codable {
    var schemaVersion: Int = 1
    var id: String
    var name: String
    var author: String?
    var version: String?
    var idle: PresetSelection
    var unassigned: PresetSelection
    var presets: [PetImagePreset]
    var mappings: [PresetKeyMapping] = []
}

/// Inspection record obtained from pre-extraction safety scanning.
struct PetPackInspection {
    let fileCount: Int
    let totalCompressedBytes: Int64
    let totalUncompressedBytes: Int64
    let fileNames: [String]
}

/// Safe exporter and importer for `.petpack` single-file archives.
enum PetPackArchive {
    // MARK: - Safety Limits
    static let maximumArchiveSizeBytes: Int64 = 25 * 1024 * 1024    // 25 MiB
    static let maximumTotalUncompressedBytes: Int64 = 50 * 1024 * 1024 // 50 MiB
    static let maximumSingleFileBytes: Int64 = 10 * 1024 * 1024     // 10 MiB
    static let maximumFileCount: Int = 200
    static let maximumCompressionRatio: Double = 10.0
    static let allowedExtensions: Set<String> = ["json", "png", "jpg", "jpeg", "gif", "webp"]

    // MARK: - Validation & Pre-inspection

    private static func readUInt16(at offset: Int, in bytes: [UInt8]) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(at offset: Int, in bytes: [UInt8]) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    /// Performs zero-extraction safety scanning on a .petpack archive.
    static func inspectAndValidate(url: URL) throws -> PetPackInspection {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize <= maximumArchiveSizeBytes else {
            throw PetPackArchiveError.fileTooLarge(fileSize)
        }
        guard fileSize >= 22 else { // Smallest possible ZIP is 22 bytes (empty EOCD)
            throw PetPackArchiveError.invalidMagicHeader
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // 1. Verify Magic Header: PK\x03\x04
        guard let headerData = try handle.read(upToCount: 4), headerData.count == 4 else {
            throw PetPackArchiveError.invalidMagicHeader
        }
        let magic = readUInt32(at: 0, in: [UInt8](headerData))
        guard magic == 0x04034b50 else { // Little-endian PK\x03\x04
            throw PetPackArchiveError.invalidMagicHeader
        }

        // 2. Locate End of Central Directory (EOCD: PK\x05\x06 = 0x06054b50)
        let searchSize = min(fileSize, 65557) // Max comment length 65535 + 22 bytes
        try handle.seek(toOffset: UInt64(fileSize - searchSize))
        guard let tailData = try handle.read(upToCount: Int(searchSize)) else {
            throw PetPackArchiveError.corruptArchive
        }

        var eocdOffsetInTail: Int?
        let tailBytes = [UInt8](tailData)
        if tailBytes.count >= 22 {
            for i in stride(from: tailBytes.count - 22, through: 0, by: -1) {
                if tailBytes[i] == 0x50 && tailBytes[i + 1] == 0x4B && tailBytes[i + 2] == 0x05 && tailBytes[i + 3] == 0x06 {
                    eocdOffsetInTail = i
                    break
                }
            }
        }
        guard let eocdPos = eocdOffsetInTail else {
            throw PetPackArchiveError.corruptArchive
        }

        let eocdBytes = [UInt8](tailData.subdata(in: eocdPos..<(eocdPos + 22)))
        let totalEntries = Int(readUInt16(at: 10, in: eocdBytes))
        let cdSize = Int64(readUInt32(at: 12, in: eocdBytes))
        let cdOffset = Int64(readUInt32(at: 16, in: eocdBytes))

        guard totalEntries <= maximumFileCount else {
            throw PetPackArchiveError.tooManyFiles(totalEntries)
        }
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= fileSize else {
            throw PetPackArchiveError.corruptArchive
        }

        // 3. Parse Central Directory entries
        try handle.seek(toOffset: UInt64(cdOffset))
        guard let cdData = try handle.read(upToCount: Int(cdSize)), cdData.count == Int(cdSize) else {
            throw PetPackArchiveError.corruptArchive
        }

        let cdBytes = [UInt8](cdData)
        var offset = 0
        var totalCompressed: Int64 = 0
        var totalUncompressed: Int64 = 0
        var inspectedFileNames: [String] = []

        while offset + 46 <= cdBytes.count {
            let sig = readUInt32(at: offset, in: cdBytes)
            guard sig == 0x02014b50 else { break } // PK\x01\x02

            let compSize = Int64(readUInt32(at: offset + 20, in: cdBytes))
            let uncompSize = Int64(readUInt32(at: offset + 24, in: cdBytes))
            let nameLen = Int(readUInt16(at: offset + 28, in: cdBytes))
            let extraLen = Int(readUInt16(at: offset + 30, in: cdBytes))
            let commentLen = Int(readUInt16(at: offset + 32, in: cdBytes))
            let extAttr = readUInt32(at: offset + 38, in: cdBytes)

            // Check for symlinks in external file attributes (UNIX mode in upper 16 bits)
            let unixMode = (extAttr >> 16) & 0o170000
            if unixMode == 0o120000 { // S_IFLNK
                throw PetPackArchiveError.symbolicLinksNotAllowed("symlink at entry \(inspectedFileNames.count)")
            }

            let nameStart = offset + 46
            guard nameStart + nameLen <= cdData.count else { throw PetPackArchiveError.corruptArchive }
            let nameData = cdData.subdata(in: nameStart..<(nameStart + nameLen))
            let fileName = String(data: nameData, encoding: .utf8) ?? ""

            // Path Traversal & format guards
            guard !fileName.contains(".."), !fileName.hasPrefix("/"), !fileName.contains("\\") else {
                throw PetPackArchiveError.pathTraversalDetected(fileName)
            }

            // Skip AppleDouble resource forks (__MACOSX / ._*)
            if fileName.hasPrefix("__MACOSX/") || (fileName as NSString).lastPathComponent.hasPrefix("._") {
                offset += 46 + nameLen + extraLen + commentLen
                continue
            }

            // Exclude directories from size and extension check
            let isDirectory = fileName.hasSuffix("/") || ((extAttr >> 16) & 0o170000 == 0o040000) || ((extAttr & 0x10) != 0)
            if !isDirectory {
                if uncompSize > maximumSingleFileBytes {
                    throw PetPackArchiveError.singleFileSizeExceeded(fileName, uncompSize)
                }
                totalCompressed += compSize
                totalUncompressed += uncompSize

                let ext = (fileName as NSString).pathExtension.lowercased()
                if !allowedExtensions.contains(ext) {
                    throw PetPackArchiveError.disallowedFileExtension(ext)
                }
            }

            inspectedFileNames.append(fileName)
            offset += 46 + nameLen + extraLen + commentLen
        }

        guard inspectedFileNames.count <= maximumFileCount else {
            throw PetPackArchiveError.tooManyFiles(inspectedFileNames.count)
        }
        guard totalUncompressed <= maximumTotalUncompressedBytes else {
            throw PetPackArchiveError.uncompressedSizeExceeded(totalUncompressed)
        }
        if totalCompressed > 0 {
            let ratio = Double(totalUncompressed) / Double(totalCompressed)
            if ratio > maximumCompressionRatio && totalUncompressed > 1024 * 1024 {
                throw PetPackArchiveError.suspiciousCompressionRatio(ratio)
            }
        }

        return PetPackInspection(
            fileCount: inspectedFileNames.count,
            totalCompressedBytes: totalCompressed,
            totalUncompressedBytes: totalUncompressed,
            fileNames: inspectedFileNames
        )
    }

    // MARK: - Export

    /// Packages an image set and its pack configuration into a single .petpack file.
    @MainActor
    static func exportPack(
        set: PetImageSet,
        config: PetPackConfiguration,
        library: PetImageLibrary,
        store: PetPackStore,
        destinationURL: URL
    ) throws {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("petpack-export-\(UUID().uuidString)")
        let imagesStaging = staging.appendingPathComponent("images")
        try fileManager.createDirectory(at: imagesStaging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // 1. Prepare manifest
        var manifestPresets: [PetImagePreset] = []
        for preset in config.presets {
            guard let sourceURL = store.imageURL(id: preset.id, in: config, set: set) else { continue }
            let destFileName = preset.fileName
            let targetURL = imagesStaging.appendingPathComponent(destFileName)
            if !fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
            }
            manifestPresets.append(PetImagePreset(
                id: preset.id,
                name: preset.name,
                fileName: destFileName,
                source: .imageSet
            ))
        }

        let manifest = PetPackManifest(
            schemaVersion: 1,
            id: set.id.uuidString,
            name: config.name,
            author: NSFullUserName(),
            version: "1.0.0",
            idle: config.idle,
            unassigned: config.unassigned,
            presets: manifestPresets,
            mappings: config.mappings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: staging.appendingPathComponent("pack.json"))

        // 2. Compress using native /usr/bin/ditto
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", staging.path, destinationURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PetPackArchiveError.exportFailed("ditto exited with status \(process.terminationStatus)")
        }
    }

    // MARK: - Import

    /// Safely inspects, extracts, and registers a .petpack archive into PetImageLibrary and PetPackStore.
    @MainActor
    static func importPack(
        from sourceURL: URL,
        library: PetImageLibrary,
        store: PetPackStore
    ) throws -> PetImageSet {
        // 1. Pre-inspection and safety limits
        _ = try inspectAndValidate(url: sourceURL)

        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("petpack-import-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // 2. Extract into isolated staging directory
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", "--norsrc", sourceURL.path, staging.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PetPackArchiveError.extractionFailed("ditto exited with status \(process.terminationStatus)")
        }

        // 3. Parse and validate manifest
        let manifestURL = staging.appendingPathComponent("pack.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PetPackArchiveError.missingManifest
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PetPackManifest.self, from: manifestData)
        guard manifest.schemaVersion <= 1 else {
            throw PetPackArchiveError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        guard !manifest.presets.isEmpty else {
            throw PetPackError.emptyPack
        }

        // 4. Register imported set and copy preset images
        let idlePreset = manifest.presets.first(where: { manifest.idle.presetIDs.contains($0.id) }) ?? manifest.presets.first
        let idleFileName = idlePreset?.fileName ?? ""
        let reactionFileNames = manifest.presets.map(\.fileName).filter { $0 != idleFileName }

        let (newSet, destinationDir) = try library.registerImportedSet(
            name: manifest.name,
            idleFileName: idleFileName,
            reactionFileNames: reactionFileNames
        )

        do {
            let imagesFolder = staging.appendingPathComponent("images")
            for preset in manifest.presets {
                guard StoredFileName.isSafe(preset.fileName) else {
                    throw PetPackArchiveError.pathTraversalDetected(preset.fileName)
                }
                var source = imagesFolder.appendingPathComponent(preset.fileName)
                if !fileManager.fileExists(atPath: source.path) {
                    source = staging.appendingPathComponent(preset.fileName)
                }
                guard fileManager.fileExists(atPath: source.path) else {
                    throw PetPackError.invalidPreset
                }
                let dest = destinationDir.appendingPathComponent(preset.fileName)
                if !fileManager.fileExists(atPath: dest.path) {
                    try fileManager.copyItem(at: source, to: dest)
                }
            }

            // 5. Build and save configuration in PetPackStore
            let importedConfig = PetPackConfiguration(
                name: manifest.name,
                presets: manifest.presets.map { PetImagePreset(id: $0.id, name: $0.name, fileName: $0.fileName, source: .imageSet) },
                unassigned: manifest.unassigned,
                idle: manifest.idle,
                mappings: manifest.mappings
            )
            try store.save(importedConfig, for: newSet)
            return newSet
        } catch {
            try? library.deleteSet(id: newSet.id)
            throw error
        }
    }
}
