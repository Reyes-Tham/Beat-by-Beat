//
//  TargetField.swift
//  BeatByBeat
//

import Foundation
import RealityKit

enum TargetLayout: String, CaseIterable, Identifiable {
    case grid, random
    var id: Self { self }
    var displayName: String { rawValue.capitalized }
}

enum FieldMode: String, CaseIterable, Identifiable {
    /// A fixed number of targets, replaced as they're reached. No music.
    /// The simplest possible scene for a first hand-tracking run.
    case practice
    /// Targets spawn from the chart and must be reached on the beat.
    case rhythm

    var id: Self { self }
    var displayName: String { rawValue.capitalized }
}

/// Owns the live target entities, in both modes.
@MainActor
final class TargetField {

    /// How close a replacement may spawn to a palm. Without this, the target
    /// you just hit is immediately replaced under your stationary hand and the
    /// field drains itself.
    private let minPalmClearance: Float = 0.25
    /// Minimum spacing between two live targets in random layout.
    private let minSeparation: Float = 0.18
    /// Gap before a practice replacement appears, so the hit reads as an event.
    private let respawnDelay: Duration = .milliseconds(250)

    var mode: FieldMode = .practice
    /// Union of both arms — used for the outline and for practice layout.
    var volume: SpawnVolume = .fixed
    /// Per-arm boundary. Each arm's targets are placed in its own box.
    var volumeForHand: ((TrainingHand) -> SpawnVolume)?
    var layout: TargetLayout = .grid
    var hand: TrainingHand = .both
    var targetCount: Int = 3

    private(set) var hitCount = 0
    private(set) var missedCount = 0
    private(set) var judgements: [Judgement: Int] = [:]
    /// Called after any scoring change so the UI can update.
    var onScoreChange: (() -> Void)?
    /// Ding played on contact. Nil until the resource finishes loading.
    var hitSound: AudioFileResource?
    /// Chime played where a target appears, so it can be located by ear before
    /// it is found by eye. Targets spawn off to the side often enough that a
    /// purely visual cue means looking around for them.
    var spawnSound: AudioFileResource?

    private let root: Entity
    private let outline: Entity
    /// Hit effects live here rather than loose under `root`, so clearing the
    /// field can't destroy a dust cloud or a praise label mid-flight.
    private let effects: Entity
    /// Pre-warmed dust emitters, cycled round-robin.
    private var dustPool: [Entity] = []
    private var nextDust = 0
    private var pendingSpawns = 0
    /// Last known palm positions, so a delayed respawn can still steer clear of
    /// a hand that hasn't moved since the hit.
    private var lastPalms: [SIMD3<Float>] = []

    init(root: Entity) {
        self.root = root
        self.outline = Entity()
        outline.name = "VolumeOutline"
        root.addChild(outline)

        self.effects = Entity()
        effects.name = "Effects"
        root.addChild(effects)

        // Eight is comfortably more than can be in flight at once: dust lives
        // ~1.2s and hits come at most about once a second at 5 stars.
        for _ in 0..<8 {
            let emitter = TargetEntity.makeDustEmitter(radius: TargetEntity.defaultRadius)
            effects.addChild(emitter)
            dustPool.append(emitter)
        }
    }

    // MARK: - Lifecycle

    /// Destroys every live target. Used by reset, and when a song stops so
    /// nothing is left floating in the scene.
    func clearTargets() {
        for child in root.children.reversed()
        where child !== outline && child !== effects {
            TargetEntity.destroy(child)
        }
        pendingSpawns = 0
    }

    /// Clears everything. Practice mode refills immediately; rhythm mode waits
    /// for the chart to drive it.
    func reset() {
        clearTargets()
        hitCount = 0
        missedCount = 0
        judgements = [:]
        redrawOutline()
        if mode == .practice { refill(avoiding: lastPalms) }
        onScoreChange?()
    }

    // MARK: - Practice spawning

    /// Tops the field back up to `targetCount`.
    func refill(avoiding palms: [SIMD3<Float>]) {
        guard mode == .practice else { return }
        while activeTargets.count + pendingSpawns < targetCount {
            guard let position = nextPosition(avoiding: palms) else { return }
            spawn(at: position, hand: handForNextTarget())
        }
    }

