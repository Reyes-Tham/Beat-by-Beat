//
//  MovementType.swift
//  BeatByBeat
//

import Foundation

/// The kinds of movement a session can ask for.
///
/// Selected as a set rather than a level, because these train different things
/// and a patient may be working on one and not another. Reaching is gross arm
/// transport; pouring is a controlled trajectory with forearm rotation;
/// gripping is hand function. Someone can have a usable reach and no grasp, or
/// the reverse.
enum MovementType: String, CaseIterable, Identifiable, Codable {
    case reach
    case pour
    case grip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reach: "Reach"
        case .pour: "Pour"
        case .grip: "Grip"
        }
    }

    var detail: String {
        switch self {
        case .reach: "Move the hand to a target"
        case .pour: "Guide the hand along a curved path"
        case .grip: "Pick it up, carry it, and set it down"
        }
    }

    var symbol: String {
        switch self {
        case .reach: "hand.point.up.left"
        case .pour: "wave.3.right"
        case .grip: "hand.pinch"
        }
    }

    /// Pour and grip take longer than a plain reach: one is a whole trajectory,
    /// the other adds a hand action once the arm arrives.
    var travelMultiplier: Double {
        switch self {
        case .reach: 1.0
        case .pour: 1.5
        // Two legs now — reach to it, then carry it somewhere — so it needs
        // roughly twice a plain reach rather than a little extra.
        case .grip: 2.0
        }
    }
}
