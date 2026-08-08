//
//  ReachHeatmapView.swift
//  BeatByBeat
//

import RealityKit
import SwiftUI

/// Where in the workspace the hand actually got to, as a rotating block of
/// coloured cells.
///
/// Rendered inside the window rather than in the immersive space. The play
/// space belongs to the game, and a review screen has no business putting
/// geometry in it — this way the two can never collide.
struct ReachHeatmapView: View {
    let session: SessionRecord

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "HeatmapRoot"
            build(into: root)
            content.add(root)

            // Slow spin: depth in a heat cube reads from parallax, and a still
            // one is indistinguishable from a flat grid.
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                root.orientation *= simd_quatf(
                    angle: Float(event.deltaTime) * 0.35, axis: [0, 1, 0]
                )
            }
        } update: { content in
            guard let root = content.entities.first else { return }
            root.children.forEach { $0.removeFromParent() }
            build(into: root)
        }
        .frame(width: 300, height: 200)
    }

    private func build(into root: Entity) {
        let cells = session.heatmap
        let resolution = SessionRecord.heatmapResolution
        let busiest = max(1, cells.values.map(\.attempts).max() ?? 1)
        // Sized against the block's *diagonal*, not its width: it spins, so
        // the corners sweep out to sqrt(3) times the side and would otherwise
        // swing clear of the panel and draw over the rest of the page.
        let step: Float = 0.0135
        let origin = -Float(resolution - 1) * step / 2

        // The calibrated box, so an empty corner reads as unreached rather
        // than as absent.
        let outline = ModelEntity(
            mesh: .generateBox(size: Float(resolution) * step * 1.02),
            materials: [outlineMaterial()]
        )
        root.addChild(outline)

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
            opacity: .init(floatLiteral: 0.9 - 0.3 * successRate)
        )
        return material
    }

    private func outlineMaterial() -> RealityKit.Material {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.05))
        material.faceCulling = .front
        return material
    }
}
