//
//  CalibrationManager.swift
//  BeatByBeat
//

import Foundation
import QuartzCore
import simd

/// Captures the playable workspace by watching where the arm actually goes.
///
/// There is nothing to chase. An earlier version put probes at fixed corners
/// and asked the patient to reach them, which measures the probe rather than
/// the patient — someone who can't get to the upper corner produces a reading
/// about that corner, not about their arm. Here the patient simply explores
/// their own comfortable range and the box grows to fit.
///
/// Confirming is hands-free: hold your head toward the circle for three
/// seconds. A button press is the wrong ask for someone whose affected hand is
/// the thing being measured, and visionOS never exposes eye gaze to apps, so
/// head direction is what "looking at it" has to mean.
@MainActor
@Observable
final class CalibrationManager {

    enum Phase: Equatable {
        case idle
        case capturing
        case finished
    }

    static let dwellDuration: TimeInterval = 3.0
    /// How wide the confirm cone is, in degrees off head-forward.
    static let dwellConeDegrees: Float = 12

    private(set) var phase: Phase = .idle
    private(set) var profile: CalibrationProfile?

    /// Arms still to capture, plus the one in progress.
    private(set) var currentHand: TrainingHand = .right
    private var remaining: [TrainingHand] = []
    private var captured: [TrainingHand] = []

    /// 0...1 while the head is held toward the confirm circle.
    private(set) var dwellProgress: Float = 0
    private(set) var awaitingHand = true
    /// Where the confirm circle sits, fixed once at the start of each arm.
    private(set) var confirmCircle: SIMD3<Float>?

    private var lower: SIMD3<Float>?
    private var upper: SIMD3<Float>?
    private var trackingLost: [String] = []
    private var lostThisHand = false
    private var speeds: [Float] = []
    private var lastSample: (position: SIMD3<Float>, time: TimeInterval)?
    /// Smoothed hand speed, used to tell "finished reaching" from "mid-sweep".
    private var recentSpeed: Float = 0

    /// Hand is roughly parked. Generous enough to allow tremor and the small
    /// drift of holding a position, strict enough to exclude an arm still
    /// sweeping through its range (typically 0.2–0.4 m/s).
    var isHandSteady: Bool { recentSpeed < 0.12 }
    private var safetyScale: Float = 0.85
    private var sessionHand: TrainingHand = .both

    /// Box captured so far for the current arm, or nil before the first
    /// tracked sample. Drives the live preview.
    var currentBox: SpawnVolume? {
        guard let lower, let upper else { return nil }
        return SpawnVolume(center: (lower + upper) / 2, size: upper - lower)
    }

    /// Reach captured so far for the current arm, in metres.
    var currentSpan: SIMD3<Float> {
        guard let lower, let upper else { return .zero }
        return upper - lower
    }

    /// Enough movement to be worth locking in. Stops a stray first sample
    /// being confirmed as somebody's entire range.
    var canConfirm: Bool {
        let span = currentSpan
        return max(span.x, max(span.y, span.z)) >= 0.12
    }

    var progress: String {
        let total = captured.count + remaining.count + 1
        return "arm \(captured.count + 1) of \(total)"
    }

    var handName: String { currentHand.displayName }

    // MARK: - Lifecycle

    func begin(hand: TrainingHand, safetyScale: Float = 0.85) {
        self.safetyScale = safetyScale
        self.sessionHand = hand
        // Both means each arm gets its own pass; the boxes are unioned at the
        // end, so an asymmetric patient produces an asymmetric workspace.
        var order: [TrainingHand] = hand == .both ? [.left, .right] : [hand]
        currentHand = order.removeFirst()
        remaining = order
        captured = []
        trackingLost = []
        speeds = []
        phase = .capturing
        resetArm()
    }

    func cancel() {
        phase = .idle
        lastSample = nil
        confirmCircle = nil
    }

    private func resetArm() {
        lower = nil
        upper = nil
        lastSample = nil
        lostThisHand = false
        dwellProgress = 0
        awaitingHand = true
        confirmCircle = nil
    }

