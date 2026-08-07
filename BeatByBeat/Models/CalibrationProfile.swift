//
//  CalibrationProfile.swift
//  BeatByBeat
//

import Foundation
import simd

/// The result of a reach capture: the box this player can comfortably work in.
///
/// Deliberately not a clinical measurement. It records where a hand went and
/// where the headset could still see it — not joint angles, and not range of
/// motion in degrees.
struct CalibrationProfile: Codable, Equatable {
    var trainingHand: TrainingHand
    /// Bounding box of what was actually reached, before the safety scale.
    var reachedCenter: SIMD3<Float>
    var reachedSize: SIMD3<Float>
    /// Fraction of the reached box actually used for gameplay.
    var safetyScale: Float
    /// Steps where the hand stopped being tracked before it stopped moving —
    /// those limits are the headset's, not the player's.
    var trackingLimitedSteps: [String]
    /// Fastest comfortable palm speed seen during the capture, m/s.
    var peakSpeed: Float
    var createdAt: Date

    /// The volume gameplay actually uses. Never the full reached box: targets
    /// at the very edge of comfortable reach invite trunk compensation and
    /// overbalancing.
    var volume: SpawnVolume {
        SpawnVolume(center: reachedCenter, size: reachedSize * safetyScale)
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
        let size = volume.size
        return String(
            format: "%.0f×%.0f×%.0f cm · peak %.2f m/s",
            size.x * 100, size.y * 100, size.z * 100, peakSpeed
        )
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
