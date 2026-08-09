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
    @State private var recorder = SessionRecorder()
    @State private var field: TargetField?
    @State private var proxyMarkers: [TrainingHand: Entity] = [:]
    @State private var confirmRoot = Entity()
    @State private var previewRoot = Entity()
    @State private var lastCalibrationTick: TimeInterval = 0
    @State private var hitSound: AudioFileResource?
    /// Chart index the countdown was last published for, so it is republished
    /// when the next target changes and not on every frame.
    @State private var announcedNote = -1
    @State private var discoRoot = Entity()
    @State private var spawnSound: AudioFileResource?

    /// Split in two. One chain of every hook grew past what the type checker
    /// will attempt on a single expression, and it gave up rather than slowing
    /// down — so the field settings live on their own.
    var body: some View {
        scene
            .onChange(of: appModel.simulateHandWithMouse) {
                appModel.simulatedPalmUnit = nil
                updateProxyMarkers()
            }
            // `bpm` is deliberately absent: it's an output of loading a chart,
            // not an input. Observing it here made startOrStop's
            // `appModel.bpm = ...` re-enter configure and wipe the field on the
            // first Play.
            .onChange(of: appModel.mode) { configure() }
            .onChange(of: appModel.level) { configure() }
            .onChange(of: appModel.respawnRequests) { configure() }
            .onChange(of: appModel.layout) { configure() }
            .onChange(of: appModel.trainingHand) { configure() }
            .onChange(of: appModel.targetCount) { configure() }
            // Volume tweaks re-aim future spawns without disturbing live
            // targets, so they stay usable while a song is running.
            .onChange(of: appModel.manualWorkspaces) { applySettings() }
            .onChange(of: appModel.showOutline) {
                field?.outlineIsVisible = appModel.showOutline
            }
    }

    private var scene: some View {
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
            field.onReached = { component in
                recorder.noteReached(index: component.noteIndex, songTime: conductor.songTime)
            }
            field.onMissed = { component in
                recorder.noteMissed(index: component.noteIndex)
            }
            self.field = field

            discoRoot.name = "Disco"
            discoRoot.isEnabled = false
            for index in 0..<4 {
                let light = Entity()
                var point = PointLightComponent(color: .white, intensity: 4000)
                point.attenuationRadius = 6
                light.components.set(point)
                light.name = "Disco\(index)"
                discoRoot.addChild(light)
            }
            content.add(discoRoot)

            confirmRoot.name = "CalibrationConfirm"
            previewRoot.name = "CalibrationPreview"
            content.add(confirmRoot)
            content.add(previewRoot)

            configure(field)

            // The screen can ask for a capture before this closure has run —
            // launching straight into calibration does exactly that — so a
            // pending request is picked up here rather than being dropped.
            if appModel.screen == .calibration, calibration.phase == .idle {
                beginCalibration()
            } else if appModel.screen == .recenter, calibration.phase == .idle {
                calibration.beginRecenter()
                publishCalibrationState()
            }

            for hand in [TrainingHand.left, .right] {
                let marker = TargetEntity.makeHandProxyMarker(radius: 1)
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
        .onChange(of: appModel.calibrationAdvanceRequests) {
            calibration.acceptNow()
            // The tick only routes while a capture is running, and locking the
            // final arm has just ended one.
            finishCalibrationIfDone()
        }
        .onChange(of: appModel.calibrationRedoRequests) {
            calibration.redoCurrentArm()
            // Dots are rebuilt rather than left: with no points captured there
            // is no box to move them to, so they would sit at the corners of
            // the reach that was just discarded.
            buildReachPreview()
            publishCalibrationState()
        }
        .onChange(of: appModel.recenterRequests) { beginRecenter() }
        .onChange(of: appModel.recenterAcceptRequests) {
            calibration.acceptRecenter(head: handTracking.deviceTransform())
            // Applied here as well as in the tick: the tick only routes while
            // the phase is `.recentring`, and this call has just left it.
            applyRecenterIfDone()
        }
        .onChange(of: appModel.recenterCancelRequests) {
            calibration.cancel()
            publishCalibrationState()
            configure()
        }
    }

    // MARK: - Frame tick

    private func tick() {
        guard let field else { return }

        if calibration.phase == .capturing || calibration.phase == .confirming {
            tickCalibration()
            return
        }

        if calibration.phase == .recentring {
            tickRecenter()
            return
        }

        if appModel.mode == .rhythm, conductor.isRunning {
            let songTime = conductor.songTime
            appModel.songTime = songTime
            conductor.updateFade(songTime: songTime)
            announceNextTarget(songTime: songTime)

            for due in scheduler.due(at: songTime) {
                field.spawn(note: due.note, index: due.index)
                recorder.noteSpawned(
                    index: due.index,
                    unit: due.note.unit,
                    hand: due.note.hand,
                    songTime: songTime
                )
            }
            recorder.observe(hand: handTracking.proxy(for: appModel.trainingHand)?.position)
            field.expireOverdue(songTime: songTime)

            if scheduler.isFinished, field.activeTargets.isEmpty {
                appModel.recordRun()
                // Filed before isPlaying flips, so the summary the results
                // screen shows and the record the history keeps agree.
                if let session = recorder.finish(
                    songTitle: appModel.selectedSong.title,
                    level: appModel.level,
                    hand: appModel.trainingHand,
                    calibratedSize: appModel.volume.size,
                    points: appModel.livePoints
                ) {
                    PatientStore.addSession(session)
                }
                appModel.isPlaying = false
            }
        }

        updateDisco()

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
        calibration.begin(
            hand: appModel.trainingHand,
            // A closure rather than `map(HeadAnchor.init(head:))`: passing the
            // initialiser as a value hands it to a nonisolated `map`, and it is
            // main-actor isolated.
            anchor: handTracking.deviceTransform().map { HeadAnchor(head: $0) }
        )
        lastCalibrationTick = CACurrentMediaTime()
        buildReachPreview()
        publishCalibrationState()
    }

    // MARK: - Recentring

    private func beginRecenter() {
        guard let field else { return }
        appModel.isPlaying = false
        field.clearTargets()
        field.outlineIsVisible = false
        calibration.beginRecenter()
        lastCalibrationTick = CACurrentMediaTime()
        publishCalibrationState()
    }

    private func tickRecenter() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastCalibrationTick)
        lastCalibrationTick = now

        calibration.updateRecenter(head: handTracking.deviceTransform(), deltaTime: dt)
        applyRecenterIfDone()
        publishCalibrationState()
    }

    /// Moves the saved reach onto where the patient settled, and plays on.
    ///
    /// The moved profile is saved over the old one, so the anchor it carries is
    /// always the last place it was used from. Recentring from a stale anchor
    /// every time would make each session's correction relative to a chair
    /// nobody has sat in for a week.
    private func applyRecenterIfDone() {
        guard calibration.phase == .recentred else { return }

        // Shifts the sliders, not the profile alone: the sliders are what
        // gameplay reads, and reseeding them from the profile instead would
        // throw away any nudge a nurse had made since the capture.
        if let anchor = calibration.recenterAnchor {
            appModel.recentreWorkspace(to: anchor)
        }

        calibration.cancel()
        clearCalibrationScene()
        configure()
        if appModel.screen == .recenter { appModel.screen = .songSelection }
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
        calibration.noteHead(head.map { HeadAnchor(head: $0) })

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

        if calibration.phase == .capturing, !confirmRoot.children.isEmpty {
            // Circle belongs to the confirm step only; clear it when the next
            // arm starts its six directions.
            for child in confirmRoot.children.reversed() { TargetEntity.destroy(child) }
        }
        finishCalibrationIfDone()

        publishCalibrationState()
    }

    /// Files a completed capture and leaves the calibration screen.
    ///
    /// Called from the tick *and* from the lock button, because the two reach
    /// the finish from different places. The glance completes inside the tick,
    /// so the tick sees it. The button completes in its own handler, and by the
    /// next frame the phase is no longer one the tick routes on — which left
    /// the last arm locking to nothing at all, the profile unsaved and the
    /// screen stuck on a capture that was already over.
    private func finishCalibrationIfDone() {
        guard calibration.phase == .finished, let profile = calibration.profile else { return }

        appModel.calibration = profile
        // A measurement beats whatever was in the sliders, so it takes them
        // over. They are what the game reads, so this is the moment the capture
        // becomes the workspace rather than a second opinion beside it.
        appModel.seedManualFromCalibration()
        // Recorded from the same capture, so a later recentre knows where this
        // workspace was set from.
        appModel.workspaceAnchor = profile.anchor ?? handTracking.deviceTransform()
            .map { HeadAnchor(head: $0) }
        // Kept as history: a workspace is far more informative compared against
        // what it was than read on its own.
        PatientStore.addCalibration(profile)
        clearCalibrationScene()
        configure()
        if appModel.screen == .calibration { appModel.screen = .songSelection }
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
        appModel.isRecentring = calibration.phase == .recentring
        appModel.recenterProgress = calibration.recenterProgress
        appModel.recenterAwaitingHead = calibration.awaitingHead
        appModel.recenterSeat = calibration.currentHead
    }

    /// Coloured lights orbiting the play volume. Developer mode only.
    private func updateDisco() {
        guard appModel.developerMode else {
            if discoRoot.isEnabled { discoRoot.isEnabled = false }
            return
        }
        discoRoot.isEnabled = true

        let volume = appModel.volume
        let time = CACurrentMediaTime()
        for (index, light) in discoRoot.children.enumerated() {
            let phase = time * 1.4 + Double(index) * .pi / 2
            light.position = volume.center + SIMD3<Float>(
                Float(cos(phase)) * (volume.size.x * 0.9 + 0.5),
                Float(sin(phase * 0.7)) * 0.4,
                Float(sin(phase)) * 0.5
            )
            // Hue cycles per light, offset so they never agree.
            let hue = (time * 0.25 + Double(index) * 0.25).truncatingRemainder(dividingBy: 1)
            light.components[PointLightComponent.self]?.color = .init(
                Color(hue: hue, saturation: 0.95, brightness: 1)
            )
        }
    }

    /// Publishes when the next sphere will appear.
    ///
    /// The countdown spans from now to that spawn, so the bar fills exactly
    /// once between targets whatever the gap happens to be — which varies with
    /// level, and with movement type, since a carry is given longer than a
    /// reach.
    private func announceNextTarget(songTime: TimeInterval) {
        guard let pending = scheduler.pending else {
            // Chart exhausted: nothing more is coming.
            if announcedNote != -2 {
                announcedNote = -2
                appModel.nextSpawnHand = nil
                appModel.nextSpawnMovement = nil
                appModel.nextSpawnInterval = 0
            }
            return
        }
        guard pending.index != announcedNote else { return }
        announcedNote = pending.index

        // Notes spawn `travel` before their beat, so that is the moment a
        // sphere actually appears.
        let spawnAt = pending.note.time - pending.note.travel
        let remaining = max(0, spawnAt - songTime)
        appModel.nextSpawnDeadline = CACurrentMediaTime() + remaining
        appModel.nextSpawnInterval = max(0.2, remaining)
        appModel.nextSpawnHand = pending.note.hand
        appModel.nextSpawnMovement = pending.note.movement
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
                            gripOrientations: appModel.enabledGripOrientations,
                            speedScale: appModel.developerMode ? appModel.developerSpeed : 1)
            } ?? Chart.generated(
                bpm: song.bpm,
                level: appModel.level,
                hand: appModel.trainingHand,
                movements: appModel.enabledMovements,
                gripOrientations: appModel.enabledGripOrientations,
                speedScale: appModel.developerMode ? appModel.developerSpeed : 1
            )
            appModel.chartIsAuthored = beatMap != nil
            announcedNote = -1
            appModel.noteCount = chart.notes.count
            appModel.bpm = chart.bpm
            conductor.bpm = chart.bpm
            scheduler.load(chart)
            recorder.begin()
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
        field.workspaceYaw = appModel.workspaceYaw
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
        // A capture owns the scene while it runs; resetting would drop practice
        // targets on top of the probe and the reach preview.
        guard !appModel.isPlaying, calibration.phase == .idle else { return }
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
                wrist: position,
                gripPosition: position,
                // Same shape as a real hand, just aligned to the world since
                // the stand-in has no wrist to take a direction from.
                radii: SIMD3(HandProxy.simulatedRadius,
                             HandProxy.simulatedRadius * 0.8,
                             HandProxy.simulatedRadius * 1.6),
                updatedAt: 0,
                // No fingers to close in the Simulator, so the stand-in
                // alternates open and shut on a slow cycle. That way the
                // open-then-close sequence can still be exercised there.
                gripClosure: fmod(CACurrentMediaTime(), 2.0) < 1.0 ? 0 : 1
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
                // Unit sphere scaled to the semi-axes and rotated into the
                // hand's frame, so the debug shape is exactly what the hit test
                // uses rather than an approximation of it.
                marker.orientation = simd_quatf(simd_float3x3(
                    proxy.lateral, proxy.normal, proxy.forward
                ))
                marker.scale = proxy.radii
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