    /// Pins the confirm circle. Placed once per arm so it stays put while the
    /// patient reaches — a circle that follows the head could never be looked
    /// *at*, and one sitting where they're already reaching would confirm by
    /// accident.
    func placeConfirmCircle(at position: SIMD3<Float>) {
        guard phase == .capturing, confirmCircle == nil else { return }
        confirmCircle = position
    }

    // MARK: - Capture

    /// Feed every frame. `palm` is nil when the hand isn't tracked, which is
    /// itself data — a limit the headset imposed rather than one the patient
    /// chose.
    func record(palm: SIMD3<Float>?) {
        guard phase == .capturing else { return }

        guard let palm else {
            if lower != nil { lostThisHand = true }
            lastSample = nil
            return
        }

        awaitingHand = false
        let now = CACurrentMediaTime()
        if let last = lastSample {
            let dt = now - last.time
            if dt > 0.005, dt < 0.5 {
                let speed = Float(Double(distance(palm, last.position)) / dt)
                speeds.append(speed)
                recentSpeed += (speed - recentSpeed) * 0.12
            }
        }
        lastSample = (palm, now)

        lower = lower.map { simd_min($0, palm) } ?? palm
        upper = upper.map { simd_max($0, palm) } ?? palm
    }

    /// Advances or decays the confirm dwell.
    func updateDwell(isLooking: Bool, deltaTime: TimeInterval) {
        guard phase == .capturing else { return }

        // Stillness is what lets the circle sit close to head-forward. The
        // patient has to have *stopped* reaching, so glancing toward it
        // mid-sweep can't confirm — which means the circle no longer has to be
        // parked far enough down to be out of the way on geometry alone.
        guard isLooking, canConfirm, isHandSteady else {
            // Decays rather than resetting, so a blink or a small head drift
            // doesn't throw away two seconds of holding still.
            dwellProgress = max(0, dwellProgress - Float(deltaTime / Self.dwellDuration) * 1.5)
            return
        }

        dwellProgress = min(1, dwellProgress + Float(deltaTime / Self.dwellDuration))
        if dwellProgress >= 1 { commitArm() }
    }

    /// Manual lock. Kept for the therapist and for the Simulator, where there
    /// may be no head pose to dwell with.
    func confirmNow() {
        guard phase == .capturing, canConfirm else { return }
        commitArm()
    }

    private func commitArm() {
        guard let lower, let upper else { return }

        armBoxes[currentHand] = (lower, upper)
        if lostThisHand { trackingLost.append(currentHand.displayName) }
        captured.append(currentHand)

        if remaining.isEmpty {
            finish()
        } else {
            currentHand = remaining.removeFirst()
            resetArm()
        }
    }

    private var armBoxes: [TrainingHand: (SIMD3<Float>, SIMD3<Float>)] = [:]

    private func finish() {
        guard !armBoxes.isEmpty else {
            phase = .idle
            return
        }

        var lo = armBoxes.values.first!.0
        var hi = armBoxes.values.first!.1
        for (boxLow, boxHigh) in armBoxes.values {
            lo = simd_min(lo, boxLow)
            hi = simd_max(hi, boxHigh)
        }

        // A degenerate box would make every target unreachable, so hold a
        // floor. Hitting it means the capture went wrong.
        let minimum = SIMD3<Float>(0.24, 0.20, 0.14)
        let centre = (hi + lo) / 2
        let size = simd_max(hi - lo, minimum)

        profile = CalibrationProfile(
            trainingHand: sessionHand,
            reachedCenter: centre,
            reachedSize: size,
            safetyScale: safetyScale,
            trackingLimitedSteps: trackingLost,
            peakSpeed: robustPeakSpeed(),
            createdAt: Date()
        )
        phase = .finished
        confirmCircle = nil
    }

    /// 90th percentile rather than the maximum: a single tracking glitch can
    /// teleport the palm and produce an enormous instantaneous speed.
    private func robustPeakSpeed() -> Float {
        guard !speeds.isEmpty else { return 0 }
        let sorted = speeds.sorted()
        return sorted[Int(Double(sorted.count - 1) * 0.9)]
    }
}
