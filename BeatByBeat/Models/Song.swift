//
//  Song.swift
//  BeatByBeat
//

import Foundation

/// A playable track.
///
/// `audioResource` is optional because the pipeline works without it: with no
/// file the conductor free-runs and the chart comes off a constant-tempo grid.
/// Those entries are real and playable, just silent — the UI says so rather
/// than pretending otherwise.
struct Song: Identifiable, Hashable {
    let id: String
    let title: String
    /// What this track asks the body to do, for the info panel.
    let movementFocus: String
    let bpm: Double
    let audioResource: String?
    let beatMapResource: String?
    /// Nominal length, for the list. Nil when generated.
    let duration: TimeInterval?

    var hasAudio: Bool { audioResource != nil }

    var durationText: String {
        guard let duration else { return "generated" }
        return String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }

    static let catalog: [Song] = [
        Song(
            id: "demo_song",
            title: "Demo Track",
            movementFocus: "Alternating reaches, steady tempo",
            bpm: 143.87,
            audioResource: "demo_song",
            beatMapResource: "demo_song_beats",
            duration: 129
        ),
        Song(
            id: "demo_song_2",
            title: "Afro Vibes",
            movementFocus: "Slower pulse, long recovery between reaches",
            bpm: 117.41,
            audioResource: "demo_song_2",
            beatMapResource: "demo_song_2_beats",
            duration: 240
        ),
        Song(
            id: "demo_song_3",
            title: "Tung Tung Sahur",
            movementFocus: "Brisk and even, steady alternating reaches",
            bpm: 130.92,
            audioResource: "demo_song_3",
            beatMapResource: "demo_song_3_beats",
            duration: 86
        ),
        Song(
            id: "demo_song_4",
            title: "Tralalero Tralala",
            movementFocus: "Quick pulse, short bursts of movement",
            bpm: 138.09,
            audioResource: "demo_song_4",
            beatMapResource: "demo_song_4_beats",
            duration: 81
        ),
        Song(
            id: "singapore_parade",
            title: "Singapore Parade",
            movementFocus: "Marching pulse — the most predictable timing here",
            bpm: 119.99,
            audioResource: "singapore_parade",
            beatMapResource: "singapore_parade_beats",
            duration: 144
        ),
        Song(
            id: "steady_60",
            title: "Slow Steady",
            movementFocus: "Long single reaches, maximum rest",
            bpm: 60,
            audioResource: nil,
            beatMapResource: nil,
            duration: nil
        ),
    ]

    static var `default`: Song { catalog[0] }
}

/// Result of one run, kept per song and level.
///
/// Points, not a fraction. "22 of 25" makes the three that got away the
/// headline, and for someone whose arm is the reason they missed, that reads
/// as a report card. Points only ever go up, so a slower patient sees a
/// smaller number rather than a visible shortfall.
struct SessionScore: Codable, Equatable {
    var points: Int
    var reached: Int
    var excellent: Int
    var good: Int
    var date: Date

    /// Every reach scores. Timing only decides how much.
    static func points(excellent: Int, good: Int, reached: Int) -> Int {
        let onTime = excellent * 100
        let close = good * 70
        let rest = max(0, reached - excellent - good) * 50
        return onTime + close + rest
    }

    var rhythmPercent: Int {
        reached > 0 ? Int((Double(excellent + good) / Double(reached) * 100).rounded()) : 0
    }
}

/// Best run per song and mobility setting, on this device.
///
/// Keyed by the exact combination of demands rather than by a level number,
/// so a best set with height on is not compared against one without it.
enum ScoreStore {
    private static func key(song: String, mobility: String) -> String {
        "score.\(song).\(mobility)"
    }

    static func best(song: String, mobility: String) -> SessionScore? {
        guard let data = UserDefaults.standard.data(forKey: key(song: song, mobility: mobility))
        else { return nil }
        return try? JSONDecoder().decode(SessionScore.self, from: data)
    }

    /// Keeps whichever run reached more targets. Ties go to the newer run so a
    /// repeat session still shows as today's.
    static func record(_ score: SessionScore, song: String, mobility: String) {
        if let existing = best(song: song, mobility: mobility), existing.points > score.points {
            return
        }
        guard let data = try? JSONEncoder().encode(score) else { return }
        UserDefaults.standard.set(data, forKey: key(song: song, mobility: mobility))
    }
}
