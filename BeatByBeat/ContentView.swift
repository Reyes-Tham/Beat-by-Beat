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
    @State private var voice = VoiceCommandListener()
    @State private var isSyncingVoice = false
    @State private var pendingVoiceSync = false

    /// Where a spoken command is a way *in* to something.
    ///
    /// Deliberately not the game, and deliberately not a capture in progress.
    /// "Calibrate" said during a capture would throw away the directions
    /// already measured, and a therapist talking a patient through it —
    /// "right, now we calibrate your left arm" — is the likeliest thing anyone
    /// says in that room.
    private static let listeningScreens: Set<AppModel.Screen> =
        [.songSelection, .recenter, .statistics]

    var body: some View {
        HStack(spacing: 0) {
            if appModel.developerMode { DancingCats() }

            screen

            if appModel.developerMode { DancingCats() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(appModel)
        }
        .task {
            voice.onCommand = { command in
                switch command {
                case .calibrate: appModel.startCalibration()
                // Falls back to a capture when there is no saved reach to
                // move, which is the only thing recentring could mean then.
                case .recenter: appModel.startRecenter()
                }
            }
            await syncVoice()
        }
        .onChange(of: appModel.voiceControlEnabled) { Task { await syncVoice() } }
        .onChange(of: appModel.screen) { Task { await syncVoice() } }
        // Playback ending is the other moment the answer changes: leaving the
        // game hands back to a menu while the song is still winding down, and
        // the microphone waits for that rather than fighting it.
        .onChange(of: appModel.audioIsPlaying) { Task { await syncVoice() } }
        .onChange(of: voice.heard) { appModel.voiceHeard = voice.heard }
    }

    /// Brings the microphone into line with what the app is doing.
    ///
    /// Overlapping runs would each claim the audio session and race for the
    /// engine, so only one runs at a time — but a change that arrives while one
    /// is in flight is remembered rather than dropped, or the microphone would
    /// stay off for good after the one that mattered was discarded.
    private func syncVoice() async {
        guard !isSyncingVoice else {
            pendingVoiceSync = true
            return
        }
        isSyncingVoice = true
        defer { isSyncingVoice = false }

        repeat {
            pendingVoiceSync = false

            // Never while a song is sounding. The two want the audio session
            // set different ways — the microphone needs a record-capable one,
            // playback does not — and taking it mid-teardown is what made
            // leaving the game feel like the app had frozen.
            let wanted = appModel.voiceControlEnabled
                && !appModel.audioIsPlaying
                && Self.listeningScreens.contains(appModel.screen)

            if wanted {
                await voice.start()
            } else {
                voice.stop()
            }
            appModel.voiceStatus = voice.status
        } while pendingVoiceSync
    }

    @ViewBuilder
    private var screen: some View {
        Group {
            switch appModel.screen {
            case .songSelection:
                SongSelectionView(showSettings: $showSettings)
            case .calibration:
                CalibrationScreen()
            case .recenter:
                RecenterScreen()
            case .statistics:
                StatisticsView()
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
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
