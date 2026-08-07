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
            handTracking.onUpdate = { runHitTest() }
            await handTracking.start()
            appModel.handTrackingStatus = handTracking.status
        }
        .onDisappear {
            handTracking.stop()
            conductor.stop()
        }
        .onChange(of: appModel.isPlaying) { startOrStop() }
        .onChange(of: appModel.simulateHandWithMouse) {
            appModel.simulatedPalmUnit = nil
            updateProxyMarkers()
        }
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
        guard let field else { return }

        if appModel.mode == .rhythm, conductor.isRunning {
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

        // The fake palm has no update stream of its own — a target can spawn on
        // top of a stationary one, which would never produce a drag event.
        // Real hands re-test at 90 Hz from their own anchor updates.
        if appModel.simulateHandWithMouse, appModel.simulatedPalmUnit != nil {
            runHitTest()
        }
    }

    // MARK: - Transport

    private func startOrStop() {
        guard let field else { return }
        if appModel.isPlaying {
            // Authored chart if one is bundled, generated grid otherwise.
            let authored = Chart.load(resource: AudioConductor.songResourceName)
            let chart = authored ?? Chart.generated(
                bpm: appModel.bpm,
                level: appModel.level,
                hand: appModel.trainingHand
            )
            appModel.chartIsAuthored = authored != nil
            appModel.bpm = chart.bpm
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
        let volume = appModel.volume

        field.mode = appModel.mode
        field.volume = volume
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

    /// Palms currently driving the game — real ones, or the mouse stand-in.
    private var activePalms: [(hand: TrainingHand, proxy: HandProxy)] {
        if appModel.simulateHandWithMouse, let unit = appModel.simulatedPalmUnit {
            let proxy = HandProxy(
                position: appModel.volume.point(at: unit),
                radius: HandProxy.simulatedRadius,
                updatedAt: 0
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
