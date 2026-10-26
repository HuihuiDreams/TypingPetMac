import Foundation

enum SettingsDestination: Equatable {
    case imageSet(UUID), appearance, todos, general
}

struct SettingsNavigationHistory {
    private(set) var entries: [SettingsDestination]
    private(set) var index = 0

    init(initial: SettingsDestination) { entries = [initial] }
    var current: SettingsDestination { entries[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + 1 < entries.count }

    mutating func visit(_ destination: SettingsDestination) {
        guard destination != current else { return }
        entries.removeSubrange((index + 1)..<entries.count)
        entries.append(destination)
        index = entries.count - 1
    }

    mutating func goBack() { if canGoBack { index -= 1 } }
    mutating func goForward() { if canGoForward { index += 1 } }

    mutating func removeDeletedSets(validIDs: Set<UUID>, fallbackID: UUID) {
        let retained = entries.enumerated().filter { _, destination in
            if case .imageSet(let id) = destination { return validIDs.contains(id) }
            return true
        }
        let currentSurvives = retained.contains { $0.offset == index }
        let previousIndex = retained.lastIndex { $0.offset <= index } ?? 0
        entries = retained.map(\.element)
        index = previousIndex
        if entries.isEmpty { entries = [.imageSet(fallbackID)]; index = 0 }
        else if !currentSurvives { visit(.imageSet(fallbackID)) }
    }
}
