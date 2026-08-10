//
//  AudioConductor.swift
//  BeatByBeat
//

import AVFoundation
import QuartzCore

/// The single source of truth for song time.
///
/// Everything that needs to know "where are we in the song" asks this, and
/// nothing keeps its own clock. When a song is playing, time comes from the
/// audio render position — not from a timer — because a timer and the audio
/// output drift apart, and by the time that is visible in a rhythm game it is
/// unfixable.
///
/// With no audio file bundled it free-runs on the host clock, so the whole
/// note pipeline stays testable in the Simulator before anyone picks a song.
@MainActor
@Observable
final class AudioConductor {

    /// Bundle resource name to look for, minus the extension.
    static let songResourceName = "demo_song"
    /// Beat grid extracted from that song by tools/beat_reader.py.
    static let beatMapResourceName = "demo_song_beats"

    private(set) var isRunning = false
    private(set) var hasAudio = false

    /// Tempo of the loaded song. Everything musical derives from this.
    var bpm: Double = 120

    var beatDuration: TimeInterval { 60.0 / bpm }
    var barDuration: TimeInterval { beatDuration * 4 }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isGraphConnected = false
    private var fallbackStart: TimeInterval = 0

    /// Seconds since the song began.
    var songTime: TimeInterval {
        guard isRunning else { return 0 }
        return renderTime ?? (CACurrentMediaTime() - fallbackStart)
    }

    /// Audio render position, in seconds. Nil whenever no file is playing.
    private var renderTime: TimeInterval? {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else { return nil }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    // MARK: - Transport

    /// Seconds of fade before the track ends. Long enough to read as the music
    /// finishing rather than being cut off.
    static let fadeOutSeconds: TimeInterval = 3.0

    private(set) var duration: TimeInterval = 0
    private var resourceName: String?

    func start(song: Song) {
        resourceName = song.audioResource
        bpm = song.bpm
        start()
    }

    /// Ramps the mix down as the end approaches. Called from the frame tick,
    /// because song time is the only clock that knows how close the end is.
    func updateFade(songTime: TimeInterval) {
        guard isRunning, hasAudio, duration > 0 else { return }
        let remaining = duration - songTime
        guard remaining <= Self.fadeOutSeconds else {
            engine.mainMixerNode.outputVolume = 1
            return
        }
        let progress = Float(max(0, remaining) / Self.fadeOutSeconds)
        // Squared so the drop is gentle at first and only steep at the very
        // end — a linear ramp on amplitude reads as an abrupt dip.
        engine.mainMixerNode.outputVolume = progress * progress
    }

    func start() {
        guard !isRunning else { return }

        if let file = Self.loadSong(named: resourceName) {
            duration = Double(file.length) / file.processingFormat.sampleRate
            do {
                try configureSession()
                if !isGraphConnected {
                    engine.attach(player)
                    engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
                    isGraphConnected = true
                }
                engine.mainMixerNode.outputVolume = 1
                try engine.start()
                player.scheduleFile(file, at: nil)
                player.play()
                hasAudio = true
            } catch {
                print("[AudioConductor] audio failed, falling back to host clock: \(error)")
                hasAudio = false
            }
        } else {
            duration = 0
            hasAudio = false
        }

        // Set even when audio is playing: renderTime returns nil for the first
        // frames before the player reports a position, and songTime must not
        // jump when it takes over.
        fallbackStart = CACurrentMediaTime()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        // Flipped first, so anything reading these — the tick, the countdown
        // bar — sees a stopped conductor immediately rather than waiting on
        // the audio hardware.
        isRunning = false
        hasAudio = false

        // Off the main actor. Stopping a player node waits for the render
        // thread to come back, and leaving the game does it in the same turn
        // as tearing down every live target and resizing the window — which is
        // the whole of what "the app hangs going back to the songs menu"
        // looked like.
        let player = self.player
        let engine = self.engine
        Task.detached(priority: .userInitiated) {
            if player.isPlaying { player.stop() }
            if engine.isRunning { engine.pause() }
            engine.mainMixerNode.outputVolume = 1
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private static func loadSong(named name: String?) -> AVAudioFile? {
        guard let name else { return nil }
        for ext in ["m4a", "mp3", "wav", "aiff", "caf"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext)
            else { continue }
            return try? AVAudioFile(forReading: url)
        }
        print("[AudioConductor] no audio named '\(name)' — running silent.")
        return nil
    }
}
