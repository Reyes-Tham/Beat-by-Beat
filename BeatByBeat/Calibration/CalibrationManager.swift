//
//  CalibrationManager.swift
//  BeatByBeat
//

import Foundation
import QuartzCore
import simd

/// Captures each arm's boundary from six directed reaches.
///
/// Nothing is chased. An earlier version put probes at fixed corners and asked
/// the patient to reach them, which measures the probe rather than the patient
/// — someone who can't get to the upper corner produces a reading about that
/// corner. Here the patient is only told a direction, and whatever they reach
/// in it is the measurement.
///
/// Six directions rather than free exploration because free reach under-samples:
/// people forget to reach down, or never go back toward themselves, and a box
/// fitted to what they happened to do comes out wrong on that axis with no
/// indication anything was missed.
///
/// Each direction ends itself when the arm stops moving, so the patient never
/// has to press anything mid-reach. The arm is then locked with a head glance
/// at the confirm circle.
@MainActor
@Observable
final class CalibrationManager {

    enum Phase: Equatable {
        case idle
        /// Working through the six directions for the current arm.
        case capturing
        /// Six points captured; waiting for the confirm glance.
        case confirming
        case finished
    }

    static let dwellDuration: TimeInterval = 3.0
    static let dwellConeDegrees: Float = 12
    /// How long the arm must be still before a direction is accepted.
    static let holdDuration: TimeInterval = 1.0

    private(set) var phase: Phase = .idle
    private(set) var profile: CalibrationProfile?

    private(set) var currentHand: TrainingHand = .right
    private(set) var currentAxis: ReachAxis = .forward
    private var remainingHands: [TrainingHand] = []
    private var remainingAxes: [ReachAxis] = []
    private var capturedHands = 0
    private var totalHands = 1

    /// 0...1 while the arm is held still on the current direction.
    private(set) var holdProgress: Float = 0
    /// 0...1 while the head is held toward the confirm circle.
    private(set) var dwellProgress: Float = 0
    private(set) var awaitingHand = true
    private(set) var confirmCircle: SIMD3<Float>?

    private var arms: [String: ArmBoundary] = [:]
    private var points: [String: SIMD3<Float>] = [:]
    private var trackingLimited: [String] = []
    private var lostThisAxis = false

    private var stepStart: SIMD3<Float>?
    private var best: SIMD3<Float>?
    private var steadyFor: TimeInterval = 0
    private var recentSpeed: Float = 0
    private var speeds: [Float] = []
    private var lastSample: (position: SIMD3<Float>, time: TimeInterval)?
    private var safetyScale: Float = 0.85
    private var sessionHand: TrainingHand = .both

    /// Hand is roughly parked. Generous enough to allow tremor and the drift of
    /// holding a position, strict enough to exclude an arm still sweeping
    /// through its range (typically 0.2–0.4 m/s).
    var isHandSteady: Bool { recentSpeed < 0.12 }

    /// Whether the arm has actually travelled on this direction. Stops a
    /// stationary hand being accepted as somebody's limit.
    var hasMoved: Bool {
        guard let stepStart, let best else { return false }
        return distance(stepStart, best) >= 0.06
    }

    var progress: String {
        let index = ReachAxis.captureOrder.count - remainingAxes.count
        return "\(currentHand.displayName) arm · \(index) of \(ReachAxis.captureOrder.count)"
    }

    var handProgress: String { "arm \(capturedHands + 1) of \(totalHands)" }
    var instruction: String { currentAxis.prompt(for: currentHand) }
    var capturedPointCount: Int { points.count }

    // MARK: - Lifecycle

    func begin(hand: TrainingHand, safetyScale: Float = 0.85) {
        self.safetyScale = safetyScale
        self.sessionHand = hand
        var order: [TrainingHand] = hand == .both ? [.left, .right] : [hand]
        totalHands = order.count
        capturedHands = 0
        currentHand = order.removeFirst()
        remainingHands = order
        arms = [:]
        speeds = []
        phase = .capturing
        startArm()
    }

    func cancel() {
        phase = .idle
        lastSample = nil
        confirmCircle = nil
    }

    private func startArm() {
        points = [:]
        trackingLimited = []
        remainingAxes = ReachAxis.captureOrder
        currentAxis = remainingAxes.removeFirst()
        confirmCircle = nil
        dwellProgress = 0
        startAxis()
    }

    private func startAxis() {
        stepStart = nil
        best = nil
        steadyFor = 0
        holdProgress = 0
        lostThisAxis = false
        awaitingHand = true
        lastSample = nil
    }

