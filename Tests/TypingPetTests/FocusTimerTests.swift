import Foundation
import Testing
@testable import TypingPet

private final class TestClock {
    var uptime: Double = 0
    var date = Date(timeIntervalSince1970: 1_790_000_000)
    func advance(_ seconds: Double) { uptime += seconds; date += seconds }
    func engine() -> FocusTimerEngine { FocusTimerEngine(monotonicNow: { self.uptime }, wallNow: { self.date }) }
}

@Suite struct FocusTimerTests {
    @Test func actualTimeAcrossThreeSessionsIs64Minutes() throws {
        let c = TestClock()
        var e = c.engine()
        let added = e.addTodo("Work")
        let id = try #require(added)
        e.setPreference(.countdown(minutes: 25)!, for: id)
        let started1 = e.start(id)
        #expect(started1)
        c.advance(1508); e.tick()
        #expect(e.activeSession?.status == .expired)
        c.advance(300); e.finish()
        e.setPreference(.countdown(minutes: 45)!, for: id)
        let started2 = e.start(id)
        #expect(started2); c.advance(18 * 60); e.finish()
        e.setPreference(.countup, for: id)
        let started3 = e.start(id)
        #expect(started3); c.advance(21 * 60); e.finish()
        #expect(abs(e.totalSeconds(for: id) - 64 * 60) <= 0.0001)
        #expect(e.openTodos.first?.completedAt == nil)
        try e.state.validate()
    }

    @Test func extensionUsesSameSessionAndExcludesWaiting() throws {
        let c = TestClock(); var e = c.engine()
        let id = e.addTodo("Work")!
        e.start(id); let sessionID = e.activeSession?.id
        c.advance(1209); e.tick(); c.advance(450)
        e.extend(minutes: 10); c.advance(300); e.finish()
        #expect(e.state.sessions.count == 1)
        #expect(e.state.sessions[0].id == sessionID)
        #expect(e.state.sessions[0].activeSegments.count == 2)
        #expect(e.totalSeconds(for: id) == 1500)
        try e.state.validate()
    }

    @Test func repeatedPauseResumeAndWallClockChanges() throws {
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("Work")!
        e.setPreference(.countup, for: id); e.start(id)
        for _ in 0..<4 {
            c.advance(0.25); e.tick(); e.tick(); e.pause()
            c.advance(900); e.tick(); e.resume()
        }
        c.date -= 80_000; c.uptime += 2.5; e.finish()
        #expect(abs(e.totalSeconds(for: id) - 3.5) <= 0.000001)
        try e.state.validate()
    }

    @Test func switchCancelAndConfirmationTime() throws {
        let c = TestClock(); var e = c.engine()
        let a = e.addTodo("A")!; let b = e.addTodo("B")!
        e.start(a); c.advance(10)
        let startedB1 = e.start(b)
        #expect(!startedB1) // Cancel leaves the engine unchanged.
        e.setPreference(.countup, for: b)
        #expect(e.activeSession?.todoId == a)
        c.advance(6)
        let switched1 = e.start(b, replaceActive: true)
        #expect(switched1)
        #expect(e.totalSeconds(for: a) == 16)
        #expect(e.state.sessions[0].endReason == .switched)
        #expect(e.activeSession?.todoId == b)
        #expect(e.state.sessions.filter { $0.status != .finished }.count == 1)
        e.pause()
        let startedA = e.start(a)
        #expect(!startedA)
        e.resume()
        c.advance(1); e.finish(); e.start(a); c.advance(1201); e.tick()
        let startedB2 = e.start(b)
        #expect(!startedB2)
        let switched2 = e.start(b, replaceActive: true)
        #expect(switched2)
        try e.state.validate()
    }

    @Test func completeUndoDeleteAndUnrelatedTodo() throws {
        let c = TestClock(); var e = c.engine()
        let a = e.addTodo("A")!; let b = e.addTodo("B")!
        e.start(a); c.advance(7.125); e.setCompleted(b, completed: true)
        #expect(e.activeSession?.todoId == a)
        e.setCompleted(a, completed: true)
        #expect(e.activeSession == nil)
        #expect(e.state.sessions[0].endReason == .completed)
        e.setCompleted(a, completed: false); e.delete(a)
        #expect(e.totalSeconds(for: a) == 7.125)
        #expect(e.openTodos.count == 0)
        try e.state.validate()
    }

