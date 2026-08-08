//
//  HandPose.swift
//  BeatByBeat
//

import ARKit
import simd

/// Everything about one hand's shape, measured in the hand's own frame.
///
/// Hand-local on purpose. Comparing joints against world axes — "is the palm
/// facing down" — forces a textbook wrist angle and fails the moment someone
/// approaches an object from a natural direction, which is most of the time.
/// Expressed relative to the palm, the same grasp reads identically whether
/// the hand comes in from the side, from above, or upside down.
struct HandPose {
    /// Centre of the palm, world space.
    var palmCenter: SIMD3<Float>
    /// Toward the fingers, out of the palm, and across it. Orthonormal.
    var forward: SIMD3<Float>
    var palmNormal: SIMD3<Float>
    var lateral: SIMD3<Float>
    /// Wrist to middle knuckle. Everything else is scaled by this so the
    /// measurements work across hand sizes.
    var handLength: Float

    /// Per-finger closure, 0 open … 1 fully curled.
    var indexCurl: Float
    var middleCurl: Float
    var ringCurl: Float
    var littleCurl: Float
    /// How far the thumb has come across the palm, 0 … 1.
    var thumbOpposition: Float
    /// Palm speed, m/s.
    var speed: Float
    /// Rate of change of curl. Positive while closing.
    var closingRate: Float

    /// Weighted closure. Index and middle carry most of it because they do
    /// most of the work in a real grasp, and because they are the fingers
    /// tracking holds onto longest.
    var fingerCurl: Float {
        0.30 * indexCurl + 0.30 * middleCurl + 0.20 * ringCurl + 0.20 * littleCurl
    }

    /// Whether a point sits inside the volume the hand could close around.
    ///
    /// A box in front of the palm, scaled to the hand rather than fixed in
    /// centimetres. This is the test that makes approach direction irrelevant:
    /// it asks whether the object is *in the hand*, not where the hand is
    /// pointing.
    func gripVolumeContains(_ worldPoint: SIMD3<Float>, scale: Float = 1) -> Bool {
        let offset = worldPoint - gripVolumeCenter
        let half = SIMD3<Float>(
            0.55 * handLength * scale,   // across the palm
            0.55 * handLength * scale,   // palm to fingertips
            0.75 * handLength * scale    // through the grip
        )
        return abs(dot(offset, lateral)) <= half.x
            && abs(dot(offset, forward)) <= half.y
            && abs(dot(offset, palmNormal)) <= half.z
    }

    /// Sits just in front of the palm, where a held object actually rests.
    var gripVolumeCenter: SIMD3<Float> {
        palmCenter + forward * (handLength * 0.45) + palmNormal * (handLength * 0.35)
    }

    /// Distance from the palm, for the proximity term.
    func distanceToPalm(_ worldPoint: SIMD3<Float>) -> Float {
        distance(worldPoint, palmCenter)
    }
}

// MARK: - Simulator

extension HandPose {
    /// A plausible hand for the Simulator, which has no skeleton at all.
    /// Fully curled or fully open, oriented as if reaching forward.
    static func simulated(at position: SIMD3<Float>, closed: Bool) -> HandPose {
        let curl: Float = closed ? 0.95 : 0.05
        return HandPose(
            palmCenter: position,
            forward: [0, 0, -1],
            palmNormal: [0, 1, 0],
            lateral: [1, 0, 0],
            handLength: 0.09,
            indexCurl: curl,
            middleCurl: curl,
            ringCurl: curl,
            littleCurl: curl,
            thumbOpposition: closed ? 0.9 : 0.05,
            speed: 0,
            closingRate: closed ? 1.5 : -1.5
        )
    }
}

// MARK: - Extraction

extension HandPose {

    /// Builds a pose from a tracked hand, or nil if too little is visible.
    ///
    /// `previous` supplies the motion terms.
    static func make(
        from anchor: HandAnchor,
        previous: HandPose?,
        deltaTime: TimeInterval
    ) -> HandPose? {
        guard let skeleton = anchor.handSkeleton else { return nil }

        func local(_ name: HandSkeleton.JointName) -> SIMD3<Float>? {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { return nil }
            let m = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            return SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        }

        guard let wrist = local(.wrist),
              let middleKnuckle = local(.middleFingerKnuckle),
              let indexKnuckle = local(.indexFingerKnuckle),
              let littleKnuckle = local(.littleFingerKnuckle)
        else { return nil }

        let handLength = distance(middleKnuckle, wrist)
        guard handLength > 0.02 else { return nil }

        let forward = normalize(middleKnuckle - wrist)
        // Chirality flips the cross product, so without this correction the
        // palm normal points the wrong way on one hand.
        let sign: Float = anchor.chirality == .left ? -1 : 1
        var normal = cross(indexKnuckle - wrist, littleKnuckle - wrist) * sign
        guard length(normal) > 1e-5 else { return nil }
        normal = normalize(normal)
        let lateral = normalize(cross(forward, normal))

        let palmCenter = (wrist + middleKnuckle) / 2

        /// Fingertip distance to the palm, as a fraction of hand length.
        /// Open sits near 1.30, a closed finger near 0.55.
        func curl(_ tip: HandSkeleton.JointName) -> Float {
            guard let position = local(tip) else { return 0 }
            let ratio = distance(position, palmCenter) / handLength
            return min(1, max(0, (1.30 - ratio) / (1.30 - 0.55)))
        }

        // The thumb coming across toward the index base, rather than pinching
        // its tip: a hand wrapped around a mug never touches thumb to index,
        // so a pinch test would call every power grip a failure.
        var opposition: Float = 0
        if let thumbTip = local(.thumbTip) {
            let ratio = distance(thumbTip, indexKnuckle) / handLength
            opposition = min(1, max(0, (1.05 - ratio) / (1.05 - 0.55)))
        }

        var pose = HandPose(
            palmCenter: palmCenter,
            forward: forward,
            palmNormal: normal,
            lateral: lateral,
            handLength: handLength,
            indexCurl: curl(.indexFingerTip),
            middleCurl: curl(.middleFingerTip),
            ringCurl: curl(.ringFingerTip),
            littleCurl: curl(.littleFingerTip),
            thumbOpposition: opposition,
            speed: 0,
            closingRate: 0
        )

        if let previous, deltaTime > 0.001, deltaTime < 0.5 {
            pose.speed = distance(palmCenter, previous.palmCenter) / Float(deltaTime)
            pose.closingRate = (pose.fingerCurl - previous.fingerCurl) / Float(deltaTime)
        }
        return pose
    }
}
