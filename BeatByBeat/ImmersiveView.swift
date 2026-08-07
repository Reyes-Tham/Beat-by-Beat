//
//  ImmersiveView.swift
//  BeatByBeat
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel

    @State private var handTracking = HandTrackingManager()
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
            field.onHit = { appModel.hitCount = field.hitCount }
            self.field = field
            configure(field)

            for hand in [TrainingHand.left, .right] {
                let marker = TargetEntity.makeHandProxyMarker(radius: HandProxy.defaultRadius)
                marker.isEnabled = false
                content.add(marker)
                proxyMarkers[hand] = marker
            }
        }
        .task {
            // Every hand update is also a hit-test tick — no separate timer.
            handTracking.onUpdate = { onHandUpdate() }
            await handTracking.start()
            appModel.handTrackingStatus = handTracking.status
        }
        .onDisappear { handTracking.stop() }
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

    /// Pushes the tuning knobs into the field and lays it out again.
    private func configure(_ target: TargetField? = nil) {
        guard let field = target ?? field else { return }
        field.volume = appModel.volume
        field.layout = appModel.layout
        field.hand = appModel.trainingHand
        field.targetCount = appModel.targetCount
        field.outlineIsVisible = appModel.showOutline
        field.reset()
        appModel.hitCount = 0
    }

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

        field?.hitTest(palms: scoring)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
