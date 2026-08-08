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
        // Measuring six reaches per arm is the price of a first session, not of
        // every one. With a profile on file the launch asks only that they sit
        // the way they mean to play, and moves the saved reach onto that.
        screen = calibration == nil ? .calibration : .recenter
    }

    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    /// Which screen the window is showing.
    enum Screen {
        case songSelection, calibration, recenter, statistics, countdown, game, results
    }
    /// Set in `init` from whether there is a saved profile: recentre if there
    /// is, measure from scratch if not.
    var screen: Screen = .calibration

    /// Movements this session trains. Never empty — with nothing ticked there
    /// would be no chart at all.
    var enabledMovements: Set<MovementType> = [.reach] {
        didSet { if enabledMovements.isEmpty { enabledMovements = [.reach] } }
    }
    /// Hand orientations grip notes may ask for. Never empty while grip is on.
    var enabledGripOrientations: Set<GripOrientation> = [.cup] {
        didSet { if enabledGripOrientations.isEmpty { enabledGripOrientations = [.cup] } }
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
        // Stamped at the point of play, not of loading: this is what makes the
        // saved profile the one in use rather than merely the one on disk.
        calibration?.lastUsedAt = Date()
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

    /// Rhythm by default: practice is a debug scene now, and defaulting to it
    /// meant the field filled itself with spheres the moment the space opened —
    /// including during calibration.
    var mode: FieldMode = .rhythm
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

    // MARK: - Next target
    //
    // A deadline published once per target, not a per-frame countdown: the bar
    // runs off its own clock so nothing here re-renders to move it.

    /// Host-clock time the next sphere appears at.
    var nextSpawnDeadline: TimeInterval = 0
    /// Length of the current gap, so the bar knows what full means.
    var nextSpawnInterval: TimeInterval = 0
    /// Which arm the next sphere is for, and what it will ask of them.
    var nextSpawnHand: TrainingHand?
    var nextSpawnMovement: MovementType?

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
    ///
    /// On by default in the Simulator. Off, there is no palm at all there, so
    /// `acceptAxis` has nothing to record and calibration cannot be completed —
    /// the screen sits on the first of six directions with Accept greyed out
    /// and no indication that the way through is a setting two taps away.
    var simulateHandWithMouse = AppModel.isSimulator

    /// Fake palm position in unit-cube space, or nil before the first drag.
    var simulatedPalmUnit: SIMD3<Float>?
    /// Depth of the fake palm. Needs its own control: the pad only has two
    /// axes, and a palm pinned to mid-depth can't reach the volume's faces.
    var simulatedPalmDepth: Float = 0.75 {
        didSet { simulatedPalmUnit?.z = simulatedPalmDepth }
    }

    /// Disco lights, a speed boost, and dancing cats.
    ///
    /// Off by default and persisted, so it survives a relaunch while never
    /// being something a patient could stumble into.
    var developerMode = UserDefaults.standard.bool(forKey: "developerMode") {
        didSet { UserDefaults.standard.set(developerMode, forKey: "developerMode") }
    }

    /// How much faster developer mode runs a chart.
    ///
    /// Fast enough to be obviously a demo rather than a session: at six times
    /// the travel and spacing floors take over, so targets arrive about as fast
    /// as the chart can issue them.
    var developerSpeed: Double = 6.0

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

    /// Hand-set boxes, one per arm. Seeded from a calibration when there is
    /// one, so the sliders always show the numbers actually in use.
    var manualWorkspaces: [String: ManualWorkspace] = ManualWorkspace.loadAll() {
        didSet { ManualWorkspace.saveAll(manualWorkspaces) }
    }

    func manualWorkspace(for hand: TrainingHand) -> ManualWorkspace {
        manualWorkspaces[hand.rawValue] ?? .default(for: hand)
    }

    func setManualWorkspace(_ workspace: ManualWorkspace, for hand: TrainingHand) {
        manualWorkspaces[hand.rawValue] = workspace
    }

    /// Union of the hand-set boxes, for anything needing one volume.
    var manualVolume: SpawnVolume {
        let boxes = [TrainingHand.left, .right].map { manualWorkspace(for: $0).volume }
        var lo = boxes[0].minBound
        var hi = boxes[0].maxBound
        for box in boxes.dropFirst() {
            lo = simd_min(lo, box.minBound)
            hi = simd_max(hi, box.maxBound)
        }
        return SpawnVolume(center: (lo + hi) / 2, size: hi - lo)
    }

    /// Calibration result, when there is one.
    var calibration: CalibrationProfile? {
        didSet { calibration?.save() }
    }

    /// Prefer the measured boundary over the hand-set one. Turning it off lets
    /// a nurse work from the sliders without discarding the capture.
    var useCalibration = true

    var isUsingCalibration: Bool { useCalibration && calibration != nil }

    /// Copies measured boundaries into the sliders.
    ///
    /// Run automatically when a capture finishes, so the manual controls start
    /// from the patient's real numbers rather than from defaults — which is
    /// what makes adjusting one afterwards a nudge instead of a fresh capture.
    func seedManualFromCalibration() {
        guard let calibration else { return }
        for hand in [TrainingHand.left, .right] {
            guard let volume = calibration.volume(for: hand) else { continue }
            manualWorkspaces[hand.rawValue] = ManualWorkspace(volume)
        }
    }

    /// What gameplay uses for a given arm.
    ///
    /// Measured first, hand-set as the fallback. There is always a workspace,
    /// which is what lets calibration be skipped and the app still be played —
    /// on a headset or, with the simulated hand, without one.
    func volume(for hand: TrainingHand) -> SpawnVolume {
        if isUsingCalibration, let calibrated = calibration?.volume(for: hand) {
            return calibrated
        }
        return manualWorkspace(for: hand).volume
    }

    /// Union of both arms, for the outline and for practice layout.
    var volume: SpawnVolume {
        let boxes = [TrainingHand.left, .right].map { volume(for: $0) }
        var lo = boxes[0].minBound
        var hi = boxes[0].maxBound
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
    private(set) var calibrationRedoRequests = 0

    func startCalibration() {
        screen = .calibration
        calibrationRequests += 1
    }
    func cancelCalibration() {
        calibrationCancelRequests += 1
        screen = .songSelection
    }

    // MARK: - Recentring
    //
    // Same mirror-and-request shape as calibration: the screen publishes
    // intent, the RealityView owns the head pose and does the work.

    var isRecentring = false
    /// 0...1 while the head is held in one place.
    var recenterProgress: Float = 0
    var recenterAwaitingHead = true
    /// How far the patient is turned from where the saved reach was measured,
    /// radians. Nil when there is no head pose, or nothing to compare against.
    var recenterTurn: Float?
    private(set) var recenterRequests = 0
    private(set) var recenterAcceptRequests = 0
    private(set) var recenterCancelRequests = 0

    func startRecenter() {
        guard calibration != nil else { return startCalibration() }
        screen = .recenter
        recenterRequests += 1
    }

    /// Take the position as it is now instead of waiting out the hold. With no
    /// head pose to take — the Simulator has none — this keeps the saved reach
    /// where it was measured, which is the only sensible reading of "start".
    func acceptRecenter() { recenterAcceptRequests += 1 }

    func cancelRecenter() {
        recenterCancelRequests += 1
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

    /// Start the arm being measured over, keeping any already locked.
    func redoCalibrationArm() { calibrationRedoRequests += 1 }

    func clearCalibration() {
        calibration = nil
        CalibrationProfile.clearSaved()
    }
}
