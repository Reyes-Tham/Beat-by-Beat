//
//  MobilityDemand.swift
//  BeatByBeat
//

import Foundation

/// One demand a session can make of the arm, switched on or off by itself.
///
/// This replaced a single 1–5 ladder where each level added the next demand on
/// top of the last, so asking for height meant accepting distance too. Recovery
/// does not arrive in that order for everybody: an arm can have usable forward
/// reach and no lift at all, or the reverse, and a therapist working on one
/// direction had no way to ask for it alone.
///
/// Nothing ticked is not "no session" — it is the gentlest one: short reaches
/// straight ahead at chest height, close in, with long rests. Every demand
/// opens one axis of the workspace out from there.
///
/// The ordering below is still the one the ladder used, and it is worth keeping
/// in mind when choosing: post-stroke reaching is dominated by synergy
/// coupling. Reaching forward near the midline moves *with* the extensor
/// synergy and is easiest; lifting and reaching wide have to break out of the
/// flexor synergy, and abduction loading costs elbow extension range on top.
///
/// A design heuristic informed by clinical models, not an assessment. The app
/// measures where a hand can go; that isn't staging motor recovery.
enum MobilityDemand: String, CaseIterable, Identifiable, Codable {
    /// Targets further out in front — the elbow has to straighten.
    case distance
    /// Targets higher up — the shoulder has to lift against gravity.
    case height
    /// Targets out to the side rather than in front of the body.
    case width
    /// Longer jumps between one target and the next.
    case travel
    /// Less time to get there.
    case speed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .distance: "Reach further"
        case .height: "Reach higher"
        case .width: "Reach wider"
        case .travel: "Bigger steps"
        case .speed: "Move faster"
        }
    }

    /// Plain words, for the patient.
    var detail: String {
        switch self {
        case .distance: "Targets further in front, so the elbow straightens"
        case .height: "Targets higher up, lifting the arm against gravity"
        case .width: "Targets out to the side, away from the body"
        case .travel: "Longer distances from one target to the next"
        case .speed: "Less time to get there, and shorter rests"
        }
    }

    /// The movement being trained, for the therapist.
    var clinicalTerm: String {
        switch self {
        case .distance: "Elbow extension"
        case .height: "Shoulder flexion"
        case .width: "Shoulder abduction"
        case .travel: "Coordination"
        case .speed: "Speed and timing"
        }
    }

    var symbol: String {
        switch self {
        case .distance: "arrow.up.forward"
        case .height: "arrow.up"
        case .width: "arrow.left.and.right"
        case .travel: "point.topleft.down.to.point.bottomright.curvepath"
        case .speed: "hare"
        }
    }

    /// Spatial demands, as opposed to the ones about pace.
    ///
    /// Kept separate because the old ladder never raised space and speed
    /// together, and that restraint is worth keeping visible now that both can
    /// be ticked at once.
    static let spatial: [MobilityDemand] = [.distance, .height, .width, .travel]

    // MARK: - Persistence

    private static let storageKey = "mobilityDemands"

    /// Defaults to distance and height — the two the old three-star setting
    /// asked for, so an existing patient's session is unchanged by the switch
    /// to choosing them individually.
    static func loadSaved() -> Set<MobilityDemand> {
        guard let raw = UserDefaults.standard.array(forKey: storageKey) as? [String] else {
            return [.distance, .height]
        }
        return Set(raw.compactMap(MobilityDemand.init(rawValue:)))
    }

    static func save(_ demands: Set<MobilityDemand>) {
        UserDefaults.standard.set(demands.map(\.rawValue), forKey: storageKey)
    }
}

/// What the chart builder needs, worked out from the demands that are on.
///
/// Everything here used to hang off the ladder's level number. Deriving it from
/// a set instead is what lets the demands be chosen freely while the numbers
/// they produce stay exactly the ones the levels used to produce.
struct ReachProfile {
    var demands: Set<MobilityDemand>

    init(_ demands: Set<MobilityDemand> = []) {
        self.demands = demands
    }

    private func on(_ demand: MobilityDemand) -> Bool { demands.contains(demand) }

