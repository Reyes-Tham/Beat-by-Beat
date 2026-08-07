//
//  SpawnVolume.swift
//  BeatByBeat
//

import simd

/// The box that targets may spawn inside.
///
/// For now these are fixed numbers relative to the immersive space origin,
/// which visionOS places on the floor beneath the player, facing -Z. Later,
/// calibration produces this volume instead of the constants below — nothing
/// downstream should care which.
///
/// Coordinates are RealityKit's: **+X right, +Y up, -Z forward.**
struct SpawnVolume {
    /// Centre of the box, relative to the immersive space origin.
    var center: SIMD3<Float>
    /// Full extents (width, height, depth), not half-extents.
    var size: SIMD3<Float>

    /// Roughly chest height, half a metre out, about an arm-span wide.
    /// Sighting values only — tune them on device.
    static let fixed = SpawnVolume(
        center: [0, 1.25, -0.55],
        size:   [0.80, 0.60, 0.25]
    )

    var minBound: SIMD3<Float> { center - size / 2 }
    var maxBound: SIMD3<Float> { center + size / 2 }

    /// Maps a unit cube coordinate (each axis 0...1) into the box.
    func point(at unit: SIMD3<Float>) -> SIMD3<Float> {
        minBound + unit * size
    }

    func randomPoint() -> SIMD3<Float> {
        point(at: [.random(in: 0...1), .random(in: 0...1), .random(in: 0...1)])
    }

    /// Evenly spaced points on a `columns` × `rows` grid, at mid depth.
    /// Insets by half a cell so nothing lands exactly on the boundary.
    func gridPoints(columns: Int, rows: Int) -> [SIMD3<Float>] {
        guard columns > 0, rows > 0 else { return [] }
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                point(at: [
                    (Float(column) + 0.5) / Float(columns),
                    (Float(row) + 0.5) / Float(rows),
                    0.5
                ])
            }
        }
    }

    /// The eight corners, for the debug outline.
    var corners: [SIMD3<Float>] {
        let ends: [Float] = [0, 1]
        return ends.flatMap { x in
            ends.flatMap { y in
                ends.map { z in point(at: [x, y, z]) }
            }
        }
    }
}
