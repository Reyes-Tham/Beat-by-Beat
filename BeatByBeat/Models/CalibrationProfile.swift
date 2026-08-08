//
//  CalibrationProfile.swift
//  BeatByBeat
//

import Foundation
import simd

/// The six directions each arm is measured in. One point is captured per
/// direction, which is exactly the six numbers a box needs.
enum ReachAxis: String, CaseIterable, Codable {
    case forward, back, left, right, up, down

    /// Order runs easy → hard and ends on a restful one: straight-ahead
    /// reaches first, overhead late, and down last.
    static let captureOrder: [ReachAxis] = [.forward, .back, .left, .right, .up, .down]

    func prompt(for hand: TrainingHand) -> String {
        switch self {
        case .forward: "Reach straight out in front of you."
        case .back:    "Bring your hand back in toward your body."
        case .left:    hand == .left ? "Reach out to your left."
                                     : "Reach across to your left."
        case .right:   hand == .right ? "Reach out to your right."
                                      : "Reach across to your right."
        case .up:      "Reach up as high as is comfortable."
        case .down:    "Reach down toward the floor."
        }
    }

    var shortName: String { rawValue.capitalized }
}

/// One arm's measured boundary.
struct ArmBoundary: Codable, Equatable {
    /// The six captured points, keyed by direction.
    var points: [String: SIMD3<Float>]
    /// Directions where the hand stopped being tracked before it stopped
    /// moving — that limit is the headset's, not the patient's.
    var trackingLimited: [String]

    var reachedCenter: SIMD3<Float> {
        let (lo, hi) = bounds
        return (lo + hi) / 2
    }

    var reachedSize: SIMD3<Float> {
        let (lo, hi) = bounds
        // A degenerate axis would make every target unreachable, so hold a
        // floor. Hitting it means that direction wasn't really captured.
        return simd_max(hi - lo, SIMD3<Float>(0.20, 0.18, 0.12))
    }

    private var bounds: (SIMD3<Float>, SIMD3<Float>) {
        let values = Array(points.values)
        guard var lo = values.first else { return (.zero, .zero) }
        var hi = lo
        for point in values {
            lo = simd_min(lo, point)
            hi = simd_max(hi, point)
        }
        return (lo, hi)
    }

    /// Gameplay never uses the full reached box: targets at the very edge of
    /// comfortable reach invite trunk compensation and overbalancing.
    func volume(safetyScale: Float) -> SpawnVolume {
        SpawnVolume(center: reachedCenter, size: reachedSize * safetyScale)
    }
}

/// The result of a reach capture.
///
/// Each arm keeps its own boundary rather than being merged into one box.
/// Hemiparesis is by definition asymmetric — the affected arm's workspace can
/// be a fraction of the other's, and averaging them would put targets out of
/// reach on one side and make them trivial on the other.
///
/// Deliberately not a clinical measurement. It records where a wrist went and
/// where the headset could still see it — not joint angles, and not range of
/// motion in degrees.
struct CalibrationProfile: Codable, Equatable {
    var trainingHand: TrainingHand
    /// Keyed by `TrainingHand.rawValue`, because a dictionary with an enum key
    /// doesn't round-trip cleanly through JSON.
    var arms: [String: ArmBoundary]
    var safetyScale: Float
    /// Fastest comfortable wrist speed seen during the capture, m/s.
    var peakSpeed: Float
    /// Most this patient comfortably closed their hand during the capture.
    ///
    /// Grabs are scored against this rather than a healthy full fist, so a
    /// hand that cannot close all the way is not permanently short of the
    /// threshold — the same principle as measuring reach against their own
    /// workspace instead of a normal one.
    var maxCurl: Float = 1.0
    var createdAt: Date

    func boundary(for hand: TrainingHand) -> ArmBoundary? {
        arms[hand.rawValue] ?? arms.values.first
    }

    func volume(for hand: TrainingHand) -> SpawnVolume? {
        boundary(for: hand)?.volume(safetyScale: safetyScale)
    }

    var trackingLimitedSteps: [String] {
        arms.flatMap { hand, boundary in
            boundary.trackingLimited.map { "\(hand.capitalized) \($0.lowercased())" }
        }
    }

    var wasTrackingLimited: Bool { !trackingLimitedSteps.isEmpty }

    /// Starting difficulty suggested by how fast the player moved during the
    /// capture. A suggestion for the therapist, not a decision.
    var suggestedLevel: ReachLevel {
        switch peakSpeed {
        case ..<0.10: .one
        case ..<0.15: .two
        case ..<0.22: .three
        case ..<0.30: .four
        default: .five
        }
    }

    var summary: String {
        let parts = arms.keys.sorted().compactMap { key -> String? in
            guard let hand = TrainingHand(rawValue: key),
                  let size = volume(for: hand)?.size else { return nil }
            return String(format: "%@ %.0f×%.0f×%.0f",
                          hand.displayName, size.x * 100, size.y * 100, size.z * 100)
        }
        return parts.joined(separator: " · ") + " cm"
    }
}

// MARK: - Persistence

extension CalibrationProfile {
    private static let storageKey = "calibrationProfile"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func loadSaved() -> CalibrationProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(CalibrationProfile.self, from: data)
    }

    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
