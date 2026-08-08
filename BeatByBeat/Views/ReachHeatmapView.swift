//
//  ReachHeatmapView.swift
//  BeatByBeat
//

import RealityKit
import SwiftUI

/// Where in the workspace the hand actually got to, as a block of coloured
/// cells seen from a fixed three-quarter angle.
///
/// Fixed, not spinning. A rotating cube looks livelier but cannot be read:
/// there is no telling which face is up and which is forward, so a red patch
/// says nothing about where the patient struggled. Held at one angle with
/// labelled axes, the same patch is locatable.
///
/// Rendered inside the window rather than in the immersive space. The play
/// space belongs to the game, and a review screen has no business putting
/// geometry in it — this way the two can never collide.
struct ReachHeatmapView: View {
    let session: SessionRecord

    /// Yaw brings the right-hand face into view, pitch brings the top in.
    /// Together they show three faces at once, which is what makes the block
    /// read as a volume rather than a grid.
    private static let viewOrientation =
        simd_quatf(angle: -0.58, axis: [0, 1, 0]) * simd_quatf(angle: 0.38, axis: [1, 0, 0])

    var body: some View {
        RealityView { content in
            content.add(makeRoot())
        } update: { content in
            // Snapshot first: removing while iterating the live collection
            // walks its index off the end, which is a trap rather than a
            // graceful failure.
            for entity in Array(content.entities) {
                entity.removeFromParent()
            }
            content.add(makeRoot())
        }
        // Centred in the panel: at a fixed width it sat off to one side of the
        // space reserved for it.
        .frame(maxWidth: .infinity, minHeight: 210)
    }

    /// Two layers: the block is tilted, the labels are not.
    ///
    /// Labels used to sit inside the rotated group, which carried them off to
    /// wherever the rotation put them — one ended up half outside the panel.
    /// They now sit in an upright parent at the *projected* position of each
    /// axis, so they land beside the face they name and stay readable.
    private func makeRoot() -> Entity {
        let root = Entity()
        root.name = "HeatmapRoot"

        let block = Entity()
        block.name = "Block"
        block.orientation = Self.viewOrientation
        build(into: block)
        root.addChild(block)

        addLabels(to: root, span: Float(SessionRecord.heatmapResolution) * 0.0135)
        return root
    }

    private func build(into root: Entity) {
        let cells = session.heatmap
        let resolution = SessionRecord.heatmapResolution
        let busiest = max(1, cells.values.map(\.attempts).max() ?? 1)
        // Scaled against the block's diagonal, not its width, so the corners
        // stay inside the panel.
        let step: Float = 0.0135
        let origin = -Float(resolution - 1) * step / 2
        let span = Float(resolution) * step

        addWireframe(to: root, span: span)

        for (cell, entry) in cells {
            // Colour says how it went there; size says how often it was asked.
            let weight = Float(entry.attempts) / Float(busiest)
            let size = step * (0.42 + 0.46 * weight)
            let cube = ModelEntity(
                mesh: .generateBox(size: size, cornerRadius: size * 0.18),
                materials: [cellMaterial(successRate: Float(entry.successRate))]
            )
            cube.position = [
                origin + Float(cell.x) * step,
                origin + Float(cell.y) * step,
                origin + Float(cell.z) * step,
            ]
            root.addChild(cube)
        }
    }

    /// Twelve edges rather than a translucent solid: a filled box tints
    /// everything behind it, and the point is to see the cells.
    private func addWireframe(to root: Entity, span: Float) {
        let half = span / 2
        let thickness: Float = 0.0012
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.32))

        for axis in 0..<3 {
            for corner in 0..<4 {
                var size = SIMD3<Float>(repeating: thickness)
                size[axis] = span

                var position = SIMD3<Float>.zero
                let others = [0, 1, 2].filter { $0 != axis }
                position[others[0]] = corner & 1 == 0 ? -half : half
                position[others[1]] = corner & 2 == 0 ? -half : half

                let edge = ModelEntity(mesh: .generateBox(size: size), materials: [material])
                edge.position = position
                root.addChild(edge)
            }
        }
    }

    /// Axis labels, upright and pushed clear of the block.
    ///
    /// Without them a fixed view is still ambiguous — it has just stopped
    /// moving. These are what make a red patch locatable.
    private func addLabels(to root: Entity, span: Float) {
        let half = span / 2
        let axes: [(String, SIMD3<Float>)] = [
            ("UP", [0, half, 0]),
            ("LEFT", [-half, 0, 0]),
            ("RIGHT", [half, 0, 0]),
            ("NEAR", [0, 0, half]),
        ]

        let places: [(String, SIMD3<Float>)] = axes.map { text, axis in
            // Where that axis end lands once the block is tilted, nudged
            // outward along the direction it appears to point on screen.
            let projected = Self.viewOrientation.act(axis)
            var outward = SIMD3<Float>(projected.x, projected.y, 0)
            outward = length(outward) < 1e-4 ? [0, -1, 0] : normalize(outward)
            return (text, projected + outward * 0.015)
        }

        for (text, position) in places {
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.0002,
                font: .systemFont(ofSize: 0.008, weight: .semibold),
                containerFrame: .zero,
                alignment: .center
            )
            var material = UnlitMaterial(color: .white)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.7))

            let label = ModelEntity(mesh: mesh, materials: [material])
            // generateText lays out from the baseline's left edge.
            label.position = -label.visualBounds(relativeTo: nil).center

            let holder = Entity()
            holder.position = position
            holder.addChild(label)
            root.addChild(holder)
        }
    }

    /// Red where targets were missed, green where they were reached.
    ///
    /// Rate rather than count, so a patch the patient could not get to reads
    /// as a problem area instead of simply being absent from the map.
    private func cellMaterial(successRate: Float) -> RealityKit.Material {
        // Hue 0 is red, 0.33 is green.
        var material = UnlitMaterial(color: UIColor(
            hue: Double(0.33 * successRate), saturation: 0.95, brightness: 1, alpha: 1
        ))
        // Trouble spots stay solid; areas they handled sit back a little.
        material.blending = .transparent(
            opacity: .init(floatLiteral: 0.9 - 0.25 * successRate)
        )
        return material
    }
}
