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
///
/// The box carries its own facing. It used to be square to the room, which
/// meant it only described the patient while they happened to be facing the
/// way they were when it was measured — turn the chair and the same box asks
/// for reaches across the body that were measured as reaches in front of it.
struct SpawnVolume {
    /// Centre of the box, relative to the immersive space origin.
    var center: SIMD3<Float>
    /// Full extents (width, height, depth), not half-extents.
    ///
    /// Along the box's own axes: width is across the patient, depth is in
    /// front of them, whichever way they are turned.
    var size: SIMD3<Float>
    /// Which way the box faces, radians about +Y. Zero is the space's -Z, so
    /// an unturned box behaves exactly as an axis-aligned one did.
    var yaw: Float = 0

    var rotation: simd_quatf { simd_quatf(angle: yaw, axis: [0, 1, 0]) }

    /// Roughly chest height, half a metre out, about an arm-span wide.
    /// Sighting values only — tune them on device.
    ///
    /// Depth is 35 cm rather than a token amount because difficulty uses it as
    /// a real axis: level 2 adds forward distance to demand elbow extension,
    /// and a 25 cm box left barely 10 cm of travel to work with.
    static let fixed = SpawnVolume(
        center: [0, 1.25, -0.55],
        size:   [0.80, 0.60, 0.35]
    )

    /// Corners in the box's own axes, before it is turned. Not world
    /// positions once `yaw` is non-zero — use `point(at:)` for those.
    var minBound: SIMD3<Float> { center - size / 2 }
    var maxBound: SIMD3<Float> { center + size / 2 }

    /// Maps a unit cube coordinate (each axis 0...1) into the box.
    func point(at unit: SIMD3<Float>) -> SIMD3<Float> {
        center + rotation.act((unit - SIMD3<Float>(repeating: 0.5)) * size)
    }

    /// Where a world point sits in the box, as a unit cube coordinate.
    func unit(of world: SIMD3<Float>) -> SIMD3<Float> {
        rotation.inverse.act(world - center) / size + SIMD3<Float>(repeating: 0.5)
    }

    /// The smallest box containing all of these, in the first one's facing.
    ///
    /// Shared facing rather than a general union: every box in play comes from
    /// the same capture or recentre, so they are already aligned with each
    /// other. Fitting across genuinely different facings would have to grow the
    /// result to cover the corners, which is the distortion this whole design
    /// exists to avoid.
    static func union(_ boxes: [SpawnVolume]) -> SpawnVolume {
        guard let first = boxes.first else { return .fixed }
        let frame = first.rotation.inverse

        var lo = frame.act(first.center) - first.size / 2
        var hi = frame.act(first.center) + first.size / 2
        for box in boxes.dropFirst() {
            let center = frame.act(box.center)
            lo = simd_min(lo, center - box.size / 2)
            hi = simd_max(hi, center + box.size / 2)
        }
        return SpawnVolume(
            center: first.rotation.act((lo + hi) / 2),
            size: hi - lo,
            yaw: first.yaw
        )
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
