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
            id: "steady_60",
            title: "Slow Steady",
            movementFocus: "Long single reaches, maximum rest",
            bpm: 60,
            audioResource: nil,
            beatMapResource: nil,
            duration: nil
        ),
        Song(
            id: "steady_90",
            title: "Gentle Swing",
            movementFocus: "Comfortable pace, even left/right",
            bpm: 90,
            audioResource: nil,
            beatMapResource: nil,
            duration: nil
        ),
        Song(
            id: "steady_120",
            title: "Walking Pace",
            movementFocus: "Moderate tempo, wider reaches",
            bpm: 120,
            audioResource: nil,
            beatMapResource: nil,
            duration: nil
        ),
        Song(
            id: "steady_150",
            title: "Bright Step",
            movementFocus: "Quick changes, shorter recovery",
            bpm: 150,
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

/// Best run per song and level, on this device.
enum ScoreStore {
    private static func key(song: String, level: ReachLevel) -> String {
        "score.\(song).\(level.rawValue)"
    }

    static func best(song: String, level: ReachLevel) -> SessionScore? {
        guard let data = UserDefaults.standard.data(forKey: key(song: song, level: level))
        else { return nil }
        return try? JSONDecoder().decode(SessionScore.self, from: data)
    }

    /// Keeps whichever run reached more targets. Ties go to the newer run so a
    /// repeat session still shows as today's.
    static func record(_ score: SessionScore, song: String, level: ReachLevel) {
        if let existing = best(song: song, level: level), existing.points > score.points {
            return
        }
        guard let data = try? JSONEncoder().encode(score) else { return }
        UserDefaults.standard.set(data, forKey: key(song: song, level: level))
    }
}