    @discardableResult
    func spawn(
        at position: SIMD3<Float>,
        hand: TrainingHand,
        radius: Float = TargetEntity.defaultRadius,
        noteIndex: Int = -1,
        beatTime: TimeInterval? = nil,
        travelTime: TimeInterval = 1,
        movement: MovementType = .reach,
        gripOrientation: GripOrientation? = nil,
        carryDestination: SIMD3<Float>? = nil
    ) -> Entity {
        let target = TargetEntity.make(
            hand: hand, radius: radius, noteIndex: noteIndex,
            movement: movement, gripOrientation: gripOrientation
        )
        target.position = position
        target.components[TargetComponent.self]?.beatTime = beatTime
        target.components[TargetComponent.self]?.travelTime = travelTime
        target.components[TargetComponent.self]?.origin = position
        target.components[TargetComponent.self]?.carryDestination = carryDestination

        if let carryDestination {
            let zone = TargetEntity.makeDropZone(
                hand: hand, radius: radius, noteIndex: noteIndex
            )
            zone.position = carryDestination
            root.addChild(zone)
        }
        root.addChild(target)
        TargetEntity.playSpawnAnimation(on: target)
        if beatTime != nil {
            TargetEntity.addApproachShell(to: target, travelTime: travelTime, hand: hand)
        }
        if let spawnSound {
            target.spatialAudio = SpatialAudioComponent()
            target.playAudio(spawnSound)
        }
        return target
    }

    /// `.both` alternates sides so each sphere still demands a specific hand —
    /// which is what makes wrong-hand hits get ignored for free.
    private func handForNextTarget() -> TrainingHand {
        guard hand == .both else { return hand }
        return activeTargets.count.isMultiple(of: 2) ? .left : .right
    }

    /// Picks a free spot, keeping clear of the palms and of other targets.
    private func nextPosition(avoiding palms: [SIMD3<Float>]) -> SIMD3<Float>? {
        let occupied = activeTargets.map(\.position)

        func isClearOfPalms(_ candidate: SIMD3<Float>) -> Bool {
            palms.allSatisfy { distance($0, candidate) >= minPalmClearance }
        }

        switch layout {
        case .grid:
            let slots = volume.gridPoints(columns: 4, rows: 3)
            let free = slots.filter { slot in
                !occupied.contains { distance($0, slot) < 0.01 }
            }
            // Prefer a slot away from the hands; fall back to any free slot so
            // the field never stalls with the player's hand parked mid-volume.
            return free.filter(isClearOfPalms).randomElement() ?? free.randomElement()

        case .random:
            var fallback: SIMD3<Float>?
            for _ in 0..<24 {
                let candidate = volume.randomPoint()
                fallback = candidate
                let spacedOut = occupied.allSatisfy { distance($0, candidate) >= minSeparation }
                if spacedOut, isClearOfPalms(candidate) { return candidate }
            }
            return fallback
        }
    }

    // MARK: - Rhythm spawning

    func spawn(note: ChartNote, index: Int) {
        let box = volumeForHand?(note.hand) ?? volume
        spawn(
            at: box.point(at: note.unit),
            hand: note.hand,
            noteIndex: index,
            beatTime: note.time,
            travelTime: note.travel,
            movement: note.movement,
            gripOrientation: note.gripOrientation,
            carryDestination: note.carryUnit.map { box.point(at: $0) }
        )
    }

    /// Retires targets whose beat has passed without contact.
    ///
    /// Deliberately generous: a target survives a full extra `travelTime` past
    /// its beat. Nothing vanishes the instant the beat lands, because a target
    /// disappearing because a patient's arm was slow is exactly the fake
    /// failure this project is supposed to avoid.
    func expireOverdue(songTime: TimeInterval) {
        for target in activeTargets {
            guard let component = target.components[TargetComponent.self],
                  let beatTime = component.beatTime,
                  songTime > beatTime + component.travelTime,
                  // Never yank something out of a hand that is carrying it.
                  !component.grab.isHolding
            else { continue }

            target.components.remove(TargetComponent.self)
            target.components.remove(CollisionComponent.self)
            missedCount += 1
            onScoreChange?()

            // Stop the countdown too, or the shell keeps shrinking on a target
            // that is already on its way out.
            TargetEntity.removeApproachShell(from: target)
            if let zone = dropZone(for: component.noteIndex) { TargetEntity.destroy(zone) }
            TargetEntity.playMissAnimation(on: target)
            Task {
                try? await Task.sleep(for: .seconds(TargetEntity.missAnimationSeconds))
                TargetEntity.destroy(target)
            }
        }
    }

    // MARK: - Hit detection

