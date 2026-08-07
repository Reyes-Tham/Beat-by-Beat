//
//  TargetEntity.swift
//  BeatByBeat
//

import RealityKit
import SwiftUI

/// Marks an entity as a hittable rhythm target.
struct TargetComponent: Component {
    var hand: TrainingHand
    /// Radius of the sphere in metres, cached so hit tests don't walk the mesh.
    var radius: Float
    /// Index into the chart. -1 for practice targets with no beat.
    var noteIndex: Int = -1
    /// Song time this target should be contacted at. Nil in practice mode.
    var beatTime: TimeInterval?
    /// How long the player was given to reach it, for scaling the timing window.
    var travelTime: TimeInterval = 1
}

enum TargetEntity {

    /// Default target radius. Deliberately generous — the plan calls for a
    /// forgiving hit volume, and this gets tuned on device.
    nonisolated static let defaultRadius: Float = 0.07

    static func make(
        hand: TrainingHand,
        radius: Float = defaultRadius,
        noteIndex: Int = -1
    ) -> Entity {
        let root = Entity()
        root.name = "Target[\(hand.rawValue)#\(noteIndex)]"

        let sphere = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material(tint: tint(for: hand), opacity: 0.85)]
        )
        root.addChild(sphere)

        // Present from the start so palm-proxy contact is a plain
        // CollisionComponent query later, not a mesh walk.
        root.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: radius)],
            mode: .trigger
        ))
        root.components.set(TargetComponent(hand: hand, radius: radius, noteIndex: noteIndex))

        return root
    }

    /// Dim marker used to outline the spawn volume during development.
    static func makeDebugDot(radius: Float = 0.012) -> Entity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material(tint: .white, opacity: 0.45)]
        )
        entity.name = "DebugDot"
        return entity
    }

    /// Scale the approach shell starts at, relative to the target sphere.
    nonisolated static let approachStartScale: Float = 2.4

    /// Adds a shell that shrinks onto the sphere, reaching it exactly on the
    /// beat. Contact should happen as the two meet.
    ///
    /// Continuous rather than a colour change, because a patient mid-reach
    /// needs to know whether they are on pace — which a discrete state can't
    /// tell them. Geometric, so it survives colourblindness with no extra work.
    ///
    /// Linear timing on purpose: the shrink rate has to read as a constant
    /// countdown, and easing would make the remaining time misleading.
    static func addApproachShell(to target: Entity, travelTime: TimeInterval, hand: TrainingHand) {
        guard let sphere = target.children.first as? ModelEntity,
              let mesh = sphere.model?.mesh
        else { return }

        // Tinted to the hand it belongs to, so which arm is being asked for is
        // readable from the moment the shell appears rather than only once the
        // target underneath is visible.
        let shell = ModelEntity(mesh: mesh, materials: [shellMaterial(tint: tint(for: hand))])
        shell.name = "ApproachShell"
        shell.scale = .init(repeating: approachStartScale)
        target.addChild(shell)

        var collapsed = shell.transform
        collapsed.scale = .one
        shell.move(to: collapsed, relativeTo: target, duration: travelTime, timingFunction: .linear)
    }

    /// Freezes the shell where it is — used when contact lands early, so the
    /// target visibly "locks" instead of continuing to count down.
    static func lockApproachShell(on target: Entity) {
        guard let shell = target.findEntity(named: "ApproachShell") else { return }
        shell.stopAllAnimations()
        shell.isEnabled = false
    }

    /// Visible marker for the palm proxy. Invaluable while tuning the hit
    /// radius — you can see exactly what the collision is using.
    static func makeHandProxyMarker(radius: Float) -> Entity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material(tint: .white, opacity: 0.25)]
        )
        entity.name = "HandProxy"
        return entity
    }

    /// Pop-in used when a target spawns. Cheap stand-in for real VFX.
    static func playSpawnAnimation(on entity: Entity, duration: TimeInterval = 0.25) {
        let final = entity.transform
        var start = final
        start.scale = .init(repeating: 0.01)
        entity.transform = start
        entity.move(to: final, relativeTo: entity.parent, duration: duration, timingFunction: .easeOut)
    }

    nonisolated static let missAnimationSeconds: TimeInterval = 0.35

    /// Quiet shrink-away for a target that was never reached. Deliberately
    /// undramatic — not reaching in time is not a failure worth punctuating.
    static func playMissAnimation(on entity: Entity) {
        var faded = entity.transform
        faded.scale = .init(repeating: 0.01)
        entity.move(
            to: faded,
            relativeTo: entity.parent,
            duration: missAnimationSeconds,
            timingFunction: .easeIn
        )
    }

    nonisolated static let hitAnimationSeconds: TimeInterval = 0.18

    /// Burst outward on contact, so a hit is unmistakable even in peripheral
    /// vision. Caller removes the entity once this finishes.
    static func playHitAnimation(on entity: Entity) {
        var burst = entity.transform
        burst.scale = .init(repeating: 1.7)
        entity.move(
            to: burst,
            relativeTo: entity.parent,
            duration: hitAnimationSeconds,
            timingFunction: .easeOut
        )
    }

    // MARK: - Appearance

    private static func tint(for hand: TrainingHand) -> UIColor {
        switch hand {
        case .left:  UIColor(red: 0.24, green: 0.72, blue: 1.00, alpha: 1)   // cyan
        case .right: UIColor(red: 1.00, green: 0.55, blue: 0.18, alpha: 1)   // amber
        case .both:  UIColor(red: 0.70, green: 0.60, blue: 1.00, alpha: 1)   // violet
        }
    }

    /// Unlit so it reads the same against a bright room or a dark one. Faint
    /// enough not to compete with the target, but not so faint that a target
    /// appears to arrive out of nowhere — that trade-off is what this number
    /// controls, so tune it here.
    private static func shellMaterial(tint: UIColor) -> RealityKit.Material {
        var material = UnlitMaterial(color: tint)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.34))
        return material
    }

    private static func material(tint: UIColor, opacity: Float) -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.emissiveColor = .init(color: tint)
        material.emissiveIntensity = 0.65
        material.roughness = 0.3
        material.metallic = 0.0
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }
}
