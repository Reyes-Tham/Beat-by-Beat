//
//  MovementType.swift
//  BeatByBeat
//

import Foundation

/// The kinds of movement a session can ask for.
///
/// Selected as a set rather than a level, because these train different things
/// and a patient may be working on one and not another. Reaching is gross arm
/// transport; pouring is a controlled trajectory; gripping is hand function;
/// turning is forearm rotation; holding is steadiness once the arm is there.
/// Someone can have a usable reach and no grasp, or the reverse.
enum MovementType: String, CaseIterable, Identifiable, Codable {
    case reach
    case pour
    case grip
    case rotate
    case hold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reach: "Reach"
        case .pour: "Pour"
        case .grip: "Grip"
        case .rotate: "Turn"
        case .hold: "Hold"
        }
    }

    var detail: String {
        switch self {
        case .reach: "Move the hand to a target"
        case .pour: "Guide the hand along a curved path"
        case .grip: "Close the hand on the target"
        case .rotate: "Turn the palm from face-down to face-up"
        case .hold: "Keep the hand steady on the target"
        }
    }

    var symbol: String {
        switch self {
        case .reach: "hand.point.up.left"
        case .pour: "wave.3.right"
        case .grip: "hand.pinch"
        case .rotate: "arrow.trianglehead.clockwise.rotate.90"
        case .hold: "hand.raised"
        }
    }

    /// How much longer than a plain reach this needs.
    ///
    /// A pour is a whole trajectory. Grip adds a hand action once the arm
    /// arrives. Turning the forearm is slower still: supination is usually the
    /// most restricted movement a hemiparetic arm has, and rushing it just
    /// produces a shoulder swing instead. Holding needs the time it is held
    /// for, on top of getting there.
    var travelMultiplier: Double {
        switch self {
        case .reach: 1.0
        case .pour: 1.5
        case .grip: 1.25
        case .rotate: 1.6
        case .hold: 1.4
        }
    }

    /// Whether the movement asks for something once the hand has arrived,
    /// rather than being over on contact.
    var isTwoStage: Bool {
        switch self {
        case .reach, .pour: false
        case .grip, .rotate, .hold: true
        }
    }
}
