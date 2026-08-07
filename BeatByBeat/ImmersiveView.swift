//
//  ImmersiveView.swift
//  BeatByBeat
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel

    @State private var handTracking = HandTrackingManager()
    @State private var conductor = AudioConductor()
    @State private var scheduler = BeatScheduler()
    @State private var field: TargetField?
    @State private var proxyMarkers: [TrainingHand: Entity] = [:]

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
            handTracking.onUpdate = { onHandUpdate() }
            await handTracking.start()
            appModel.handTrackingStatus = handTracking.status
        }
        .onDisappear {
            handTracking.stop()
            conductor.stop()
        }
        .onChange(of: appModel.isPlaying) { startOrStop() }
        .onChange(of: appModel.mode) { configure() }
        .onChange(of: appModel.level) { configure() }
        .onChange(of: appModel.bpm) { configure() }
        .onChange(of: appModel.respawnRequests) { configure() }
        .onChange(of: appModel.layout) { configure() }
        .onChange(of: appModel.trainingHand) { configure() }
        .onChange(of: appModel.targetCount) { configure() }
        .onChange(of: appModel.centerHeight) { configure() }
        .onChange(of: appModel.centerDistance) { configure() }
        .onChange(of: appModel.spread) { configure() }
        .onChange(of: appModel.showOutline) {
            field?.outlineIsVisible = appModel.showOutline
        }
    }

    // MARK: - Frame tick

    private func tick() {
        guard let field, appModel.mode == .rhythm, conductor.isRunning else { return }

        let songTime = conductor.songTime
        appModel.songTime = songTime

        for due in scheduler.due(at: songTime) {
            field.spawn(
                note: due.note,
                beatTime: due.beatTime,
                travelTime: due.travelTime,
                index: due.index
            )
        }
        field.expireOverdue(songTime: songTime)

        if scheduler.isFinished, field.activeTargets.isEmpty {
            appModel.isPlaying = false
        }
    }

    // MARK: - Transport

    private func startOrStop() {
        guard let field else { return }
        if appModel.isPlaying {
            // Authored chart if one is bundled, generated grid otherwise.
            let chart = Chart.load(resource: AudioConductor.songResourceName)
                ?? Chart.generated(
                    bpm: appModel.bpm,
                    level: appModel.level,
                    hand: appModel.trainingHand
                )
            appModel.bpm = chart.bpm
            appModel.chartIsAuthored = Chart.load(resource: AudioConductor.songResourceName) != nil
            conductor.bpm = chart.bpm
            scheduler.load(chart)
            field.reset()
            conductor.start()
            appModel.audioIsPlaying = conductor.hasAudio
        } else {
            conductor.stop()
            scheduler.rewind()
            appModel.audioIsPlaying = false
        }
    }

    /// Pushes the tuning knobs into the field and lays it out again.
    private func configure(_ target: TargetField? = nil) {
        guard let field = target ?? field else { return }
        field.mode = appModel.mode
        field.volume = appModel.volume
        field.layout = appModel.layout
        field.hand = appModel.trainingHand
        field.targetCount = appModel.targetCount
        field.outlineIsVisible = appModel.showOutline
        field.reset()
    }

    private func publishScore(_ field: TargetField) {
        appModel.hitCount = field.hitCount
        appModel.missedCount = field.missedCount
        appModel.judgements = field.judgements
    }

    // MARK: - Hands

    private func onHandUpdate() {
        let palms = handTracking.trackedPalms

        for hand in [TrainingHand.left, TrainingHand.right] {
            guard let marker = proxyMarkers[hand] else { continue }
            if let proxy = palms.first(where: { $0.hand == hand })?.proxy {
                marker.isEnabled = appModel.showHandProxy
                marker.position = proxy.position
            } else {
                marker.isEnabled = false
            }
        }

        // Only the training hand can score. This is what stops a patient
        // compensating with their stronger arm.
        let scoring = appModel.trainingHand == .both
            ? palms
            : palms.filter { $0.hand == appModel.trainingHand }

        field?.hitTest(palms: scoring, songTime: conductor.songTime)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
