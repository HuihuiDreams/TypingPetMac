import Foundation

/// The interactive idle micro-state of the desktop pet.
internal enum PetIdleState: String, Equatable {
    /// Actively receiving user keystrokes.
    case active
    /// Standard calm resting posture (breathing).
    case resting
    /// Deep inactive sleep / drowsy posture after extended idle timeout.
    case sleeping
}

/// State machine managing transitions between active typing, calm resting, and deep sleep.
/// Designed for zero idle energy drain using exclusively one-shot cancelable tasks.
@MainActor
internal final class PetIdleStateMachine {
    private(set) var state: PetIdleState = .resting
    var onStateChanged: ((PetIdleState) -> Void)?
    var onWakeUp: (() -> Void)?

    private let restingDelay: TimeInterval
    private let sleepDelay: TimeInterval

    private var restingWorkItem: DispatchWorkItem?
    private var sleepWorkItem: DispatchWorkItem?
    private(set) var isPaused: Bool = false

    init(
        restingDelay: TimeInterval = 0.35,
        sleepDelay: TimeInterval = 300.0 // 5 minutes standard
    ) {
        self.restingDelay = restingDelay
        self.sleepDelay = sleepDelay
    }

    /// Invoked whenever a keystroke is received via global key monitoring.
    /// Wakes up the pet immediately from sleep regardless of whether a custom reaction image is mapped.
    func receiveInput() {
        guard !isPaused else { return }
        let wasSleeping = (state == .sleeping)

        // Invalidate pending settle and sleep timers
        restingWorkItem?.cancel()
        restingWorkItem = nil
        sleepWorkItem?.cancel()
        sleepWorkItem = nil

        let previousState = state
        state = .active

        if wasSleeping {
            onWakeUp?()
        }
        if previousState != .active {
            onStateChanged?(.active)
        }

        scheduleRestingTransition()
    }

    private func scheduleRestingTransition() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isPaused else { return }
            self.transitionToResting()
        }
        restingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + restingDelay, execute: workItem)
    }

    private func transitionToResting() {
        restingWorkItem = nil
        state = .resting
        onStateChanged?(.resting)
        scheduleSleepTransition()
    }

    private func scheduleSleepTransition() {
        sleepWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isPaused else { return }
            self.transitionToSleeping()
        }
        sleepWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + sleepDelay, execute: workItem)
    }

    private func transitionToSleeping() {
        sleepWorkItem = nil
        state = .sleeping
        onStateChanged?(.sleeping)
    }

    /// Suspends all timers when the pet window is hidden or system is locked.
    func pause() {
        isPaused = true
        restingWorkItem?.cancel()
        restingWorkItem = nil
        sleepWorkItem?.cancel()
        sleepWorkItem = nil
    }

    /// Resumes monitoring and schedules appropriate timeouts when pet window is shown.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        switch state {
        case .active:
            scheduleRestingTransition()
        case .resting:
            scheduleSleepTransition()
        case .sleeping:
            break
        }
    }

    /// Resets state immediately back to resting.
    func resetToResting() {
        restingWorkItem?.cancel()
        restingWorkItem = nil
        sleepWorkItem?.cancel()
        sleepWorkItem = nil
        isPaused = false
        state = .resting
        onStateChanged?(.resting)
        scheduleSleepTransition()
    }

    #if DEBUG
    func forceTransitionToResting() {
        restingWorkItem?.cancel()
        restingWorkItem = nil
        transitionToResting()
    }

    func forceTransitionToSleeping() {
        sleepWorkItem?.cancel()
        sleepWorkItem = nil
        transitionToSleeping()
    }
    #endif

    deinit {
        restingWorkItem?.cancel()
        sleepWorkItem?.cancel()
    }
}