    @Test func localCalendarMidnightKeepsOpenTodosAndTimer() throws {
        let c = TestClock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        c.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23, minute: 59))!
        var e = c.engine(); let a = e.addTodo("A")!; let b = e.addTodo("B")!
        e.setCompleted(a, completed: true); e.start(b)
        #expect(e.completedToday(calendar: calendar).count == 1)
        c.advance(120); e.tick()
        #expect(e.completedToday(calendar: calendar).count == 0)
        #expect(e.openTodos.map(\.id) == [b])
        #expect(e.activeSession?.status == .running)
        #expect(e.totalSeconds(for: b) == 120)
    }

    @Test func renameKeepsSessionsAndRejectsBlankTitles() throws {
        let c = TestClock()
        var e = c.engine()
        let added = e.addTodo("Draft")
        let id = try #require(added)
        let started = e.start(id)
        #expect(started); c.advance(90)
        e.rename(id, to: "  Final title  ")
        #expect(e.activeSession?.todoId == id)
        e.finish()
        e.rename(id, to: " \n ")
        #expect(e.state.todos[0].title == "Final title")
        #expect(abs(e.totalSeconds(for: id) - 90) <= 0.0001)
        e.delete(id); e.rename(id, to: "Hidden")
        #expect(e.state.todos[0].title == "Final title")
        try e.state.validate()
    }

    @Test func settingsAreIndependentAndDoNotStartTimer() throws {
        var e = TestClock().engine(); let a = e.addTodo("Same")!; let b = e.addTodo("Same")!
        let blank = e.addTodo(" \n ")
        #expect(blank == nil)
        e.setPreference(.countup, for: a)
        #expect(e.state.todos[1].timerPreference == TimerPreference())
        #expect(e.activeSession == nil)
        #expect(a != b)
        #expect(TimerPreference.countdown(minutes: 0) == nil)
        #expect(TimerPreference.countdown(minutes: 1000) == nil)
        #expect(TimerPreference.countdown(minutes: 999) != nil)
        e.setPreference(TimerPreference(seconds: .infinity), for: a)
        #expect(e.state.todos[0].timerPreference == .countup)
    }

    @Test func restartRestoresPausedAndDoesNotAddOfflineTime() throws {
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("Work")!
        e.start(id); c.advance(12.25); e.tick()
        let snapshot = e.state
        c.advance(80_000)
        e = FocusTimerEngine(state: snapshot, monotonicNow: { c.uptime }, wallNow: { c.date })
        e.tick(); #expect(e.activeSession?.status == .paused)
        #expect(e.totalSeconds(for: id) == 12.25)
        e.resume(); c.advance(0.75); e.finish()
        #expect(e.totalSeconds(for: id) == 13)
        try e.state.validate()
    }

    @Test func absencePauseTakesBackIdleTimeAndIncludingRestoresIt() throws {
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("Work")!
        e.setPreference(.countup, for: id); e.start(id)
        c.advance(1000)
        let pausedSeconds = e.pause(excludingLast: 900)
        #expect(pausedSeconds == 900)
        #expect(e.activeSession?.status == .paused)
        #expect(e.activeSession?.totalActiveSeconds == 100)
        c.advance(3600); e.resume(adding: 4500)
        #expect(e.activeSession?.status == .running)
        #expect(e.activeSession?.totalActiveSeconds == 4600)
        c.advance(10); e.pause(excludingLast: 99_999)
        #expect(e.activeSession?.totalActiveSeconds == 0)
        e.finish()
        e.setPreference(.countdown(minutes: 20)!, for: id); e.start(id)
        c.advance(600); e.pause(excludingLast: 300)
        #expect(e.displaySeconds == 900)
        e.resume(adding: 2000)
        #expect(e.activeSession?.status == .expired)
        #expect(e.activeSession?.activeSegments.last?.actualActiveSeconds == 1200)
        try e.state.validate()
    }
}