    func placeConfirmCircle(at position: SIMD3<Float>) {
        guard phase == .confirming, confirmCircle == nil else { return }
        confirmCircle = position
    }

    // MARK: - Capture

    /// Feed every frame. `palm` is nil when the hand isn't tracked, which is
    /// itself data — a limit the headset imposed rather than one the patient
    /// chose.
    func record(palm: SIMD3<Float>?, deltaTime: TimeInterval) {
        guard phase == .capturing else { return }

        guard let palm else {
            if stepStart != nil { lostThisAxis = true }
            lastSample = nil
            return
        }

        awaitingHand = false
        if stepStart == nil { stepStart = palm }

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

        // Keep the furthest point *along this direction*, not the last one —
        // the patient will usually drift back a little as they settle.
        best = extremeOf(best, palm, along: currentAxis)

        if hasMoved, isHandSteady {
            steadyFor += deltaTime
            holdProgress = min(1, Float(steadyFor / Self.holdDuration))
            if steadyFor >= Self.holdDuration { acceptAxis() }
        } else {
            steadyFor = 0
            holdProgress = 0
        }
    }

    /// Manual accept, for the therapist and for the Simulator.
    func acceptNow() {
        switch phase {
        case .capturing where hasMoved: acceptAxis()
        case .confirming: commitArm()
        default: break
        }
    }

    private func extremeOf(
        _ current: SIMD3<Float>?,
        _ candidate: SIMD3<Float>,
        along axis: ReachAxis
    ) -> SIMD3<Float> {
        guard let current else { return candidate }
        // -Z is away from the player, so "forward" wants the smallest z.
        return switch axis {
        case .forward: candidate.z < current.z ? candidate : current
        case .back:    candidate.z > current.z ? candidate : current
        case .left:    candidate.x < current.x ? candidate : current
        case .right:   candidate.x > current.x ? candidate : current
        case .up:      candidate.y > current.y ? candidate : current
        case .down:    candidate.y < current.y ? candidate : current
        }
    }

    private func acceptAxis() {
        guard let best else { return }
        points[currentAxis.rawValue] = best
        if lostThisAxis { trackingLimited.append(currentAxis.shortName) }

        if remainingAxes.isEmpty {
            // Six points captured — hand off to the confirm glance.
            phase = .confirming
            holdProgress = 0
        } else {
            currentAxis = remainingAxes.removeFirst()
            startAxis()
        }
    }

    // MARK: - Confirm

    func updateDwell(isLooking: Bool, deltaTime: TimeInterval) {
        guard phase == .confirming else { return }

        // Stillness is what lets the circle sit close to head-forward: the
        // patient must have stopped, so a glance mid-reach can't confirm.
        guard isLooking, isHandSteady else {
            // Decays rather than resetting, so a blink or a small head drift
            // doesn't throw away two seconds of holding still.
            dwellProgress = max(0, dwellProgress - Float(deltaTime / Self.dwellDuration) * 1.5)
            return
        }

        dwellProgress = min(1, dwellProgress + Float(deltaTime / Self.dwellDuration))
        if dwellProgress >= 1 { commitArm() }
    }

    private func commitArm() {
        arms[currentHand.rawValue] = ArmBoundary(
            points: points,
            trackingLimited: trackingLimited
        )
        capturedHands += 1

        if remainingHands.isEmpty {
            finish()
        } else {
            currentHand = remainingHands.removeFirst()
            phase = .capturing
            startArm()
        }
    }

    private func finish() {
        guard !arms.isEmpty else {
            phase = .idle
            return
        }
        profile = CalibrationProfile(
            trainingHand: sessionHand,
            arms: arms,
            safetyScale: safetyScale,
            peakSpeed: robustPeakSpeed(),
            createdAt: Date()
        )
        phase = .finished
        confirmCircle = nil
    }

    /// Live boundary for the arm in progress, for the preview dots.
    var currentBox: SpawnVolume? {
        guard !points.isEmpty else { return nil }
        let boundary = ArmBoundary(points: points, trackingLimited: [])
        return SpawnVolume(center: boundary.reachedCenter, size: boundary.reachedSize)
    }

    /// 90th percentile rather than the maximum: a single tracking glitch can
    /// teleport the palm and produce an enormous instantaneous speed.
    private func robustPeakSpeed() -> Float {
        guard !speeds.isEmpty else { return 0 }
        let sorted = speeds.sorted()
        return sorted[Int(Double(sorted.count - 1) * 0.9)]
    }
}
