//
//  Chart.swift
//  BeatByBeat
//

import Foundation
import simd

extension ClosedRange where Bound == Float {
    var mid: Float { (lowerBound + upperBound) / 2 }
    func clamping(_ value: Float) -> Float {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

/// Where the beats actually fall in a song, in seconds.
///
/// Stored as timestamps rather than a tempo, because a tempo plus a grid drifts
/// against the recording — a 0.5 BPM error is a whole beat by the end of a
/// three-minute song. Timestamps can't drift, and they follow a song that
/// speeds up or slows down for free.
struct BeatMap: Codable {
    var songId: String
    /// Nominal tempo, for display and for deriving travel times only.
    var bpm: Double
    var beats: [TimeInterval]

    static func load(resource: String) -> BeatMap? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        do {
            return try JSONDecoder().decode(BeatMap.self, from: data)
        } catch {
            print("[BeatMap] failed to decode \(resource).json: \(error)")
            return nil
        }
    }
}

/// One note, in normalized space and absolute song time.
///
/// Holds no metres: `unit` is a position inside the unit cube, which
/// `SpawnVolume` maps into the world — so the same chart plays at any size,
/// and swapping the fixed volume for a calibrated one later changes nothing
/// here. That separation is the whole point (plan §6).
struct ChartNote: Codable, Equatable {
    /// Song time the target should be contacted at.
    var time: TimeInterval
    /// How long the player gets to travel to it.
    var travel: TimeInterval
    /// Which hand must reach it.
    var hand: TrainingHand
    /// Position within the spawn volume, each axis 0...1.
    var unit: SIMD3<Float>
    /// What the player has to do when they get there.
    var movement: MovementType = .reach
    /// How the hand must be turned. Grip notes only.
    var gripOrientation: GripOrientation?

    private enum CodingKeys: String, CodingKey {
        case time, travel, hand, x, y, z, movement, gripOrientation
    }

    init(
        time: TimeInterval,
        travel: TimeInterval,
        hand: TrainingHand,
        unit: SIMD3<Float>,
        movement: MovementType = .reach,
        gripOrientation: GripOrientation? = nil
    ) {
        self.time = time
        self.travel = travel
        self.hand = hand
        self.unit = unit
        self.movement = movement
        self.gripOrientation = gripOrientation
    }

    // SIMD3 isn't usefully Codable, so x/y/z go over the wire separately.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(TimeInterval.self, forKey: .time)
        travel = try container.decode(TimeInterval.self, forKey: .travel)
        hand = try container.decode(TrainingHand.self, forKey: .hand)
        unit = SIMD3(
            try container.decode(Float.self, forKey: .x),
            try container.decode(Float.self, forKey: .y),
            try container.decode(Float.self, forKey: .z)
        )
        movement = try container.decodeIfPresent(MovementType.self, forKey: .movement) ?? .reach
        gripOrientation = try container.decodeIfPresent(
            GripOrientation.self, forKey: .gripOrientation
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encode(travel, forKey: .travel)
        try container.encode(hand, forKey: .hand)
        try container.encode(unit.x, forKey: .x)
        try container.encode(unit.y, forKey: .y)
        try container.encode(unit.z, forKey: .z)
        try container.encode(movement, forKey: .movement)
        try container.encodeIfPresent(gripOrientation, forKey: .gripOrientation)
    }
}

struct Chart {
    var songId: String
    var bpm: Double
    var notes: [ChartNote]
}

// MARK: - Building

extension Chart {

