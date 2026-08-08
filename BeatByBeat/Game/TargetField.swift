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

    private let root: Entity
    private let outline: Entity
    private var pendingSpawns = 0
    /// Last known palm positions, so a delayed respawn can still steer clear of
    /// a hand that hasn't moved since the hit.
    private var lastPalms: [SIMD3<Float>] = []

    init(root: Entity) {
        self.root = root
        self.outline = Entity()
        outline.name = "VolumeOutline"
        root.addChild(outline)
    }

    // MARK: - Lifecycle

    /// Destroys every live target. Used by reset, and when a song stops so
    /// nothing is left floating in the scene.
    func clearTargets() {
        for child in root.children.reversed() where child !== outline {
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
        travelTime: TimeInterval = 1
    ) -> Entity {
        let target = TargetEntity.make(hand: hand, radius: radius, noteIndex: noteIndex)
        target.position = position
        target.components[TargetComponent.self]?.beatTime = beatTime
        target.components[TargetComponent.self]?.travelTime = travelTime
        root.addChild(target)
        TargetEntity.playSpawnAnimation(on: target)
        if beatTime != nil {
            TargetEntity.addApproachShell(to: target, travelTime: travelTime, hand: hand)
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
            travelTime: note.travel
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
                  songTime > beatTime + component.travelTime
            else { continue }

            target.components.remove(TargetComponent.self)
            target.components.remove(CollisionComponent.self)
            missedCount += 1
            onScoreChange?()

            // Stop the countdown too, or the shell keeps shrinking on a target
            // that is already on its way out.
            TargetEntity.removeApproachShell(from: target)
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
            let reach = palms.first { palm in
                palm.hand == component.hand
                    && distance(palm.proxy.position, target.position)
                        <= palm.proxy.radius + component.radius
            }
            if reach != nil {
                retire(target, component: component, songTime: songTime)
            }
        }

        if mode == .practice { refill(avoiding: lastPalms) }
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
        let dust = TargetEntity.makeDustBurst(hand: hand, radius: TargetEntity.defaultRadius)
        dust.position = position
        root.addChild(dust)

        if let hitSound {
            // Spatial, so the ding comes from where the hand actually is —
            // useful feedback in its own right when a target is off to one side.
            dust.spatialAudio = SpatialAudioComponent()
            dust.playAudio(hitSound)
        }

        Task {
            // Emit for a moment, then let the existing particles live out
            // their lifespan so the cloud thins rather than cutting off.
            try? await Task.sleep(for: .milliseconds(90))
            TargetEntity.stopDust(dust)
            try? await Task.sleep(for: .seconds(TargetEntity.dustSeconds))
            TargetEntity.destroy(dust)
        }
    }

    /// Pops praise above a reached target. Parented to the field root, not the
    /// target, so it survives the target being torn down under it.
    private func showPraise(_ judgement: Judgement, at position: SIMD3<Float>) {
        let label = TargetEntity.makePraiseLabel(for: judgement)
        label.position = position + [0, TargetEntity.defaultRadius + 0.05, 0]
        root.addChild(label)
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
