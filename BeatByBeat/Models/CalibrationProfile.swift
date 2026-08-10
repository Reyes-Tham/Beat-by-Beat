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

    /// The box the six points fit in, measured along the patient's own axes.
    ///
    /// Fitted in their frame rather than the room's. "Forward" has to mean
    /// forward *for them*: a patient sitting at 30° to the room reaches along
    /// their own axes, and a box squared to the room around those same points
    /// comes out both larger and wrong — wide where they are shallow, and
    /// deep where they are narrow.
    ///
    /// Gameplay never uses the full reached box: targets at the very edge of
    /// comfortable reach invite trunk compensation and overbalancing.
    func volume(safetyScale: Float, in anchor: HeadAnchor?) -> SpawnVolume {
        let frame = anchor ?? .identity
        let local = points.values.map { frame.toLocal($0) }

        guard var lo = local.first else { return .fixed }
        var hi = lo
        for point in local {
            lo = simd_min(lo, point)
            hi = simd_max(hi, point)
        }

        // A degenerate axis would make every target unreachable, so hold a
        // floor. Hitting it means that direction wasn't really captured.
        let size = simd_max(hi - lo, SIMD3<Float>(0.20, 0.18, 0.12))
        return SpawnVolume(
            center: frame.toWorld((lo + hi) / 2),
            size: size * safetyScale,
            yaw: frame.yaw
        )
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

    /// The space origin, facing -Z. Used as the frame to fit a box in when a
    /// capture recorded no seat: only the *facing* of a frame affects a fit,
    /// since the position subtracts out again, so the origin is as good as any.
    static let identity = HeadAnchor(position: .zero, yaw: 0)

    /// What to assume about a seat that was never recorded, given where the
    /// patient is now.
    ///
    /// visionOS puts the space origin on the floor beneath the player, facing
    /// -Z, so horizontally and in facing the origin is the best guess at where
    /// they were. Height is deliberately *not* guessed from it. The origin is
    /// on the floor and a seat is at head height, so taking it literally lifts
    /// the whole workspace by about 1.3 m — which is what it did, before this
    /// existed. Assuming they are the height they are now makes that axis a
    /// no-op instead of a metre of error.
    static func assumedPrevious(matching current: HeadAnchor) -> HeadAnchor {
        HeadAnchor(position: [0, current.position.y, 0], yaw: 0)
    }

    var rotation: simd_quatf { simd_quatf(angle: yaw, axis: [0, 1, 0]) }

    /// A room point as the patient would describe it: so far to their right,
    /// so far above their eyes, so far in front.
    func toLocal(_ world: SIMD3<Float>) -> SIMD3<Float> {
        rotation.inverse.act(world - position)
    }

    func toWorld(_ local: SIMD3<Float>) -> SIMD3<Float> {
        position + rotation.act(local)
    }

    /// Smallest angle between two facings, radians. Wrapped, so a pair either
    /// side of ±π reads as the small difference it is rather than a full turn.
    func facingChange(from other: HeadAnchor) -> Float {
        abs(atan2(sin(yaw - other.yaw), cos(yaw - other.yaw)))
    }

    // MARK: - Persistence

    private static let storageKey = "workspaceAnchor"

    static func loadWorkspace() -> HeadAnchor? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(HeadAnchor.self, from: data)
    }

    static func saveWorkspace(_ anchor: HeadAnchor?) {
        guard let anchor, let data = try? JSONEncoder().encode(anchor) else {
            return UserDefaults.standard.removeObject(forKey: storageKey)
        }
        UserDefaults.standard.set(data, forKey: storageKey)
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
        boundary(for: hand)?.volume(safetyScale: safetyScale, in: anchor)
    }

    var trackingLimitedSteps: [String] {
        arms.flatMap { hand, boundary in
            boundary.trackingLimited.map { "\(hand.capitalized) \($0.lowercased())" }
        }
    }

    var wasTrackingLimited: Bool { !trackingLimitedSteps.isEmpty }

    /// Where to start, suggested by how fast the arm moved during the capture.
    /// A suggestion for the therapist, not a decision — and now a set they can
    /// take apart rather than a rung they have to accept whole.
    var suggestedMobility: Set<MobilityDemand> {
        switch peakSpeed {
        case ..<0.10: []
        case ..<0.15: [.distance]
        case ..<0.22: [.distance, .height]
        case ..<0.30: [.distance, .height, .width]
        default: [.distance, .height, .width, .travel]
        }
    }

    var suggestedMobilitySummary: String { ReachProfile(suggestedMobility).summary }

    /// The same reach, moved onto where the patient is sitting now.
    ///
    /// This is what makes a saved profile worth keeping. Without it the box
    /// stays at the old chair, and a patient who sat down half a metre to the
    /// left finds every target half a metre to their right — which looks like
    /// the calibration was wrong rather than merely somewhere else.
    ///
    /// A full rigid move: every point keeps its place relative to the patient,
    /// so a new chair and a new facing are the same operation. The box that
    /// comes out is the measured one turned, not a larger box fitted around
    /// turned points — which is only true because the fit happens in the
    /// patient's frame. See `ArmBoundary.volume(safetyScale:in:)`.
    ///
    /// A profile with no recorded seat is placed by `assumedPrevious`.
    func recentred(to newAnchor: HeadAnchor) -> CalibrationProfile {
        var moved = self
        moved.anchor = newAnchor
        let old = anchor ?? .assumedPrevious(matching: newAnchor)

        moved.arms = arms.mapValues { boundary in
            var shifted = boundary
            shifted.points = boundary.points.mapValues {
                newAnchor.toWorld(old.toLocal($0))
            }
            return shifted
        }
        return moved
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
