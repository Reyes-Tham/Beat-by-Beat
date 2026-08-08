//
//  GrabDetector.swift
//  BeatByBeat
//

import Foundation
import simd

/// How the hand came at the object. Derived from where the object sits
/// relative to the palm, not from which way the wrist is turned.
///
/// This is what makes "cup" and "overhand" describable without demanding a
/// textbook wrist angle: reaching down onto something and reaching across to
/// something are different approaches even when the hand shape is identical.
enum ApproachDirection: String {
    case side
    case top

    static func from(palmCenter: SIMD3<Float>, object: SIMD3<Float>) -> ApproachDirection {
        let toObject = object - palmCenter
        guard length(toObject) > 1e-4 else { return .side }
        // Object clearly below the hand → the hand came down onto it.
        return dot(normalize(toObject), SIMD3<Float>(0, -1, 0)) >= 0.55 ? .top : .side
    }
}

/// Blended evidence that the hand is closing on a particular object.
///
/// A weighted score rather than a chain of booleans. Any single test fails
/// often enough on a tracked hand — and on an impaired one — that requiring
/// all of them to pass at once is how grabs come to feel arbitrary.
struct GrabConfidence {
    var closure: Float      // 30%
    var opposition: Float   // 20%
    var inVolume: Float     // 25%
    var proximity: Float    // 15%
    var closing: Float      // 10%

    var total: Float {
        0.30 * closure + 0.20 * opposition + 0.25 * inVolume
            + 0.15 * proximity + 0.10 * closing
    }

    /// - Parameter maxCurl: this patient's own comfortable maximum closure.
    ///   Curl is scored against that rather than against a healthy full fist,
    ///   so a hand that cannot close all the way is not permanently at zero.
    static func evaluate(
        pose: HandPose,
        object: SIMD3<Float>,
        objectRadius: Float,
        maxCurl: Float
    ) -> GrabConfidence {
        let ceiling = max(0.25, maxCurl)
        let closure = min(1, pose.fingerCurl / ceiling)

        let reach = pose.handLength * 1.6 + objectRadius
        let proximity = min(1, max(0, 1 - pose.distanceToPalm(object) / reach))

        // Volume test is graded rather than binary: a slightly larger box gives
        // partial credit, so an object at the edge of the hand still scores.
        let inVolume: Float = pose.gripVolumeContains(object) ? 1
            : (pose.gripVolumeContains(object, scale: 1.45) ? 0.5 : 0)

        // Any closing at all counts; the rate only says the hand is moving the
        // right way, not how fast it should.
        let closing = min(1, max(0, pose.closingRate / 1.5))

        return GrabConfidence(
            closure: closure,
            opposition: pose.thumbOpposition,
            inVolume: inVolume,
            proximity: proximity,
            closing: closing
        )
    }
}

/// Per-object grab state.
///
/// A state machine rather than a per-frame test, because hand tracking jitters
/// and a single frame is never evidence. Grab and release use different
/// thresholds so an object cannot flicker between held and dropped.
enum GrabPhase: String, Codable {
    case open
    case approaching
    case enclosing
    case grabbed
    case releasing
}

struct GrabState: Codable {
    var phase: GrabPhase = .open
    var frames: Int = 0

    static let grabThreshold: Float = 0.65
    static let enclosingThreshold: Float = 0.55
    static let releaseThreshold: Float = 0.35
    /// ~110ms at 90Hz. Long enough to reject jitter, short enough not to feel
    /// like a delay.
    static let holdFrames = 10

    /// Advances the machine. Returns true on the frame the object is grabbed.
    ///
    /// - Parameter handOpen: the hand is genuinely open, judged on curl alone
    ///   rather than on blended confidence — proximity and volume terms are
    ///   high whenever the hand is near the object, so the blend can't tell an
    ///   open hand from a closed one.
    mutating func update(confidence: Float, objectNear: Bool, handOpen: Bool) -> Bool {
        switch phase {
        case .open:
            // The hand has to arrive *open*. Arming on proximity alone let a
            // hand that was already closed walk straight through to a grab.
            if objectNear, handOpen { phase = .approaching; frames = 0 }

        case .approaching:
            guard objectNear else { phase = .open; frames = 0; break }
            if confidence >= Self.enclosingThreshold { phase = .enclosing; frames = 0 }

        case .enclosing:
            guard objectNear else { phase = .open; frames = 0; break }
            if confidence >= Self.grabThreshold {
                frames += 1
                if frames >= Self.holdFrames {
                    phase = .grabbed
                    frames = 0
                    return true
                }
            } else if confidence < Self.releaseThreshold {
                phase = .approaching
                frames = 0
            } else {
                frames = 0
            }

        case .grabbed:
            // Only a clear opening releases. The gap between the thresholds is
            // what stops a jittering hand dropping and re-grabbing.
            if confidence <= Self.releaseThreshold { phase = .releasing; frames = 0 }

        case .releasing:
            if confidence >= Self.grabThreshold {
                phase = .grabbed
                frames = 0
            } else {
                frames += 1
            }
        }
        return false
    }

    /// True once the hand has clearly let go and held it.
    var hasReleased: Bool { phase == .releasing && frames >= Self.holdFrames }

    var isHolding: Bool { phase == .grabbed || phase == .releasing }
}
