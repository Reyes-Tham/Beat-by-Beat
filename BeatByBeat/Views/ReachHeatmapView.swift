//
//  ReachHeatmapView.swift
//  BeatByBeat
//

import SwiftUI

/// Where in the workspace the hand actually got to, as two flat grids.
///
/// Flat, and deliberately so. This was a 3D block of cells, which could only
/// ever be shown from some angle — and a visionOS window is stereo, so the
/// angle shifts with the viewer's head and nothing holds a fixed place on the
/// page. Worse, depth in a solid can only be read when the near cells hide the
/// far ones, which is exactly what a map of every target must not do.
///
/// Front view and view from above carry all three axes between them, and a
/// square that is second from the left in the top row stays there.
struct ReachHeatmapView: View {
    let session: SessionRecord

    private static let cellSize: CGFloat = 26
    private static let gap: CGFloat = 3

    private var gridWidth: CGFloat {
        let n = CGFloat(SessionRecord.heatmapResolution)
        return n * Self.cellSize + (n - 1) * Self.gap
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                view(.frontal, title: "Facing them", top: "Up", bottom: "Down")
                view(.transverse, title: "From above", top: "Far", bottom: "Near")
            }
            legend
        }
        // Centred in whatever the panel gives it, rather than pinned left.
        .frame(maxWidth: .infinity)
    }

    // MARK: - One view

    private func view(
        _ plane: SessionRecord.HeatPlane,
        title: String,
        top: String,
        bottom: String
    ) -> some View {
        let cells = session.heatmap(plane)
        // Against the busiest cell, so size reads as "asked for more often
        // than anywhere else" rather than as an absolute count.
        let busiest = max(1, cells.values.map(\.attempts).max() ?? 1)
        let n = SessionRecord.heatmapResolution

        return VStack(spacing: 4) {
            Text(title)
                .font(.caption)
            edgeLabel(top)

            VStack(spacing: Self.gap) {
                ForEach(0..<n, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<n, id: \.self) { column in
                            cell(cells[SIMD2(column, row)], busiest: busiest)
                        }
                    }
                }
            }

            edgeLabel(bottom)

            HStack(spacing: 0) {
                edgeLabel("Left")
                Spacer(minLength: 0)
                edgeLabel("Right")
            }
            .frame(width: gridWidth)
        }
    }

    /// An empty square where nothing was asked, so the grid keeps its shape and
    /// "never went there" stays distinguishable from "went there and missed".
    private func cell(_ cell: SessionRecord.HeatCell?, busiest: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        return shape
            .fill(Color.white.opacity(0.07))
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay {
                if let cell {
                    // Colour says how it went there, size says how often it was
                    // asked for: a busy cell fills its square, a rare one sits
                    // small inside it.
                    let weight = CGFloat(cell.attempts) / CGFloat(busiest)
                    shape
                        .fill(colour(successRate: cell.successRate))
                        .padding(Self.cellSize * (0.30 - 0.27 * weight))
                }
            }
    }

    private func edgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Missed")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Capsule()
                .fill(LinearGradient(
                    colors: [colour(successRate: 0), colour(successRate: 0.5),
                             colour(successRate: 1)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 90, height: 6)
            Text("Reached")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Red where targets were missed, green where they were reached.
    ///
    /// Rate rather than count, so a patch the patient could not get to reads as
    /// a problem area instead of simply being absent from the map.
    private func colour(successRate: Double) -> Color {
        // Hue 0 is red, 0.33 is green.
        Color(hue: 0.33 * successRate, saturation: 0.85, brightness: 0.95)
    }
}
