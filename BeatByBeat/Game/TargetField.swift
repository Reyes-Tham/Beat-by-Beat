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

/// Keeps a fixed number of targets alive inside the spawn volume, and retires
/// one when a hand reaches it.
///
/// `spawn(at:hand:)` is the single place a target enters the world. When the
/// chart lands it drives that call instead of `refill()`.
@MainActor
final class TargetField {

    /// How close a replacement may spawn to a palm. Without this, the target
    /// you just hit is immediately replaced under your stationary hand and the
    /// field drains itself.
    private let minPalmClearance: Float = 0.25
    /// Minimum spacing between two live targets in random layout.
    private let minSeparation: Float = 0.18
    /// Gap before a replacement appears, so the hit reads as an event.
    private let respawnDelay: Duration = .milliseconds(250)

    var volume: SpawnVolume = .fixed
    var layout: TargetLayout = .grid
    var hand: TrainingHand = .both
    var targetCount: Int = 3

    private(set) var hitCount = 0
    /// Called on each hit so the UI can update.
    var onHit: (() -> Void)?

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

    // MARK: - Spawning

    /// Clears everything and refills to `targetCount`.
    func reset() {
        for child in root.children.reversed() where child !== outline {
            child.removeFromParent()
        }
        pendingSpawns = 0
        hitCount = 0
        redrawOutline()
        refill(avoiding: lastPalms)
    }

    /// Tops the field back up to `targetCount`.
    func refill(avoiding palms: [SIMD3<Float>]) {
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
        noteIndex: Int = -1
    ) -> Entity {
        let target = TargetEntity.make(hand: hand, radius: radius, noteIndex: noteIndex)
        target.position = position
        root.addChild(target)
        TargetEntity.playSpawnAnimation(on: target)
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

    // MARK: - Hit detection

    /// Contact test against every tracked palm. Call this on each hand update.
    ///
    /// A target only answers to the palm matching its own side, so hitting a
    /// left target with the right hand does nothing.
    func hitTest(palms: [(hand: TrainingHand, proxy: HandProxy)]) {
        lastPalms = palms.map(\.proxy.position)

        for target in activeTargets {
            guard let component = target.components[TargetComponent.self] else { continue }
            let reach = palms.first { palm in
                palm.hand == component.hand
                    && distance(palm.proxy.position, target.position)
                        <= palm.proxy.radius + component.radius
            }
            if reach != nil {
                retire(target)
            }
        }
        refill(avoiding: lastPalms)
    }

    /// Removes a reached target and queues its replacement.
    private func retire(_ target: Entity) {
        // Dropping the component immediately makes the target inert, so the
        // frames it spends animating out can't score twice.
        target.components.remove(TargetComponent.self)
        target.components.remove(CollisionComponent.self)

        hitCount += 1
        onHit?()

        pendingSpawns += 1
        TargetEntity.playHitAnimation(on: target)

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(TargetEntity.hitAnimationSeconds))
            target.removeFromParent()

            try? await Task.sleep(for: self?.respawnDelay ?? .zero)
            guard let self else { return }
            self.pendingSpawns -= 1
            self.refill(avoiding: self.lastPalms)
        }
    }

    // MARK: - Debug outline

    private func redrawOutline() {
        outline.children.forEach { $0.removeFromParent() }
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
