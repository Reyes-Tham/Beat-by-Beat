//
//  RecenterScreen.swift
//  BeatByBeat
//

import SwiftUI

/// What a returning patient sees instead of a fresh capture.
///
/// Six directed reaches per arm is a lot to ask of someone with a weak arm, and
/// asking it at every launch is asking it when they are freshest — spending the
/// good minutes on setup. A saved profile removes all of that except the one
/// thing that genuinely changes between sessions: where they are sitting.
///
/// So this screen asks only that, and takes it from the head pose. Nothing has
/// to be reached for and nothing has to be pressed — sitting still is the whole
/// interaction.
struct RecenterScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Welcome back")
                    .font(.largeTitle)
                Spacer()
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

            VStack(alignment: .leading, spacing: 16) {
                if appModel.immersiveSpaceState != .open {
                    Label("Opening the play space…", systemImage: "circle.dotted")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    savedReach
                    Divider()
                    settleStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 20)

            Divider()

            HStack(spacing: 12) {
                Button("Start") {
                    appModel.acceptRecenter()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.immersiveSpaceState != .open)

                Button("Calibrate again") {
                    appModel.startCalibration()
                }
                Spacer()
                Text("or just sit still")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 620, minHeight: 520)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(appModel)
        }
        .task {
            if appModel.immersiveSpaceState == .closed {
                appModel.immersiveSpaceState = .inTransition
                _ = await openImmersiveSpace(id: appModel.immersiveSpaceID)
            }
            startIfReady()
        }
        .onChange(of: appModel.immersiveSpaceState) { startIfReady() }
    }

    /// Launching lands here directly, so no button was pressed to ask for the
    /// recentre — the screen has to ask for one itself, once there is a space
    /// to run in.
    private func startIfReady() {
        guard appModel.immersiveSpaceState == .open, !appModel.isRecentring else { return }
        appModel.startRecenter()
    }

    /// Shown before anything happens, because a profile being reused silently
    /// is a profile nobody checks. A therapist glancing at these numbers is how
    /// a stale or wrong capture gets caught.
    @ViewBuilder
    private var savedReach: some View {
        if let profile = appModel.calibration {
            Text("Your saved reach")
                .font(.headline)
            Text(profile.summary)
                .font(.title3)
                .monospacedDigit()

            HStack(spacing: 18) {
                Label {
                    Text("Measured \(profile.createdAt, style: .relative) ago")
                } icon: {
                    Image(systemName: "ruler")
                }
                if let used = profile.lastUsedAt {
                    Label {
                        Text("Last played \(used, style: .relative) ago")
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var settleStep: some View {
        Text("Sit the way you'll be playing and look straight ahead.")
            .font(.title3)

        Text("Your saved reach moves onto wherever you are now — a different "
             + "chair, a different height, facing a different way. The targets "
             + "land in the same places relative to you.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if appModel.recenterAwaitingHead {
            // Expected on the Simulator, which reports no head pose at all.
            // Start still works there; it keeps the reach where it was measured.
            Label("Waiting for the headset to find its position.",
                  systemImage: "circle.dotted")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            ProgressView(value: Double(appModel.recenterProgress))
                .tint(.green)
            Text("Holding steady — this locks in on its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
