import Foundation

enum FocusMode: String, Codable { case countdown, countup }

struct TimerPreference: Codable, Equatable {
    var mode: FocusMode = .countdown
    var seconds: Double? = 1200

    static let countup = TimerPreference(mode: .countup, seconds: nil)
    static func countdown(minutes: Int) -> TimerPreference? {
        guard (1...999).contains(minutes) else { return nil }
        return TimerPreference(seconds: Double(minutes * 60))
    }
    var isValid: Bool {
        if mode == .countup { return seconds == nil }
        guard let seconds else { return false }
        return seconds.isFinite && seconds >= 60 && seconds <= 59940 && seconds.truncatingRemainder(dividingBy: 60) == 0
    }
}

// One place for title rules, so typing, adding, and renaming agree.
enum TodoTitlePolicy {
    static let maxLength = 120
    // Show a counter from here on while typing.
    static let warningLength = 100
    // Line breaks and runs of whitespace become one space; the result is trimmed and capped.
    static func normalized(_ title: String) -> String {
        String(title.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maxLength))
    }
    // While typing, keep the user's spacing but drop line breaks and stop at the cap.
    static func limitedDraft(_ text: String) -> String {
        let flat = text.contains(where: \.isNewline) ? text.components(separatedBy: .newlines).joined(separator: " ") : text
        return flat.count > maxLength ? String(flat.prefix(maxLength)) : flat
    }
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var createdAt: Date
    var completedAt: Date?
    var deletedAt: Date?
    var timerPreference = TimerPreference()
}

enum FocusStatus: String, Codable { case running, paused, expired, finished }
enum FocusEndReason: String, Codable { case userStopped, switched, completed, deleted }

struct FocusSegment: Codable, Equatable {
    var configuredSeconds: Double?
    var actualActiveSeconds: Double = 0
}

struct FocusSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var todoId: UUID
    var startedAt: Date
    var endedAt: Date?
    var modeAtStart: FocusMode
    var status: FocusStatus = .running
    var endReason: FocusEndReason?
    var activeSegments: [FocusSegment]
    // Derive this value to prevent duplicate accumulation.
    var totalActiveSeconds: Double { activeSegments.reduce(0) { $0 + $1.actualActiveSeconds } }

    enum CodingKeys: String, CodingKey {
        case id, todoId, startedAt, endedAt, modeAtStart, status, endReason, activeSegments, totalActiveSeconds
    }
    init(todoId: UUID, startedAt: Date, preference: TimerPreference) {
        self.todoId = todoId
        self.startedAt = startedAt
        modeAtStart = preference.mode
        activeSegments = [FocusSegment(configuredSeconds: preference.seconds)]
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        todoId = try c.decode(UUID.self, forKey: .todoId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        modeAtStart = try c.decode(FocusMode.self, forKey: .modeAtStart)
        status = try c.decode(FocusStatus.self, forKey: .status)
        endReason = try c.decodeIfPresent(FocusEndReason.self, forKey: .endReason)
        activeSegments = try c.decode([FocusSegment].self, forKey: .activeSegments)
        let savedTotal = try c.decode(Double.self, forKey: .totalActiveSeconds)
        guard abs(savedTotal - totalActiveSeconds) < 0.001 else { throw TodoDataError.invalidState }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(todoId, forKey: .todoId)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encode(modeAtStart, forKey: .modeAtStart)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(endReason, forKey: .endReason)
        try c.encode(activeSegments, forKey: .activeSegments)
        try c.encode(totalActiveSeconds, forKey: .totalActiveSeconds)
    }
}

struct TodoFeaturePreferences: Codable, Equatable {
    var enabled = false
    var bubbleHidden = false
}

struct TodoState: Codable, Equatable {
    var schemaVersion = 1
    var featurePreferences = TodoFeaturePreferences()
    var todos: [TodoItem] = []
    var sessions: [FocusSession] = []
    var activeSessionId: UUID?

    func validate() throws {
        guard schemaVersion == 1 else { throw TodoDataError.unsupportedSchema }
        let todoIDs = Set(todos.map(\.id))
        guard todoIDs.count == todos.count, Set(sessions.map(\.id)).count == sessions.count,
              todos.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.timerPreference.isValid })
        else { throw TodoDataError.invalidState }
        let active = sessions.filter { $0.status != .finished }
        guard active.count <= 1, active.first?.id == activeSessionId else { throw TodoDataError.invalidState }
        for session in sessions {
            guard todoIDs.contains(session.todoId), !session.activeSegments.isEmpty,
                  session.totalActiveSeconds.isFinite,
                  (session.status == .finished) == (session.endedAt != nil),
                  (session.status == .finished) == (session.endReason != nil)
            else { throw TodoDataError.invalidState }
            for segment in session.activeSegments {
                guard segment.actualActiveSeconds.isFinite, segment.actualActiveSeconds >= 0 else { throw TodoDataError.invalidState }
                if session.modeAtStart == .countdown {
                    guard let configured = segment.configuredSeconds,
                          TimerPreference(seconds: configured).isValid,
                          segment.actualActiveSeconds <= configured else { throw TodoDataError.invalidState }
                } else if segment.configuredSeconds != nil { throw TodoDataError.invalidState }
            }
            if session.status != .finished {
                guard let todo = todos.first(where: { $0.id == session.todoId }),
                      todo.completedAt == nil, todo.deletedAt == nil else { throw TodoDataError.invalidState }
                let last = session.activeSegments.last!
                if session.status == .expired {
                    guard session.modeAtStart == .countdown, last.actualActiveSeconds == last.configuredSeconds else { throw TodoDataError.invalidState }
                } else if let configured = last.configuredSeconds, last.actualActiveSeconds >= configured {
                    throw TodoDataError.invalidState
                }
            }
        }
    }
}

enum TodoDataError: LocalizedError {
    case unsupportedSchema, invalidState
    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: return L("This record version is not supported. The original file was preserved.")
        case .invalidState: return L("The records contain invalid data. The original file was preserved.")
        }
    }
}
