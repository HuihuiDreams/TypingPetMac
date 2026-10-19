import Foundation
import Combine

struct TodoFileStorage {
    let url: URL
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypingPet", isDirectory: true).appendingPathComponent("todo-state.json")
    }
    func load() throws -> TodoState {
        guard FileManager.default.fileExists(atPath: url.path) else { return TodoState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(TodoState.self, from: Data(contentsOf: url))
        try state.validate()
        return state
    }
    func save(_ state: TodoState) throws {
        try state.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var engine: FocusTimerEngine
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadBlocked = false
    @Published var expanded = true
    let storage: TodoFileStorage
    private var lastCheckpoint: TimeInterval
    private let monotonicNow: () -> TimeInterval

    init(url: URL = TodoFileStorage.defaultURL, monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, wallNow: @escaping () -> Date = Date.init) {
        storage = TodoFileStorage(url: url)
        self.monotonicNow = monotonicNow
        lastCheckpoint = monotonicNow()
        do {
            engine = FocusTimerEngine(state: try storage.load(), monotonicNow: monotonicNow, wallNow: wallNow)
        } catch {
            engine = FocusTimerEngine(monotonicNow: monotonicNow, wallNow: wallNow)
            loadBlocked = true
            errorMessage = "Cannot read the Todo record. The original file is unchanged. \(error.localizedDescription)"
        }
        if engine.activeSession != nil { expanded = false }
        if !loadBlocked { persist() }
    }
    func change(_ operation: (inout FocusTimerEngine) -> Void) {
        guard !loadBlocked else { return }
        let previous = engine.activeSession?.status
        engine.tick()
        operation(&engine)
        if engine.activeSession?.status == .expired, previous != .expired { expanded = false }
        persist()
    }
    func tick() {
        guard !loadBlocked else { return }
        let previous = engine.activeSession?.status
        engine.tick()
        // Also publish date changes while the timer is idle.
        objectWillChange.send()
        if engine.activeSession?.status == .expired, previous != .expired { expanded = false }
        if previous != engine.activeSession?.status || monotonicNow() - lastCheckpoint >= 5 {
            if engine.activeSession?.status == .running || previous != engine.activeSession?.status || errorMessage != nil { persist() }
        }
    }
    func pauseForSleepOrTermination() { change { $0.pause() } }
    func show() {
        expanded = true
        change { $0.setFeature(enabled: true, hidden: false) }
    }
    func hide() { change { $0.setFeature(enabled: true, hidden: true) } }
    func persist() {
        guard !loadBlocked else { return }
        do {
            try storage.save(engine.state)
            lastCheckpoint = monotonicNow()
            errorMessage = nil
        } catch {
            errorMessage = "Cannot save the Todo record. Recent changes can be lost. \(error.localizedDescription)"
        }
    }
}
