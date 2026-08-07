//
//  Chart.swift
//  BeatByBeat
//

import Foundation
import simd

/// One note, in normalized space.
///
/// Deliberately holds no metres. `unit` is a position inside the unit cube,
/// which `SpawnVolume` maps into the world — so the same chart plays at any
/// size, and swapping the fixed volume for a calibrated one later changes
/// nothing here. That separation is the whole point (plan §6).
struct ChartNote: Codable, Equatable {
    /// Musical position, in beats from the start of the song.
    var beat: Double
    /// Which hand must reach it.
    var hand: TrainingHand
    /// Position within the spawn volume, each axis 0...1.
    var unit: SIMD3<Float>
    /// How long the player gets to travel to it, in beats.
    var travelBeats: Double

    private enum CodingKeys: String, CodingKey {
        case beat, hand, x, y, z, travelBeats
    }

    init(beat: Double, hand: TrainingHand, unit: SIMD3<Float>, travelBeats: Double) {
        self.beat = beat
        self.hand = hand
        self.unit = unit
        self.travelBeats = travelBeats
    }

    // SIMD3 isn't usefully Codable, so x/y/z go over the wire separately.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beat = try container.decode(Double.self, forKey: .beat)
        hand = try container.decode(TrainingHand.self, forKey: .hand)
        unit = SIMD3(
            try container.decode(Float.self, forKey: .x),
            try container.decode(Float.self, forKey: .y),
            try container.decode(Float.self, forKey: .z)
        )
        travelBeats = try container.decode(Double.self, forKey: .travelBeats)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(beat, forKey: .beat)
        try container.encode(hand, forKey: .hand)
        try container.encode(unit.x, forKey: .x)
        try container.encode(unit.y, forKey: .y)
        try container.encode(unit.z, forKey: .z)
        try container.encode(travelBeats, forKey: .travelBeats)
    }
}

struct Chart: Codable {
    var songId: String
    var bpm: Double
    var notes: [ChartNote]
}

// MARK: - Sources

extension Chart {

    /// Loads an authored chart from the bundle. This is the real path — a
    /// generated grid can't follow a song's intros, breaks or fills.
    static func load(resource: String) -> Chart? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        do {
            return try JSONDecoder().decode(Chart.self, from: data)
        } catch {
            print("[Chart] failed to decode \(resource).json: \(error)")
            return nil
        }
    }

    /// Builds a chart on a plain BPM grid, for use before a song is authored.
    ///
    /// Not fully random: consecutive notes stay within `level.maxStep` of each
    /// other in unit space. That's the coordination knob — small steps are
    /// short adjustments, large steps cross the body and demand a planned
    /// trajectory. Random placement can't express that at all.
    static func generated(
        bpm: Double,
        level: ReachLevel,
        hand: TrainingHand,
        beats: Double = 240
    ) -> Chart {
        var notes: [ChartNote] = []
        var cursor = SIMD3<Float>(0.5, 0.5, 0.5)
        var beat = level.travelBeats  // leave room for the first note's approach
        var index = 0

        while beat < beats {
            cursor = step(from: cursor, maxStep: level.maxStep)
            notes.append(ChartNote(
                beat: beat,
                hand: hand == .both ? (index.isMultiple(of: 2) ? .left : .right) : hand,
                unit: cursor,
                travelBeats: level.travelBeats
            ))
            beat += level.spacingBeats
            index += 1
        }

        return Chart(songId: "generated_\(Int(bpm))bpm_L\(level.rawValue)", bpm: bpm, notes: notes)
    }

    /// Random walk through the unit cube, clamped to the box.
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
