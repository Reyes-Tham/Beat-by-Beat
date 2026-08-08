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
    /// Where the object has to be carried to, as an offset in unit space.
    ///
    /// Chosen to match the object: a mug slides across the surface it is on,
    /// while something picked up overhand is lifted and set down higher. Both
    /// legs stay inside the arm's own calibrated box.
    func carryOffset(for hand: TrainingHand) -> SIMD3<Float> {
        switch self {
        case .cup:      [0.34 * (hand == .left ? 1 : -1), 0, 0]  // across, toward the midline
        case .overhand: [0, 0.30, 0]                              // lift and place higher
        }
    }

    /// The approach this orientation asks for.
    ///
    /// Approach, not palm facing. Asking which way the wrist is turned demands
    /// a textbook hand pose and fails as soon as someone comes at the object
    /// from a natural angle. Asking where the object sits relative to the palm
    /// describes the same two tasks without caring how the hand got there —
    /// and it is checked only at the moment of the grab, so the arm is free to
    /// travel however it likes on the way in.
    var approach: ApproachDirection {
        switch self {
        case .cup: .side
        case .overhand: .top
        }
    }

    func matches(approach direction: ApproachDirection) -> Bool {
        direction == approach
    }
}
