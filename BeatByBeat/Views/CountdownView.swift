//
//  CountdownView.swift
//  BeatByBeat
//

import SwiftUI

/// Three, two, one — with the song title underneath.
///
/// The count is the point: a patient who needs three seconds to travel to the
/// first target should be moving before the music starts, not discovering it
/// has already begun.
struct CountdownView: View {
    let songTitle: String
    let onFinished: () -> Void

    @State private var remaining = 3
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 4)
                    .frame(width: 240, height: 240)
                Text("\(remaining)")
                    .font(.system(size: 110, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .scaleEffect(pulse ? 1.06 : 1)
            .animation(.easeOut(duration: 0.25), value: pulse)

            Text(songTitle)
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            for step in stride(from: 3, through: 1, by: -1) {
                withAnimation { remaining = step }
                pulse = true
                try? await Task.sleep(for: .milliseconds(250))
                pulse = false
                try? await Task.sleep(for: .milliseconds(750))
            }
            onFinished()
        }
    }
}

#Preview(windowStyle: .automatic) {
    CountdownView(songTitle: "Demo Track") {}
        .frame(width: 520, height: 520)
}
