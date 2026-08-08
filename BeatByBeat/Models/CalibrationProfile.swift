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

/// Where the patient's head was when a capture was made.
///
/// Reach points are stored in the immersive space's coordinates, which are
/// pinned to the room rather than to the person — so a box measured yesterday
/// sits wherever yesterday's chair was. Keeping the head pose alongside the
/// points is what lets the same measurements be lifted onto today's seat.
///
/// Yaw only. Head roll and pitch are where someone happened to be looking in
/// that instant, not which way they are facing, and folding them in would tip
/// the whole workspace.
struct HeadAnchor: Codable, Equatable {
    var position: SIMD3<Float>
    /// Radians about +Y, zero when facing the space's -Z.
    var yaw: Float

    init(position: SIMD3<Float>, yaw: Float) {
        self.position = position
        self.yaw = yaw
    }

    init(head: simd_float4x4) {
        position = SIMD3(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let forward = -SIMD3<Float>(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        yaw = atan2(-forward.x, -forward.z)
    }

    /// Smallest angle between two facings, radians. Wrapped, so a pair either
    /// side of ±π reads as the small difference it is rather than a full turn.
    func facingChange(from other: HeadAnchor) -> Float {
        abs(atan2(sin(yaw - other.yaw), cos(yaw - other.yaw)))
    }

    /// Whether the head has stayed put, for the hold that locks a recentre in.
    func isClose(to other: HeadAnchor, within metres: Float, radians: Float) -> Bool {
        distance(position, other.position) <= metres && facingChange(from: other) <= radians
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
    var createdAt: Date
    /// Where the patient was sitting when this was measured. Optional because
    /// captures made before recentring existed have no anchor to move from.
    var anchor: HeadAnchor?
    /// When it was last played with, as opposed to when it was measured. This
    /// is the one that matters for picking a profile back up: a capture from
    /// last week that has been used every day since is the current one.
    var lastUsedAt: Date?

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

    /// The same reach, moved onto where the patient is sitting now.
    ///
    /// This is what makes a saved profile worth keeping. Without it the box
    /// stays at the old chair, and a patient who sat down half a metre to the
    /// left finds every target half a metre to their right — which looks like
    /// the calibration was wrong rather than merely somewhere else.
    ///
    /// A shift, not a full rigid transform. Turning the six points about the
    /// new facing is the mathematically tidier move, but `SpawnVolume` is
    /// axis-aligned, so the box is refitted around the turned points and comes
    /// out bigger — at 15° a shallow workspace gains about 40% of depth, and
    /// every target on that axis lands past where the patient can reach. A
    /// shift preserves the measured extents exactly. What the facing is for is
    /// telling the patient when it has changed enough to matter; see
    /// `facingChange(from:)`.
    ///
    /// A profile with no anchor adopts the new one without moving anything: its
    /// points can only be assumed to have been measured where they sit, and
    /// from then on it recentres like any other.
    func recentred(to newAnchor: HeadAnchor) -> CalibrationProfile {
        var moved = self
        moved.anchor = newAnchor
        guard let old = anchor else { return moved }

        let shift = newAnchor.position - old.position
        moved.arms = arms.mapValues { boundary in
            var shifted = boundary
            shifted.points = boundary.points.mapValues { $0 + shift }
            return shifted
        }
        return moved
    }

    /// How far the patient has turned since this was measured, radians.
    ///
    /// Beyond a modest angle the saved box no longer lines up with the way they
    /// are facing, and no amount of moving it will fix that — the honest answer
    /// there is to measure again.
    func facingChange(from newAnchor: HeadAnchor) -> Float? {
        anchor.map { newAnchor.facingChange(from: $0) }
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
