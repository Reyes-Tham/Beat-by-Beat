//
//  ContentView.swift
//  BeatByBeat
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 16) {
            header

            Label(trackingLabel, systemImage: trackingSymbol)
                .font(.callout)
                .foregroundStyle(trackingIsHealthy ? Color.secondary : Color.orange)

            Picker("Mode", selection: $appModel.mode) {
                ForEach(FieldMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Hand", selection: $appModel.trainingHand) {
                ForEach(TrainingHand.allCases, id: \.self) { hand in
                    Text(hand.displayName).tag(hand)
                }
            }
            .pickerStyle(.segmented)

            if appModel.mode == .rhythm {
                rhythmControls
            } else {
                practiceControls
            }

            Divider()
            volumeControls

            HStack {
                ToggleImmersiveSpaceButton()
                Button(appModel.mode == .rhythm ? "Respawn" : "Respawn") {
                    appModel.requestRespawn()
                }
                .disabled(appModel.immersiveSpaceState != .open)
            }
        }
        .padding(36)
        .frame(width: 500)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Beat By Beat")
                .font(.extraLargeTitle2)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("Reached: \(appModel.hitCount)")
                    .monospacedDigit()
                if appModel.mode == .rhythm {
                    Text("Not reached: \(appModel.missedCount)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.title2)
        }
    }

    @ViewBuilder
    private var rhythmControls: some View {
        @Bindable var appModel = appModel

        Picker("Level", selection: $appModel.level) {
            ForEach(ReachLevel.allCases) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .disabled(appModel.isPlaying)

        HStack {
            Button(appModel.isPlaying ? "Stop" : "Play") {
                appModel.isPlaying.toggle()
            }
            .disabled(appModel.immersiveSpaceState != .open)

            Text(String(format: "%.1fs", appModel.songTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            Text(sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !appModel.isPlaying {
            // Rhythm mode is chart-driven, so nothing but the volume outline
            // exists until the song starts. Saying so stops that reading as a
            // failure to spawn.
            Text("Press Play — targets are spawned by the song, not on standby.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(pacingLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if appModel.judgements.values.reduce(0, +) > 0 {
            HStack(spacing: 16) {
                ForEach(Judgement.allCases, id: \.self) { judgement in
                    Text("\(judgement.displayName): \(appModel.judgements[judgement] ?? 0)")
                        .font(.callout)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var practiceControls: some View {
        @Bindable var appModel = appModel

        Picker("Layout", selection: $appModel.layout) {
            ForEach(TargetLayout.allCases) { layout in
                Text(layout.displayName).tag(layout)
            }
        }
        .pickerStyle(.segmented)

        Stepper("Live targets: \(appModel.targetCount)",
                value: $appModel.targetCount, in: 1...12)
    }

    @ViewBuilder
    private var volumeControls: some View {
        @Bindable var appModel = appModel

        slider("Height", value: $appModel.centerHeight, range: 0.70...1.70, unit: "cm")
        slider("Distance", value: $appModel.centerDistance, range: 0.25...1.00, unit: "cm")
        slider("Spread", value: $appModel.spread, range: 0.4...2.0, unit: "×")

        Toggle("Show volume outline", isOn: $appModel.showOutline)
        Toggle("Show hand proxy", isOn: $appModel.showHandProxy)

        if AppModel.isSimulator {
            Toggle("Simulate hand with mouse", isOn: $appModel.simulateHandWithMouse)
            if appModel.simulateHandWithMouse {
                handPad
            }
        }
    }

    /// Trackpad for the fake palm: drag anywhere inside to move it through the
    /// spawn volume. Lives here rather than in the immersive space because an
    /// input-targetable entity floating in front of the player intercepts every
    /// pinch meant for this window.
    private var handPad: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tertiary)
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary, lineWidth: 1)

                if let unit = appModel.simulatedPalmUnit {
                    Circle()
                        .fill(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .offset(
                            x: CGFloat(unit.x) * geometry.size.width - 11,
                            // Screen y grows downward, volume y grows up.
                            y: CGFloat(1 - unit.y) * geometry.size.height - 11
                        )
                } else {
                    Text("Drag here to move the hand")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let x = Float(value.location.x / geometry.size.width)
                    let y = Float(1 - value.location.y / geometry.size.height)
                    appModel.simulatedPalmUnit = SIMD3(
                        min(max(x, 0), 1),
                        min(max(y, 0), 1),
                        0.5  // mid-depth; the stand-in's larger radius covers the rest
                    )
                }
            )
        }
        .frame(height: 150)
    }

    // MARK: - Readouts

    /// Spells out the pacing in seconds, since beats-per-note says nothing
    /// about whether a level actually feels restful.
    private var pacingLabel: String {
        let beat = 60.0 / max(appModel.bpm, 1)
        let travel = appModel.level.travelBeats * beat
        let perArm = appModel.level.perArmBeats * beat
        return String(
            format: "%.1fs to reach · same arm every %.1fs · %d notes",
            travel, perArm, appModel.noteCount
        )
    }

    private var sourceLabel: String {
        let chart = appModel.chartIsAuthored ? "authored chart" : "generated chart"
        let audio = appModel.audioIsPlaying ? "audio clock" : "silent clock"
        return "\(chart) · \(audio)"
    }

    private var trackingIsHealthy: Bool {
        appModel.handTrackingStatus == .running
    }

    private var trackingSymbol: String {
        trackingIsHealthy ? "hand.raised" : "exclamationmark.triangle"
    }

    private var trackingLabel: String {
        switch appModel.handTrackingStatus {
        case .idle: "Hand tracking not started"
        case .running: "Hand tracking active"
        case .unsupported: "Hand tracking unavailable — run on Vision Pro"
        case .denied: "Hand tracking permission denied"
        case .failed(let message): "Hand tracking failed: \(message)"
        }
    }

    @ViewBuilder
    private func slider(
        _ title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(unit == "×"
                 ? "\(title): \(value.wrappedValue, specifier: "%.1f")×"
                 : "\(title): \(Int(value.wrappedValue * 100)) cm")
                .font(.callout)
            Slider(value: value, in: range)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
