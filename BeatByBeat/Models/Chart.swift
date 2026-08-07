//
//  Chart.swift
//  BeatByBeat
//

import Foundation
import simd

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

    private enum CodingKeys: String, CodingKey {
        case time, travel, hand, x, y, z
    }

    init(time: TimeInterval, travel: TimeInterval, hand: TrainingHand, unit: SIMD3<Float>) {
        self.time = time
        self.travel = travel
        self.hand = hand
        self.unit = unit
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encode(travel, forKey: .travel)
        try container.encode(hand, forKey: .hand)
        try container.encode(unit.x, forKey: .x)
        try container.encode(unit.y, forKey: .y)
        try container.encode(unit.z, forKey: .z)
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
        level: ReachLevel,
        hand: TrainingHand
    ) -> Chart {
        let beats = beatMap.beats
        let travelBeats = Int(level.travelBeats)
        let spacing = Int(level.spacingBeats)

        var notes: [ChartNote] = []
        var cursor = SIMD3<Float>(0.5, 0.5, 0.5)
        var index = travelBeats  // leave room for the first note's approach
        var placed = 0

        while index < beats.count {
            cursor = step(from: cursor, maxStep: level.maxStep)
            notes.append(ChartNote(
                time: beats[index],
                // Travel spans real beats, so it tracks any tempo drift in the
                // song instead of assuming a constant period.
                travel: beats[index] - beats[index - travelBeats],
                hand: hand == .both ? (placed.isMultiple(of: 2) ? .left : .right) : hand,
                unit: cursor
            ))
            index += spacing
            placed += 1
        }

        return Chart(songId: beatMap.songId, bpm: beatMap.bpm, notes: notes)
    }

    /// Fallback for when no beat map is bundled: a plain constant-tempo grid.
    static func generated(
        bpm: Double,
        level: ReachLevel,
        hand: TrainingHand,
        seconds: TimeInterval = 120
    ) -> Chart {
        let beatDuration = 60.0 / bpm
        let count = Int(seconds / beatDuration)
        let synthetic = BeatMap(
            songId: "generated",
            bpm: bpm,
            beats: (0..<count).map { Double($0) * beatDuration }
        )
        return build(from: synthetic, level: level, hand: hand)
    }

    /// Random walk through the unit cube, clamped to the box.
    ///
    /// Not fully random: consecutive notes stay within `maxStep` of each other.
    /// That's the coordination knob — small steps are short adjustments, large
    /// steps cross the body and demand a planned trajectory. Pure random
    /// placement can't express that at all.
    private static func step(from current: SIMD3<Float>, maxStep: Float) -> SIMD3<Float> {
        for _ in 0..<12 {
            let delta = SIMD3<Float>(
                .random(in: -maxStep...maxStep),
                .random(in: -maxStep...maxStep),
                .random(in: -maxStep...maxStep) * 0.5  // depth varies less
            )
            let candidate = clamp(current + delta, min: .init(repeating: 0), max: .init(repeating: 1))
            // Reject a step that barely moves; a target on top of the last one
            // is not a reach.
            if distance(candidate, current) > maxStep * 0.4 { return candidate }
        }
        return SIMD3(.random(in: 0...1), .random(in: 0...1), .random(in: 0...1))
    }
}
