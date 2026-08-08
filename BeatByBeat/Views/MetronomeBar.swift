//
//  MetronomeBar.swift
//  BeatByBeat
//

import SwiftUI

/// Looping beat indicator: a bar that fills across each beat, over a row of
/// dots showing where in the bar the song is.
///
/// Driven by beat *events* rather than a per-frame phase. Publishing progress
/// every frame would re-render the whole panel ninety times a second to move a
/// bar; instead each beat starts one linear animation that runs for exactly
/// that beat's length, which is both smoother and nearly free.
struct MetronomeBar: View {
    let beat: Int
    let beatDuration: TimeInterval
    let beatsPerBar: Int
    let isRunning: Bool

    @State private var fill: CGFloat = 0

    private var beatInBar: Int { beatsPerBar > 0 ? beat % beatsPerBar : 0 }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Beat \(beatInBar + 1) of \(beatsPerBar)")
                    .font(.callout)
                    .monospacedDigit()
                Spacer()
                Text(String(format: "%.0f BPM", beatDuration > 0 ? 60 / beatDuration : 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(.tint)
                        .frame(width: geometry.size.width * fill)
                }
            }
            .frame(height: 12)

            HStack(spacing: 10) {
                ForEach(0..<max(beatsPerBar, 1), id: \.self) { index in
                    Circle()
                        // The downbeat stays distinguishable even when it isn't
                        // the current one, so the bar has a readable shape
                        // rather than one lit dot travelling along a row.
                        .fill(index == beatInBar ? AnyShapeStyle(.tint)
                              : AnyShapeStyle(index == 0 ? .secondary : .quaternary))
                        .frame(width: index == beatInBar ? 14 : 10,
                               height: index == beatInBar ? 14 : 10)
                        .animation(.snappy(duration: 0.12), value: beatInBar)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: beat) { restart() }
        .onChange(of: isRunning) { if !isRunning { fill = 0 } }
    }

    private func restart() {
        guard isRunning, beatDuration > 0 else { fill = 0; return }
        // Snap back with no animation, then run the fill across exactly one
        // beat. Animating the reset would make the bar sweep backwards.
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { fill = 0 }
        withAnimation(.linear(duration: beatDuration)) { fill = 1 }
    }
}

#Preview {
    MetronomeBar(beat: 2, beatDuration: 0.417, beatsPerBar: 4, isRunning: true)
        .padding(40)
        .frame(width: 360)
}
