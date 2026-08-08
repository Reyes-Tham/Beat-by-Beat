//
//  GripOrientation.swift
//  BeatByBeat
//

import Foundation
import simd

/// How the hand has to be turned to take hold of a target.
///
/// Two orientations, not four. Four sat within 45° of each other once the
/// tolerance was wide enough to be fair to an impaired forearm, so they could
/// not actually be told apart — the app was asking for a distinction it had no
/// way to measure. Cup and overhand are perpendicular, which leaves room for a
/// generous window around each and still keeps them distinct.
enum GripOrientation: String, CaseIterable, Identifiable, Codable {
    /// Palm toward the midline, as if closing around a mug.
    case cup
    /// Palm down, as if picking something off a table.
    case overhand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cup: "Cup"
        case .overhand: "Overhand"
        }
    }

    var detail: String {
        switch self {
        case .cup: "Palm inward, closing around a mug"
        case .overhand: "Palm down, lifting off a table"
        }
    }

    /// Palm direction this orientation asks for, in world space.
    ///
    /// The cup grip mirrors: each hand closes toward the body's midline, so a
    /// right hand's palm faces left and a left hand's faces right.
    func requiredPalmNormal(for hand: TrainingHand) -> SIMD3<Float> {
        switch self {
        case .cup:      [hand == .left ? 1 : -1, 0, 0]
        case .overhand: [0, -1, 0]
        }
    }

    /// Cosine of the widest acceptable error, ~41°.
    ///
    /// The two orientations are 90° apart, so anything looser than cos(45°)
    /// makes a palm held exactly between them satisfy *both* — which is how
    /// the orientations stopped meaning anything. This leaves a small dead
    /// band in the middle instead: a hand that hasn't committed to either turn
    /// scores neither, which is the honest answer.
    static let tolerance: Float = 0.75

    func matches(palmNormal: SIMD3<Float>, hand: TrainingHand) -> Bool {
        guard length(palmNormal) > 0.1 else { return true }  // unknown → don't block
        return dot(normalize(palmNormal), requiredPalmNormal(for: hand)) >= Self.tolerance
    }
}
