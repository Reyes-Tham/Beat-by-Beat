//
//  ReachLevel.swift
//  BeatByBeat
//

import Foundation

/// Difficulty, as five stars.
///
/// The progression opens up the workspace before it adds any time pressure:
/// height first (1→3), then lateral range (3→4), and only then speed (4→5).
/// Reach demand and speed demand are kept separate so a patient is never asked
/// to move faster and further at the same time.
enum ReachLevel: Int, CaseIterable, Identifiable, Codable {
    case one = 1
    case two
    case three
    case four
    case five

    var id: Int { rawValue }

    var displayName: String { "\(rawValue)★" }

    /// What actually changes at this level.
    var summary: String {
        switch self {
        case .one:   "Own side, low — no crossing the middle"
        case .two:   "Own side, up to mid height"
        case .three: "Own side, full height"
        case .four:  "Own side plus centre — longer reaches"
        case .five:  "Own side plus centre, faster reaches"
        }
    }

    // MARK: - Pacing

    /// Time the player gets to travel to a target, in beats.
    ///
    /// Whole musical units on purpose: a reach that takes exactly two bars
    /// lands its contact on a downbeat, so the movement *is* the phrase.
    /// Only level 5 shortens it — 1 through 4 differ in space, not time.
    var travelBeats: Double {
        self == .five ? 4 : 8
    }

    /// Quiet beats after a target's beat before the next one appears.
    ///
    /// Never zero at any level. Without a rest the next target spawns the
    /// instant the last is contacted and the arms never stop moving; the rest
    /// is what makes this turn-taking rather than continuous work.
    var restBeats: Double { 4 }

    /// Beats between consecutive notes.
    ///
    /// Kept even so notes land on detected beats rather than on the
    /// interpolated midpoints of the beat grid.
    var spacingBeats: Double { travelBeats + restBeats }

    /// Beats between two notes for the *same* arm, when hands alternate.
    /// This is the number that decides whether a level feels restful.
    var perArmBeats: Double { spacingBeats * 2 }

    // MARK: - Workspace

    /// Vertical band of the spawn volume this level uses, 0 = bottom.
    /// Lower levels stay low so the patient isn't reaching overhead.
    var heightRange: ClosedRange<Float> {
        switch self {
        case .one:   0.00...0.32
        case .two:   0.00...0.58
        case .three, .four, .five: 0.00...1.00
        }
    }

    /// Whether a hand may use the middle of the volume.
    var allowsCentre: Bool { self == .four || self == .five }

    /// Horizontal band a given hand may spawn in, 0 = player's left.
    ///
    /// Levels 1–3 keep each arm on its own side with a gap through the middle,
    /// so neither arm is asked to cross the body. Levels 4–5 open the centre,
    /// which lengthens the reaches available to both.
    func horizontalRange(for hand: TrainingHand) -> ClosedRange<Float> {
        switch hand {
        case .left:  allowsCentre ? 0.00...0.62 : 0.00...0.42
        case .right: allowsCentre ? 0.38...1.00 : 0.58...1.00
        case .both:  0.00...1.00
        }
    }

    /// Depth band. Trimmed away from the volume's front and back faces so
    /// targets don't sit on the very edge of the reachable box.
    var depthRange: ClosedRange<Float> { 0.20...0.80 }

    /// Largest jump between consecutive targets *for the same arm*, in unit
    /// space. The coordination axis: small = local adjustments, large = a
    /// planned trajectory across the workspace.
    var maxStep: Float {
        switch self {
        case .one: 0.30
        case .two: 0.40
        case .three: 0.50
        case .four: 0.65
        case .five: 0.80
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
