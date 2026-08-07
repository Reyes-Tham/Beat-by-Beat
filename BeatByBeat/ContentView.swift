//
//  ContentView.swift
//  BeatByBeat
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showSettings = false

    var body: some View {
        @Bindable var appModel = appModel

        // Header and actions are pinned; only the settings scroll. The action
        // row is how you open the immersive space, so it must never be the
        // thing that gets pushed off the bottom.
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if appModel.isCalibrating {
                        calibrationFlow
                    } else {
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
                        workspaceSummary
                    }

                    // Kept in the main panel rather than behind the gear: it's
                    // needed while calibrating and while playing, so burying it
                    // in a sheet would mean closing the thing you're driving.
                    if AppModel.isSimulator, appModel.simulateHandWithMouse {
                        handPad
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            }

            Divider()

            actionBar
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
        }
        .frame(width: 520)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(appModel)
        }
    }

    // MARK: - Calibration

    @ViewBuilder
    private var calibrationFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibrating — \(appModel.calibrationProgress)")
                .font(.title3)

            Text(appModel.calibrationStepName)
                .font(.headline)

            Text(appModel.calibrationInstruction)
                .foregroundStyle(.secondary)

            if appModel.calibrationAwaitingHand {
                Label("Looking for your hand — move it into view.",
                      systemImage: "hand.raised")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Text("Go only as far as is comfortable. Touching the sphere is not "
                 + "required — press Far enough when you've stopped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var workspaceSummary: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Workspace")
                    .font(.headline)
                Spacer()
                if appModel.calibration != nil {
                    Toggle("Use calibration", isOn: $appModel.useCalibration)
                        .labelsHidden()
                }
            }

            if let profile = appModel.calibration, appModel.useCalibration {
                Text("Calibrated · \(profile.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if profile.wasTrackingLimited {
                    Text("Tracking-limited: \(profile.trackingLimitedSteps.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Suggested start: \(profile.suggestedLevel.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let size = appModel.manualVolume.size
                Text(String(format: "Manual · %.0f×%.0f×%.0f cm — set in settings",
                            size.x * 100, size.y * 100, size.z * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pinned sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Beat By Beat")
                    .font(.title)
                Label(trackingLabel, systemImage: trackingSymbol)
                    .font(.caption)
                    .foregroundStyle(trackingIsHealthy ? Color.secondary : Color.orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("Reached: \(appModel.hitCount)")
                    .font(.title3)
                    .monospacedDigit()
                if appModel.mode == .rhythm {
                    Text("Not reached: \(appModel.missedCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if appModel.isCalibrating {
            HStack(spacing: 12) {
                Button("Far enough") { appModel.advanceCalibration() }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { appModel.cancelCalibration() }
                Spacer()
            }
        } else {
            HStack(spacing: 12) {
                ToggleImmersiveSpaceButton()

                Button("Calibrate") { appModel.startCalibration() }
                    .disabled(appModel.immersiveSpaceState != .open)

                if appModel.mode == .rhythm {
                    Button(appModel.isPlaying ? "Stop" : "Play") {
                        appModel.isPlaying.toggle()
                    }
                    .disabled(appModel.immersiveSpaceState != .open)
                }

                Button("Respawn") { appModel.requestRespawn() }
                    .disabled(appModel.immersiveSpaceState != .open)

                Spacer()

                if appModel.mode == .rhythm, appModel.isPlaying {
                    Text(String(format: "%.1fs", appModel.songTime))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Scrolling sections

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

        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.level.summary)
            Text(pacingLabel)
            Text(sourceLabel)
        }
        .font(.caption)
        .foregroundStyle(.secondary)

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

    /// Trackpad for the fake palm: drag anywhere inside to move it through the
    /// spawn volume. Lives here rather than in the immersive space because an
    /// input-targetable entity floating in front of the player intercepts every
    /// pinch meant for this window.
    @ViewBuilder
    private var handPad: some View {
        @Bindable var appModel = appModel

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
                        appModel.simulatedPalmDepth
                    )
                }
            )
        }
        .frame(height: 140)

        VStack(alignment: .leading, spacing: 2) {
            Text("Hand depth: \(Int(appModel.simulatedPalmDepth * 100))% forward")
                .font(.caption)
            Slider(value: $appModel.simulatedPalmDepth, in: 0...1)
        }
    }

    // MARK: - Readouts

    /// Spells out the pacing in seconds, since beats-per-note says nothing
    /// about whether a level actually feels restful.
    private var pacingLabel: String {
        let beat = 60.0 / max(appModel.bpm, 1)
        let travel = appModel.level.travelBeats * beat
        let perArm = appModel.level.perArmBeats * beat
        return String(format: "%.1fs to reach · same arm every %.1fs", travel, perArm)
    }

    /// Before Play, reports what's *bundled*; during playback, what's actually
    /// driving. Previously it always read "generated · silent" while stopped,
    /// which looked like the song had failed to load.
    private var sourceLabel: String {
        guard appModel.isPlaying else {
            let song = AppModel.hasBundledSong ? "song ready" : "no song bundled"
            let grid = AppModel.hasBundledBeatMap ? "beat grid ready" : "no beat grid"
            return "\(song) · \(grid) — press Play"
        }
        let chart = appModel.chartIsAuthored ? "song beat grid" : "generated grid"
        let audio = appModel.audioIsPlaying ? "audio clock" : "silent clock"
        return "\(chart) · \(audio) · \(appModel.noteCount) notes"
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
