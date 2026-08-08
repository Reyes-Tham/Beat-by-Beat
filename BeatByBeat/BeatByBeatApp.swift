//
//  BeatByBeatApp.swift
//  BeatByBeat
//
//  Created by Reyes on 7/8/26.
//

import SwiftUI

@main
struct BeatByBeatApp: App {

    @State private var appModel = AppModel()
    @State private var avPlayerViewModel = AVPlayerViewModel()

    var body: some Scene {
        WindowGroup {
            if avPlayerViewModel.isPlaying {
                AVPlayerView(viewModel: avPlayerViewModel)
            } else {
                ContentView()
                    .environment(appModel)
            }
        }
        // The window follows its content, and each screen states a size that
        // already fits everything it shows — so nothing has to be dragged open
        // to read it. Minimums stop "follows content" collapsing a screen.
        .defaultSize(width: 1160, height: 660)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                    avPlayerViewModel.play()
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    avPlayerViewModel.reset()
                }
        }
        // Mixed, not full: the player needs to see their own arm and the room
        // they are reaching in. Passthrough is a safety requirement here, not a
        // style choice.
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