    /// Contact test against every tracked palm. Call this on each hand update.
    ///
    /// A target only answers to the palm matching its own side, so hitting a
    /// left target with the right hand does nothing.
    func hitTest(palms: [(hand: TrainingHand, proxy: HandProxy)], songTime: TimeInterval) {
        lastPalms = palms.map(\.proxy.position)

        for target in activeTargets {
            guard let component = target.components[TargetComponent.self] else { continue }
            guard let palm = palms.first(where: { $0.hand == component.hand }) else { continue }

            switch component.movement {
            case .reach:
                if touches(palm, target.position, component.radius) {
                    retire(target, component: component, songTime: songTime)
                }

            case .grip:
                advanceGrip(target, component: component, palm: palm, songTime: songTime)

            case .pour:
                advancePour(target, component: component, palm: palm, songTime: songTime)
            }
        }

        if mode == .practice { refill(avoiding: lastPalms) }
    }

    private func touches(
        _ palm: (hand: TrainingHand, proxy: HandProxy),
        _ position: SIMD3<Float>,
        _ radius: Float
    ) -> Bool {
        distance(palm.proxy.position, position) <= palm.proxy.radius + radius
    }

    /// Grabbing, as a blended judgement rather than a chain of booleans.
    ///
    /// Finger curl, thumb opposition, whether the object sits inside the
    /// volume the hand could close around, how near the palm is, and whether
    /// the hand is actively closing all contribute. Any one of those fails
    /// often enough on a tracked hand — and far more often on an impaired one
    /// — that requiring all of them at once is how grabs come to feel
    /// arbitrary.
    private func advanceGrip(
        _ target: Entity,
        component: TargetComponent,
        palm: (hand: TrainingHand, proxy: HandProxy),
        songTime: TimeInterval
    ) {
        // An unknown pose is not an open hand. ARKit drops the fingertips
        // exactly when the hand closes, so treating unknown as open let a
        // closed fist score on arrival.
        guard let pose = palm.proxy.pose else { return }

        var state = component
        var grab = state.grab

        let confidence = GrabConfidence.evaluate(
            pose: pose,
            object: target.position,
            objectRadius: component.radius,
            maxCurl: maxComfortableCurl
        ).total

        // Generous: the object only has to be within reach of the hand for the
        // machine to start paying attention.
        let near = pose.distanceToPalm(target.position)
            <= pose.handLength * 1.8 + component.radius
        // Judged on curl against this patient's own maximum, so a hand that
        // cannot fully open still registers as open.
        let handOpen = pose.fingerCurl / max(0.25, maxComfortableCurl) <= 0.35

        if grab.isHolding {
            // Carried: the object goes where the hand goes.
            target.position = pose.gripVolumeCenter
            _ = grab.update(confidence: confidence, objectNear: true, handOpen: handOpen)

            if let destination = state.carryDestination {
                let overZone = distance(target.position, destination)
                    <= component.radius + TargetEntity.defaultRadius * 1.35
                if let zone = dropZone(for: component.noteIndex) {
                    TargetEntity.setDropZoneActive(zone, active: overZone, hand: component.hand)
                }
                if grab.hasReleased {
                    state.grab = grab
                    target.components.set(state)
                    if overZone {
                        retire(target, component: state, songTime: songTime)
                    } else {
                        // A drop is not a failure: it goes back so the movement
                        // can be tried again rather than being lost.
                        dropCarried(target, state: state)
                    }
                    return
                }
            } else if grab.hasReleased {
                state.grab = grab
                target.components.set(state)
                retire(target, component: state, songTime: songTime)
                return
            }

            state.grab = grab
            target.components.set(state)
            return
        }

        // Approach is checked only at the moment of the grab, so the hand can
        // arrive however it likes and still be asked for the right task.
        let approachOK = state.gripOrientation.map {
            $0.matches(approach: .from(palmCenter: pose.palmCenter, object: target.position))
        } ?? true

        let grabbed = grab.update(
            confidence: approachOK ? confidence : 0,
            objectNear: near,
            handOpen: handOpen
        )
        state.grab = grab
        target.components.set(state)

        TargetEntity.setGripArmed(
            target,
            armed: grab.phase == .enclosing || grab.isHolding,
            hand: component.hand
        )

        if grabbed {
            TargetEntity.removeApproachShell(from: target)
            // Nothing to carry means picking it up was the whole movement.
            if state.carryDestination == nil {
                retire(target, component: state, songTime: songTime)
            }
        }
    }

    private func dropCarried(_ target: Entity, state: TargetComponent) {
        var reset = state
        reset.grab = GrabState()
        target.components.set(reset)
        target.position = state.origin
        TargetEntity.setGripArmed(target, armed: false, hand: state.hand)
        if let zone = dropZone(for: state.noteIndex) {
            TargetEntity.setDropZoneActive(zone, active: false, hand: state.hand)
        }
    }

