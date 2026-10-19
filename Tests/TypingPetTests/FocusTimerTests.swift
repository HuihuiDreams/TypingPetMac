import XCTest
@testable import TypingPet

private final class TestClock {
    var uptime: Double = 0
    var date = Date(timeIntervalSince1970: 1_790_000_000)
    func advance(_ seconds: Double) { uptime += seconds; date += seconds }
    func engine() -> FocusTimerEngine { FocusTimerEngine(monotonicNow: { self.uptime }, wallNow: { self.date }) }
}

final class FocusTimerTests: XCTestCase {
    func testActualTimeAcrossThreeSessionsIs64Minutes() throws {
        let c = TestClock()
        var e = c.engine()
        let id = try XCTUnwrap(e.addTodo("Work"))
        e.setPreference(.countdown(minutes: 25)!, for: id)
        XCTAssertTrue(e.start(id))
        c.advance(1508); e.tick()
        XCTAssertEqual(e.activeSession?.status, .expired)
        c.advance(300); e.finish()
        e.setPreference(.countdown(minutes: 45)!, for: id)
        XCTAssertTrue(e.start(id)); c.advance(18 * 60); e.finish()
        e.setPreference(.countup, for: id)
        XCTAssertTrue(e.start(id)); c.advance(21 * 60); e.finish()
        XCTAssertEqual(e.totalSeconds(for: id), 64 * 60, accuracy: 0.0001)
        XCTAssertNil(e.openTodos.first?.completedAt)
        try e.state.validate()
    }

    func testExtensionUsesSameSessionAndExcludesWaiting() throws {
        let c = TestClock(); var e = c.engine()
        let id = e.addTodo("Work")!
        e.start(id); let sessionID = e.activeSession?.id
        c.advance(1209); e.tick(); c.advance(450)
        e.extend(minutes: 10); c.advance(300); e.finish()
        XCTAssertEqual(e.state.sessions.count, 1)
        XCTAssertEqual(e.state.sessions[0].id, sessionID)
        XCTAssertEqual(e.state.sessions[0].activeSegments.count, 2)
        XCTAssertEqual(e.totalSeconds(for: id), 1500)
        try e.state.validate()
    }

    func testRepeatedPauseResumeAndWallClockChanges() throws {
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("Work")!
        e.setPreference(.countup, for: id); e.start(id)
        for _ in 0..<4 {
            c.advance(0.25); e.tick(); e.tick(); e.pause()
            c.advance(900); e.tick(); e.resume()
        }
        c.date -= 80_000; c.uptime += 2.5; e.finish()
        XCTAssertEqual(e.totalSeconds(for: id), 3.5, accuracy: 0.000001)
        try e.state.validate()
    }

    func testSwitchCancelAndConfirmationTime() throws {
        let c = TestClock(); var e = c.engine()
        let a = e.addTodo("A")!; let b = e.addTodo("B")!
        e.start(a); c.advance(10)
        XCTAssertFalse(e.start(b)) // Cancel leaves the engine unchanged.
        e.setPreference(.countup, for: b)
        XCTAssertEqual(e.activeSession?.todoId, a)
        c.advance(6); XCTAssertTrue(e.start(b, replaceActive: true))
        XCTAssertEqual(e.totalSeconds(for: a), 16)
        XCTAssertEqual(e.state.sessions[0].endReason, .switched)
        XCTAssertEqual(e.activeSession?.todoId, b)
        XCTAssertEqual(e.state.sessions.filter { $0.status != .finished }.count, 1)
        e.pause(); XCTAssertFalse(e.start(a)); e.resume()
        c.advance(1); e.finish(); e.start(a); c.advance(1201); e.tick()
        XCTAssertFalse(e.start(b)); XCTAssertTrue(e.start(b, replaceActive: true))
        try e.state.validate()
    }

    func testCompleteUndoDeleteAndUnrelatedTodo() throws {
        let c = TestClock(); var e = c.engine()
        let a = e.addTodo("A")!; let b = e.addTodo("B")!
        e.start(a); c.advance(7.125); e.setCompleted(b, completed: true)
        XCTAssertEqual(e.activeSession?.todoId, a)
        e.setCompleted(a, completed: true)
        XCTAssertNil(e.activeSession)
        XCTAssertEqual(e.state.sessions[0].endReason, .completed)
        e.setCompleted(a, completed: false); e.delete(a)
        XCTAssertEqual(e.totalSeconds(for: a), 7.125)
        XCTAssertEqual(e.openTodos.count, 0)
        try e.state.validate()
    }

    func testLocalCalendarMidnightKeepsOpenTodosAndTimer() throws {
        let c = TestClock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        c.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23, minute: 59))!
        var e = c.engine(); let a = e.addTodo("A")!; let b = e.addTodo("B")!
        e.setCompleted(a, completed: true); e.start(b)
        XCTAssertEqual(e.completedToday(calendar: calendar).count, 1)
        c.advance(120); e.tick()
        XCTAssertEqual(e.completedToday(calendar: calendar).count, 0)
        XCTAssertEqual(e.openTodos.map(\.id), [b])
        XCTAssertEqual(e.activeSession?.status, .running)
        XCTAssertEqual(e.totalSeconds(for: b), 120)
    }

    func testSettingsAreIndependentAndDoNotStartTimer() throws {
        var e = TestClock().engine(); let a = e.addTodo("Same")!; let b = e.addTodo("Same")!
        XCTAssertNil(e.addTodo(" \n "))
        e.setPreference(.countup, for: a)
        XCTAssertEqual(e.state.todos[1].timerPreference, TimerPreference())
        XCTAssertNil(e.activeSession)
        XCTAssertNotEqual(a, b)
        XCTAssertNil(TimerPreference.countdown(minutes: 0))
        XCTAssertNil(TimerPreference.countdown(minutes: 1000))
        XCTAssertNotNil(TimerPreference.countdown(minutes: 999))
        e.setPreference(TimerPreference(seconds: .infinity), for: a)
        XCTAssertEqual(e.state.todos[0].timerPreference, .countup)
    }

    func testRestartRestoresPausedAndDoesNotAddOfflineTime() throws {
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("Work")!
        e.start(id); c.advance(12.25); e.tick()
        let snapshot = e.state
        c.advance(80_000)
        e = FocusTimerEngine(state: snapshot, monotonicNow: { c.uptime }, wallNow: { c.date })
        e.tick(); XCTAssertEqual(e.activeSession?.status, .paused)
        XCTAssertEqual(e.totalSeconds(for: id), 12.25)
        e.resume(); c.advance(0.75); e.finish()
        XCTAssertEqual(e.totalSeconds(for: id), 13)
        try e.state.validate()
    }
}

