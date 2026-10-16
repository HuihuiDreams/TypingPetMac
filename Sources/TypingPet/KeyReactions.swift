import AppKit
import CoreGraphics
import Foundation

struct KeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let control = KeyModifiers(rawValue: 1 << 2)
    static let shift = KeyModifiers(rawValue: 1 << 3)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(eventFlags: CGEventFlags) {
        var result: KeyModifiers = []
        if eventFlags.contains(.maskCommand) { result.insert(.command) }
        if eventFlags.contains(.maskAlternate) { result.insert(.option) }
        if eventFlags.contains(.maskControl) { result.insert(.control) }
        if eventFlags.contains(.maskShift) { result.insert(.shift) }
        self = result
    }

    var displayPrefix: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        return value
    }
}

struct KeyStroke: Codable, Hashable {
    let keyCode: UInt16
    let modifiers: KeyModifiers

    var displayName: String { modifiers.displayPrefix + KeyCodeNames.name(for: keyCode) }
}

struct KeyReactionRule: Codable, Identifiable, Equatable {
    let id: UUID
    var stroke: KeyStroke
    var imageFileName: String
}

enum KeyReactionError: LocalizedError {
    case unreadableImage(String)
    case unsupportedFormat(String)
    case invalidStoragePath

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let name): "无法读取图像: \(name)"
        case .unsupportedFormat(let name): "不支持的图像格式: \(name)"
        case .invalidStoragePath: "按键反应图像路径无效，无法安全清理文件。"
        }
    }
}

@MainActor
final class KeyReactionStore {
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let directory: URL
    private(set) var rules: [KeyReactionRule]

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.fileManager = fileManager
        self.defaults = defaults
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = directory ?? baseDirectory
            .appendingPathComponent("TypingPet", isDirectory: true)
            .appendingPathComponent("KeyReactions", isDirectory: true)
        if let data = defaults.data(forKey: AppPreferencesKey.keyReactionRules),
           let decoded = try? JSONDecoder().decode([KeyReactionRule].self, from: data) {
            rules = decoded
        } else {
            rules = []
        }
    }

    func imageURL(matching stroke: KeyStroke) -> URL? {
        rules.first(where: { $0.stroke == stroke }).flatMap(imageURL(for:))
    }

    func imageURL(for rule: KeyReactionRule) -> URL? {
        guard StoredFileName.isSafe(rule.imageFileName) else { return nil }
        let url = directory.appendingPathComponent(rule.imageFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func setRule(for stroke: KeyStroke, image sourceURL: URL) throws -> KeyReactionRule {
        let ext = sourceURL.pathExtension.lowercased()
        guard FolderImageSelection.supportedExtensions.contains(ext) else {
            throw KeyReactionError.unsupportedFormat(sourceURL.lastPathComponent)
        }
        guard NSImage(contentsOf: sourceURL) != nil else {
            throw KeyReactionError.unreadableImage(sourceURL.lastPathComponent)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        let oldRules = rules.filter { $0.stroke == stroke }
        let rule = KeyReactionRule(id: UUID(), stroke: stroke, imageFileName: fileName)
        let nextRules = (rules.filter { $0.stroke != stroke } + [rule])
            .sorted { $0.stroke.displayName < $1.stroke.displayName }
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
            for oldRule in oldRules {
                try deleteImageFileIfOrphaned(oldRule.imageFileName, remainingRules: nextRules)
            }
        } catch {
            if fileManager.fileExists(atPath: destination.path) { try? fileManager.removeItem(at: destination) }
            throw error
        }
        rules = nextRules
        persist()
        return rule
    }

    func removeRule(id: UUID) throws {
        let removed = rules.filter { $0.id == id }
        let nextRules = rules.filter { $0.id != id }
        for rule in removed {
            try deleteImageFileIfOrphaned(rule.imageFileName, remainingRules: nextRules)
        }
        rules = nextRules
        persist()
    }

    private func deleteImageFileIfOrphaned(_ fileName: String, remainingRules: [KeyReactionRule]) throws {
        guard StoredFileName.isSafe(fileName) else {
            throw KeyReactionError.invalidStoragePath
        }
        guard !remainingRules.contains(where: { $0.imageFileName == fileName }) else { return }
        let fileURL = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: AppPreferencesKey.keyReactionRules) }
    }
}

enum KeyCodeNames {
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "Delete", 53: "Esc", 76: "Enter", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 109: "F10", 111: "F12", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func name(for keyCode: UInt16) -> String { names[keyCode] ?? "按键 \(keyCode)" }
}
