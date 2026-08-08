//
//  TargetEntity.swift
//  BeatByBeat
//

import RealityKit
import SwiftUI

/// Marks an entity as a hittable rhythm target.
/// Progress through a pour's waypoints.
struct PourComponent: Component {
    var waypoints: [SIMD3<Float>]
    var nextIndex: Int = 0
    var isComplete: Bool { nextIndex >= waypoints.count }
}

struct TargetComponent: Component {
    var movement: MovementType = .reach
    /// Set only on grip targets: how the hand has to be turned.
    var gripOrientation: GripOrientation?
    /// Grip targets only: the open hand has been seen at the target, so a
    /// closing hand now counts. Without this the target scores off whatever
    /// the hand happened to already be doing when it arrived.
    var gripArmed: Bool = false
    /// Consecutive frames the hand has held the pose being waited for. Hand
    /// tracking is noisy enough that a single frame is not evidence.
    var gripFrames: Int = 0
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
        noteIndex: Int = -1,
        movement: MovementType = .reach,
        gripOrientation: GripOrientation? = nil
    ) -> Entity {
        if movement == .pour {
            return makePourTube(hand: hand, radius: radius, noteIndex: noteIndex)
        }

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
        if movement == .grip {
            // A ring around the sphere: reads as something to close a hand on
            // rather than something to bump into.
            let ring = ModelEntity(
                mesh: .generateSphere(radius: radius * 1.5),
                materials: [gripRingMaterial(tint: tint(for: hand))]
            )
            ring.name = "GripRing"
            root.addChild(ring)

            if let icon = makeGripIcon(radius: radius, orientation: gripOrientation) {
                root.addChild(icon)
            }
        }

        root.components.set(TargetComponent(
            movement: movement,
            gripOrientation: gripOrientation,
            hand: hand,
            radius: radius,
            noteIndex: noteIndex
        ))

        return root
    }

    /// Number of waypoints along a pour path.
    nonisolated static let pourWaypoints = 5

    /// A curved tube the hand is guided along, waypoint by waypoint.
    ///
    /// An arc rather than a straight line: pouring is a controlled trajectory
    /// with forearm rotation, and a straight path would just be a slow reach.
    static func makePourTube(
        hand: TrainingHand,
        radius: Float,
        noteIndex: Int
    ) -> Entity {
        let root = Entity()
        root.name = "Pour[\(hand.rawValue)#\(noteIndex)]"

        // Arc sweeps across the body and lifts in the middle, mirrored so each
        // arm curves outward from its own side.
        let direction: Float = hand == .left ? -1 : 1
        let span: Float = 0.30
        var points: [SIMD3<Float>] = []
        for step in 0..<pourWaypoints {
            let t = Float(step) / Float(pourWaypoints - 1)
            points.append([
                (t - 0.5) * span * direction,
                sin(t * .pi) * 0.10,
                -sin(t * .pi) * 0.04
            ])
        }

        for (index, point) in points.enumerated() {
            let node = ModelEntity(
                mesh: .generateSphere(radius: radius * 0.55),
                materials: [material(tint: tint(for: hand), opacity: 1.0)]
            )
            node.name = "Way\(index)"
            node.position = point
            // All but the first start dim: the lit one is where to go next.
            node.components.set(OpacityComponent(opacity: index == 0 ? 1 : 0.28))
            root.addChild(node)
        }

        root.components.set(PourComponent(waypoints: points))
        root.components.set(TargetComponent(
            movement: .pour,
            hand: hand,
            radius: radius * 0.9,
            noteIndex: noteIndex
        ))
        return root
    }

    /// Lights the next waypoint and dims the ones already passed.
    static func updatePour(_ entity: Entity, nextIndex: Int) {
        for index in 0..<pourWaypoints {
            guard let node = entity.findEntity(named: "Way\(index)") else { continue }
            let opacity: Float = index < nextIndex ? 0.12 : (index == nextIndex ? 1 : 0.28)
            node.components.set(OpacityComponent(opacity: opacity))
        }
    }

    /// Fist badge sitting on top of the sphere, so a grip note is identifiable
    /// before the hand gets there rather than only once it fails to score.
    ///
    /// Uses a bundled `grip_icon` image when one is present and falls back to a
    /// drawn glyph otherwise — drop a PNG in Resources to replace the artwork
    /// without touching this code.
    static func makeGripIcon(radius: Float, orientation: GripOrientation? = nil) -> Entity? {
        guard let texture = gripTexture(for: orientation) else { return nil }

        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)
        material.opacityThreshold = 0.02

        let size = radius * 1.5
        let plane = ModelEntity(mesh: .generatePlane(width: size, height: size), materials: [material])
        let root = Entity()
        root.name = "GripIcon"
        root.position = [0, radius * 1.85, 0]
        root.addChild(plane)
        root.components.set(BillboardComponent())
        return root
    }

    /// One glyph per orientation, built once on first use.
    ///
    /// Distinct pictures rather than the same fist rotated: a rotated fist and
    /// an upright one are hard to tell apart at target size and across the
    /// room, which is most of why the orientations felt indistinguishable.
    nonisolated(unsafe) private static var cachedIcons: [String: TextureResource] = [:]

    private static func gripTexture(for orientation: GripOrientation?) -> TextureResource? {
        let key = orientation?.rawValue ?? "grip"
        if let cached = cachedIcons[key] { return cached }

        let image: UIImage = switch orientation {
        case .cup: drawMug()
        default: drawFist()
        }
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        else { return nil }
        cachedIcons[key] = texture
        return texture
    }

    /// Mug outline: square-ish body with a D handle, matching the usual
    /// pictogram for a cup grasp.
    private static func drawMug(side: CGFloat = 256) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let c = ctx.cgContext
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(side * 0.055)
            c.setLineCap(.round)
            c.setLineJoin(.round)

            let u = side / 100

            c.addPath(UIBezierPath(
                roundedRect: CGRect(x: 12 * u, y: 20 * u, width: 52 * u, height: 60 * u),
                cornerRadius: 8 * u
            ).cgPath)

            // Handle: a half-round on the right side of the body.
            let handle = UIBezierPath(
                arcCenter: CGPoint(x: 64 * u, y: 45 * u),
                radius: 18 * u,
                startAngle: -.pi / 2,
                endAngle: .pi / 2,
                clockwise: true
            )
            c.addPath(handle.cgPath)

            c.strokePath()
        }
    }

    /// Outline fist, drawn to match the usual grip pictogram: a block of four
    /// finger segments with the thumb folded across them.
    private static func drawFist(side: CGFloat = 256) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let c = ctx.cgContext
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(side * 0.055)
            c.setLineCap(.round)
            c.setLineJoin(.round)

            let u = side / 100  // work in a 100×100 grid

            // Palm / fist body.
            c.addPath(UIBezierPath(
                roundedRect: CGRect(x: 16 * u, y: 40 * u, width: 56 * u, height: 46 * u),
                cornerRadius: 12 * u
            ).cgPath)

            // Four finger segments folded over the top.
            for index in 0..<4 {
                let x = 30 * u + CGFloat(index) * 12 * u
                c.addPath(UIBezierPath(
                    roundedRect: CGRect(x: x, y: (14 + CGFloat(index) * 3) * u,
                                        width: 11 * u, height: (30 - CGFloat(index) * 2) * u),
                    cornerRadius: 5.5 * u
                ).cgPath)
            }

            // Thumb across the front.
            c.addPath(UIBezierPath(
                roundedRect: CGRect(x: 22 * u, y: 52 * u, width: 34 * u, height: 12 * u),
                cornerRadius: 6 * u
            ).cgPath)

            c.strokePath()
        }
    }

    /// Brightens the ring once the open hand has been seen, so the patient can
    /// tell the difference between "get here" and "now close".
    static func setGripArmed(_ target: Entity, armed: Bool, hand: TrainingHand) {
        guard let ring = target.findEntity(named: "GripRing") as? ModelEntity else { return }
        ring.model?.materials = [
            gripRingMaterial(tint: armed ? .white : tint(for: hand), opacity: armed ? 0.55 : 0.22)
        ]
    }

    private static func gripRingMaterial(
        tint: UIColor,
        opacity: Float = 0.22
    ) -> RealityKit.Material {
        var material = UnlitMaterial(color: tint)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .front
        return material
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

    nonisolated static let hitAnimationSeconds: TimeInterval = 0.12
    nonisolated static let dustSeconds: TimeInterval = 1.2

    /// Collapse on contact, quickly, so the dust burst reads as the sphere
    /// coming apart rather than as something separate happening next to it.
    static func playHitAnimation(on entity: Entity) {
        var collapsed = entity.transform
        collapsed.scale = .init(repeating: 0.01)
        entity.move(
            to: collapsed,
            relativeTo: entity.parent,
            duration: hitAnimationSeconds,
            timingFunction: .easeIn
        )
    }

    /// An idle dust emitter, ready to be fired.
    ///
    /// Built once and reused rather than created per hit. A freshly created
    /// emitter has to be registered, started and stopped inside a couple of
    /// frames, and it does not reliably get to emit in that window — which is
    /// why the effect only appeared some of the time.
    static func makeDustEmitter(radius: Float) -> Entity {
        let entity = Entity()
        entity.name = "Dust"

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterShapeSize = .init(repeating: radius * 0.75)
        particles.birthLocation = .volume
        particles.birthDirection = .normal
        particles.speed = 0.32
        particles.speedVariation = 0.24
        // Silent until fired: continuous emission is off, and each hit
        // releases one burst.
        particles.isEmitting = false
        particles.burstCount = 320

        particles.mainEmitter.birthRate = 0
        particles.mainEmitter.lifeSpan = 0.65
        particles.mainEmitter.lifeSpanVariation = 0.35
        // Fine: small enough to read as dust rather than as debris.
        particles.mainEmitter.size = 0.0035
        particles.mainEmitter.sizeVariation = 0.0022
        particles.mainEmitter.opacityCurve = .easeFadeOut
        particles.mainEmitter.blendMode = .additive
        // A little gravity so the cloud settles instead of hanging.
        particles.mainEmitter.acceleration = [0, -0.45, 0]
        particles.mainEmitter.dampingFactor = 2.4

        entity.components.set(particles)
        return entity
    }

    /// Fires one burst, recoloured for the arm that earned it.
    static func fireDust(_ entity: Entity, hand: TrainingHand) {
        guard var particles = entity.components[ParticleEmitterComponent.self] else { return }
        particles.mainEmitter.color = .evolving(
            start: .single(tint(for: hand)),
            end: .single(.init(white: 1, alpha: 0))
        )
        particles.burst()
        entity.components.set(particles)
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
