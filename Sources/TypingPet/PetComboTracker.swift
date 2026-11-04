import Foundation

/// Calculated metrics from recent typing rhythm.
internal struct PetComboMetrics: Equatable {
    let comboCount: Int
    let wpm: Double
    let scaleMultiplier: CGFloat
    let amplitudeMultiplier: CGFloat
}

/// Lightweight, energy-guarded typing velocity and combo tracker.
/// Operates strictly on an event-driven basis with zero repeating polling timers.
@MainActor
internal final class PetComboTracker {
    private var timestamps: [Double] = []
    private let windowDuration: Double
    private let maxTimestamps: Int
    private let comboTimeout: Double
    private let wpmIdleTimeout: Double

    private(set) var comboCount: Int = 0
    private var lastValidKeyUptime: Double = 0

    /// Callback invoked when combo resets to 0 upon timeout, enabling smooth visual decay.
    var onComboReset: (() -> Void)?
    private var resetWorkItem: DispatchWorkItem?

    init(
        windowDuration: Double = 3.0,
        maxTimestamps: Int = 30,
        comboTimeout: Double = 1.2,
        wpmIdleTimeout: Double = 1.5
    ) {
        self.windowDuration = windowDuration
        self.maxTimestamps = maxTimestamps
        self.comboTimeout = comboTimeout
        self.wpmIdleTimeout = wpmIdleTimeout
    }

    /// Records a keystroke and returns current velocity metrics.
    /// Key repeat events (`isAutorepeat == true`) are ignored for combo count and WPM.
    @discardableResult
    func recordKeystroke(
        _ stroke: KeyStroke? = nil,
        now: Double = ProcessInfo.processInfo.systemUptime
    ) -> PetComboMetrics {
        // Cancel any pending reset work item
        resetWorkItem?.cancel()
        resetWorkItem = nil

        let isRepeat = stroke?.isAutorepeat ?? false
        if !isRepeat {
            // Update Combo
            if lastValidKeyUptime > 0 && (now - lastValidKeyUptime) <= comboTimeout {
                comboCount += 1
            } else {
                comboCount = 1
            }
            lastValidKeyUptime = now

            // Update sliding window timestamps
            timestamps.append(now)
            let cutoff = now - windowDuration
            timestamps.removeAll { $0 < cutoff }
            if timestamps.count > maxTimestamps {
                timestamps.removeFirst(timestamps.count - maxTimestamps)
            }
        }

        // Schedule one-shot cancellation timer to reset combo if no subsequent key arrives
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resetCombo()
        }
        resetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + comboTimeout, execute: workItem)

        return currentMetrics(now: now)
    }

    /// Computes the current metrics based on active timestamps and combo count.
    func currentMetrics(now: Double = ProcessInfo.processInfo.systemUptime) -> PetComboMetrics {
        var wpm: Double = 0
        if lastValidKeyUptime > 0 && (now - lastValidKeyUptime) <= wpmIdleTimeout {
            let cutoff = now - windowDuration
            let valid = timestamps.filter { $0 >= cutoff }
            if valid.count >= 2, let first = valid.first, let last = valid.last, (last - first) > 0.3 {
                let dt = last - first
                // 1 Word = 5 Keystrokes. wpm = (valid.count / 5.0) / (dt / 60.0) = 12 * valid.count / dt
                wpm = (Double(valid.count) * 12.0) / dt
            }
        }

        let scaleMult: CGFloat
        let ampMult: CGFloat

        if comboCount >= 30 || wpm >= 80 {
            scaleMult = 1.05
            ampMult = 1.40
        } else if comboCount >= 15 || wpm >= 50 {
            scaleMult = 1.03
            ampMult = 1.25
        } else if comboCount >= 5 || wpm >= 30 {
            scaleMult = 1.015
            ampMult = 1.10
        } else {
            scaleMult = 1.0
            ampMult = 1.0
        }

        return PetComboMetrics(
            comboCount: comboCount,
            wpm: wpm,
            scaleMultiplier: scaleMult,
            amplitudeMultiplier: ampMult
        )
    }

    func resetCombo() {
        resetWorkItem?.cancel()
        resetWorkItem = nil
        comboCount = 0
        timestamps.removeAll(keepingCapacity: true)
        lastValidKeyUptime = 0
        onComboReset?()
    }

    func teardown() {
        resetWorkItem?.cancel()
        resetWorkItem = nil
        timestamps.removeAll()
        comboCount = 0
        lastValidKeyUptime = 0
    }

    deinit {
        resetWorkItem?.cancel()
    }
}
