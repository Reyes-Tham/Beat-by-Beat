//
//  AppModel.swift
//  BeatByBeat
//

import RealityKit
import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    init() {
        // Registered here rather than in the App: importing RealityKit into a
        // file that declares `body: some Scene` makes `Scene` ambiguous.
        TargetComponent.registerComponent()
        calibration = CalibrationProfile.loadSaved()
    }

    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    /// Which screen the window is showing.
    enum Screen { case songSelection, calibration, countdown, game, results }
    var screen: Screen = .songSelection

    /// Movements this session trains. Never empty — with nothing ticked there
    /// would be no chart at all.
    var enabledMovements: Set<MovementType> = [.reach] {
        didSet { if enabledMovements.isEmpty { enabledMovements = [.reach] } }
    }
    /// The run just finished, shown on the results screen.
    var lastRun: SessionScore?

    var selectedSong: Song = .default
    /// Best previous run for the current song and level, if any.
    var bestScore: SessionScore? {
        ScoreStore.best(song: selectedSong.id, level: level)
    }

    /// Counts in first; the game screen starts the song when it lands.
    func startGame() {
        hitCount = 0
        missedCount = 0
        judgements = [:]
        lastRun = nil
        mode = .rhythm
        screen = .countdown
    }

    func countdownFinished() {
        screen = .game
        isPlaying = true
    }

    func backToSongs() {
        isPlaying = false
        screen = .songSelection
    }

    /// Files the run that just ended and shows the summary.
    func recordRun() {
        guard noteCount > 0 else { return }
        let excellent = judgements[.excellent] ?? 0
        let good = judgements[.good] ?? 0
        let run = SessionScore(
            points: SessionScore.points(excellent: excellent, good: good, reached: hitCount),
            reached: hitCount,
            excellent: excellent,
            good: good,
            date: Date()
        )
        ScoreStore.record(run, song: selectedSong.id, level: level)
        lastRun = run
        screen = .results
    }

    // MARK: - Session config

    var mode: FieldMode = .practice
    var level: ReachLevel = .three
    var trainingHand: TrainingHand = .both
    var bpm: Double = 120

    // MARK: - Transport

    var isPlaying = false
    var songTime: TimeInterval = 0
    /// Whether a real audio file is driving the clock, or it's free-running.
    var audioIsPlaying = false
    /// Whether the chart came from the song's real beat grid, or a synthetic
    /// constant-tempo one.
    var chartIsAuthored = false
    var noteCount = 0

    // MARK: - Spawn tuning
    //
    // Temporary: these knobs exist so we can find sane fixed numbers on device.
    // Calibration replaces them later.

    var layout: TargetLayout = .grid
    /// How many targets are alive at once, in practice mode.
    var targetCount: Int = 3
    var showOutline = true
    var showHandProxy = true

    /// Drives a fake palm from a drag pad so the hit loop can be exercised
    /// without a headset. The Simulator reports no hand anchors at all, so
    /// there is otherwise no way to test contact there.
    ///
    /// The pad lives in the window rather than the immersive space on purpose:
    /// anything with an `InputTargetComponent` sitting between the player and
    /// the window swallows every pinch aimed at the UI.
    var simulateHandWithMouse = false

    /// Fake palm position in unit-cube space, or nil before the first drag.
    var simulatedPalmUnit: SIMD3<Float>?
    /// Depth of the fake palm. Needs its own control: the pad only has two
    /// axes, and a palm pinned to mid-depth can't reach the volume's faces.
    var simulatedPalmDepth: Float = 0.75 {
        didSet { simulatedPalmUnit?.z = simulatedPalmDepth }
    }

    /// Gates the simulator-only affordances, so the toggle can't be left on
    /// during a device demo.
    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    /// Checked once so the panel can report what's bundled before playback,
    /// rather than showing the post-play flags while still stopped.
    static let hasBundledSong: Bool = ["m4a", "mp3", "wav", "aiff", "caf"].contains {
        Bundle.main.url(forResource: AudioConductor.songResourceName, withExtension: $0) != nil
    }
    static let hasBundledBeatMap: Bool =
        Bundle.main.url(forResource: AudioConductor.beatMapResourceName, withExtension: "json") != nil

    /// Height of the volume centre above the floor.
    var centerHeight: Float = SpawnVolume.fixed.center.y
    /// Distance of the volume centre in front of the player.
    var centerDistance: Float = -SpawnVolume.fixed.center.z
    /// Scales width and height together; depth stays fixed.
    var spread: Float = 1.0

    /// Volume set by hand. Stays available as the therapist override, and as
    /// the fallback if a capture fails during a demo — a live demo should
    /// never have calibration as a single point of failure.
    var manualVolume: SpawnVolume {
        let base = SpawnVolume.fixed
        return SpawnVolume(
            center: [0, centerHeight, -centerDistance],
            size: [base.size.x * spread, base.size.y * spread, base.size.z]
        )
    }

    /// Calibration result, when there is one.
    var calibration: CalibrationProfile? {
        didSet { calibration?.save() }
    }
    /// Lets the therapist fall back to the sliders without discarding a
    /// capture.
    var useCalibration = true

    var isUsingCalibration: Bool { useCalibration && calibration != nil }

    /// What gameplay uses for a given arm.
    ///
    /// Per-arm because hemiparesis is asymmetric: the affected arm's workspace
    /// can be a fraction of the other's, and one shared box would put targets
    /// out of reach on one side and make them trivial on the other.
    func volume(for hand: TrainingHand) -> SpawnVolume {
        guard isUsingCalibration,
              let calibrated = calibration?.volume(for: hand)
        else { return manualVolume }
        return calibrated
    }

    /// Union of both arms, for the outline and for anything that needs one box.
    var volume: SpawnVolume {
        guard isUsingCalibration, let calibration else { return manualVolume }
        let boxes = [TrainingHand.left, .right].compactMap { calibration.volume(for: $0) }
        guard let first = boxes.first else { return manualVolume }
        var lo = first.minBound
        var hi = first.maxBound
        for box in boxes.dropFirst() {
            lo = simd_min(lo, box.minBound)
            hi = simd_max(hi, box.maxBound)
        }
        return SpawnVolume(center: (lo + hi) / 2, size: hi - lo)
    }

    // MARK: - Live readouts

    var hitCount = 0
    var missedCount = 0
    var judgements: [Judgement: Int] = [:]
    var handTrackingStatus: HandTrackingManager.Status = .idle

    /// Bumped to ask ImmersiveView to lay the targets out again. Screens don't
    /// reach into the RealityView directly.
    private(set) var respawnRequests = 0

    func requestRespawn() {
        respawnRequests += 1
    }

    // MARK: - Calibration flow
    //
    // Mirrors of CalibrationManager state, which lives with the RealityView.
    // The panel reads these; it never touches the manager directly.

    var isCalibrating = false
    var calibrationStepName = ""
    var calibrationInstruction = ""
    var calibrationProgress = ""
    var calibrationAwaitingHand = false
    /// 0...1 while the head is held toward the confirm circle.
    var calibrationDwell: Float = 0
    var calibrationCanConfirm = false
    /// Whether the arm has stopped moving — the second gate on confirming.
    var calibrationHandSteady = false
    /// True once six points are captured and the confirm glance is pending.
    var calibrationIsConfirming = false
    /// 0...1 while the arm is held still on the current direction.
    var calibrationHold: Float = 0
    var calibrationPointsCaptured = 0
    var calibrationHandProgress = ""
    /// Direction the current step is asking for, for the stick-figure guide.
    var calibrationAxis: ReachAxis = .forward
    /// Arm being measured right now.
    var calibrationHand: TrainingHand = .right
    /// Reach captured so far for the current arm, in metres.
    var calibrationSpan: SIMD3<Float> = .zero
    private(set) var calibrationRequests = 0
    private(set) var calibrationCancelRequests = 0
    private(set) var calibrationAdvanceRequests = 0

    func startCalibration() {
        screen = .calibration
        calibrationRequests += 1
    }
    func cancelCalibration() {
        calibrationCancelRequests += 1
        screen = .songSelection
    }

    /// Live points during a run, so the in-game readout matches the summary.
    var livePoints: Int {
        SessionScore.points(
            excellent: judgements[.excellent] ?? 0,
            good: judgements[.good] ?? 0,
            reached: hitCount
        )
    }
    /// Manual lock, for the therapist and for the Simulator where there may be
    /// no head pose to dwell with.
    func advanceCalibration() { calibrationAdvanceRequests += 1 }

    func clearCalibration() {
        calibration = nil
        CalibrationProfile.clearSaved()
    }
}
