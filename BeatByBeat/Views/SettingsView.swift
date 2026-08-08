//
//  SettingsView.swift
//  BeatByBeat
//

import SwiftUI

/// Tuning and debug knobs, kept out of the main panel so the gameplay flow
/// stays short. The manual workspace sliders live here rather than being
/// removed: they're the therapist override, and the fallback if a capture
/// fails mid-demo.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingArm: TrainingHand = .right

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 22) {
                        calibrationSection
                        Spacer(minLength: 0)
                    }
                    .frame(width: 380)

                    VStack(alignment: .leading, spacing: 22) {
                        voiceSection

                        Divider()

                        manualSection

                        Divider()

                        section("Developer mode") {
                        Toggle("Disco lights, 6× speed, dancing cats",
                               isOn: $appModel.developerMode)
                        Text("For showing the app off, not for a session. "
                             + "Off by default and remembered between launches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if appModel.developerMode {
                            Text(String(format: "Charts run at %.0f× speed.",
                                        appModel.developerSpeed))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                        Divider()

                        section("Debug") {
                            Toggle("Show volume outline", isOn: $appModel.showOutline)
                            Toggle("Show hand proxy", isOn: $appModel.showHandProxy)
                            if AppModel.isSimulator {
                                Toggle("Simulate hand with mouse",
                                       isOn: $appModel.simulateHandWithMouse)
                                Text("The drag pad appears in the main panel.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(width: 380)
                }
                .padding(30)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 880, height: 720)
    }

    /// Per-arm box editor.
    ///
    /// One arm at a time: six sliders twice over is a wall, and a therapist is
    /// only ever adjusting the arm in front of them.
    @ViewBuilder
    private var manualSection: some View {
        @Bindable var appModel = appModel
        let workspace = appModel.manualWorkspace(for: editingArm)

        section("Manual workspace") {
            // One source, stated plainly. There used to be a switch choosing
            // between these sliders and the measured box, which meant a slider
            // could be dragged with no effect and nothing saying why.
            Text(appModel.calibration == nil
                 ? "These sliders are where targets go."
                 : "These sliders are where targets go. Your last capture wrote "
                   + "them, and the next one will overwrite them again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Arm", selection: $editingArm) {
                Text("Left").tag(TrainingHand.left)
                Text("Right").tag(TrainingHand.right)
            }
            .pickerStyle(.segmented)

            Text("Centre")
                .font(.caption)
                .foregroundStyle(.secondary)
            armSlider("Height", value: workspace.center.y, range: 0.70...1.70,
                      onChange: update { $0.center.y = $1 })
            armSlider("Distance", value: -workspace.center.z, range: 0.25...1.00,
                      onChange: update { $0.center.z = -$1 })
            armSlider("Sideways", value: workspace.center.x, range: -0.60...0.60,
                      onChange: update { $0.center.x = $1 })

            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)
            armSlider("Width", value: workspace.size.x, range: 0.15...1.20,
                      onChange: update { $0.size.x = $1 })
            armSlider("Height", value: workspace.size.y, range: 0.15...1.20,
                      onChange: update { $0.size.y = $1 })
            armSlider("Depth", value: workspace.size.z, range: 0.10...0.70,
                      onChange: update { $0.size.z = $1 })

            if appModel.calibration != nil {
                Button("Copy measured values into these sliders") {
                    appModel.seedManualFromCalibration()
                }
            }
            Button("Reset this arm to defaults") {
                appModel.setManualWorkspace(.default(for: editingArm), for: editingArm)
            }
        }
    }

    /// Sliders write through a closure rather than binding directly, since the
    /// value lives inside a dictionary on the model.
    private func update(
        _ change: @escaping (inout ManualWorkspace, Float) -> Void
    ) -> (Float) -> Void {
        { newValue in
            var workspace = appModel.manualWorkspace(for: editingArm)
            change(&workspace, newValue)
            appModel.setManualWorkspace(workspace, for: editingArm)
        }
    }

    @ViewBuilder
    private func armSlider(
        _ title: String,
        value: Float,
        range: ClosedRange<Float>,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(Int(value * 100)) cm")
                .font(.callout)
                .monospacedDigit()
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range
            )
        }
    }

    @ViewBuilder
    private var voiceSection: some View {
        @Bindable var appModel = appModel

        section("Voice control") {
            Toggle("Listen for spoken commands", isOn: $appModel.voiceControlEnabled)

            LabeledContent("\"Calibrate\"") { Text("Measure your reach again") }
            LabeledContent("\"Recenter\"") { Text("Move it onto where you're sitting") }

            Text("Heard only in the menus — never while a song is playing, and "
                 + "never during a capture, where it would throw away the "
                 + "directions already measured.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Recognition happens on the headset. Nothing that is said is "
                 + "sent anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch appModel.voiceStatus {
            case .listening:
                Label("Listening", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.green)
                if !appModel.voiceHeard.isEmpty {
                    // Shown so a nurse can tell the difference between "it
                    // isn't hearing me" and "it heard something else".
                    Text("Heard: \(appModel.voiceHeard)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            case .denied:
                Label("Microphone or speech access was refused — it can only be "
                      + "granted back in the system Settings app.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .off:
                Text(appModel.voiceControlEnabled
                     ? "Starts listening when you're back in the menus."
                     : "Off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var calibrationSection: some View {
        @Bindable var appModel = appModel

        section("Calibration") {
            if let profile = appModel.calibration {
                Text("What the last capture measured. Recording one writes these "
                     + "numbers into the workspace sliders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // One row per arm: the two boundaries are separate, and seeing
                // how far apart they are is the point of measuring them apart.
                ForEach(profile.arms.keys.sorted(), id: \.self) { key in
                    if let hand = TrainingHand(rawValue: key),
                       let size = profile.volume(for: hand)?.size {
                        LabeledContent("\(hand.displayName) arm") {
                            Text(String(format: "%.0f × %.0f × %.0f cm",
                                        size.x * 100, size.y * 100, size.z * 100))
                                .monospacedDigit()
                        }
                    }
                }
                LabeledContent("Safety scale") {
                    Text(String(format: "%.0f%% of reached", profile.safetyScale * 100))
                }
                LabeledContent("Peak speed") {
                    Text(String(format: "%.2f m/s", profile.peakSpeed))
                        .monospacedDigit()
                }
                LabeledContent("Suggested level") {
                    Text(profile.suggestedLevel.displayName)
                }
                LabeledContent("Captured") {
                    Text(profile.createdAt, style: .relative)
                }
                if let used = profile.lastUsedAt {
                    LabeledContent("Last played") {
                        Text(used, style: .relative)
                    }
                }

                // Separate from recalibrating on purpose: a patient who has
                // shifted in their chair needs the box moved, not measured
                // again, and the two are easy to confuse from the outside.
                Button("Recentre on where I'm sitting") {
                    dismiss()
                    appModel.startRecenter()
                }
                .disabled(appModel.immersiveSpaceState != .open)

                if profile.wasTrackingLimited {
                    // Worth calling out separately: these limits are the
                    // headset's, not the player's, and shouldn't be read as
                    // the patient being unable to reach further.
                    Label(
                        "Limited by tracking, not reach: "
                        + profile.trackingLimitedSteps.joined(separator: ", "),
                        systemImage: "eye.trianglebadge.exclamationmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Button("Clear calibration", role: .destructive) {
                    appModel.clearCalibration()
                }
            } else {
                Text("No calibration yet — targets use the manual workspace below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Run calibration") {
                dismiss()
                appModel.startCalibration()
            }
            .disabled(appModel.immersiveSpaceState != .open)

            if appModel.immersiveSpaceState != .open {
                Text("Open the immersive space first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
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

#Preview {
    SettingsView()
        .environment(AppModel())
}
