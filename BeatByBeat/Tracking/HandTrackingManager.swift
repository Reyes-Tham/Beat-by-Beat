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

    /// Thumb-to-index distance under which the hand counts as closed.
    /// Generous: a hemiparetic hand often can't fully oppose, and the point is
    /// to train the attempt, not to measure pinch precision.
    static let gripThreshold: Float = 0.045

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
    /// How closed the hand is, 0 open … 1 shut.
    var gripClosure: Float = 0
    /// Direction the palm faces, in world space. Zero when unknown.
    var palmNormal: SIMD3<Float> = .zero

    var isGripping: Bool { gripClosure >= 1 }
    /// Hand clearly open. The gap between this and `isGripping` is deliberate:
    /// a grip has to be a *movement* from one to the other, not a hand that
    /// drifted across a single threshold.
    var isOpen: Bool { gripClosure <= 0.25 }
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
        let proxy = anchor.isTracked ? Self.palmProxy(from: anchor) : nil
        switch anchor.chirality {
        case .left: left = proxy
        case .right: right = proxy
        @unknown default: break
        }
    }

    /// Wrist position in world space.
    private static func palmProxy(from anchor: HandAnchor) -> HandProxy? {
        guard let skeleton = anchor.handSkeleton else { return nil }

        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return nil }

        let world = anchor.originFromAnchorTransform * wrist.anchorFromJointTransform
        let wristPosition = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)

        return HandProxy(
            position: wristPosition,
            gripPosition: graspPoint(of: skeleton, anchor: anchor) ?? wristPosition,
            updatedAt: anchor.timestamp,
            gripClosure: closure(of: skeleton),
            palmNormal: palmNormal(of: skeleton, anchor: anchor) ?? .zero
        )
    }

    /// Midpoint of the thumb and index tips, in world space.
    private static func graspPoint(
        of skeleton: HandSkeleton,
        anchor: HandAnchor
    ) -> SIMD3<Float>? {
        let thumb = skeleton.joint(.thumbTip)
        let index = skeleton.joint(.indexFingerTip)
        guard thumb.isTracked, index.isTracked else { return nil }

        func world(_ joint: HandSkeleton.Joint) -> SIMD3<Float> {
            let m = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            return SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        }
        return (world(thumb) + world(index)) / 2
    }

    /// Which way the palm faces, from the plane through the wrist and the
    /// index and little knuckles.
    ///
    /// The cross product's sign follows the hand's chirality, so the left hand
    /// is flipped — otherwise every orientation would read inverted on one
    /// side and grips would only ever register with one hand.
    private static func palmNormal(
        of skeleton: HandSkeleton,
        anchor: HandAnchor
    ) -> SIMD3<Float>? {
        let wrist = skeleton.joint(.wrist)
        let index = skeleton.joint(.indexFingerKnuckle)
        let little = skeleton.joint(.littleFingerKnuckle)
        guard wrist.isTracked, index.isTracked, little.isTracked else { return nil }

        func world(_ joint: HandSkeleton.Joint) -> SIMD3<Float> {
            let m = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            return SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        }

        let origin = world(wrist)
        let normal = cross(world(index) - origin, world(little) - origin)
        guard length(normal) > 1e-5 else { return nil }
        let sign: Float = anchor.chirality == .left ? -1 : 1
        return normalize(normal) * sign
    }

    /// Thumb tip to index tip, mapped to 0…1. Nil-safe: an untracked fingertip
    /// reports open rather than closed, so a tracking gap can never look like
    /// a successful grip.
    private static func closure(of skeleton: HandSkeleton) -> Float {
        let thumb = skeleton.joint(.thumbTip)
        let index = skeleton.joint(.indexFingerTip)
        guard thumb.isTracked, index.isTracked else { return 0 }

        let a = thumb.anchorFromJointTransform.columns.3
        let b = index.anchorFromJointTransform.columns.3
        let gap = distance(SIMD3(a.x, a.y, a.z), SIMD3(b.x, b.y, b.z))

        let open: Float = 0.11
        let shut = HandProxy.gripThreshold
        return min(1, max(0, (open - gap) / (open - shut)))
    }
}
