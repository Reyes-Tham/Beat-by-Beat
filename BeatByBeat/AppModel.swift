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
    }

    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    // MARK: - Session config

    var mode: FieldMode = .practice
    var level: ReachLevel = .moderate
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

    /// Gates the simulator-only affordances, so the toggle can't be left on
    /// during a device demo.
    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    /// Height of the volume centre above the floor.
    var centerHeight: Float = SpawnVolume.fixed.center.y
    /// Distance of the volume centre in front of the player.
    var centerDistance: Float = -SpawnVolume.fixed.center.z
    /// Scales width and height together; depth stays fixed.
    var spread: Float = 1.0

    var volume: SpawnVolume {
        let base = SpawnVolume.fixed
        return SpawnVolume(
            center: [0, centerHeight, -centerDistance],
            size: [base.size.x * spread, base.size.y * spread, base.size.z]
        )
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
}
