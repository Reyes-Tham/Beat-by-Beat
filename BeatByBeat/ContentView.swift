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
            case .game:
                GameView(showSettings: $showSettings)
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