    /// Builds a chart by picking notes off a song's real beat grid.
    ///
    /// Difficulty chooses *which* beats get notes and how many beats of travel
    /// each one allows; the timestamps come from the song. Because every
    /// level's spacing is even and the grid holds interpolated midpoints,
    /// notes land on detected beats rather than on interpolated ones.
    static func build(
        from beatMap: BeatMap,
        profile: ReachProfile,
        hand: TrainingHand,
        movements: Set<MovementType> = [.reach],
        gripOrientations: Set<GripOrientation> = [.cup],
        speedScale: Double = 1
    ) -> Chart {
        // Never empty: with nothing selected there would be no chart at all.
        let palette = movements.isEmpty ? [MovementType.reach]
                                        : MovementType.allCases.filter(movements.contains)
        let grips = gripOrientations.isEmpty ? [GripOrientation.cup]
                                             : GripOrientation.allCases.filter(gripOrientations.contains)
        // One bag per arm rather than one shared: this way each arm is
        // handed every selected movement, which is what a therapist ticking
        // three of them is asking for. A shared bag only evens out across the
        // pair, so one arm could still see far more of one movement.
        var movementBags: [TrainingHand: ShuffleBag<MovementType>] = [:]
        var gripBag = ShuffleBag(grips)
        let beats = beatMap.beats
        // Floors of 1 and 2: a chart with zero travel would spawn targets on
        // top of their own beat, and zero spacing would never advance.
        let travelBeats = max(1, Int(profile.travelBeats / speedScale))
        let spacing = max(2, Int(profile.spacingBeats / speedScale))

        var notes: [ChartNote] = []
        // One cursor per arm, so each arm's successive targets relate to each
        // other. A single shared cursor would make every step a jump across
        // the body, since consecutive notes alternate sides.
        var cursors: [TrainingHand: SIMD3<Float>] = [:]
        var index = travelBeats  // leave room for the first note's approach
        var placed = 0

        while index < beats.count {
            let noteHand: TrainingHand = hand == .both
                ? (placed.isMultiple(of: 2) ? .left : .right)
                : hand
            let box = UnitBox(profile: profile, hand: noteHand)
            let position = step(
                from: cursors[noteHand] ?? box.centre,
                maxStep: profile.maxStep,
                within: box
            )
            cursors[noteHand] = position

            // Drawn from a shuffled bag, not cycled. Cycling walked the
            // palette in step with the alternating hands, so with two
            // movements ticked one arm got every pour and the other every
            // reach, for the whole song.
            var bag = movementBags[noteHand] ?? ShuffleBag(palette)
            let movement = bag.next() ?? .reach
            movementBags[noteHand] = bag

            var orientation: GripOrientation?
            if movement == .grip {
                orientation = gripBag.next()
            }
            // Travel spans real beats, so it tracks any tempo drift in the
            // song instead of assuming a constant period. Capped at the gap to
            // the note before it: the slower movements stretch their approach
            // by up to 1.6x, which at some levels is longer than the spacing —
            // and a target that appears before the last one's beat has passed
            // puts two of them in the air for the same arm.
            let approach = (beats[index] - beats[index - travelBeats])
                * movement.travelMultiplier
            let gap = index >= spacing
                ? beats[index] - beats[index - spacing]
                : Double.greatestFiniteMagnitude
            notes.append(ChartNote(
                time: beats[index],
                travel: min(approach, gap * 0.95),
                hand: noteHand,
                unit: position,
                movement: movement,
                gripOrientation: orientation
            ))
            index += spacing
            placed += 1
        }

        return Chart(songId: beatMap.songId, bpm: beatMap.bpm, notes: notes)
    }

    /// The slice of the unit cube a given hand may use at a given level.
    private struct UnitBox {
        var x: ClosedRange<Float>
        var y: ClosedRange<Float>
        var z: ClosedRange<Float>

        init(profile: ReachProfile, hand: TrainingHand) {
            x = profile.horizontalRange(for: hand)
            y = profile.heightRange
            z = profile.depthRange
        }

        var centre: SIMD3<Float> {
            SIMD3(x.mid, y.mid, z.mid)
        }

        func clamp(_ p: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(x.clamping(p.x), y.clamping(p.y), z.clamping(p.z))
        }

        func randomPoint() -> SIMD3<Float> {
            SIMD3(.random(in: x), .random(in: y), .random(in: z))
        }
    }

    /// Fallback for when no beat map is bundled: a plain constant-tempo grid.
    static func generated(
        bpm: Double,
        profile: ReachProfile,
        hand: TrainingHand,
        movements: Set<MovementType> = [.reach],
        gripOrientations: Set<GripOrientation> = [.cup],
        speedScale: Double = 1,
        seconds: TimeInterval = 120
    ) -> Chart {
        let beatDuration = 60.0 / bpm
        let count = Int(seconds / beatDuration)
        let synthetic = BeatMap(
            songId: "generated",
            bpm: bpm,
            beats: (0..<count).map { Double($0) * beatDuration }
        )
        return build(from: synthetic, profile: profile, hand: hand,
                     movements: movements, gripOrientations: gripOrientations,
                     speedScale: speedScale)
    }

    /// Random walk inside one arm's allowed box.
    ///
    /// Not fully random: consecutive targets for the same arm stay within
    /// `maxStep` of each other. That's the coordination knob — small steps are
    /// short adjustments, large steps demand a planned trajectory. Pure random
    /// placement can't express that at all.
    private static func step(
        from current: SIMD3<Float>,
        maxStep: Float,
        within box: UnitBox
    ) -> SIMD3<Float> {
        let start = box.clamp(current)
        for _ in 0..<16 {
            let delta = SIMD3<Float>(
                .random(in: -maxStep...maxStep),
                .random(in: -maxStep...maxStep),
                .random(in: -maxStep...maxStep) * 0.5  // depth varies less
            )
            let candidate = box.clamp(start + delta)
            // Reject a step that barely moves; a target on top of the last one
            // is not a reach. The threshold is relative to the box, so a
            // narrow band at level 1 doesn't reject every candidate.
            if distance(candidate, start) > maxStep * 0.3 { return candidate }
        }
        return box.randomPoint()
    }
}
