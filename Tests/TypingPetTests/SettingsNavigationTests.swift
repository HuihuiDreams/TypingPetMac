import Foundation
import Testing
@testable import TypingPet

@Suite struct SettingsNavigationTests {
    @Test func backAndForwardRestorePagesAndIndividualSets() {
        let first = UUID(), second = UUID()
        var history = SettingsNavigationHistory(initial: .imageSet(first))
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
        history.visit(.general)
        history.visit(.imageSet(second))
        history.goBack()
        #expect(history.current == .general)
        history.goBack()
        #expect(history.current == .imageSet(first))
        history.goForward()
        history.goForward()
        #expect(history.current == .imageSet(second))
        #expect(!history.canGoForward)
    }

    @Test func duplicateSelectionDoesNotAddHistoryAndNewVisitClearsForwardHistory() {
        var history = SettingsNavigationHistory(initial: .general)
        history.visit(.general)
        #expect(history.entries.count == 1)
        history.visit(.appearance)
        history.visit(.todos)
        history.goBack()
        history.visit(.general)
        #expect(!history.canGoForward)
        #expect(history.entries == [.general, .appearance, .general])
        history.goForward()
        #expect(history.current == .general)
    }

    @Test func deletedSetsAreRemovedWithoutChangingTheCurrentValidPage() {
        let removed = UUID(), kept = UUID()
        var history = SettingsNavigationHistory(initial: .imageSet(removed))
        history.visit(.general)
        history.visit(.imageSet(kept))
        history.removeDeletedSets(validIDs: [kept], fallbackID: kept)
        #expect(history.current == .imageSet(kept))
        history.goBack()
        #expect(history.current == .general)
        #expect(!history.canGoBack)

        var empty = SettingsNavigationHistory(initial: .imageSet(removed))
        empty.removeDeletedSets(validIDs: [kept], fallbackID: kept)
        #expect(empty.current == .imageSet(kept))
        #expect(!empty.canGoBack)
    }
}
