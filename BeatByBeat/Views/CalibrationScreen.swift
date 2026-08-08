//
//  CalibrationScreen.swift
//  BeatByBeat
//

import SwiftUI

/// The reach capture, on its own screen.
///
/// Separate from the game panel because calibration now gates play: a session
/// starts here, not as a setting someone might skip.
struct CalibrationScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calibration")
                    .font(.largeTitle)
                Text(appModel.calibrationHandProgress)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                // Settings stay reachable even though calibration gates play,
                // so the manual workspace and debug aids are never locked away.
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 36)
            .padding(.top, 26)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if appModel.immersiveSpaceState != .open {
                        waitingForSpace
                    } else if appModel.calibrationIsConfirming {
                        confirmStep
                    } else {
                        captureStep
                    }

                    if AppModel.isSimulator, appModel.simulateHandWithMouse {
                        HandPad()
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 20)
            }

            Divider()

            HStack(spacing: 12) {
                Button(appModel.calibrationIsConfirming ? "Lock this arm" : "Accept") {
                    appModel.advanceCalibration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.calibrationIsConfirming && !appModel.calibrationCanConfirm)

                Button(appModel.calibration == nil ? "Skip for now" : "Cancel") {
                    appModel.cancelCalibration()
                }
                Spacer()
                Text(appModel.calibrationIsConfirming
                     ? "or glance at the circle"
                     : "or just hold still")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
        }
        .frame(width: 560)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(appModel)
        }
        .task {
            // Calibration needs the space open; opening it here means the
            // patient never has to know that.
            if appModel.immersiveSpaceState == .closed {
                appModel.immersiveSpaceState = .inTransition
                _ = await openImmersiveSpace(id: appModel.immersiveSpaceID)
            }
            startIfReady()
        }
        .onChange(of: appModel.immersiveSpaceState) { startIfReady() }
    }

    /// Launching lands on this screen directly, which means no button was
    /// pressed to request the capture — so it has to ask for one itself, once
    /// there is a space to run in.
    private func startIfReady() {
        guard appModel.immersiveSpaceState == .open, !appModel.isCalibrating else { return }
        appModel.startCalibration()
    }

    @ViewBuilder
    private var waitingForSpace: some View {
        Label("Opening the play space…", systemImage: "circle.dotted")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var captureStep: some View {
        Text(appModel.calibrationProgress)
            .font(.headline)

        Text(appModel.calibrationInstruction)
            .foregroundStyle(.secondary)

        HStack {
            Spacer()
            StickFigureGuide(axis: appModel.calibrationAxis, hand: appModel.calibrationHand)
            Spacer()
        }

        if appModel.calibrationAwaitingHand {
            Label("Looking for your hand — move it into view.", systemImage: "hand.raised")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            ProgressView(value: Double(appModel.calibrationHold))
                .tint(.blue)
            Text(appModel.calibrationCanConfirm
                 ? "Hold it there for a moment."
                 : "Go only as far as is comfortable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var confirmStep: some View {
        Text("All six directions captured")
            .font(.headline)

        Text("Rest your arm and glance at the circle for 3 seconds to lock this arm in.")
            .foregroundStyle(.secondary)

        ProgressView(value: Double(appModel.calibrationDwell))
            .tint(.green)

        if !appModel.calibrationHandSteady {
            Text("Rest your arm — it still needs to come to a stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Text("Uses head direction — visionOS doesn't share eye gaze with apps.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

/// Simulator-only drag pad for the fake hand. Shared by calibration and the
/// game panel, so it isn't defined twice.
struct HandPad: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12).fill(.tertiary)
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1)

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

            Text("Hand depth: \(Int(appModel.simulatedPalmDepth * 100))% forward")
                .font(.caption)
            Slider(value: $appModel.simulatedPalmDepth, in: 0...1)
        }
    }
}
