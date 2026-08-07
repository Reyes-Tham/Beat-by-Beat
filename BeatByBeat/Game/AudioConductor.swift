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

    func start() {
        guard !isRunning else { return }

        if let file = Self.loadSong() {
            do {
                try configureSession()
                if !isGraphConnected {
                    engine.attach(player)
                    engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
                    isGraphConnected = true
                }
                try engine.start()
                player.scheduleFile(file, at: nil)
                player.play()
                hasAudio = true
            } catch {
                print("[AudioConductor] audio failed, falling back to host clock: \(error)")
                hasAudio = false
            }
        } else {
            print("[AudioConductor] no '\(Self.songResourceName)' in bundle — running silent.")
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
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.pause() }
        isRunning = false
        hasAudio = false
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private static func loadSong() -> AVAudioFile? {
        for ext in ["m4a", "mp3", "wav", "aiff", "caf"] {
            guard let url = Bundle.main.url(forResource: songResourceName, withExtension: ext)
            else { continue }
            return try? AVAudioFile(forReading: url)
        }
        return nil
    }
}
