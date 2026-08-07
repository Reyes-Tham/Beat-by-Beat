//
//  ReachLevel.swift
//  BeatByBeat
//

import Foundation

/// Difficulty. Scales *speed and coordination*, not how far the player has to
/// reach — reach distance belongs to the spawn volume (and later, calibration).
///
/// Only the three anchors are implemented. Levels 2 and 4 are interpolation
/// once these feel right, which is why the raw values are 1/3/5.
enum ReachLevel: Int, CaseIterable, Identifiable, Codable {
    case minimal = 1
    case moderate = 3
    case challenge = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .minimal: "Minimal"
        case .moderate: "Moderate"
        case .challenge: "Challenge"
        }
    }

    /// Time the player gets to travel to a target, in beats.
    ///
    /// Whole musical units on purpose: a reach that takes exactly two bars
    /// lands its contact on a downbeat, so the movement *is* the phrase.
    var travelBeats: Double {
        switch self {
        case .minimal: 8      // 2 bars
        case .moderate: 4     // 1 bar
        case .challenge: 2    // half a bar
        }
    }

    /// Quiet beats after a target's beat before the next one appears.
    ///
    /// Without this the next target spawns the instant the last is contacted,
    /// so the arms never stop moving. At Minimal the rest is what turns the
    /// chart into clear turn-taking: reach, return, then the other arm goes.
    var restBeats: Double {
        switch self {
        case .minimal: 4      // ~1.7s of stillness between reaches
        case .moderate: 2
        case .challenge: 0    // continuous
        }
    }

    /// Beats between consecutive notes.
    ///
    /// Kept even so notes land on detected beats rather than on the
    /// interpolated midpoints of the beat grid.
    var spacingBeats: Double { travelBeats + restBeats }

    /// Beats between two notes for the *same* arm, when hands alternate.
    /// This is the number that decides whether Minimal feels restful.
    var perArmBeats: Double { spacingBeats * 2 }

    /// Largest jump between consecutive notes, in unit-cube space.
    /// This is the coordination axis: small = local adjustments, large =
    /// crossing the midline and planning a trajectory.
    var maxStep: Float {
        switch self {
        case .minimal: 0.35
        case .moderate: 0.55
        case .challenge: 0.90
        }
    }
}

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
}

/// Outcome of a single note. Kept separate from `Judgement` because reaching
/// late is a different thing from never reaching, and both are different from
/// the headset losing track of the hand.
enum NoteOutcome: Equatable {
    case hit(Judgement)
    case notReached
    case trackingSkipped
}
