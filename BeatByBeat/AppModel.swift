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

    // MARK: - Spawn tuning
    //
    // All of this is temporary: these knobs exist so we can find sane fixed
    // numbers on device. Calibration replaces them later.

    var trainingHand: TrainingHand = .both
    var layout: TargetLayout = .grid
    /// How many targets are alive at once.
    var targetCount: Int = 3
    var showOutline = true
    var showHandProxy = true

    // MARK: - Live readouts

    var hitCount = 0
    var handTrackingStatus: HandTrackingManager.Status = .idle

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

    /// Bumped to ask ImmersiveView to lay the targets out again. Screens don't
    /// reach into the RealityView directly.
    private(set) var respawnRequests = 0

    func requestRespawn() {
        respawnRequests += 1
    }
}
