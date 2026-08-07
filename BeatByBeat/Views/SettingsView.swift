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

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    calibrationSection

                    Divider()

                    section("Manual workspace") {
                        if appModel.isUsingCalibration {
                            Text("A calibration is in use — these apply when it's "
                                 + "switched off.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        slider("Height", value: $appModel.centerHeight,
                               range: 0.70...1.70, unit: "cm")
                        slider("Distance", value: $appModel.centerDistance,
                               range: 0.25...1.00, unit: "cm")
                        slider("Spread", value: $appModel.spread,
                               range: 0.4...2.0, unit: "×")
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
                }
                .padding(32)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 520, height: 640)
    }

    @ViewBuilder
    private var calibrationSection: some View {
        @Bindable var appModel = appModel

        section("Calibration") {
            if let profile = appModel.calibration {
                Toggle("Use calibrated workspace", isOn: $appModel.useCalibration)

                let size = profile.volume.size
                LabeledContent("Playable") {
                    Text(String(format: "%.0f × %.0f × %.0f cm",
                                size.x * 100, size.y * 100, size.z * 100))
                        .monospacedDigit()
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