    // MARK: - Pacing

    /// Time the player gets to travel to a target, in beats.
    ///
    /// Whole musical units on purpose: a reach that takes exactly two bars
    /// lands its contact on a downbeat, so the movement *is* the phrase.
    var travelBeats: Double { on(.speed) ? 4 : 8 }

    /// Quiet beats after a target's beat before the next one appears.
    ///
    /// Longest with nothing ticked and never zero. Fatigue is a bigger
    /// constraint after a stroke than people expect, and tolerance for
    /// sustained work is itself part of what recovers — so rest shortens as
    /// more is asked for, rather than being constant.
    /// Even numbers only. Spacing has to stay even so notes land on detected
    /// beats rather than on the interpolated midpoints of the beat grid, and
    /// travel is already even.
    var restBeats: Double {
        switch demands.count {
        case 0: 8
        case 1, 2: 6
        default: 4
        }
    }

    /// Beats between consecutive notes.
    var spacingBeats: Double { travelBeats + restBeats }

    /// Beats between two notes for the *same* arm, when hands alternate.
    /// This is the number that decides whether a session feels restful.
    var perArmBeats: Double { spacingBeats * 2 }

    // MARK: - Workspace

    /// Vertical band of the volume, 0 = bottom.
    ///
    /// A narrow band at chest height — the natural resting height for a reach —
    /// until height is asked for, and then mostly upward: 10% of the box
    /// downward against 35% up. Gravity assists a downward reach, so lifting is
    /// the demand worth adding, and a band that opened equally both ways would
    /// have spent half of "reach higher" on the easier direction.
    var heightRange: ClosedRange<Float> {
        on(.height) ? 0.30...0.95 : 0.40...0.60
    }

    /// Depth band, 0 = furthest from the player, 1 = closest.
    ///
    /// Stays close in, where the elbow is still flexed, until distance is asked
    /// for — opening the far end is what turns a reach into an elbow extension.
    var depthRange: ClosedRange<Float> {
        on(.distance) ? 0.15...0.90 : 0.60...0.90
    }

    /// Whether targets may sit out to the side rather than in front.
    var allowsLateral: Bool { on(.width) }

    /// Horizontal band a given hand may spawn in, 0 = player's left.
    ///
    /// Both arms work near the midline, slightly biased to their own side — the
    /// position where the extensor synergy helps rather than hinders — until
    /// width is asked for, which opens the full span and with it the shoulder
    /// abduction that has to break out of the flexor synergy.
    func horizontalRange(for hand: TrainingHand) -> ClosedRange<Float> {
        switch hand {
        case .left:  allowsLateral ? 0.00...0.62 : 0.28...0.55
        case .right: allowsLateral ? 0.38...1.00 : 0.45...0.72
        case .both:  0.00...1.00
        }
    }

    /// Largest jump between consecutive targets *for the same arm*, in unit
    /// space. Small means local adjustments; large means a planned trajectory
    /// across the workspace.
    var maxStep: Float { on(.travel) ? 0.70 : 0.20 }

    // MARK: - Description

    /// A stable code for the exact combination, for keying best scores.
    ///
    /// Sorted so the same set always produces the same string, whatever order
    /// the demands were ticked in.
    var code: String {
        demands.isEmpty ? "base" : demands.map(\.rawValue).sorted().joined(separator: "+")
    }

    /// What this asks for, in plain words.
    var summary: String {
        guard !demands.isEmpty else {
            return "Short reaches straight ahead, chest height, close in — long rests"
        }
        return MobilityDemand.allCases
            .filter(demands.contains)
            .map(\.displayName)
            .joined(separator: " · ")
    }

    /// Whether pace is being asked for on top of most of the space.
    ///
    /// Not a block — a therapist can ask for whatever they mean to. But the
    /// ladder deliberately never raised space and speed together, and somebody
    /// ticking everything should see that said once.
    var pushesSpaceAndSpeed: Bool {
        on(.speed) && demands.intersection(Set(MobilityDemand.spatial)).count >= 3
    }
}
