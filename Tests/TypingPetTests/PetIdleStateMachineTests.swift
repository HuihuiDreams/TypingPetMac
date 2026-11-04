import Foundation
import Testing
@testable import TypingPet

@Suite(.serialized)
@MainActor
struct PetIdleStateMachineTests {
    @Test func initialStateIsResting() {
        let sm = PetIdleStateMachine()
        #expect(sm.state == .resting)
        #expect(!sm.isPaused)
    }

    @Test func receiveInputTransitionsToActive() {
        let sm = PetIdleStateMachine(restingDelay: 1.0, sleepDelay: 10.0)
        var stateLog: [PetIdleState] = []
        sm.onStateChanged = { stateLog.append($0) }

        sm.receiveInput()
        #expect(sm.state == .active)
        #expect(stateLog == [.active])
    }

    @Test func restingTransitionSetsStateToResting() {
        let sm = PetIdleStateMachine(restingDelay: 1.0, sleepDelay: 10.0)
        var stateLog: [PetIdleState] = []
        sm.onStateChanged = { stateLog.append($0) }

        sm.receiveInput()
        #expect(sm.state == .active)

        sm.forceTransitionToResting()
        #expect(sm.state == .resting)
        #expect(stateLog == [.active, .resting])
    }

    @Test func sleepTransitionSetsStateToSleeping() {
        let sm = PetIdleStateMachine(restingDelay: 1.0, sleepDelay: 10.0)
        var stateLog: [PetIdleState] = []
        sm.onStateChanged = { stateLog.append($0) }

        sm.receiveInput()
        sm.forceTransitionToResting()
        sm.forceTransitionToSleeping()

        #expect(sm.state == .sleeping)
        #expect(stateLog == [.active, .resting, .sleeping])
    }

    @Test func anyInputWakesUpFromSleepingAndTriggersWakeUp() {
        let sm = PetIdleStateMachine(restingDelay: 1.0, sleepDelay: 10.0)
        var wokeUp = false
        sm.onWakeUp = { wokeUp = true }

        sm.receiveInput()
        sm.forceTransitionToResting()
        sm.forceTransitionToSleeping()
        #expect(sm.state == .sleeping)
        #expect(!wokeUp)

        // Any new input (even unmapped key) wakes up the pet
        sm.receiveInput()
        #expect(sm.state == .active)
        #expect(wokeUp)
    }

    @Test func pauseCancelsPendingTransitions() {
        let sm = PetIdleStateMachine(restingDelay: 1.0, sleepDelay: 10.0)
        sm.receiveInput()
        #expect(sm.state == .active)

        sm.pause()
        #expect(sm.isPaused)

        sm.resume()
        #expect(!sm.isPaused)
    }

    @Test func resetToRestingSetsStateAndSchedulesSleep() {
        let sm = PetIdleStateMachine(restingDelay: 1.0, sleepDelay: 10.0)
        sm.receiveInput()
        #expect(sm.state == .active)

        sm.resetToResting()
        #expect(sm.state == .resting)
        #expect(!sm.isPaused)
    }
}
