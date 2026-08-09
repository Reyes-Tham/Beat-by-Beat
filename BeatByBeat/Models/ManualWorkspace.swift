//
//  ManualWorkspace.swift
//  BeatByBeat
//

import Foundation
import simd

/// A workspace box set by hand rather than measured.
///
/// Per arm, exactly like a calibrated boundary, because the two have to be
/// interchangeable: gameplay places targets in one box per arm and should not
/// care which of the two it was handed. A single shared manual box would also
/// be wrong for the same reason a single shared calibrated box was — an
/// affected arm and a sound one do not work in the same space.
///
/// This is what makes the app testable without a headset, and what lets a
/// nurse nudge a boundary without putting the patient through the capture
/// again.
struct ManualWorkspace: Codable, Equatable {
    var center: SIMD3<Float>
    var size: SIMD3<Float>
    /// Which way the box faces, radians about +Y. Carried so a box keeps
    /// pointing where the patient does after they turn their chair.
    var yaw: Float = 0

    var volume: SpawnVolume { SpawnVolume(center: center, size: size, yaw: yaw) }

    init(center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float = 0) {
        self.center = center
        self.size = size
        self.yaw = yaw
    }

    init(_ volume: SpawnVolume) {
        center = volume.center
        size = volume.size
        yaw = volume.yaw
    }

    /// Written by hand because the synthesised decoder has no notion of a
    /// default: it fails outright on a missing key, and every workspace saved
    /// before boxes could turn is missing this one. Losing a nurse's settings
    /// to a new field would be a poor trade.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        center = try container.decode(SIMD3<Float>.self, forKey: .center)
        size = try container.decode(SIMD3<Float>.self, forKey: .size)
        yaw = try container.decodeIfPresent(Float.self, forKey: .yaw) ?? 0
    }

    /// Sensible starting boxes, offset to each side of the midline so the two
    /// arms don't start on top of each other.
    static func `default`(for hand: TrainingHand) -> ManualWorkspace {
        let base = SpawnVolume.fixed
        let side: Float = hand == .left ? -1 : 1
        return ManualWorkspace(
            center: [0.18 * side, base.center.y, base.center.z],
            size: [0.55, 0.55, base.size.z]
        )
    }

    // MARK: - Persistence

    private static let storageKey = "manualWorkspaces"

    static func loadAll() -> [String: ManualWorkspace] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ManualWorkspace].self, from: data)
        else {
            return [
                TrainingHand.left.rawValue: .default(for: .left),
                TrainingHand.right.rawValue: .default(for: .right),
            ]
        }
        return decoded
    }

    static func saveAll(_ workspaces: [String: ManualWorkspace]) {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