    private func dropZone(for noteIndex: Int) -> Entity? {
        root.children.first { $0.name == "Drop#\(noteIndex)" }
    }

    /// This patient's own comfortable maximum closure, from calibration.
    /// Curl is scored against this rather than a healthy full fist, so a hand
    /// that cannot close all the way is not permanently short of the threshold.
    var maxComfortableCurl: Float = 1.0

    /// Walks the hand through a pour's waypoints, in order.
    ///
    /// Strictly in order: skipping to the end would turn a guided trajectory
    /// back into a single reach, which is the thing pour exists not to be.
    private func advancePour(
        _ target: Entity,
        component: TargetComponent,
        palm: (hand: TrainingHand, proxy: HandProxy),
        songTime: TimeInterval
    ) {
        guard var pour = target.components[PourComponent.self], !pour.isComplete else { return }
        let waypoint = target.position + pour.waypoints[pour.nextIndex]
        guard touches(palm, waypoint, component.radius) else { return }

        pour.nextIndex += 1
        target.components.set(pour)
        TargetEntity.updatePour(target, nextIndex: pour.nextIndex)

        if pour.isComplete {
            retire(target, component: component, songTime: songTime)
        }
    }

    /// Removes a reached target, scores it, and queues a replacement in
    /// practice mode.
    private func retire(_ target: Entity, component: TargetComponent, songTime: TimeInterval) {
        // Dropping the component immediately makes the target inert, so the
        // frames it spends animating out can't score twice.
        target.components.remove(TargetComponent.self)
        target.components.remove(CollisionComponent.self)

        hitCount += 1
        if let beatTime = component.beatTime {
            let judgement = Judgement.judge(
                offset: songTime - beatTime,
                travelTime: component.travelTime
            )
            judgements[judgement, default: 0] += 1
            showPraise(judgement, at: target.position)
        }
        onScoreChange?()

        TargetEntity.removeApproachShell(from: target)
        if let zone = dropZone(for: component.noteIndex) { TargetEntity.destroy(zone) }
        TargetEntity.playHitAnimation(on: target)
        showShatter(hand: component.hand, at: target.position)

        let wasPractice = mode == .practice
        if wasPractice { pendingSpawns += 1 }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(TargetEntity.hitAnimationSeconds))
            TargetEntity.destroy(target)

            guard let self, wasPractice else { return }
            try? await Task.sleep(for: self.respawnDelay)
            // Decremented before the mode check: switching modes mid-flight
            // used to strand this count, and refill would then permanently
            // believe a spawn was still pending and never top the field up.
            self.pendingSpawns = max(0, self.pendingSpawns - 1)
            self.refill(avoiding: self.lastPalms)
        }
    }

    /// Dust burst plus the hit sound, at the reached target's position.
    ///
    /// Both are parented to the field root rather than the target: the target
    /// collapses and is destroyed within a couple of frames, and would take
    /// the particles and the audio player with it.
    private func showShatter(hand: TrainingHand, at position: SIMD3<Float>) {
        guard !dustPool.isEmpty else { return }
        let dust = dustPool[nextDust % dustPool.count]
        nextDust += 1

        dust.position = position
        TargetEntity.fireDust(dust, hand: hand)

        if let hitSound {
            // Spatial, so the ding comes from where the hand actually is —
            // useful feedback in its own right when a target is off to one side.
            dust.spatialAudio = SpatialAudioComponent()
            dust.playAudio(hitSound)
        }
    }

    /// Pops praise above a reached target. Parented to the field root, not the
    /// target, so it survives the target being torn down under it.
    private func showPraise(_ judgement: Judgement, at position: SIMD3<Float>) {
        let label = TargetEntity.makePraiseLabel(for: judgement)
        label.position = position + [0, TargetEntity.defaultRadius + 0.05, 0]
        effects.addChild(label)
        TargetEntity.playPraiseAnimation(on: label)

        Task {
            try? await Task.sleep(for: .seconds(TargetEntity.praiseSeconds))
            TargetEntity.destroy(label)
        }
    }

    // MARK: - Debug outline

    func redrawOutline() {
        outline.children.reversed().forEach { TargetEntity.destroy($0) }
        for corner in volume.corners {
            let dot = TargetEntity.makeDebugDot()
            dot.position = corner
            outline.addChild(dot)
        }
    }

    var outlineIsVisible: Bool {
        get { outline.isEnabled }
        set { outline.isEnabled = newValue }
    }

    /// Live, hittable targets — excludes the outline and anything retiring.
    var activeTargets: [Entity] {
        root.children.filter { $0.components[TargetComponent.self] != nil }
    }
}
