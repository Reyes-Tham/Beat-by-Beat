//
//  ContentView.swift
//  BeatByBeat
//

import SwiftUI

/// Routes between song selection and the game panel.
///
/// The settings sheet is owned here so the same gear opens it from either
/// screen, and calibration started from settings survives the switch.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showSettings = false

    var body: some View {
        Group {
            switch appModel.screen {
            case .songSelection:
                SongSelectionView(showSettings: $showSettings)
            case .calibration:
                CalibrationScreen()
            case .countdown:
                CountdownView(songTitle: appModel.selectedSong.title) {
                    appModel.countdownFinished()
                }
                .frame(minWidth: 460, minHeight: 460)
            case .game:
                GameView(showSettings: $showSettings)
            case .results:
                ResultsView(score: appModel.lastRun ?? .init(
                    points: appModel.livePoints,
                    reached: appModel.hitCount,
                    excellent: 0, good: 0, date: Date()
                )) {
                    appModel.backToSongs()
                }
                .frame(minWidth: 560, minHeight: 600)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(appModel)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
