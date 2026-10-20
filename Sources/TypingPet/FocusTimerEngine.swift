import Foundation

// The engine has no UI or file dependencies. Inject both clocks for tests.
struct FocusTimerEngine {
    private(set) var state: TodoState
    private let monotonicNow: () -> TimeInterval
    private let wallNow: () -> Date
    private var lastSample: TimeInterval?

    init(state: TodoState = TodoState(), monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, wallNow: @escaping () -> Date = Date.init) {
        self.state = state
        self.monotonicNow = monotonicNow
        self.wallNow = wallNow
        // Never add time while the process was absent.
        if let index = activeIndex, self.state.sessions[index].status == .running {
            self.state.sessions[index].status = .paused
        }
    }

    private var activeIndex: Int? { state.sessions.firstIndex { $0.id == state.activeSessionId } }
    var activeSession: FocusSession? { activeIndex.map { state.sessions[$0] } }
    var openTodos: [TodoItem] { state.todos.filter { $0.completedAt == nil && $0.deletedAt == nil } }
    func completedToday(calendar: Calendar = .current) -> [TodoItem] {
        state.todos.filter { $0.deletedAt == nil && $0.completedAt.map { calendar.isDate($0, inSameDayAs: wallNow()) } == true }
    }
    func totalSeconds(for todoID: UUID) -> Double {
        state.sessions.filter { $0.todoId == todoID }.reduce(0) { $0 + $1.totalActiveSeconds }
    }
    var displaySeconds: Double {
        guard let session = activeSession, let segment = session.activeSegments.last else { return 0 }
        return segment.configuredSeconds.map { max(0, $0 - segment.actualActiveSeconds) } ?? session.totalActiveSeconds
    }

    mutating func setFeature(enabled: Bool, hidden: Bool) {
        state.featurePreferences = TodoFeaturePreferences(enabled: enabled, bubbleHidden: hidden)
    }
    @discardableResult mutating func addTodo(_ title: String) -> UUID? {
        let title = TodoTitlePolicy.normalized(title)
        guard !title.isEmpty else { return nil }
        let item = TodoItem(title: title, createdAt: wallNow())
        state.todos.append(item)
        return item.id
    }
    // Sessions reference the ID, so a new title keeps every record.
    // An unchanged title is left alone, so older titles above the cap are not cut just by opening the editor.
    mutating func rename(_ todoID: UUID, to title: String) {
        guard let i = state.todos.firstIndex(where: { $0.id == todoID && $0.deletedAt == nil }),
              title.trimmingCharacters(in: .whitespacesAndNewlines) != state.todos[i].title else { return }
        let title = TodoTitlePolicy.normalized(title)
        guard !title.isEmpty else { return }
        state.todos[i].title = title
    }
    mutating func setPreference(_ preference: TimerPreference, for todoID: UUID) {
        guard preference.isValid, let i = state.todos.firstIndex(where: { $0.id == todoID }) else { return }
        state.todos[i].timerPreference = preference
    }
    // The caller must ask for confirmation before passing replaceActive = true.
    @discardableResult mutating func start(_ todoID: UUID, replaceActive: Bool = false) -> Bool {
        guard let todo = openTodos.first(where: { $0.id == todoID }) else { return false }
        if let active = activeSession {
            guard active.todoId != todoID, replaceActive else { return false }
            finish(reason: .switched)
        }
        let session = FocusSession(todoId: todoID, startedAt: wallNow(), preference: todo.timerPreference)
        state.sessions.append(session)
        state.activeSessionId = session.id
        lastSample = monotonicNow()
        return true
    }
    // Account only for measured running time. Clamp late countdown callbacks.
    mutating func tick() {
        guard let i = activeIndex, state.sessions[i].status == .running, let lastSample else { return }
        let now = monotonicNow()
        let elapsed = max(0, now - lastSample)
        self.lastSample = now
        let j = state.sessions[i].activeSegments.count - 1
        let segment = state.sessions[i].activeSegments[j]
        let remaining = segment.configuredSeconds.map { max(0, $0 - segment.actualActiveSeconds) }
        state.sessions[i].activeSegments[j].actualActiveSeconds += min(elapsed, remaining ?? elapsed)
        if let remaining, elapsed >= remaining {
            state.sessions[i].status = .expired
            self.lastSample = nil
        }
    }
    mutating func pause() {
        tick()
        guard let i = activeIndex, state.sessions[i].status == .running else { return }
        state.sessions[i].status = .paused
        lastSample = nil
    }
    mutating func resume() {
        guard let i = activeIndex, state.sessions[i].status == .paused else { return }
        state.sessions[i].status = .running
        lastSample = monotonicNow()
    }
    mutating func extend(minutes: Int) {
        guard let preference = TimerPreference.countdown(minutes: minutes), let i = activeIndex,
              state.sessions[i].status == .expired else { return }
        state.sessions[i].activeSegments.append(FocusSegment(configuredSeconds: preference.seconds))
        state.sessions[i].status = .running
        lastSample = monotonicNow()
    }
    mutating func finish(reason: FocusEndReason = .userStopped) {
        tick()
        guard let i = activeIndex else { return }
        state.sessions[i].status = .finished
        state.sessions[i].endedAt = wallNow()
        state.sessions[i].endReason = reason
        state.activeSessionId = nil
        lastSample = nil
    }
    mutating func setCompleted(_ todoID: UUID, completed: Bool) {
        guard let i = state.todos.firstIndex(where: { $0.id == todoID && $0.deletedAt == nil }) else { return }
        if completed, activeSession?.todoId == todoID { finish(reason: .completed) }
        state.todos[i].completedAt = completed ? wallNow() : nil
    }
    mutating func delete(_ todoID: UUID) {
        guard let i = state.todos.firstIndex(where: { $0.id == todoID }) else { return }
        if activeSession?.todoId == todoID { finish(reason: .deleted) }
        state.todos[i].deletedAt = wallNow()
    }
}
