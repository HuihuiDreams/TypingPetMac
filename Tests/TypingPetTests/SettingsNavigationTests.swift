import XCTest
@testable import TypingPet

final class SettingsNavigationTests: XCTestCase {
    func testBackAndForwardRestorePagesAndIndividualSets() {
        let first = UUID(), second = UUID()
        var history = SettingsNavigationHistory(initial: .imageSet(first))
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
        history.visit(.general)
        history.visit(.imageSet(second))
        history.goBack()
        XCTAssertEqual(history.current, .general)
        history.goBack()
        XCTAssertEqual(history.current, .imageSet(first))
        history.goForward()
        history.goForward()
        XCTAssertEqual(history.current, .imageSet(second))
        XCTAssertFalse(history.canGoForward)
    }

    func testDuplicateSelectionDoesNotAddHistoryAndNewVisitClearsForwardHistory() {
        var history = SettingsNavigationHistory(initial: .general)
        history.visit(.general)
        XCTAssertEqual(history.entries.count, 1)
        history.visit(.appearance)
        history.visit(.todos)
        history.goBack()
        history.visit(.general)
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.entries, [.general, .appearance, .general])
        history.goForward()
        XCTAssertEqual(history.current, .general)
    }

    func testDeletedSetsAreRemovedWithoutChangingTheCurrentValidPage() {
        let removed = UUID(), kept = UUID()
        var history = SettingsNavigationHistory(initial: .imageSet(removed))
        history.visit(.general)
        history.visit(.imageSet(kept))
        history.removeDeletedSets(validIDs: [kept], fallbackID: kept)
        XCTAssertEqual(history.current, .imageSet(kept))
        history.goBack()
        XCTAssertEqual(history.current, .general)
        XCTAssertFalse(history.canGoBack)

        var empty = SettingsNavigationHistory(initial: .imageSet(removed))
        empty.removeDeletedSets(validIDs: [kept], fallbackID: kept)
        XCTAssertEqual(empty.current, .imageSet(kept))
        XCTAssertFalse(empty.canGoBack)
    }
}
