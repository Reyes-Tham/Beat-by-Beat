//
//  SessionRecorder.swift
//  BeatByBeat
//

import Foundation
import QuartzCore
import simd

/// Collects what happened during a run.
///
/// Deliberately passive: it is told about spawns, contacts and misses and does
/// no work of its own beyond arithmetic. Anything heavier here would be running
/// inside the frame tick, and the game has to keep its timing.
@MainActor
final class SessionRecorder {

    /// Tracking gaps longer than this count as the patient stopping, rather
    /// than as the headset blinking.
    private let pauseThreshold: TimeInterval = 1.5

    private var outcomes: [Int: NoteOutcomeRecord] = [:]
    private var spawnTimes: [Int: TimeInterval] = [:]
    private var order: [Int] = []

    private var startedAt: TimeInterval = 0
    private var pausedSeconds: TimeInterval = 0
    private var pauses = 0
    private var lastHandSeen: TimeInterval = 0
    private var handMissingSince: TimeInterval?

    /// Bounding box of where the hand actually got to.
    private var reachedLow: SIMD3<Float>?
    private var reachedHigh: SIMD3<Float>?

    func begin() {
        outcomes = [:]
        spawnTimes = [:]
        order = []
        startedAt = CACurrentMediaTime()
        pausedSeconds = 0
        pauses = 0
        lastHandSeen = startedAt
        handMissingSince = nil
        reachedLow = nil
        reachedHigh = nil
    }

    func noteSpawned(index: Int, unit: SIMD3<Float>, hand: TrainingHand, songTime: TimeInterval) {
        guard outcomes[index] == nil else { return }
        outcomes[index] = NoteOutcomeRecord(unit: unit, hand: hand, reached: false, reachTime: nil)
        spawnTimes[index] = songTime
        order.append(index)
    }

    func noteReached(index: Int, songTime: TimeInterval) {
        guard var record = outcomes[index] else { return }
        record.reached = true
        if let spawned = spawnTimes[index] {
            record.reachTime = max(0, songTime - spawned)
        }
        outcomes[index] = record
    }

    func noteMissed(index: Int) {
        // Already false by default; the call exists so a miss is explicit
        // rather than inferred from something not having happened.
        guard outcomes[index] != nil else { return }
    }

    /// Feed every frame. Nil means the hand isn't being tracked.
    func observe(hand position: SIMD3<Float>?) {
        let now = CACurrentMediaTime()
        guard let position else {
            if handMissingSince == nil { handMissingSince = now }
            return
        }

        if let missingSince = handMissingSince {
            let gap = now - missingSince
            if gap >= pauseThreshold {
                pauses += 1
                pausedSeconds += gap
            }
            handMissingSince = nil
        }
        lastHandSeen = now

        reachedLow = reachedLow.map { simd_min($0, position) } ?? position
        reachedHigh = reachedHigh.map { simd_max($0, position) } ?? position
    }

    /// Builds the record. Nil when nothing was presented, so an aborted run
    /// doesn't leave an empty session in the history.
    func finish(
        songTitle: String,
        mobility: Set<MobilityDemand>,
        hand: TrainingHand,
        calibratedSize: SIMD3<Float>,
        points: Int
    ) -> SessionRecord? {
        guard !order.isEmpty else { return nil }

        var elapsed = CACurrentMediaTime() - startedAt
        if let missingSince = handMissingSince {
            let gap = CACurrentMediaTime() - missingSince
            if gap >= pauseThreshold {
                pauses += 1
                pausedSeconds += gap
            }
        }
        elapsed = max(0, elapsed - pausedSeconds)

        let size: SIMD3<Float>
        if let low = reachedLow, let high = reachedHigh {
            size = simd_max(high - low, .zero)
        } else {
            size = .zero
        }

        return SessionRecord(
            date: Date(),
            songTitle: songTitle,
            level: mobility.count,
            mobility: mobility.map(\.rawValue).sorted(),
            hand: hand,
            // Kept in presentation order so the fatigue comparison means
            // "later in the run" rather than "later in a dictionary".
            outcomes: order.compactMap { outcomes[$0] },
            activeSeconds: elapsed,
            pauses: pauses,
            calibratedSize: calibratedSize,
            reachedSize: size,
            points: points
        )
    }
}
