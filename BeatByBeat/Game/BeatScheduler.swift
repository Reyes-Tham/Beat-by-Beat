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
    private var beatDuration: TimeInterval = 0.5

    /// A note that should appear now, with its times already in seconds.
    struct Due {
        let note: ChartNote
        let index: Int
        let beatTime: TimeInterval
        let travelTime: TimeInterval
    }

    func load(_ chart: Chart) {
        self.chart = chart
        self.beatDuration = 60.0 / chart.bpm
        nextIndex = 0
    }

    func rewind() {
        nextIndex = 0
    }

    var isFinished: Bool {
        guard let chart else { return true }
        return nextIndex >= chart.notes.count
    }

    /// Notes whose approach should begin at or before `songTime`.
    ///
    /// A note spawns `travelTime` *before* its beat — the spawn is the cue to
    /// start moving, and the beat is the arrival deadline.
    func due(at songTime: TimeInterval) -> [Due] {
        guard let chart else { return [] }
        var ready: [Due] = []

        while nextIndex < chart.notes.count {
            let note = chart.notes[nextIndex]
            let beatTime = note.beat * beatDuration
            let travelTime = note.travelBeats * beatDuration

            guard songTime >= beatTime - travelTime else { break }

            ready.append(Due(
                note: note,
                index: nextIndex,
                beatTime: beatTime,
                travelTime: travelTime
            ))
            nextIndex += 1
        }

        return ready
    }
}
