//
//  CalibrationManager.swift
//  BeatByBeat
//

import Foundation
import QuartzCore
import simd

/// Runs the reach capture: show a probe out past where the player can
/// comfortably get, watch where their hand actually goes, repeat for each
/// corner, then fit a box to the result.
///
/// The probe is deliberately out of reach. Nothing requires the player to
/// touch it — the useful measurement is how far they *chose* to go, so a
/// patient who gets a third of the way still produces good data. Contact just
/// ends the step early.
@MainActor
@Observable
final class CalibrationManager {

    struct Step {
        let name: String
        let instruction: String
        /// Where the probe sits, in unit-cube coordinates of the probe box.
        let unit: SIMD3<Float>
    }

    /// Four corners plus one forward point. The corners fix width and height;
    /// the span between them and the forward point fixes depth.
    ///
    /// The corners sit near the player (unit z 0.7) rather than at mid-depth.
    /// With everything on one plane the fitted box's near face *was* that
    /// plane, so depth came out as half its true size and kept bottoming out
    /// against the minimum.
    static let steps: [Step] = [
        Step(name: "Upper left",
             instruction: "Reach up and to your left, only as far as is comfortable.",
             unit: [0.0, 1.0, 0.7]),
        Step(name: "Upper right",
             instruction: "Now up and to your right.",
             unit: [1.0, 1.0, 0.7]),
        Step(name: "Lower left",
             instruction: "Down and to your left.",
             unit: [0.0, 0.0, 0.7]),
        Step(name: "Lower right",
             instruction: "Down and to your right.",
             unit: [1.0, 0.0, 0.7]),
        // Unit z of 0 is the far face: minBound.z is the most negative, and
        // -Z is away from the player.
        Step(name: "Forward",
             instruction: "Reach straight out in front of you.",
             unit: [0.5, 0.5, 0.0]),
    ]

    enum Phase: Equatable {
        case idle
        case capturing
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var stepIndex = 0
    private(set) var reached: [SIMD3<Float>] = []
    private(set) var profile: CalibrationProfile?
    /// True while the current step has never seen a tracked hand.
    private(set) var awaitingHand = false

    /// Box the probes are placed in — a generous expansion of wherever the
    /// player was already working.
    private(set) var probeBox: SpawnVolume = .fixed
    private var hand: TrainingHand = .both
    private var safetyScale: Float = 0.85

    private var samples: [SIMD3<Float>] = []
    private var trackingLost: [String] = []
    private var lostThisStep = false
    private var speeds: [Float] = []
    private var lastSample: (position: SIMD3<Float>, time: TimeInterval)?

    var currentStep: Step? {
        stepIndex < Self.steps.count ? Self.steps[stepIndex] : nil
    }

    var progress: String { "\(min(stepIndex + 1, Self.steps.count)) of \(Self.steps.count)" }

    /// World position of the probe for the current step.
    var probePosition: SIMD3<Float>? {
        currentStep.map { probeBox.point(at: $0.unit) }
    }

    // MARK: - Lifecycle

    func begin(base: SpawnVolume, hand: TrainingHand, safetyScale: Float = 0.85) {
        // Probes sit well outside the current working box so the player's own
        // stopping point is the measurement, not the probe's position.
        self.probeBox = SpawnVolume(
            center: base.center,
            size: [base.size.x * 1.6, base.size.y * 1.6, base.size.z * 1.5]
        )
        self.hand = hand
        self.safetyScale = safetyScale
        phase = .capturing
        stepIndex = 0
        reached = []
        trackingLost = []
        resetStep()
    }

    func cancel() {
        phase = .idle
        samples = []
        lastSample = nil
    }

    private func resetStep() {
        samples = []
        lastSample = nil
        lostThisStep = false
        awaitingHand = true
    }

    // MARK: - Capture

    /// Feed every frame while capturing. `palm` is nil when the hand isn't
    /// tracked, which is itself data — a limit the headset imposed rather than
    /// one the player chose.
    func record(palm: SIMD3<Float>?) {
        guard phase == .capturing else { return }

        guard let palm else {
            if !samples.isEmpty { lostThisStep = true }
            lastSample = nil
            return
        }

        awaitingHand = false
        let now = CACurrentMediaTime()
        if let last = lastSample {
            let dt = now - last.time
            if dt > 0.005, dt < 0.5 {
                speeds.append(Float(Double(distance(palm, last.position)) / dt))
            }
        }
        lastSample = (palm, now)
        samples.append(palm)
    }

    /// Ends the current step and moves on. Called on probe contact, or when
    /// the player says they've gone far enough.
    func advance() {
        guard phase == .capturing, let step = currentStep else { return }

        // Their closest approach to the probe is their best attempt at that
        // corner. If the hand was never seen, fall back to the box centre so a
        // failed step shrinks the envelope rather than corrupting it.
        let probe = probeBox.point(at: step.unit)
        let best = samples.min { distance($0, probe) < distance($1, probe) }
            ?? probeBox.point(at: [0.5, 0.5, 0.5])

        reached.append(best)
        if lostThisStep { trackingLost.append(step.name) }

        stepIndex += 1
        if stepIndex >= Self.steps.count {
            finish()
        } else {
            resetStep()
        }
    }

    /// True once the palm is inside the probe, so the caller can auto-advance.
    func hasReachedProbe(palm: SIMD3<Float>, palmRadius: Float, probeRadius: Float) -> Bool {
        guard let probe = probePosition else { return false }
        return distance(palm, probe) <= palmRadius + probeRadius
    }

    private func finish() {
        guard !reached.isEmpty else {
            phase = .idle
            return
        }

        var lower = reached[0]
        var upper = reached[0]
        for point in reached {
            lower = simd_min(lower, point)
            upper = simd_max(upper, point)
        }

        // A degenerate box would make every target unreachable, so hold a
        // floor. Hitting this floor means the capture went wrong.
        let minimum = SIMD3<Float>(0.24, 0.20, 0.14)
        var size = upper - lower
        let centre = (upper + lower) / 2
        size = simd_max(size, minimum)

        profile = CalibrationProfile(
            trainingHand: hand,
            reachedCenter: centre,
            reachedSize: size,
            safetyScale: safetyScale,
            trackingLimitedSteps: trackingLost,
            peakSpeed: robustPeakSpeed(),
            createdAt: Date()
        )
        phase = .finished
    }

    /// 90th percentile rather than the maximum: a single tracking glitch can
    /// teleport the palm and produce an enormous instantaneous speed.
    private func robustPeakSpeed() -> Float {
        guard !speeds.isEmpty else { return 0 }
        let sorted = speeds.sorted()
        return sorted[Int(Double(sorted.count - 1) * 0.9)]
    }
}
