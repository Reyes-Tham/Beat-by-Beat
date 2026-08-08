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

        // Opaque, deliberately. A translucent target does not write depth, so
        // it sorts per-entity against the window panel and against its own
        // approach shell — which showed up as the panel ghosting through it.
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material(tint: tint(for: hand), opacity: 1.0)]
        )
        sphere.name = "Core"
        root.addChild(sphere)

        if let letter = handLetter(hand, radius: radius) {
            root.addChild(letter)
        }

        // Present from the start so palm-proxy contact is a plain
        // CollisionComponent query later, not a mesh walk.
        root.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: radius)],
            mode: .trigger
        ))
        root.components.set(TargetComponent(hand: hand, radius: radius, noteIndex: noteIndex))

        return root
    }

    /// "L" or "R" sitting on the face of the target.
    ///
    /// Says which arm outright rather than relying on colour alone, which is
    /// the plan's §17 requirement — and unlike the pips it was carrying before,
    /// a letter is unambiguous at a glance and doesn't read as clutter.
    ///
    /// Offset toward the player (+Z) so it clears the opaque sphere, and
    /// billboarded so it stays square-on as they move.
    private static func handLetter(_ hand: TrainingHand, radius: Float) -> Entity? {
        let glyph: String
        switch hand {
        case .left: glyph = "L"
        case .right: glyph = "R"
        case .both: return nil
        }

        let root = Entity()
        root.name = "HandLetter"
        root.position = [0, 0, radius + 0.008]

        let mesh = MeshResource.generateText(
            glyph,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: CGFloat(radius) * 1.1, weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let text = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        // generateText lays out from the baseline's left edge, so the glyph has
        // to be shifted back onto the anchor to sit centred on the sphere.
        let bounds = text.visualBounds(relativeTo: nil)
        text.position = -bounds.center
        root.addChild(text)

        root.components.set(BillboardComponent())
        return root
    }

    /// Dim marker used to outline the spawn volume during development.
    /// Opaque despite being a debug aid — it is tiny, and keeping it out of the
    /// transparent pass means it can't sort oddly against targets.
    static func makeDebugDot(radius: Float = 0.012) -> Entity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material(tint: .init(white: 0.75, alpha: 1), opacity: 1.0)]
        )
        entity.name = "DebugDot"
        return entity
    }

    /// Scale the approach shell starts at, relative to the target sphere.
    nonisolated static let approachStartScale: Float = 2.4

    /// Scale the shell stops at. Never 1.0: two identical sphere meshes at the
    /// same scale are coplanar and z-fight, which is what put a hard seam
    /// across the target's equator.
    nonisolated static let approachEndScale: Float = 1.12

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
        collapsed.scale = .init(repeating: approachEndScale)
        shell.move(to: collapsed, relativeTo: target, duration: travelTime, timingFunction: .linear)

        // Dissolve rather than pop. The fade starts shortly *before* the beat
        // and finishes just after it, so the shell is still visible at the
        // moment of arrival — fading it out earlier would erase the very cue
        // it exists to give.
        let lead = min(0.30, travelTime * 0.2)
        Task {
            try? await Task.sleep(for: .seconds(max(0, travelTime - lead)))
            guard let shell = target.findEntity(named: "ApproachShell") else { return }
            fade(shell, to: 0, duration: lead + 0.25)
            try? await Task.sleep(for: .seconds(lead + 0.25))
            removeApproachShell(from: target)
        }
    }

    /// Animates an entity's overall opacity. `OpacityComponent` scales whatever
    /// the material already does, so a 34%-opaque shell fades 34% → 0.
    static func fade(_ entity: Entity, to opacity: Float, duration: TimeInterval) {
        let current = entity.components[OpacityComponent.self]?.opacity ?? 1
        entity.components.set(OpacityComponent(opacity: current))

        let animation = FromToByAnimation(
            name: "fade",
            from: current,
            to: opacity,
            duration: duration,
            timing: .easeOut,
            bindTarget: .opacity
        )
        if let resource = try? AnimationResource.generate(with: animation) {
            entity.playAnimation(resource)
        } else {
            // Better a hard cut than a shell that never leaves.
            entity.components.set(OpacityComponent(opacity: opacity))
        }
    }

    /// Removes the shell outright — used when contact lands, when the note
    /// expires, and when the countdown finishes.
    static func removeApproachShell(from target: Entity) {
        guard let shell = target.findEntity(named: "ApproachShell") else { return }
        shell.stopAllAnimations()
        shell.removeFromParent()
    }

    /// Confirm circle for calibration: an outline that fills as the player
    /// holds their head toward it. The fill is the only progress indicator
    /// they can see without looking away from it.
    static func makeConfirmCircle(radius: Float = 0.055) -> Entity {
        let root = Entity()
        root.name = "ConfirmCircle"

        let backing = ModelEntity(
            mesh: .generateCylinder(height: 0.004, radius: radius),
            materials: [material(tint: .init(white: 0.9, alpha: 1), opacity: 0.22)]
        )
        // Cylinders stand along Y; lay it flat so the face points outward,
        // then billboard the parent so it always faces the player.
        backing.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        backing.name = "Backing"
        root.addChild(backing)

        let fill = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: radius * 0.86),
            materials: [material(tint: UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1),
                                 opacity: 1.0)]
        )
        fill.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        fill.name = "Fill"
        fill.scale = [0.001, 1, 0.001]
        root.addChild(fill)

        root.components.set(BillboardComponent())
        return root
    }

    /// Grows the fill to match dwell progress.
    static func updateConfirmCircle(_ circle: Entity, progress: Float) {
        guard let fill = circle.findEntity(named: "Fill") else { return }
        let scale = max(0.001, progress)
        fill.scale = [scale, 1, scale]
    }

    nonisolated static let praiseSeconds: TimeInterval = 0.9

    /// Floating praise for a hit — rises out of the target and dissolves.
    ///
    /// Billboarded so it stays readable wherever the player is looking, and
    /// unlit so it doesn't dim in a dark room.
    static func makePraiseLabel(for judgement: Judgement) -> Entity {
        let root = Entity()
        root.name = "Praise"

        let mesh = MeshResource.generateText(
            judgement.praise,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.055, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let text = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: praiseTint(judgement))])
        // generateText lays out from the baseline's left edge, so the mesh has
        // to be shifted back onto the anchor to sit over the target.
        let bounds = text.visualBounds(relativeTo: nil)
        text.position = -bounds.center
        root.addChild(text)

        root.components.set(BillboardComponent())
        return root
    }

    /// Rises and fades. Caller destroys it after `praiseSeconds`.
    static func playPraiseAnimation(on entity: Entity) {
        var risen = entity.transform
        risen.translation.y += 0.14
        entity.move(to: risen, relativeTo: entity.parent,
                    duration: praiseSeconds, timingFunction: .easeOut)
        fade(entity, to: 0, duration: praiseSeconds)
    }

    private static func praiseTint(_ judgement: Judgement) -> UIColor {
        // Deliberately off the hand palette (cyan / amber) so praise can never
        // be mistaken for a which-arm cue.
        switch judgement {
        case .excellent: UIColor(red: 1.00, green: 0.86, blue: 0.30, alpha: 1)  // gold
        case .good:      UIColor(white: 1.00, alpha: 1)                          // white
        case .reached:   UIColor(white: 0.72, alpha: 1)                          // soft grey
        }
    }

    /// Tears an entity down completely.
    ///
    /// `removeFromParent()` alone leaves running animations and child entities
    /// holding the subtree alive, so a target that looked gone could still be
    /// animating and still be referenced. Stopping animations first, then
    /// dismantling children, makes the removal final.
    static func destroy(_ entity: Entity) {
        entity.stopAllAnimations(recursive: true)
        for child in entity.children.reversed() {
            destroy(child)
        }
        entity.components.removeAll()
        entity.removeFromParent()
    }

    /// Visible marker for the palm proxy. Invaluable while tuning the hit
    /// radius — you can see exactly what the collision is using.
    static func makeHandProxyMarker(radius: Float) -> Entity {
        // Faint: it sits between the player and everything else, and at the
        // Simulator stand-in's larger radius a solid sphere this size blots
        // out the targets it is meant to be reaching.
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material(tint: .white, opacity: 0.12)]
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
        // Only opt into the transparent pass when it's actually needed —
        // anything transparent skips depth writes and has to be sorted.
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }
}
