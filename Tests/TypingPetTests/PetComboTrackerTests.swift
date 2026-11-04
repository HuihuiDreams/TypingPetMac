import Foundation
import Testing
@testable import TypingPet

@Suite
@MainActor
struct PetComboTrackerTests {
    @Test func initialMetricsAreZeroAndDefaultMultipliers() {
        let tracker = PetComboTracker()
        let metrics = tracker.currentMetrics(now: 100.0)

        #expect(metrics.comboCount == 0)
        #expect(metrics.wpm == 0)
        #expect(metrics.scaleMultiplier == 1.0)
        #expect(metrics.amplitudeMultiplier == 1.0)
    }

    @Test func nonAutorepeatKeystrokesIncrementCombo() {
        let tracker = PetComboTracker()
        let stroke1 = KeyStroke(keyCode: 0, modifiers: [], isAutorepeat: false)
        let stroke2 = KeyStroke(keyCode: 1, modifiers: [], isAutorepeat: false)

        let m1 = tracker.recordKeystroke(stroke1, now: 100.0)
        #expect(m1.comboCount == 1)

        let m2 = tracker.recordKeystroke(stroke2, now: 100.2)
        #expect(m2.comboCount == 2)
    }

    @Test func autorepeatKeystrokesDoNotIncrementComboOrWPM() {
        let tracker = PetComboTracker()
        let normalStroke = KeyStroke(keyCode: 0, modifiers: [], isAutorepeat: false)
        let repeatStroke = KeyStroke(keyCode: 0, modifiers: [], isAutorepeat: true)

        let m1 = tracker.recordKeystroke(normalStroke, now: 100.0)
        #expect(m1.comboCount == 1)

        // Multiple autorepeat events
        let m2 = tracker.recordKeystroke(repeatStroke, now: 100.05)
        #expect(m2.comboCount == 1)

        let m3 = tracker.recordKeystroke(repeatStroke, now: 100.10)
        #expect(m3.comboCount == 1)

        // Next distinct key
        let nextStroke = KeyStroke(keyCode: 1, modifiers: [], isAutorepeat: false)
        let m4 = tracker.recordKeystroke(nextStroke, now: 100.3)
        #expect(m4.comboCount == 2)
    }

    @Test func comboTimeoutResetsComboAndInvokesCallback() {
        let tracker = PetComboTracker(comboTimeout: 0.1)
        var resetInvoked = false
        tracker.onComboReset = { resetInvoked = true }

        tracker.recordKeystroke(KeyStroke(keyCode: 0, modifiers: []), now: 100.0)
        #expect(tracker.comboCount == 1)

        // Next key arrives after timeout (0.15s > 0.1s timeout)
        let m2 = tracker.recordKeystroke(KeyStroke(keyCode: 1, modifiers: []), now: 100.15)
        #expect(m2.comboCount == 1)

        tracker.resetCombo()
        #expect(tracker.comboCount == 0)
        #expect(resetInvoked)
    }

    @Test func wpmCalculationFollowsStandardTypingCadence() {
        let tracker = PetComboTracker(windowDuration: 3.0)
        // Simulate typing 10 keystrokes over 1.0 second
        // 10 keystrokes = 2 words in 1 second -> 2 words * 60s = 120 WPM
        var now = 100.0
        for code in 0..<10 {
            tracker.recordKeystroke(KeyStroke(keyCode: UInt16(code), modifiers: []), now: now)
            now += 0.1
        }

        let metrics = tracker.currentMetrics(now: now - 0.1)
        #expect(metrics.comboCount == 10)
        // 10 keys across 0.9s: (10 / 5) / (0.9 / 60) = 2 / 0.015 = 133.33 WPM
        #expect(metrics.wpm > 100 && metrics.wpm < 150)
        #expect(metrics.amplitudeMultiplier > 1.0)
    }

    @Test func multiplierTiersScaleWithComboThresholds() {
        let tracker = PetComboTracker()
        var now = 100.0

        for code in 0..<6 {
            tracker.recordKeystroke(KeyStroke(keyCode: UInt16(code), modifiers: []), now: now)
            now += 0.05
        }
        let tier1 = tracker.currentMetrics(now: now)
        #expect(tier1.comboCount == 6)
        #expect(tier1.scaleMultiplier >= 1.015)
        #expect(tier1.amplitudeMultiplier >= 1.10)

        for code in 6..<16 {
            tracker.recordKeystroke(KeyStroke(keyCode: UInt16(code), modifiers: []), now: now)
            now += 0.05
        }
        let tier2 = tracker.currentMetrics(now: now)
        #expect(tier2.comboCount == 16)
        #expect(tier2.scaleMultiplier >= 1.03)
        #expect(tier2.amplitudeMultiplier >= 1.25)
    }
}