final class TodoPersistenceTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("todo-state.json")
    }

    func testJSONRoundTripAndPreferences() throws {
        let storage = TodoFileStorage(url: try temporaryFile())
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("한글 Work")!
        e.setFeature(enabled: true, hidden: true)
        e.setPreference(.countup, for: id); e.start(id)
        c.advance(1.234567); e.finish()
        try storage.save(e.state)
        let restored = try storage.load()
        XCTAssertEqual(restored.todos, e.state.todos)
        XCTAssertEqual(restored.featurePreferences, e.state.featurePreferences)
        XCTAssertEqual(restored.sessions[0].totalActiveSeconds, 1.234567)
        XCTAssertEqual(restored.sessions[0].endedAt!.timeIntervalSince1970, e.state.sessions[0].endedAt!.timeIntervalSince1970, accuracy: 1)
        let text = try String(contentsOf: storage.url, encoding: .utf8)
        XCTAssertTrue(text.contains("totalActiveSeconds"))
        XCTAssertTrue(text.contains("Z"))
    }

    @MainActor func testCheckpointCrashSleepAndNormalTerminationRecovery() throws {
        let url = try temporaryFile(); let c = TestClock()
        var store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
        store.change { e in let id = e.addTodo("Work")!; e.start(id) }
        c.advance(5); store.tick()
        c.advance(3) // Uncommitted time is lost after a crash.
        store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
        XCTAssertEqual(store.engine.activeSession?.status, .paused)
        XCTAssertEqual(store.engine.activeSession?.totalActiveSeconds, 5)
        store.change { $0.resume() }; c.advance(2.5)
        store.pauseForSleepOrTermination(); c.advance(9000); store.tick()
        XCTAssertEqual(store.engine.activeSession?.totalActiveSeconds, 7.5)
        store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
        XCTAssertEqual(store.engine.activeSession?.status, .paused)
        XCTAssertEqual(store.engine.activeSession?.totalActiveSeconds, 7.5)
    }

    @MainActor func testCorruptAndFutureFilesAreNeverOverwritten() throws {
        for data in [Data("broken".utf8), Data("{\"schemaVersion\":99,\"todos\":[],\"sessions\":[],\"featurePreferences\":{\"enabled\":false,\"bubbleHidden\":false}}".utf8)] {
            let url = try temporaryFile(); try data.write(to: url)
            let store = TodoStore(url: url)
            XCTAssertTrue(store.loadBlocked)
            XCTAssertNotNil(store.errorMessage)
            store.show(); store.tick(); store.persist()
            XCTAssertEqual(try Data(contentsOf: url), data)
            XCTAssertTrue(store.engine.state.todos.isEmpty)
        }
    }

    @MainActor func testWriteFailureIsVisibleAndRetryCanSave() throws {
        let url = try temporaryFile()
        try Data("block folder".utf8).write(to: url)
        let target = url.appendingPathComponent("record.json")
        let store = TodoStore(url: target)
        XCTAssertNotNil(store.errorMessage)
        store.change { _ = $0.addTodo("Keep me") }
        try FileManager.default.removeItem(at: url)
        store.persist()
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(try TodoFileStorage(url: target).load().todos.first?.title, "Keep me")
    }

    @MainActor func testVisibilitySavesMeasuredTimeAndDoesNotStopTimer() throws {
        let url = try temporaryFile(); let c = TestClock()
        let store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
        store.change { e in let id = e.addTodo("Work")!; e.setPreference(.countup, for: id); e.start(id) }
        c.advance(2.25); store.hide()
        let hidden = try TodoFileStorage(url: url).load()
        XCTAssertTrue(hidden.featurePreferences.bubbleHidden)
        XCTAssertEqual(hidden.sessions[0].totalActiveSeconds, 2.25)
        c.advance(1); store.show()
        XCTAssertEqual(store.engine.activeSession?.status, .running)
        XCTAssertEqual(store.engine.activeSession?.totalActiveSeconds, 3.25)
    }

    func testInvalidTotalsAndSessionReferencesAreRejected() throws {
        let c = TestClock(); var e = c.engine(); let id = e.addTodo("Work")!
        e.start(id); c.advance(60); e.finish()
        var state = e.state; state.todos = []
        XCTAssertThrowsError(try state.validate())
        let storage = TodoFileStorage(url: try temporaryFile()); try storage.save(e.state)
        var text = try String(contentsOf: storage.url, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"totalActiveSeconds\" : 60", with: "\"totalActiveSeconds\" : 600")
        try Data(text.utf8).write(to: storage.url)
        XCTAssertThrowsError(try storage.load())
    }
}
