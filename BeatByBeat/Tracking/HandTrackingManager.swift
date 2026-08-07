//
//  HandTrackingManager.swift
//  BeatByBeat
//

import ARKit
import RealityKit

/// A forgiving stand-in for the hand: a sphere at the centre of the palm.
///
/// Palm, not fingertip, on purpose — a stroke patient may not fully extend
/// their index finger, and the therapeutic goal is bringing the hand to the
/// target, not pointing at it.
struct HandProxy {
    /// Generous on purpose — contact should be forgiving, and this is the main
    /// dial for how easy a target is to reach. Tune on device.
    static let defaultRadius: Float = 0.055

    var position: SIMD3<Float>
    var radius: Float = HandProxy.defaultRadius
    var updatedAt: TimeInterval
}

/// Streams palm positions from ARKit.
///
/// Hand anchors arrive at roughly 90 Hz, which is also the natural cadence for
/// hit testing — so instead of publishing state for SwiftUI to observe, this
/// calls `onUpdate` on every batch and lets the caller do its work there.
@MainActor
@Observable
final class HandTrackingManager {

    enum Status: Equatable {
        case idle
        case unsupported
        case denied
        case running
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var left: HandProxy?
    private(set) var right: HandProxy?

    /// Called after each batch of anchor updates. Not observed by SwiftUI.
    @ObservationIgnored var onUpdate: (() -> Void)?

    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private var updateTask: Task<Void, Never>?

    func proxy(for hand: TrainingHand) -> HandProxy? {
        switch hand {
        case .left: left
        case .right: right
        case .both:
            // Whichever hand reported most recently.
            [left, right].compactMap(\.self).max { $0.updatedAt < $1.updatedAt }
        }
    }

    /// Every currently tracked palm, tagged with its side, for hit testing.
    var trackedPalms: [(hand: TrainingHand, proxy: HandProxy)] {
        [(TrainingHand.left, left), (TrainingHand.right, right)]
            .compactMap { side, proxy in proxy.map { (side, $0) } }
    }

    func start() async {
        guard HandTrackingProvider.isSupported else {
            status = .unsupported
            print("[HandTracking] not supported here — expected in the Simulator.")
            return
        }

        let authorizations = await session.requestAuthorization(for: [.handTracking])
        guard authorizations[.handTracking] == .allowed else {
            status = .denied
            print("[HandTracking] authorization denied.")
            return
        }

        do {
            try await session.run([provider])
        } catch {
            status = .failed("\(error)")
            print("[HandTracking] failed to run: \(error)")
            return
        }

        status = .running
        updateTask = Task { [weak self] in
            guard let self else { return }
            for await update in provider.anchorUpdates {
                self.apply(update.anchor)
                self.onUpdate?()
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        session.stop()
        left = nil
        right = nil
        status = .idle
    }

    private func apply(_ anchor: HandAnchor) {
        let proxy = anchor.isTracked ? Self.palmProxy(from: anchor) : nil
        switch anchor.chirality {
        case .left: left = proxy
        case .right: right = proxy
        @unknown default: break
        }
    }

    /// Palm centre, approximated as the midpoint between the wrist and the
    /// knuckle of the middle finger.
    private static func palmProxy(from anchor: HandAnchor) -> HandProxy? {
        guard let skeleton = anchor.handSkeleton else { return nil }

        let wrist = skeleton.joint(.wrist)
        let knuckle = skeleton.joint(.middleFingerKnuckle)
        guard wrist.isTracked, knuckle.isTracked else { return nil }

        let toWorld = { (joint: HandSkeleton.Joint) -> SIMD3<Float> in
            let world = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
        }

        return HandProxy(
            position: (toWorld(wrist) + toWorld(knuckle)) / 2,
            updatedAt: anchor.timestamp
        )
    }
}
