//
//  VoiceCommandListener.swift
//  BeatByBeat
//

import AVFoundation
import Foundation
import Speech

/// Listens for a couple of spoken words, so the two setup steps can be reached
/// without a pinch.
///
/// Pinching a button is a fine gesture for most people and a poor one for
/// somebody whose hand is the reason they are here. These are exactly the steps
/// that come *before* the app knows anything about their reach, which is when
/// pointing at a control is hardest.
///
/// Recognition is required to be on-device. Speech from a rehabilitation
/// session is not something to send anywhere, and a keyword this small does not
/// need a server to hear it — so where on-device recognition is unavailable
/// this reports itself unavailable rather than quietly falling back.
@MainActor
@Observable
final class VoiceCommandListener {

    enum Status: Equatable {
        case off
        case listening
        /// Refused at the system prompt. Recoverable only in Settings, so the
        /// panel has to say so rather than looking merely idle.
        case denied
        case unavailable(String)
    }

    /// Long enough that one utterance can't fire twice while the recogniser
    /// settles, short enough to say it again if nothing seemed to happen.
    private static let repeatGap: TimeInterval = 2.5

    private(set) var status: Status = .off
    /// Last thing it made out, so the settings panel can show that it is
    /// hearing something even when no command matched.
    private(set) var heard = ""

    @ObservationIgnored var onCommand: ((VoiceCommand) -> Void)?

    /// Holds whichever request the microphone tap should feed.
    ///
    /// The tap runs on the audio thread and a recognition pass is replaced
    /// every time a command fires, so the tap cannot close over one request
    /// directly — it would keep feeding the pass that already ended. Swapping
    /// the reference in a box lets the tap stay installed across restarts, and
    /// a pointer swap is the whole of the race.
    private final class RequestBox: @unchecked Sendable {
        var request: SFSpeechAudioBufferRecognitionRequest?
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var request: SFSpeechAudioBufferRecognitionRequest? {
        get { box.request }
        set { box.request = newValue }
    }
    private var task: SFSpeechRecognitionTask?
    private var lastFired: [VoiceCommand: Date] = [:]
    private var isRunning = false

    // MARK: - Lifecycle

    func start() async {
        guard !isRunning else { return }

        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Speech recognition isn't available here.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = .unavailable("This device can't recognise speech without sending it away.")
            return
        }
        guard await requestPermissions() else {
            status = .denied
            return
        }

        do {
            try await beginListening()
            isRunning = true
            status = .listening
        } catch {
            stop()
            status = .unavailable("\(error.localizedDescription)")
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        isRunning = false
        heard = ""
        if status == .listening { status = .off }

        // Off the main actor for the same reason as starting: stopping an
        // engine and handing the session back both block, and doing it on the
        // way out of a screen froze the app there.
        let engine = self.engine
        Task.detached(priority: .userInitiated) {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            // Handed back so a song plays through a plain playback session
            // rather than the record-capable one the microphone needs.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        }
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Listening

    /// Claims the microphone, off the main actor.
    ///
    /// Every call in here blocks: activating an audio session takes as long as
    /// it takes, and starting an engine right after another one was torn down
    /// can take a good deal longer. Run on the main actor — which is where a
    /// screen change puts it — that stalls the whole interface, and the app
    /// appeared to hang on the way back to the songs menu. Nothing here needs
    /// the main actor; only the state afterwards does.
    private func beginListening() async throws {
        let engine = self.engine
        let box = self.box
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            // Measurement mode turns off the processing meant for calls, which
            // otherwise gates and shapes exactly the quiet speech this has to
            // hear.
            try session.setCategory(.playAndRecord, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                // Called on the audio thread. Appending a buffer is what the
                // request is for, and hopping to the main actor first would put
                // a scheduler between the microphone and the recogniser.
                box.request?.append(buffer)
            }

            engine.prepare()
            try engine.start()
        }.value

        listen()
    }

    /// Starts a recognition pass, and keeps starting new ones.
    ///
    /// A pass is not a long-lived thing: it ends on its own after a stretch of
    /// audio, and it ends when a command fires so the matched word leaves the
    /// running transcript. Without that restart the transcript keeps the word
    /// and every later partial result matches it again.
    private func listen() {
        guard let recognizer, isRunning || request == nil else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // A short list of keywords, not dictation. The hint is what stops it
        // reaching for a plausible sentence instead of the word it heard.
        request.taskHint = .search
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Only the text crosses back; the result object belongs to whatever
            // queue this is.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let transcript { self.consider(transcript) }
                if isFinal || failed { self.restart() }
            }
        }
    }

    /// Ends the current pass and opens another, keeping the microphone running.
    private func restart() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        listen()
    }

    // MARK: - Matching

    private func consider(_ transcript: String) {
        heard = transcript
        guard let command = VoiceCommand.spoken(in: transcript) else { return }
        if let last = lastFired[command],
           Date().timeIntervalSince(last) < Self.repeatGap {
            return
        }

        lastFired[command] = Date()
        onCommand?(command)
        // Clears the transcript, so the word just acted on can't be matched
        // again on the next partial result.
        restart()
    }

}
