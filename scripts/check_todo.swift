import AppKit
import Foundation

// Run these checks when Command Line Tools do not include XCTest.
// All record files use a temporary directory.
private final class Clock {
    var uptime: Double = 0
    var date = Date(timeIntervalSince1970: 1_790_000_000)
    func advance(_ seconds: Double) { uptime += seconds; date += seconds }
    func engine() -> FocusTimerEngine { FocusTimerEngine(monotonicNow: { self.uptime }, wallNow: { self.date }) }
}
private enum CheckError: Error { case failed(String) }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckError.failed(message) }
}

@main
struct TodoChecks {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPetChecks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var passed = 0
        func test(_ name: String, _ operation: () throws -> Void) throws {
            try operation(); passed += 1; print("PASS: \(name)")
        }
        try test("Development and production identities and data paths are separate") {
            let dev = AppProfile.development; let prod = AppProfile.production
            let base = folder.appendingPathComponent("Application Support")
            try check(dev.bundleIdentifier != prod.bundleIdentifier, "Shared bundle identity")
            try check(dev.preferencesDomain != prod.preferencesDomain, "Shared preferences")
            try check(dev.preferencesDomain != dev.bundleIdentifier, "macOS rejects a suite with its own bundle identity")
            _ = AppEnvironment.defaults
            try check(dev.supportDirectory(in: base) != prod.supportDirectory(in: base), "Shared data path")
            try check(dev.frameAutosaveName != prod.frameAutosaveName, "Shared frame key")
            try check(dev.displayName == "TypingPet Dev", "Missing Dev label")
            try check(AppProfile.resolve(channel: nil, bundleIdentifier: nil) == .development, "swift run selected production")
            try check(AppProfile.resolve(channel: "production", bundleIdentifier: "unknown") == .development, "Unknown bundle selected production")
            try check(AppProfile.resolve(channel: "production", bundleIdentifier: prod.bundleIdentifier) == .production, "Explicit production is broken")
            try check(AppEnvironment.isDevelopment, "Executable checks must use development")
            try check(TodoFileStorage.defaultURL.deletingLastPathComponent().lastPathComponent == "TypingPetDev", "Todo path not isolated")
        }
        try test("A second development process cannot acquire the same record lock") {
            let file = folder.appendingPathComponent("dev/.runtime.lock")
            var first: DevelopmentRunLock? = DevelopmentRunLock()
            let acquired = try first!.acquire(at: file)
            try check(acquired, "First runtime lock failed")
            let second = DevelopmentRunLock()
            let duplicate = try second.acquire(at: file)
            try check(!duplicate, "Duplicate runtime can write the same data")
            first = nil
            let restarted = try second.acquire(at: file)
            try check(restarted, "Exited runtime did not release the lock")
        }
        try test("25 + 18 + 21 minutes equals 64 minutes") {
            let c = Clock(); var e = c.engine(); let id = e.addTodo("Work")!
            e.setPreference(.countdown(minutes: 25)!, for: id); e.start(id)
            c.advance(1510); e.tick(); c.advance(500); e.finish()
            e.setPreference(.countdown(minutes: 45)!, for: id); e.start(id); c.advance(1080); e.finish()
            e.setPreference(.countup, for: id); e.start(id); c.advance(1260); e.finish()
            try check(e.totalSeconds(for: id) == 3840, "Wrong total")
            try check(e.openTodos.count == 1, "Timer completed the Todo")
            try e.state.validate()
        }
        try test("Extension stays in one session and excludes expired waiting") {
            let c = Clock(); var e = c.engine(); let id = e.addTodo("Work")!
            e.start(id); let original = e.activeSession?.id
            c.advance(1207); e.tick(); c.advance(600); e.extend(minutes: 10)
            c.advance(300); e.finish()
            try check(e.totalSeconds(for: id) == 1500, "Wrong extension total")
            try check(e.state.sessions.count == 1 && e.state.sessions[0].id == original, "Session changed")
            try check(e.state.sessions[0].activeSegments.count == 2, "Missing extension segment")
        }
        try test("Pause, sleep, and wall clock changes cannot add time") {
            let c = Clock(); var e = c.engine(); let id = e.addTodo("Work")!
            e.setPreference(.countup, for: id); e.start(id)
            for _ in 0..<5 {
                c.advance(0.25); e.tick(); e.tick(); e.pause(); c.advance(900); e.tick(); e.resume()
            }
            c.date -= 100_000; c.uptime += 2.5; e.finish()
            try check(e.totalSeconds(for: id) == 3.75, "Pause or clock affected total")
        }
        try test("Switch requires confirmation and includes decision time") {
            let c = Clock(); var e = c.engine(); let a = e.addTodo("A")!; let b = e.addTodo("B")!
            e.start(a); c.advance(10); try check(!e.start(b), "Switched without confirmation")
            e.setPreference(.countup, for: b); c.advance(7)
            try check(e.start(b, replaceActive: true), "Confirmed switch failed")
            try check(e.totalSeconds(for: a) == 17, "Decision time missing")
            try check(e.state.sessions.filter { $0.status != .finished }.count == 1, "Multiple active timers")
            e.pause(); try check(!e.start(a), "Paused switch bypassed confirmation")
            e.finish(); e.start(a); c.advance(1200); e.tick()
            try check(!e.start(b), "Expired switch bypassed confirmation")
            try e.state.validate()
        }
        try test("Complete, undo, and delete preserve actual time") {
            let c = Clock(); var e = c.engine(); let a = e.addTodo("A")!; let b = e.addTodo("B")!
            e.start(a); c.advance(7.125); e.setCompleted(b, completed: true)
            try check(e.activeSession?.todoId == a, "Other completion stopped timer")
            e.setCompleted(a, completed: true)
            try check(e.activeSession == nil, "Active completion did not stop timer")
            e.setCompleted(a, completed: false); e.delete(a)
            try check(e.totalSeconds(for: a) == 7.125, "Lost history")
            try e.state.validate()
        }
        try test("Local midnight filters completion and keeps running timer") {
            let c = Clock(); var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 32400)!
            c.date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23, minute: 59))!
            var e = c.engine(); let a = e.addTodo("A")!; let b = e.addTodo("B")!
            e.setCompleted(a, completed: true); e.start(b)
            try check(e.completedToday(calendar: calendar).count == 1, "Today filter failed")
            c.advance(120); e.tick()
            try check(e.completedToday(calendar: calendar).isEmpty, "Yesterday item remains")
            try check(e.activeSession?.status == .running && e.openTodos.count == 1, "Midnight reset data")
        }
        try test("Independent preferences and custom bounds do not start timers") {
            var e = Clock().engine(); let a = e.addTodo("Same")!; let b = e.addTodo("Same")!
            e.setPreference(.countup, for: a)
            try check(a != b && e.state.todos[1].timerPreference == TimerPreference(), "Preferences leaked")
            try check(e.activeSession == nil && e.addTodo(" \n ") == nil, "Unexpected start or blank item")
            try check(TimerPreference.countdown(minutes: 0) == nil && TimerPreference.countdown(minutes: 1000) == nil, "Invalid bounds")
            try check(TimerPreference.countdown(minutes: 1) != nil && TimerPreference.countdown(minutes: 999) != nil, "Valid bounds rejected")
        }
        try test("JSON preserves fractions, preferences, soft deletion, and schema") {
            let c = Clock(); var e = c.engine(); let id = e.addTodo("한글 Work")!
            e.setFeature(enabled: true, hidden: true); e.setPreference(.countup, for: id)
            e.start(id); c.advance(1.234567); e.finish(); e.delete(id)
            let storage = TodoFileStorage(url: folder.appendingPathComponent("roundtrip.json"))
            try storage.save(e.state); let loaded = try storage.load()
            try check(loaded.sessions[0].totalActiveSeconds == 1.234567, "Lost fractional seconds")
            try check(loaded.todos[0].timerPreference == .countup && loaded.todos[0].deletedAt != nil, "Lost Todo fields")
            try check(loaded.schemaVersion == 1 && loaded.featurePreferences.bubbleHidden, "Lost preferences")
        }
        try test("Five-second checkpoint recovers paused after a crash") {
            let c = Clock(); let url = folder.appendingPathComponent("checkpoint.json")
            var store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
            store.change { e in let id = e.addTodo("Work")!; e.start(id) }
            c.advance(5); store.tick(); c.advance(3)
            store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
            try check(store.engine.activeSession?.status == .paused, "Recovery resumed")
            try check(store.engine.activeSession?.totalActiveSeconds == 5, "Wrong checkpoint")
            store.change { $0.resume() }; c.advance(2.5); store.pauseForSleepOrTermination()
            c.advance(9000); store.tick()
            store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
            try check(store.engine.activeSession?.status == .paused && store.engine.activeSession?.totalActiveSeconds == 7.5, "Offline time added")
        }
        try test("Damaged and future records cannot be overwritten") {
            for (i, text) in ["broken", "{\"schemaVersion\":99,\"todos\":[],\"sessions\":[],\"featurePreferences\":{\"enabled\":false,\"bubbleHidden\":false}}"].enumerated() {
                let url = folder.appendingPathComponent("bad-\(i).json"); let data = Data(text.utf8); try data.write(to: url)
                let store = TodoStore(url: url); store.show(); store.persist(); store.tick()
                try check(store.loadBlocked && store.errorMessage != nil, "Bad record accepted")
                let after = try Data(contentsOf: url); try check(data == after, "Original file overwritten")
            }
        }
        try test("Save errors are visible and a retry preserves changes") {
            let blocker = folder.appendingPathComponent("blocker"); try Data("block".utf8).write(to: blocker)
            let storageURL = blocker.appendingPathComponent("todo.json"); let store = TodoStore(url: storageURL)
            store.change { _ = $0.addTodo("Keep me") }; try check(store.errorMessage != nil, "Error hidden")
            try FileManager.default.removeItem(at: blocker); store.persist()
            let loaded = try TodoFileStorage(url: storageURL).load()
            try check(store.errorMessage == nil && loaded.todos.first?.title == "Keep me", "Retry lost data")
        }
        try test("Visibility changes save current time and keep the timer running") {
            let c = Clock(); let url = folder.appendingPathComponent("hidden.json")
            let store = TodoStore(url: url, monotonicNow: { c.uptime }, wallNow: { c.date })
            store.change { e in let id = e.addTodo("Work")!; e.setPreference(.countup, for: id); e.start(id) }
            c.advance(2.25); store.hide()
            var saved = try TodoFileStorage(url: url).load()
            try check(saved.sessions[0].totalActiveSeconds == 2.25 && saved.featurePreferences.bubbleHidden, "Hide lost current time")
            c.advance(1); store.show(); saved = try TodoFileStorage(url: url).load()
            try check(saved.sessions[0].status == .running && saved.sessions[0].totalActiveSeconds == 3.25, "Visibility stopped timer")
        }
        try test("Countdown pause keeps the remainder and late ticks clamp exactly") {
            let c = Clock(); var e = c.engine(); let id = e.addTodo("Work")!
            e.setPreference(.countdown(minutes: 1)!, for: id); e.start(id)
            c.advance(20); e.pause(); c.advance(900); e.tick()
            try check(e.displaySeconds == 40, "Paused countdown changed")
            e.resume(); c.advance(5); e.tick()
            try check(e.displaySeconds == 35, "Resume lost remainder")
            c.advance(100); e.tick(); e.pause(); e.resume()
            try check(e.activeSession?.status == .expired && e.totalSeconds(for: id) == 60, "Late callback added excess")
            e.extend(minutes: 1); c.advance(2); e.finish()
            try check(e.totalSeconds(for: id) == 62, "Extension total changed")
        }
        try test("Invalid totals, orphan sessions, and duplicate IDs are rejected") {
            let c = Clock(); var e = c.engine(); let id = e.addTodo("Work")!
            e.start(id); c.advance(2); e.finish()
            var invalid = e.state; invalid.todos.append(invalid.todos[0])
            var rejected = false
            do { try invalid.validate() } catch { rejected = true }
            try check(rejected, "Duplicate UUID accepted")
            invalid = e.state; invalid.todos = []; rejected = false
            do { try invalid.validate() } catch { rejected = true }
            try check(rejected, "Orphan session accepted")
            let storage = TodoFileStorage(url: folder.appendingPathComponent("invalid-total.json"))
            try storage.save(e.state)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: storage.url)) as! [String: Any]
            var sessions = json["sessions"] as! [[String: Any]]
            sessions[0]["totalActiveSeconds"] = 999
            json["sessions"] = sessions
            try JSONSerialization.data(withJSONObject: json).write(to: storage.url)
            rejected = false
            do { _ = try storage.load() } catch { rejected = true }
            try check(rejected, "Invalid saved total accepted")
        }
        try test("Bubble and entry stay inside each display") {
            for screen in [CGRect(x: 0, y: 24, width: 1440, height: 876), CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 300, height: 250)] {
                for x in [screen.minX, screen.midX, screen.maxX - 180] {
                    for y in [screen.minY, screen.midY, screen.maxY - 140] {
                        let pet = CGRect(x: x, y: y, width: 180, height: 140)
                        try check(screen.contains(TodoBubbleGeometry.frame(size: CGSize(width: 340, height: 430), pet: pet, visible: screen)), "Bubble clipped")
                        try check(screen.contains(TodoBubbleGeometry.entryFrame(pet: pet, visible: screen)), "Entry clipped")
                    }
                }
            }
        }
        try test("Rename keeps sessions and ignores blank titles") {
            let c = Clock(); var e = c.engine(); let id = e.addTodo("Draft")!
            e.start(id); c.advance(90); e.rename(id, to: "  Final title  "); e.finish(); e.rename(id, to: " \n ")
            try check(e.state.todos[0].title == "Final title", "Rename failed or accepted a blank title")
            try check(e.totalSeconds(for: id) == 90 && e.state.sessions[0].todoId == id, "Rename lost history")
            e.delete(id); e.rename(id, to: "Hidden")
            try check(e.state.todos[0].title == "Final title", "Deleted Todo was renamed")
            try e.state.validate()
        }
        try test("Bubble tail faces the pet and stays inside the bubble") {
            let screen = CGRect(x: 0, y: 24, width: 1440, height: 876); let content = CGSize(width: 320, height: 300)
            let cases: [(CGRect, TodoBubbleEdge)] = [
                (CGRect(x: 12, y: 40, width: 180, height: 140), .bottom),
                (CGRect(x: 12, y: 500, width: 180, height: 140), .leading),
                (CGRect(x: 1250, y: 500, width: 180, height: 140), .trailing),
                (CGRect(x: 12, y: 750, width: 180, height: 140), .leading)
            ]
            for (pet, edge) in cases {
                let placement = TodoBubbleGeometry.placement(content: content, tail: 10, pet: pet, visible: screen, gap: 2)
                try check(placement.tailEdge == edge, "Wrong tail edge for \(pet)")
                try check(screen.contains(placement.frame), "Bubble clipped")
                let span = edge == .bottom || edge == .top ? placement.frame.width : placement.frame.height
                try check(abs(placement.tailOffset) <= span / 2 - 28, "Tail left the bubble")
            }
            let narrow = CGRect(x: 0, y: 24, width: 400, height: 876)
            let below = TodoBubbleGeometry.placement(content: content, tail: 10, pet: CGRect(x: 110, y: 750, width: 180, height: 140), visible: narrow, gap: 2)
            try check(below.tailEdge == .top && narrow.contains(below.frame), "Top pet on a narrow display did not open below")
            let bottomLeft = TodoBubbleGeometry.placement(content: content, tail: 10, pet: cases[0].0, visible: screen, gap: 2)
            try check(bottomLeft.frame.height == 310 && bottomLeft.tailOffset < 0, "Tail does not point back at a corner pet")
        }
        try test("Zoom snaps to browser steps and display preferences persist") {
            try check(TodoBubbleZoom.larger(than: 1) == 1.1 && TodoBubbleZoom.smaller(than: 1) == 0.9, "Wrong neighbor steps")
            try check(TodoBubbleZoom.larger(than: 2) == 2 && TodoBubbleZoom.smaller(than: 0.8) == 0.8, "Zoom left its range")
            try check(TodoBubbleZoom.normalized(1.3) == 1.25 && TodoBubbleZoom.normalized(0) == 0.8, "Zoom did not snap")
            let suite = "TypingPetChecks-\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let url = folder.appendingPathComponent("display.json")
            var store = TodoStore(url: url, defaults: defaults)
            try check(store.zoom == 1 && store.bubbleVisibility == .always && store.bubbleRestingOpacity == 1 && store.bubbleHoverOpacity == 1, "Wrong display defaults")
            store.zoomIn(); store.zoomIn(); store.setBubbleVisibility(.hover); store.setBubbleRestingOpacity(-1); store.setBubbleHoverOpacity(0.4)
            store = TodoStore(url: url, defaults: defaults)
            try check(store.zoom == 1.25 && store.zoomPercent == 125, "Zoom not restored")
            try check(store.bubbleVisibility == .hover && store.bubbleRestingOpacity == 0 && store.bubbleHoverOpacity == 0.4, "Visibility or opacity not restored, or not clamped")
            let record = try TodoFileStorage(url: url).load()
            try check(record.schemaVersion == 1 && record.todos.isEmpty, "Display preferences leaked into the record file")
        }
        try test("Canvas keeps the bubble beside the pet and inside the display") {
            let screen = CGRect(x: 0, y: 24, width: 1440, height: 876)
            let pets = [CGRect(x: 12, y: 40, width: 220, height: 220), CGRect(x: 600, y: 300, width: 220, height: 220),
                        CGRect(x: 1200, y: 640, width: 220, height: 220), CGRect(x: 12, y: 680, width: 220, height: 220)]
            for pet in pets {
                for content in [CGSize(width: 320, height: 330), CGSize(width: 226, height: 77)] {
                    let canvas = TodoBubbleGeometry.canvas(content: content, tail: 10, width: 320, maxHeight: 560, pet: pet, visible: screen)
                    try check(screen.contains(canvas.frame), "Canvas clipped for \(pet)")
                    try check(canvas.frame.insetBy(dx: -0.5, dy: -0.5).contains(canvas.bubble), "Bubble left the canvas")
                    try check(!canvas.bubble.intersects(pet.insetBy(dx: 1, dy: 1)), "Bubble covers the pet")
                    try check(canvas.maxContentHeight + 0.5 >= content.height, "Height cap below the content")
                    let touches: Bool
                    switch canvas.tailEdge {
                    case .bottom: touches = canvas.bubble.minY == canvas.frame.minY
                    case .top: touches = canvas.bubble.maxY == canvas.frame.maxY
                    case .leading: touches = canvas.bubble.minX == canvas.frame.minX
                    case .trailing: touches = canvas.bubble.maxX == canvas.frame.maxX
                    }
                    try check(touches, "Bubble does not sit on the pet side")
                }
            }
            let shadowed = TodoBubbleGeometry.canvas(content: CGSize(width: 226, height: 77), tail: 10, width: 320, maxHeight: 560, pet: pets[1], visible: screen, margin: 20)
            let plain = TodoBubbleGeometry.canvas(content: CGSize(width: 226, height: 77), tail: 10, width: 320, maxHeight: 560, pet: pets[1], visible: screen)
            try check(shadowed.bubble == plain.bubble && shadowed.frame == plain.frame.insetBy(dx: -20, dy: -20), "Shadow margin moved the bubble")
            let corner = TodoBubbleGeometry.canvas(content: CGSize(width: 226, height: 77), tail: 10, width: 320, maxHeight: 560, pet: pets[0], visible: screen)
            try check(corner.tailEdge == .bottom && corner.frame.height == 570, "Bottom-left pet should get the full room above")
        }
        try test("Editing shortcuts map to text actions on any input source") {
            func action(_ flags: NSEvent.ModifierFlags, _ chars: String, _ code: UInt16) -> Selector? {
                TextEditingShortcuts.action(modifiers: flags, characters: chars, keyCode: code)
            }
            try check(action(.command, "a", 0) == #selector(NSText.selectAll(_:)), "Command-A")
            try check(action(.command, "c", 8) == #selector(NSText.copy(_:)) && action(.command, "v", 9) == #selector(NSText.paste(_:)), "Copy or paste")
            try check(action(.command, "x", 7) == #selector(NSText.cut(_:)) && action(.command, "z", 6) == Selector(("undo:")), "Cut or undo")
            try check(action([.command, .shift], "Z", 6) == Selector(("redo:")), "Redo")
            try check(action(.command, "ㅁ", 0) == #selector(NSText.selectAll(_:)), "Korean input source missed Command-A")
            try check(action([.command, .capsLock], "a", 0) == #selector(NSText.selectAll(_:)), "Caps Lock blocked a shortcut")
            try check(action(.command, "=", 24) == nil && action([], "a", 0) == nil && action([.command, .option], "a", 0) == nil, "Unrelated keys were taken")
        }
        try test("Title policy trims, flattens, caps, and keeps old long titles until edited") {
            try check(TodoTitlePolicy.normalized("  회의   준비\n\n자료 \t정리 ") == "회의 준비 자료 정리", "Whitespace not collapsed")
            let long = String(repeating: "가", count: 150)
            try check(TodoTitlePolicy.normalized(long).count == 120, "Cap not applied")
            try check(TodoTitlePolicy.normalized(String(repeating: "👩‍💻", count: 130)).count == 120, "Grapheme count wrong")
            try check(TodoTitlePolicy.limitedDraft("a\nb  c") == "a b  c", "Draft spacing changed")
            var e = Clock().engine(); let id = e.addTodo(long + "\n끝")!
            try check(e.state.todos[0].title.count == 120, "Added title not capped")
            var old = e.state; old.todos[0].title = long
            e = FocusTimerEngine(state: old)
            e.rename(id, to: long + " ")
            try check(e.state.todos[0].title == long, "Unchanged old title was cut")
            e.rename(id, to: "새 제목\n입니다")
            try check(e.state.todos[0].title == "새 제목 입니다", "Rename did not apply the policy")
            try e.state.validate()
        }
        try test("Existing opacity, pointer avoidance, and resize geometry") {
            try check(PetOpacityBehavior.opacity(isHovering: true, restingOpacity: 1, hoverOpacity: 0.25) == 0.25, "Opacity changed")
            try check(PetResizeGeometry.scale(initialScale: 0.5, initialSize: CGSize(width: 200, height: 200), dragDelta: CGPoint(x: 2000, y: 0)) == 1.25, "Resize bound changed")
            let bounds = CGRect(x: 0, y: 24, width: 1440, height: 876); let pet = CGRect(x: 500, y: 400, width: 200, height: 160)
            let target = PetPointerAvoidance.targetOrigin(mouseLocation: CGPoint(x: 500, y: 420), petFrame: pet, bounds: bounds)
            try check(target != nil && bounds.contains(CGRect(origin: target!, size: pet.size)), "Avoidance changed")
        }
        print("All \(passed) executable checks passed.")
    }
}
