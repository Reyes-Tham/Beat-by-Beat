//
//  SessionRecord.swift
//  BeatByBeat
//

import Foundation
import simd

/// Parts of the workspace a target can belong to.
///
/// A target usually belongs to several — upper *and* left, say — and each is
/// counted independently, because the useful question is "how do they do with
/// overhead targets", not "which single bucket does this one fall in".
enum ReachRegion: String, CaseIterable, Codable {
    case upper, lower, left, right, forward, crossBody

    var displayName: String {
        switch self {
        case .upper: "Upper reach"
        case .lower: "Lower reach"
        case .left: "Left reach"
        case .right: "Right reach"
        case .forward: "Forward reach"
        case .crossBody: "Cross-body"
        }
    }

    /// Regions a target at `unit` belongs to, for the arm being asked.
    ///
    /// Cross-body depends on which hand: reaching past the midline is a
    /// different task from reaching to your own side, and only the hand
    /// involved says which one this is.
    static func regions(unit: SIMD3<Float>, hand: TrainingHand) -> [ReachRegion] {
        var found: [ReachRegion] = []
        if unit.y >= 0.62 { found.append(.upper) }
        if unit.y <= 0.38 { found.append(.lower) }
        if unit.x <= 0.38 { found.append(.left) }
        if unit.x >= 0.62 { found.append(.right) }
        // Unit z of 0 is furthest from the player.
        if unit.z <= 0.35 { found.append(.forward) }

        let crossed = hand == .left ? unit.x >= 0.58 : unit.x <= 0.42
        if crossed, hand != .both { found.append(.crossBody) }
        return found
    }
}

/// One target's outcome, kept only as long as it takes to summarise a run.
struct NoteOutcomeRecord: Codable {
    var unit: SIMD3<Float>
    var hand: TrainingHand
    var reached: Bool
    /// Spawn to contact. Nil when it was never reached.
    var reachTime: TimeInterval?
}

