//
//  GameView.swift
//  BeatByBeat
//

import SwiftUI

/// In-game panel. Deliberately almost empty: during a run the player should be
/// looking at the targets, not at a control surface. Everything that used to
/// live here is now either chosen before the run in song selection, or behind
/// the gear.
struct GameView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    appModel.backToSongs()
                } label: {
                    Label("Songs", systemImage: "chevron.left")
                }

                Spacer()

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 2) {
                Text(appModel.selectedSong.title)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("\(appModel.livePoints)")
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: appModel.livePoints)
                Text("points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NextTargetBar(
                deadline: appModel.nextSpawnDeadline,
                interval: appModel.nextSpawnInterval,
                hand: appModel.nextSpawnHand,
                movement: appModel.nextSpawnMovement,
                isRunning: appModel.isPlaying
            )

            if !trackingIsHealthy {
                Label(trackingLabel, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if AppModel.isSimulator, appModel.simulateHandWithMouse {
                HandPad()
            }
        }
        .padding(28)
        .frame(minWidth: 380, minHeight: 340)
    }

    private var trackingIsHealthy: Bool {
        appModel.handTrackingStatus == .running
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
}

#Preview(windowStyle: .automatic) {
    GameView(showSettings: .constant(false))
        .environment(AppModel())
}
