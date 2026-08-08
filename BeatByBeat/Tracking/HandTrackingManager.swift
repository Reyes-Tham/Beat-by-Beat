//
//  HandTrackingManager.swift
//  BeatByBeat
//

import ARKit
import QuartzCore
import RealityKit

/// A forgiving stand-in for the hand: a sphere at the wrist.
///
/// Wrist, not fingertip and not palm centre. A stroke patient may hold the
/// hand flexed or clenched, which moves a palm estimate around without the arm
/// having gone anywhere; the wrist is a stable joint and is the usual endpoint
/// for measuring reach. Calibration and gameplay both use it, so the envelope
/// is measured in the same coordinates it is later tested in.
struct HandProxy {
    /// Generous on purpose — contact should be forgiving, and this is the main
    /// dial for how easy a target is to reach. Tune on device.
    static let defaultRadius: Float = 0.055

    /// Radius for the mouse-driven stand-in used in the Simulator.
    ///
    /// Still larger than the real thing, because the fake palm slides on a flat
    /// plane at the volume's mid-depth and would otherwise only touch targets
    /// sitting exactly on that plane. The floor is set by the volume's depth:
    /// a target at the far face is 0.125 m off-plane, so with a 0.07 m target
    /// this leaves about 9 cm of lateral slack there. Going much below this
    /// starts making deep targets unreachable rather than merely fiddly.
    ///
    /// This is for proving the loop is wired up, not for judging how forgiving
    /// contact feels — that's `defaultRadius`, and only on device.
    static let simulatedRadius: Float = 0.085



    /// Wrist. Where the *arm* got to, which is what reaching measures.
    var position: SIMD3<Float>
    /// Between the thumb and index tips — where a grasped object would sit.
    ///
    /// Separate from `position` because they are ~10cm apart and answer
    /// different questions: testing a grip against the wrist meant the hand had
    /// to overshoot the target by a whole hand's length before it counted.
    var gripPosition: SIMD3<Float>
    var radius: Float = HandProxy.defaultRadius
    var updatedAt: TimeInterval
    /// Full hand shape, in the hand's own frame. **Nil when the pose isn't
    /// known**, which is not the same as open — reporting unknown as open is
    /// what let a closed fist arm a grip target, since ARKit loses the
    /// fingertips exactly when the hand closes.
    var pose: HandPose?

    /// Whether the hand pose is known at all.
    var handKnown: Bool { pose != nil }

    /// Both are false when the pose is unknown. Used for coarse checks only —
    /// grabbing an object goes through `GrabConfidence`, which weighs the whole
    /// hand rather than one number.
    var isGripping: Bool { (pose?.fingerCurl ?? 0) >= 0.6 }
    var isOpen: Bool { (pose?.fingerCurl ?? 1) <= 0.3 }
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

    private var previousPose: [HandAnchor.Chirality: HandPose] = [:]
    private var previousPoseTime: [HandAnchor.Chirality: TimeInterval] = [:]

    /// Called after each batch of anchor updates. Not observed by SwiftUI.
    @ObservationIgnored var onUpdate: (() -> Void)?

    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    /// Head pose. visionOS never exposes eye gaze to apps, so head direction is
    /// what "looking at something" has to mean.
    private let worldTracking = WorldTrackingProvider()
    private var updateTask: Task<Void, Never>?

    /// Current head transform, or nil if world tracking hasn't produced one.
    func deviceTransform() -> simd_float4x4? {
        guard worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked
        else { return nil }
        return anchor.originFromAnchorTransform
    }

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
            // One session for both: hand anchors and head pose are needed
            // together, and calibration confirms with a head-direction dwell.
            var providers: [any DataProvider] = [provider]
            if WorldTrackingProvider.isSupported { providers.append(worldTracking) }
            try await session.run(providers)
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
        let proxy = anchor.isTracked ? makeProxy(from: anchor) : nil
        switch anchor.chirality {
        case .left: left = proxy
        case .right: right = proxy
        @unknown default: break
        }
    }

    private func makeProxy(from anchor: HandAnchor) -> HandProxy? {
        guard let skeleton = anchor.handSkeleton else { return nil }

        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return nil }

        let world = anchor.originFromAnchorTransform * wrist.anchorFromJointTransform
        let wristPosition = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)

        let now = CACurrentMediaTime()
        let delta = now - (previousPoseTime[anchor.chirality] ?? now)
        let pose = HandPose.make(
            from: anchor,
            previous: previousPose[anchor.chirality],
            deltaTime: delta
        )
        if let pose {
            previousPose[anchor.chirality] = pose
            previousPoseTime[anchor.chirality] = now
        }

        return HandProxy(
            position: wristPosition,
            // The palm, not the fingertips: it is the stable centre of the
            // hand and the thing a grip volume is built around.
            gripPosition: pose?.palmCenter ?? wristPosition,
            updatedAt: anchor.timestamp,
            pose: pose
        )
    }



}
