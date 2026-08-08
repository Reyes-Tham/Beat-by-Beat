//
//  GripOrientation.swift
//  BeatByBeat
//

import Foundation
import simd

/// How the hand has to be turned to take hold of a target.
///
/// Named for real objects rather than for anatomy, because that is how a
/// patient will think about the movement — and because reaching for a cup and
/// reaching for a door knob are genuinely different tasks even though the arm
/// travels the same distance.
///
/// Forearm rotation is commonly impaired after a stroke, so every orientation
/// is opt-in and the tolerance is deliberately wide. This trains turning the
/// hand; it does not measure how far it turned.
enum GripOrientation: String, CaseIterable, Identifiable, Codable {
    /// Palm toward the midline, as if closing around a cup.
    case cup
    /// Palm forward, as if taking a door knob.
    case knob
    /// Palm down, as if picking something off a table.
    case overhand
    /// Palm up, as if receiving something.
    case underhand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cup: "Cup"
        case .knob: "Door knob"
        case .overhand: "Overhand"
        case .underhand: "Underhand"
        }
    }

    var detail: String {
        switch self {
        case .cup: "Palm inward, closing around a glass"
        case .knob: "Palm forward, as if turning a handle"
        case .overhand: "Palm down, lifting off a table"
        case .underhand: "Palm up, taking something offered"
        }
    }

    /// How far the icon is turned on the target, in radians.
    var iconRotation: Float {
        switch self {
        case .knob: 0
        case .cup: .pi / 2
        case .overhand: .pi
        case .underhand: -.pi / 2
        }
    }

    /// Palm direction this orientation asks for, in world space.
    ///
    /// The cup grip mirrors: each hand closes toward the body's midline, so a
    /// right hand's palm faces left and a left hand's faces right.
    func requiredPalmNormal(for hand: TrainingHand) -> SIMD3<Float> {
        switch self {
        case .knob:      [0, 0, -1]                       // away from the player
        case .cup:       [hand == .left ? 1 : -1, 0, 0]   // toward the midline
        case .overhand:  [0, -1, 0]
        case .underhand: [0, 1, 0]
        }
    }

    /// Cosine of the widest acceptable error. 60° — generous on purpose:
    /// a narrow window would be measuring pronation and supination range
    /// rather than training the reach-and-turn.
    static let tolerance: Float = 0.5

    func matches(palmNormal: SIMD3<Float>, hand: TrainingHand) -> Bool {
        let required = requiredPalmNormal(for: hand)
        guard length(palmNormal) > 0.1 else { return true }  // unknown → don't block
        return dot(normalize(palmNormal), required) >= Self.tolerance
    }
}
