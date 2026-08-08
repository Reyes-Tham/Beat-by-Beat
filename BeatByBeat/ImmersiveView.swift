//
//  ImmersiveView.swift
//  BeatByBeat
//

import QuartzCore
import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel

    @State private var handTracking = HandTrackingManager()
    @State private var conductor = AudioConductor()
    @State private var scheduler = BeatScheduler()
    @State private var calibration = CalibrationManager()
    @State private var field: TargetField?
    @State private var proxyMarkers: [TrainingHand: Entity] = [:]
    @State private var confirmRoot = Entity()
    @State private var previewRoot = Entity()
    @State private var lastCalibrationTick: TimeInterval = 0
    @State private var hitSound: AudioFileResource?
    @State private var spawnSound: AudioFileResource?

    var body: some View {
        RealityView { content in
            // Positions are relative to the immersive space origin, which
            // visionOS puts on the floor beneath the player, facing -Z. ARKit
            // reports hand anchors in the same space, so palm positions and
            // target positions compare directly.
            let root = Entity()
            root.name = "TargetRoot"
            content.add(root)

            let field = TargetField(root: root)
            field.onScoreChange = { publishScore(field) }
            self.field = field

            confirmRoot.name = "CalibrationConfirm"
            previewRoot.name = "CalibrationPreview"
            content.add(confirmRoot)
            content.add(previewRoot)

            configure(field)

            for hand in [TrainingHand.left, .right] {
                let marker = TargetEntity.makeHandProxyMarker(radius: HandProxy.defaultRadius)
                marker.isEnabled = false
                content.add(marker)
                proxyMarkers[hand] = marker
            }

            // Frame tick: spawning and expiry are driven by song time, which
            // moves independently of whether the hands are being tracked.
            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                tick()
            }
        }
        .task {
            // Every hand update is also a hit-test tick — no separate timer.
            handTracking.onUpdate = { runHitTest() }
            await loadHitSound()
            await handTracking.start()
            appModel.handTrackingStatus = handTracking.status
        }
        .onDisappear {
            handTracking.stop()
            conductor.stop()
        }
        .onChange(of: appModel.isPlaying) { startOrStop() }
        .onChange(of: appModel.calibrationRequests) { beginCalibration() }
        .onChange(of: appModel.calibrationCancelRequests) { cancelCalibration() }
        .onChange(of: appModel.calibrationAdvanceRequests) { calibration.acceptNow() }
        .onChange(of: appModel.useCalibration) { configure() }
        .onChange(of: appModel.simulateHandWithMouse) {
            appModel.simulatedPalmUnit = nil
            updateProxyMarkers()
        }
        // `bpm` is deliberately absent: it's an output of loading a chart, not
        // an input. Observing it here made startOrStop's `appModel.bpm = ...`
        // re-enter configure and wipe the field on the first Play.
        .onChange(of: appModel.mode) { configure() }
        .onChange(of: appModel.level) { configure() }
        .onChange(of: appModel.respawnRequests) { configure() }
        .onChange(of: appModel.layout) { configure() }
        .onChange(of: appModel.trainingHand) { configure() }
        .onChange(of: appModel.targetCount) { configure() }
        // Volume tweaks re-aim future spawns without disturbing live targets,
        // so they stay usable while a song is running.
        .onChange(of: appModel.centerHeight) { applySettings() }
        .onChange(of: appModel.centerDistance) { applySettings() }
        .onChange(of: appModel.spread) { applySettings() }
        .onChange(of: appModel.showOutline) {
            field?.outlineIsVisible = appModel.showOutline
        }
    }

    // MARK: - Frame tick

    private func tick() {
        guard let field else { return }

        if calibration.phase == .capturing || calibration.phase == .confirming {
            tickCalibration()
            return
        }

        if appModel.mode == .rhythm, conductor.isRunning {
            let songTime = conductor.songTime
            appModel.songTime = songTime
            conductor.updateFade(songTime: songTime)

            for due in scheduler.due(at: songTime) {
                field.spawn(note: due.note, index: due.index)
            }
            field.expireOverdue(songTime: songTime)

            if scheduler.isFinished, field.activeTargets.isEmpty {
                appModel.recordRun()
                appModel.isPlaying = false
            }
        }

        // The fake palm has no update stream of its own — a target can spawn on
        // top of a stationary one, which would never produce a drag event.
        // Real hands re-test at 90 Hz from their own anchor updates.
        if appModel.simulateHandWithMouse, appModel.simulatedPalmUnit != nil {
            runHitTest()
        }
    }

    private func loadHitSound() async {
        do {
            // Held in view state, not written straight to the field: `.task`
            // can run before RealityView's make closure, so the field may not
            // exist yet. applySettings hands it over once both are ready.
            hitSound = try await AudioFileResource(
                named: "hit_ding.caf",
                configuration: .init(shouldLoop: false)
            )
            spawnSound = try await AudioFileResource(
                named: "spawn_cue.caf",
                configuration: .init(shouldLoop: false)
            )
            field?.hitSound = hitSound
            field?.spawnSound = spawnSound
        } catch {
            // Not fatal: the shatter and praise still land, just silently.
            print("[Audio] hit sound unavailable: \(error)")
        }
    }

    // MARK: - Calibration

    private func beginCalibration() {
        guard let field else { return }
        appModel.isPlaying = false
        field.clearTargets()
        field.outlineIsVisible = false
        calibration.begin(hand: appModel.trainingHand)
        lastCalibrationTick = CACurrentMediaTime()
        buildReachPreview()
        publishCalibrationState()
    }

    private func cancelCalibration() {
        calibration.cancel()
        clearCalibrationScene()
        publishCalibrationState()
        configure()
    }

    private func tickCalibration() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastCalibrationTick)
        lastCalibrationTick = now

        let head = handTracking.deviceTransform()

        // Pinned once per arm, just below eye line — about 18° down rather
        // than the 42° an earlier version needed, so confirming is a glance
        // and not a neck movement. What keeps that safe is the stillness gate
        // in updateDwell, not distance from where they're looking.
        if calibration.phase == .confirming, calibration.confirmCircle == nil, let head {
            let position = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
            var forward = -SIMD3<Float>(head.columns.2.x, head.columns.2.y, head.columns.2.z)
            forward.y = 0
            forward = length(forward) < 1e-4 ? [0, 0, -1] : normalize(forward)
            calibration.placeConfirmCircle(at: position + forward * 0.55 + [0, -0.18, 0])
            showConfirmCircle()
        }

        let palm = handTracking.proxy(for: calibration.currentHand)?.position
            ?? (appModel.simulateHandWithMouse
                ? appModel.simulatedPalmUnit.map { appModel.manualVolume.point(at: $0) }
                : nil)

        calibration.record(palm: palm, deltaTime: dt)
        calibration.updateDwell(isLooking: isLookingAtConfirmCircle(head: head), deltaTime: dt)

        updateProxyMarkers()
        updateReachPreview()
        if let circle = confirmRoot.children.first {
            TargetEntity.updateConfirmCircle(circle, progress: calibration.dwellProgress)
        }

        if calibration.phase == .finished, let profile = calibration.profile {
            appModel.calibration = profile
            appModel.useCalibration = true
            clearCalibrationScene()
            configure()
            if appModel.screen == .calibration { appModel.screen = .songSelection }
        } else if calibration.phase == .capturing, !confirmRoot.children.isEmpty {
            // Circle belongs to the confirm step only; clear it when the next
            // arm starts its six directions.
            for child in confirmRoot.children.reversed() { TargetEntity.destroy(child) }
        }

        publishCalibrationState()
    }

    /// Head direction, not eye gaze — visionOS keeps gaze private, so this is
    /// what "looking at" can mean. For a target in front of the player the two
    /// amount to the same movement.
    private func isLookingAtConfirmCircle(head: simd_float4x4?) -> Bool {
        guard let head, let circle = calibration.confirmCircle else { return false }
        let position = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let forward = -SIMD3<Float>(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        let toCircle = circle - position
        guard length(toCircle) > 1e-4 else { return false }
        let cosAngle = dot(normalize(forward), normalize(toCircle))
        let limit = cos(CalibrationManager.dwellConeDegrees * .pi / 180)
        return cosAngle >= limit
    }

    private func showConfirmCircle() {
        guard let position = calibration.confirmCircle else { return }
        for child in confirmRoot.children.reversed() { TargetEntity.destroy(child) }
        let circle = TargetEntity.makeConfirmCircle()
        circle.position = position
        confirmRoot.addChild(circle)
    }

    /// Eight dots showing the box captured so far, so the patient and the
    /// therapist can both see the range growing as they move.
    private func buildReachPreview() {
        for child in previewRoot.children.reversed() { TargetEntity.destroy(child) }
        for _ in 0..<8 {
            let dot = TargetEntity.makeDebugDot(radius: 0.016)
            dot.isEnabled = false
            previewRoot.addChild(dot)
        }
    }

    private func updateReachPreview() {
        guard let box = calibration.currentBox else { return }
        // Dots are moved rather than rebuilt: this runs every frame.
        for (index, corner) in box.corners.enumerated() where index < previewRoot.children.count {
            let dot = previewRoot.children[index]
            dot.isEnabled = true
            dot.position = corner
        }
    }

    private func clearCalibrationScene() {
        for child in confirmRoot.children.reversed() { TargetEntity.destroy(child) }
        for child in previewRoot.children.reversed() { TargetEntity.destroy(child) }
    }

    private func publishCalibrationState() {
        appModel.isCalibrating = calibration.phase == .capturing
            || calibration.phase == .confirming
        appModel.calibrationIsConfirming = calibration.phase == .confirming
        appModel.calibrationInstruction = calibration.instruction
        appModel.calibrationHold = calibration.holdProgress
        appModel.calibrationPointsCaptured = calibration.capturedPointCount
        appModel.calibrationHandProgress = calibration.handProgress
        appModel.calibrationAxis = calibration.currentAxis
        appModel.calibrationHand = calibration.currentHand
        appModel.calibrationStepName = calibration.currentAxis.shortName
        appModel.calibrationProgress = calibration.progress
        appModel.calibrationAwaitingHand = calibration.awaitingHand
        appModel.calibrationDwell = calibration.dwellProgress
        appModel.calibrationCanConfirm = calibration.hasMoved
        appModel.calibrationHandSteady = calibration.isHandSteady
        appModel.calibrationSpan = calibration.currentBox?.size ?? .zero
    }

    // MARK: - Transport

    private func startOrStop() {
        guard let field else { return }
        if appModel.isPlaying {
            // Real beat grid if the song ships one, constant-tempo grid otherwise.
            let song = appModel.selectedSong
            let beatMap = song.beatMapResource.flatMap { BeatMap.load(resource: $0) }
            let chart = beatMap.map {
                Chart.build(from: $0, level: appModel.level, hand: appModel.trainingHand,
                            movements: appModel.enabledMovements,
                            gripOrientations: appModel.enabledGripOrientations)
            } ?? Chart.generated(
                bpm: song.bpm,
                level: appModel.level,
                hand: appModel.trainingHand,
                movements: appModel.enabledMovements,
                gripOrientations: appModel.enabledGripOrientations
            )
            appModel.chartIsAuthored = beatMap != nil
            appModel.noteCount = chart.notes.count
            appModel.bpm = chart.bpm
            conductor.bpm = chart.bpm
            scheduler.load(chart)
            field.reset()
            conductor.start(song: song)
            appModel.audioIsPlaying = conductor.hasAudio
        } else {
            conductor.stop()
            scheduler.rewind()
            // Without this, stopping mid-song left every in-flight target
            // hanging in the scene with no clock to expire it.
            field.clearTargets()
            appModel.audioIsPlaying = false
        }
    }

    /// Pushes the tuning knobs into the field without disturbing live targets.
    private func applySettings(_ target: TargetField? = nil) {
        guard let field = target ?? field else { return }
        field.mode = appModel.mode
        field.volume = appModel.volume
        field.volumeForHand = { appModel.volume(for: $0) }
        field.hitSound = hitSound
        field.spawnSound = spawnSound
        field.layout = appModel.layout
        field.hand = appModel.trainingHand
        field.targetCount = appModel.targetCount
        field.outlineIsVisible = appModel.showOutline
        field.redrawOutline()
    }

    /// Applies settings and lays the field out again.
    ///
    /// Resetting mid-song would clear targets the chart has already scheduled
    /// and zero the score, so a running song is left alone.
    private func configure(_ target: TargetField? = nil) {
        guard let field = target ?? field else { return }
        applySettings(field)
        guard !appModel.isPlaying else { return }
        field.reset()
    }

    private func publishScore(_ field: TargetField) {
        appModel.hitCount = field.hitCount
        appModel.missedCount = field.missedCount
        appModel.judgements = field.judgements
    }

    // MARK: - Hands

    private var activePalmRadius: Float {
        appModel.simulateHandWithMouse ? HandProxy.simulatedRadius : HandProxy.defaultRadius
    }

    /// Palms currently driving the game — real ones, or the mouse stand-in.
    private var activePalms: [(hand: TrainingHand, proxy: HandProxy)] {
        if appModel.simulateHandWithMouse, let unit = appModel.simulatedPalmUnit {
            // During a capture the pad spans the manual box, which is the
            // widest reference available before a profile exists.
            let box = calibration.phase == .capturing ? appModel.manualVolume : appModel.volume
            let position = box.point(at: unit)
            let proxy = HandProxy(
                position: position,
                gripPosition: position,
                radius: HandProxy.simulatedRadius,
                updatedAt: 0,
                // The Simulator has no fingers to close, so the stand-in
                // always counts as gripping — otherwise grip notes could never
                // be tested without a headset.
                gripClosure: 1
            )
            // One mouse can't have two chiralities: when a specific hand is
            // being trained it takes that side, and only with Both does it
            // stand in for either — so wrong-hand rejection stays testable.
            let sides: [TrainingHand] = appModel.trainingHand == .both
                ? [.left, .right]
                : [appModel.trainingHand]
            return sides.map { ($0, proxy) }
        }
        return handTracking.trackedPalms
    }

    private func runHitTest() {
        updateProxyMarkers()

        // A capture is a measurement, not a game — targets must not score.
        guard calibration.phase != .capturing else { return }

        let palms = activePalms
        // Only the training hand can score. This is what stops a patient
        // compensating with their stronger arm.
        let scoring = appModel.trainingHand == .both
            ? palms
            : palms.filter { $0.hand == appModel.trainingHand }

        field?.hitTest(palms: scoring, songTime: conductor.songTime)
    }

    private func updateProxyMarkers() {
        let palms = activePalms
        for hand in [TrainingHand.left, TrainingHand.right] {
            guard let marker = proxyMarkers[hand] else { continue }
            if let proxy = palms.first(where: { $0.hand == hand })?.proxy {
                marker.isEnabled = appModel.showHandProxy
                marker.position = proxy.position
                marker.scale = .init(repeating: proxy.radius / HandProxy.defaultRadius)
            } else {
                marker.isEnabled = false
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
