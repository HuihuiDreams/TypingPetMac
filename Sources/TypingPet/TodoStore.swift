import Foundation
import Combine

struct TodoFileStorage {
    let url: URL
    static var defaultURL: URL {
        AppEnvironment.supportDirectory.appendingPathComponent("todo-state.json")
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

enum TodoBubbleVisibility: String, CaseIterable {
    case always, hover
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var engine: FocusTimerEngine
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadBlocked = false
    @Published var expanded = true
    // A display preference, so it lives in UserDefaults instead of the record file.
    @Published private(set) var zoom: Double
    @Published private(set) var bubbleVisibility: TodoBubbleVisibility
    // Same model as the pet: opacity while the pointer is away, and while it is over the pet or bubble.
    @Published private(set) var bubbleRestingOpacity: Double
    @Published private(set) var bubbleHoverOpacity: Double
    let storage: TodoFileStorage
    private var lastCheckpoint: TimeInterval
    private let monotonicNow: () -> TimeInterval
    private let defaults: UserDefaults
    private static let zoomKey = "todoBubbleZoom"
    private static let visibilityKey = "todoBubbleVisibility"
    private static let restingOpacityKey = "todoBubbleRestingOpacity"
    private static let hoverOpacityKey = "todoBubbleHoverOpacity"

    init(url: URL = TodoFileStorage.defaultURL, defaults: UserDefaults = AppEnvironment.defaults, monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, wallNow: @escaping () -> Date = Date.init) {
        storage = TodoFileStorage(url: url)
        self.defaults = defaults
        zoom = (defaults.object(forKey: Self.zoomKey) as? Double).map(TodoBubbleZoom.normalized) ?? 1
        bubbleVisibility = defaults.string(forKey: Self.visibilityKey).flatMap(TodoBubbleVisibility.init(rawValue:)) ?? .always
        bubbleRestingOpacity = (defaults.object(forKey: Self.restingOpacityKey) as? Double).map(Self.clampedOpacity) ?? 1
        bubbleHoverOpacity = (defaults.object(forKey: Self.hoverOpacityKey) as? Double).map(Self.clampedOpacity) ?? 1
        self.monotonicNow = monotonicNow
        lastCheckpoint = monotonicNow()
        do {
            engine = FocusTimerEngine(state: try storage.load(), monotonicNow: monotonicNow, wallNow: wallNow)
        } catch {
            engine = FocusTimerEngine(monotonicNow: monotonicNow, wallNow: wallNow)
            loadBlocked = true
            errorMessage = "할 일 기록을 읽지 못했어요. 원본 파일은 그대로 두었어요. \(error.localizedDescription)"
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
    var zoomPercent: Int { Int((zoom * 100).rounded()) }
    var canZoomIn: Bool { zoom < TodoBubbleZoom.steps[TodoBubbleZoom.steps.count - 1] }
    var canZoomOut: Bool { zoom > TodoBubbleZoom.steps[0] }
    func zoomIn() { setZoom(TodoBubbleZoom.larger(than: zoom)) }
    func zoomOut() { setZoom(TodoBubbleZoom.smaller(than: zoom)) }
    func resetZoom() { setZoom(1) }
    func setBubbleVisibility(_ value: TodoBubbleVisibility) {
        guard value != bubbleVisibility else { return }
        bubbleVisibility = value
        defaults.set(value.rawValue, forKey: Self.visibilityKey)
    }
    func setBubbleRestingOpacity(_ value: Double) {
        let value = Self.clampedOpacity(value)
        guard value != bubbleRestingOpacity else { return }
        bubbleRestingOpacity = value
        defaults.set(value, forKey: Self.restingOpacityKey)
    }
    func setBubbleHoverOpacity(_ value: Double) {
        let value = Self.clampedOpacity(value)
        guard value != bubbleHoverOpacity else { return }
        bubbleHoverOpacity = value
        defaults.set(value, forKey: Self.hoverOpacityKey)
    }
    private static func clampedOpacity(_ value: Double) -> Double { min(max(value, 0), 1) }
    func setZoom(_ value: Double) {
        let value = TodoBubbleZoom.normalized(value)
        guard value != zoom else { return }
        zoom = value
        defaults.set(value, forKey: Self.zoomKey)
    }
    func persist() {
        guard !loadBlocked else { return }
        do {
            try storage.save(engine.state)
            lastCheckpoint = monotonicNow()
            errorMessage = nil
        } catch {
            errorMessage = "할 일 기록을 저장하지 못했어요. 최근 변경 사항이 사라질 수 있어요. \(error.localizedDescription)"
        }
    }
}
