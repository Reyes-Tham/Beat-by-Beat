//
//  ReachLevel.swift
//  BeatByBeat
//

import Foundation

/// Difficulty, as five stars.
///
/// Ordered by what is actually hard after a stroke rather than by how big the
/// movement looks. Post-stroke reaching is dominated by synergy coupling: the
/// extensor synergy links shoulder adduction with elbow extension, so reaching
/// **forward and near the midline with an extended elbow moves with the
/// synergy** and is easiest. Reaching laterally or overhead with an extended
/// elbow fights the flexor synergy and is much harder. Raising the arm against
/// gravity compounds it further — abduction loading costs elbow extension
/// range.
///
/// So the progression is: centre-forward and near (1) → forward distance,
/// demanding elbow extension (2) → height, demanding shoulder flexion against
/// gravity (3) → lateral, breaking synergy (4) → speed and timing (5).
///
/// Rest also shortens as levels rise, because fatigue tolerance is itself part
/// of what recovers. Reach demand and speed demand stay separate: nobody is
/// asked to move faster and further at the same time.
///
/// This is a design heuristic informed by clinical models, not an assessment.
/// The app measures where a hand can go; that isn't staging motor recovery.
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
        case .one:   "Centre, chest height, close in — long rests"
        case .two:   "Adds forward distance — elbow extension"
        case .three: "Adds height — reaching up against gravity"
        case .four:  "Adds width — reaching out to the side"
        case .five:  "Same space, faster reaches"
        }
    }

    /// The movement each level is asking for, in plain words.
    var focus: String {
        switch self {
        case .one:   "Short reaches straight ahead"
        case .two:   "Straightening the elbow"
        case .three: "Lifting the arm"
        case .four:  "Reaching away from the body"
        case .five:  "Moving to time"
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
    /// Longest at level 1 and never zero. Fatigue is a bigger constraint after
    /// a stroke than people expect, and tolerance for sustained work is itself
    /// part of what recovers — so rest shortens as the levels rise rather than
    /// being constant.
    var restBeats: Double {
        switch self {
        case .one: 8
        case .two: 6
        case .three, .four, .five: 4
        }
    }

    /// Beats between consecutive notes.
    ///
    /// Kept even so notes land on detected beats rather than on the
    /// interpolated midpoints of the beat grid.
    var spacingBeats: Double { travelBeats + restBeats }

    /// Beats between two notes for the *same* arm, when hands alternate.
    /// This is the number that decides whether a level feels restful.
    var perArmBeats: Double { spacingBeats * 2 }

    // MARK: - Workspace

    /// Vertical band of the volume, 0 = bottom.
    ///
    /// Starts as a narrow band at chest height — the natural resting height for
    /// a reach — and opens at level 3, mostly upward: 10% of the box downward
    /// against 35% up. Gravity assists a downward reach, so lifting is the
    /// demand worth adding, and a band that opened equally both ways would have
    /// spent half of "adds height" on the easier direction.
    var heightRange: ClosedRange<Float> {
        switch self {
        case .one, .two: 0.40...0.60
        case .three, .four, .five: 0.30...0.95
        }
    }

    /// Depth band, 0 = furthest from the player, 1 = closest.
    ///
    /// Level 1 stays close in, where the elbow is still flexed. Level 2 opens
    /// the far end, which is what turns a reach into an elbow extension.
    var depthRange: ClosedRange<Float> {
        switch self {
        case .one: 0.60...0.90
        case .two, .three, .four, .five: 0.15...0.90
        }
    }

    /// Whether targets may sit out to the side rather than in front.
    var allowsLateral: Bool { self == .four || self == .five }

    /// Horizontal band a given hand may spawn in, 0 = player's left.
    ///
    /// Levels 1–3 keep both arms working near the midline, slightly biased to
    /// their own side — the position where the extensor synergy helps rather
    /// than hinders. Level 4 opens the full width, which is the shoulder
    /// abduction that has to break out of the flexor synergy.
    func horizontalRange(for hand: TrainingHand) -> ClosedRange<Float> {
        switch hand {
        case .left:  allowsLateral ? 0.00...0.62 : 0.28...0.55
        case .right: allowsLateral ? 0.38...1.00 : 0.45...0.72
        case .both:  0.00...1.00
        }
    }

    /// Largest jump between consecutive targets *for the same arm*, in unit
    /// space. The coordination axis: small = local adjustments, large = a
    /// planned trajectory across the workspace.
    var maxStep: Float {
        switch self {
        case .one: 0.20
        case .two: 0.30
        case .three: 0.45
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