@Suite struct TodoPersistenceTests {
    private func temporaryFile() throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder.appendingPathComponent("todo-state.json"), folder)
    }

    @Test func jsonRoundTripAndPreferences() throws {
        let (file, folder) = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = TodoFileStorage(url: file)
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("中文 Work")!
        e.setFeature(enabled: true, hidden: true)
        e.setPreference(.countup, for: id); e.start(id)
        c.advance(1.234567); e.finish()
        try storage.save(e.state)
        let restored = try storage.load()
        #expect(restored.todos == e.state.todos)
        #expect(restored.featurePreferences == e.state.featurePreferences)
        #expect(restored.sessions[0].totalActiveSeconds == 1.234567)
        #expect(abs(restored.sessions[0].endedAt!.timeIntervalSince1970 - e.state.sessions[0].endedAt!.timeIntervalSince1970) <= 1)
        let text = try String(contentsOf: storage.url, encoding: .utf8)
        #expect(text.contains("totalActiveSeconds"))
        #expect(text.contains("Z"))
    }

    @Test @MainActor func checkpointCrashSleepAndNormalTerminationRecovery() throws {
        let (url, folder) = try temporaryFile(); let c = TestClock()
        defer { try? FileManager.default.removeItem(at: folder) }
        var store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { 0 })
        store.change { e in let id = e.addTodo("Work")!; e.start(id) }
        c.advance(5); store.tick()
        c.advance(3) // Uncommitted time is lost after a crash.
        store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { 0 })
        #expect(store.engine.activeSession?.status == .paused)
        #expect(store.engine.activeSession?.totalActiveSeconds == 5)
        store.change { $0.resume() }; c.advance(2.5)
        store.pauseForSleepOrTermination(); c.advance(9000); store.tick()
        #expect(store.engine.activeSession?.totalActiveSeconds == 7.5)
        store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { 0 })
        #expect(store.engine.activeSession?.status == .paused)
        #expect(store.engine.activeSession?.totalActiveSeconds == 7.5)
    }

    @Test @MainActor func corruptAndFutureFilesAreNeverOverwritten() throws {
        for data in [Data("broken".utf8), Data("{\"schemaVersion\":99,\"todos\":[],\"sessions\":[],\"featurePreferences\":{\"enabled\":false,\"bubbleHidden\":false}}".utf8)] {
            let (url, folder) = try temporaryFile()
            defer { try? FileManager.default.removeItem(at: folder) }
            try data.write(to: url)
            let store = TodoStore(url: url)
            #expect(store.loadBlocked)
            #expect(store.errorMessage != nil)
            store.show(); store.tick(); store.persist()
            #expect(try Data(contentsOf: url) == data)
            #expect(store.engine.state.todos.isEmpty)
        }
    }

    @Test @MainActor func writeFailureIsVisibleAndRetryCanSave() throws {
        let (url, folder) = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("block folder".utf8).write(to: url)
        let target = url.appendingPathComponent("record.json")
        let store = TodoStore(url: target)
        #expect(store.errorMessage != nil)
        store.change { _ = $0.addTodo("Keep me") }
        try FileManager.default.removeItem(at: url)
        store.persist()
        #expect(store.errorMessage == nil)
        #expect(try TodoFileStorage(url: target).load().todos.first?.title == "Keep me")
    }

    @Test @MainActor func visibilitySavesMeasuredTimeAndDoesNotStopTimer() throws {
        let (url, folder) = try temporaryFile(); let c = TestClock()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { 0 })
        store.change { e in let id = e.addTodo("Work")!; e.setPreference(.countup, for: id); e.start(id) }
        c.advance(2.25); store.hide()
        let hidden = try TodoFileStorage(url: url).load()
        #expect(hidden.featurePreferences.bubbleHidden)
        #expect(hidden.sessions[0].totalActiveSeconds == 2.25)
        c.advance(1); store.show()
        #expect(store.engine.activeSession?.status == .running)
        #expect(store.engine.activeSession?.totalActiveSeconds == 3.25)
    }

    @Test @MainActor func idleLockAndSleepPauseAndTheNoticeFollowsTheAnswer() throws {
        let (url, folder) = try temporaryFile(); let c = TestClock(); var idle = 0.0
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "TypingPetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var store = TodoStore(url: url, defaults: defaults, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { idle })
        #expect(store.idleMinutes == 15)
        var id: UUID?
        store.change { id = $0.addTodo("Work"); $0.setPreference(.countup, for: id!); $0.start(id!) }
        let start = c.date
        c.advance(600); idle = 300; store.tick()
        #expect(store.engine.activeSession?.status == .running)
        c.advance(600); idle = 900; store.tick()
        #expect(store.engine.activeSession?.status == .paused)
        #expect(store.engine.activeSession?.totalActiveSeconds == 300)
        #expect(store.absence?.reason == .idle)
        #expect(store.absence?.since == start + 300)
        c.advance(3600); idle = 4500; store.tick()
        #expect(store.absence?.returnedAt == nil)
        idle = 1; store.tick()
        #expect(store.absence?.returnedAt == c.date)
        #expect(store.absence?.awaySeconds(now: c.date + 99) == 4500)
        c.advance(10); store.includeAbsence()
        #expect(store.engine.activeSession?.status == .running)
        #expect(store.engine.activeSession?.totalActiveSeconds == 4810)
        #expect(store.absence == nil)
        idle = 2; store.screenDidLock()
        #expect(store.absence?.reason == .locked)
        c.advance(60); idle = 0.5; store.tick()
        #expect(store.absence?.returnedAt == nil)
        store.screenDidUnlock()
        #expect(store.absence?.returnedAt == c.date)
        store.change { $0.resume() }
        #expect(store.absence == nil)
        idle = 3; store.pauseForSleep()
        #expect(store.absence?.reason == .sleep)
        store.change { $0.finish() }
        #expect(store.absence == nil)
        store.change { $0.start(id!) }
        store.setIdleMinutes(7); store.setIdleMinutes(0)
        #expect(store.idleMinutes == 0)
        c.advance(5); idle = 99_999; store.tick(); store.screenDidLock()
        #expect(store.engine.activeSession?.status == .running)
        store.pauseForSleep()
        #expect(store.engine.activeSession?.status == .paused)
        #expect(store.absence == nil)
        store.setIdleMinutes(30)
        store = TodoStore(url: url, defaults: defaults, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { idle })
        #expect(store.idleMinutes == 30)
        try TodoFileStorage(url: url).load().validate()
    }

    @Test @MainActor func bubbleHopsOnExpiryAndOnReturnToAMissedNotice() throws {
        let c = TestClock(); var idle = 0.0
        let suite = "TypingPetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (file, folder) = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TodoStore(url: file, defaults: defaults, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { idle })
        var id: UUID?
        store.change { id = $0.addTodo("Work"); $0.start(id!) }
        c.advance(1200); store.tick()
        #expect(store.engine.activeSession?.status == .expired && store.attentionRequest == 1)
        c.advance(5); idle = 1; store.tick()
        #expect(store.attentionRequest == 1)
        store.change { $0.finish(); $0.start(id!) }
        c.advance(1195); idle = 600; store.tick(); c.advance(5); idle = 605; store.tick()
        #expect(store.attentionRequest == 2)
        c.advance(60); idle = 665; store.tick()
        #expect(store.attentionRequest == 2)
        idle = 1; store.tick()
        #expect(store.attentionRequest == 3)
        store.change { $0.finish(); $0.setPreference(.countup, for: id!); $0.start(id!) }
        c.advance(1000); idle = 900; store.tick()
        #expect(store.absence != nil && store.attentionRequest == 3)
        c.advance(600); idle = 1; store.tick()
        #expect(store.attentionRequest == 4)
        store.change { $0.resume() }
        idle = 1; store.screenDidLock(); c.advance(30); store.change { $0.finish() }; store.screenDidUnlock(); store.tick()
        #expect(store.attentionRequest == 4)
    }

    @Test @MainActor func compactListStaysOpenWhileATimerRunsEndsAndRelaunches() throws {
        let c = TestClock()
        let suite = "TypingPetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (url, folder) = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        @MainActor func open() -> TodoStore { TodoStore(url: url, defaults: defaults, monotonicNow: { c.uptime }, wallNow: { c.date }, idleSeconds: { 0 }) }
        var store = open()
        store.setListStyle(.compact)
        store.change { let id = $0.addTodo("Work")!; $0.start(id) }
        store.expanded = true
        c.advance(1200); store.tick()
        #expect(store.engine.activeSession?.status == .expired && store.expanded)
        store.change { $0.extend(minutes: 10) }
        store = open()
        #expect(store.engine.activeSession?.status == .paused && store.expanded)
        store.setListStyle(.full)
        store = open()
        #expect(!store.expanded)
        store.change { $0.resume() }; store.expanded = true
        c.advance(600); store.tick()
        #expect(store.engine.activeSession?.status == .expired && !store.expanded)
    }

    @Test func invalidTotalsAndSessionReferencesAreRejected() throws {
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("Work")!
        e.start(id); c.advance(60); e.finish()
        var state = e.state; state.todos = []
        #expect(throws: (any Error).self) { try state.validate() }
        let (file, folder) = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = TodoFileStorage(url: file); try storage.save(e.state)
        var text = try String(contentsOf: storage.url, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"totalActiveSeconds\" : 60", with: "\"totalActiveSeconds\" : 600")
        try Data(text.utf8).write(to: storage.url)
        #expect(throws: (any Error).self) { try storage.load() }
    }

    @Test func inputHardeningBoundsTitlesRejectsSymlinksAndSecuresPermissions() throws {
        let huge = String(repeating: "a\nb ", count: 20_000)
        let draft = TodoTitlePolicy.limitedDraft(huge)
        #expect(draft.count == TodoTitlePolicy.maxLength)
        #expect(!draft.contains("\n"))
        let normalized = TodoTitlePolicy.normalized(huge)
        #expect(normalized.count <= TodoTitlePolicy.maxLength)
        #expect(!normalized.contains("\n"))

        var multilineState = TodoState(todos: [TodoItem(title: "Line 1\nLine 2", createdAt: Date())])
        #expect(throws: TodoDataError.self) { try multilineState.validate() }
        multilineState.todos[0].title = String(repeating: "x", count: TodoTitlePolicy.maxRecordLength + 1)
        #expect(throws: TodoDataError.self) { try multilineState.validate() }

        let (file, folder) = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = TodoFileStorage(url: file)
        var e = TestClock().engine()
        _ = e.addTodo("Private task")
        try storage.save(e.state)
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)

        let link = folder.appendingPathComponent("symlink.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: TodoDataError.self) { _ = try TodoFileStorage(url: link).load() }
    }
}
