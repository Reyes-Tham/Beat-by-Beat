//
//  TrainingHand.swift
//  BeatByBeat
//

import Foundation

/// Which arm the session is training. Hits from the other hand are ignored
/// during Reach Mode so the stronger side can't compensate.
enum TrainingHand: String, Codable, CaseIterable {
    case left, right, both

    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .both: "Both"
        }
    }

    /// +1 for the right side, -1 for the left. Used to mirror the
    /// training-side diagonal. `both` is treated as right-handed.
    var lateralSign: Float {
        self == .left ? -1 : 1
    }
}
