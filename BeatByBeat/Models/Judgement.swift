//
//  ReachLevel.swift
//  BeatByBeat
//

import Foundation

/// How close contact was to the beat.
///
/// Windows are a *fraction of travel time*, not fixed milliseconds. A ±100 ms
/// window on a four-second reach is 2.5% and would be absurd; scaling keeps the
/// felt difficulty the same for a slow mover and a fast one.
enum Judgement: String, CaseIterable, Codable {
    case excellent
    case good
    case reached

    static func judge(offset: TimeInterval, travelTime: TimeInterval) -> Judgement {
        let error = abs(offset) / max(travelTime, 0.001)
        return switch error {
        case ..<0.10: .excellent
        case ..<0.25: .good
        default: .reached
        }
    }

    var displayName: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .reached: "Reached"
        }
    }

    /// What the player sees pop up on a hit.
    ///
    /// The weakest tier still reads as success: they got their arm there,
    /// which is the movement goal. Only the rhythm was loose, and that isn't
    /// worth telling a patient off about.
    var praise: String {
        switch self {
        case .excellent: "Excellent!"
        case .good: "Good!"
        case .reached: "Okay!"
        }
    }
}

/// Outcome of a single note. Kept separate from `Judgement` because reaching
/// late is a different thing from never reaching, and both are different from
/// the headset losing track of the hand.
enum NoteOutcome: Equatable {
    case hit(Judgement)
    case notReached
    case trackingSkipped
}
