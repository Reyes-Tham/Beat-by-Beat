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