/// A finished run.
///
/// Stores outcomes rather than pre-computed metrics: the numbers a therapist
/// wants have changed twice already, and re-deriving them from the raw
/// outcomes costs nothing while re-recording a session is impossible.
struct SessionRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var songTitle: String
    var level: Int
    var hand: TrainingHand

    var outcomes: [NoteOutcomeRecord]
    /// Seconds actually spent moving, excluding pauses.
    var activeSeconds: TimeInterval
    /// Stretches where tracking was lost long enough to count as a break.
    var pauses: Int
    /// Size of the workspace targets were placed in, metres.
    var calibratedSize: SIMD3<Float>
    /// Bounding box of where the hand actually got to.
    var reachedSize: SIMD3<Float>
    var points: Int

    // MARK: - Metrics

    var presented: Int { outcomes.count }
    var reached: Int { outcomes.filter(\.reached).count }
    var missed: Int { presented - reached }

    var successRate: Double {
        presented > 0 ? Double(reached) / Double(presented) : 0
    }

    /// How much of the calibrated box the hand actually visited.
    ///
    /// A ratio of volumes: reaching a bit further on one axis matters less than
    /// reaching further on all three, and this is the number that moves when a
    /// workspace genuinely opens up.
    var workspaceCoverage: Double {
        let calibrated = Double(calibratedSize.x * calibratedSize.y * calibratedSize.z)
        guard calibrated > 0 else { return 0 }
        let used = Double(reachedSize.x * reachedSize.y * reachedSize.z)
        return min(1, used / calibrated)
    }

    var reachTimes: [TimeInterval] { outcomes.compactMap(\.reachTime) }

    var averageReachTime: TimeInterval {
        reachTimes.isEmpty ? 0 : reachTimes.reduce(0, +) / Double(reachTimes.count)
    }

    /// Spread of reach times. Falling consistency is a better sign of
    /// improvement than a faster average, which one lucky reach can move.
    var reachTimeDeviation: TimeInterval {
        let times = reachTimes
        guard times.count > 1 else { return 0 }
        let mean = averageReachTime
        let variance = times.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(times.count)
        return variance.squareRoot()
    }

    func successRate(in region: ReachRegion) -> Double? {
        let relevant = outcomes.filter {
            ReachRegion.regions(unit: $0.unit, hand: $0.hand).contains(region)
        }
        guard !relevant.isEmpty else { return nil }
        return Double(relevant.filter(\.reached).count) / Double(relevant.count)
    }

    func successRate(forHand hand: TrainingHand) -> Double? {
        let relevant = outcomes.filter { $0.hand == hand }
        guard !relevant.isEmpty else { return nil }
        return Double(relevant.filter(\.reached).count) / Double(relevant.count)
    }

    /// Change in success rate from the first quarter of the run to the last.
    ///
    /// Negative means later repetitions went worse — the thing worth flagging,
    /// since it can mean the session ran past what the patient had in them.
    var fatigueChange: Double? {
        guard outcomes.count >= 8 else { return nil }
        let block = outcomes.count / 4
        let first = outcomes.prefix(block)
        let last = outcomes.suffix(block)
        let firstRate = Double(first.filter(\.reached).count) / Double(first.count)
        let lastRate = Double(last.filter(\.reached).count) / Double(last.count)
        return lastRate - firstRate
    }

    /// One cell of the reach map.
    struct HeatCell {
        var attempts: Int
        var successes: Int
        var successRate: Double {
            attempts > 0 ? Double(successes) / Double(attempts) : 0
        }
    }

    /// Deliberately coarse. A single run only presents a few dozen targets, so
    /// a fine grid puts at most one in each cell and the map degenerates into
    /// scattered dots of identical colour.
    static let heatmapResolution = 5

    /// Attempts and successes per cell.
    ///
    /// Both, not just successes: colouring by hit count alone made every cell
    /// identical when nothing repeated, whereas success *rate* shows the thing
    /// worth seeing — which part of the workspace they struggled in.
    var heatmap: [SIMD3<Int>: HeatCell] {
        var cells: [SIMD3<Int>: HeatCell] = [:]
        let n = Self.heatmapResolution
        for outcome in outcomes {
            let cell = SIMD3<Int>(
                min(n - 1, max(0, Int(outcome.unit.x * Float(n)))),
                min(n - 1, max(0, Int(outcome.unit.y * Float(n)))),
                min(n - 1, max(0, Int(outcome.unit.z * Float(n))))
            )
            var entry = cells[cell] ?? HeatCell(attempts: 0, successes: 0)
            entry.attempts += 1
            if outcome.reached { entry.successes += 1 }
            cells[cell] = entry
        }
        return cells
    }
}

/// Everything kept about the person using the app.
///
/// One record per device: this is a single-patient tool, and pretending
/// otherwise would mean building account handling that nothing needs yet.
struct PatientRecord: Codable {
    /// Newest last. Old captures are kept so a workspace can be compared
    /// against what it was, not only against today.
    var calibrations: [CalibrationProfile] = []
    var sessions: [SessionRecord] = []

    var currentCalibration: CalibrationProfile? { calibrations.last }
    var previousCalibration: CalibrationProfile? {
        calibrations.count > 1 ? calibrations[calibrations.count - 2] : nil
    }

    /// The session before `index`, for trends.
    func previousSession(before index: Int) -> SessionRecord? {
        index > 0 && index <= sessions.count ? sessions[index - 1] : nil
    }
}

// MARK: - Persistence

enum PatientStore {
    private static let key = "patientRecord"
    /// Enough history to show a trend without the file growing without bound.
    private static let sessionLimit = 60
    private static let calibrationLimit = 20

    static func load() -> PatientRecord {
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(PatientRecord.self, from: data)
        else { return PatientRecord() }
        return record
    }

    static func save(_ record: PatientRecord) {
        var trimmed = record
        trimmed.sessions = Array(record.sessions.suffix(sessionLimit))
        trimmed.calibrations = Array(record.calibrations.suffix(calibrationLimit))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func addSession(_ session: SessionRecord) {
        var record = load()
        record.sessions.append(session)
        save(record)
    }

    static func addCalibration(_ profile: CalibrationProfile) {
        var record = load()
        record.calibrations.append(profile)
        save(record)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
