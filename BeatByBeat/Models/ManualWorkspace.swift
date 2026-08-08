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

    var volume: SpawnVolume { SpawnVolume(center: center, size: size) }

    init(center: SIMD3<Float>, size: SIMD3<Float>) {
        self.center = center
        self.size = size
    }

    init(_ volume: SpawnVolume) {
        center = volume.center
        size = volume.size
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
