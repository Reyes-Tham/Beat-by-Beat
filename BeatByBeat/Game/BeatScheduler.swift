//
//  BeatScheduler.swift
//  BeatByBeat
//

import Foundation

/// Walks a chart against song time and reports which notes are due to spawn.
///
/// Holds no clock of its own — it's told the song time and answers. That keeps
/// `AudioConductor` the only source of truth for where we are in the song.
@MainActor
final class BeatScheduler {

    private(set) var chart: Chart?
    private var nextIndex = 0

    /// A note that should appear now.
    struct Due {
        let note: ChartNote
        let index: Int
    }

    func load(_ chart: Chart) {
        self.chart = chart
        nextIndex = 0
    }

    func rewind() {
        nextIndex = 0
    }

    var isFinished: Bool {
        guard let chart else { return true }
        return nextIndex >= chart.notes.count
    }

    var noteCount: Int { chart?.notes.count ?? 0 }

    /// The next note that hasn't spawned, and its index. Used to count down to
    /// the next sphere rather than to the next beat.
    var pending: (note: ChartNote, index: Int)? {
        guard let chart, nextIndex < chart.notes.count else { return nil }
        return (chart.notes[nextIndex], nextIndex)
    }

    /// Notes whose approach should begin at or before `songTime`.
    ///
    /// A note spawns `travel` seconds *before* its beat — the spawn is the cue
    /// to start moving, and the beat is the arrival deadline.
    func due(at songTime: TimeInterval) -> [Due] {
        guard let chart else { return [] }
        var ready: [Due] = []

        while nextIndex < chart.notes.count {
            let note = chart.notes[nextIndex]
            guard songTime >= note.time - note.travel else { break }
            ready.append(Due(note: note, index: nextIndex))
            nextIndex += 1
        }

        return ready
    }
}
