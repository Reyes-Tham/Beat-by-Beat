//
//  VoiceCommand.swift
//  BeatByBeat
//

import Foundation

/// The words the app answers to, and what counts as having said one.
///
/// Kept apart from the listener that hears them. The vocabulary is the part
/// worth being sure about, and on its own it can be checked without a
/// microphone, an audio session, or a headset to run them on.
enum VoiceCommand: CaseIterable {
    case calibrate, recenter

    /// What counts as having said it.
    ///
    /// Several spellings each, because the recogniser picks between homophones
    /// using context it does not have here — a single word with no sentence
    /// around it is the worst case for that — and because someone whose speech
    /// is affected after a stroke is precisely who this is for. Near misses
    /// should still work.
    var phrases: [String] {
        switch self {
        case .calibrate: ["calibrate", "calibration", "caliber8", "callibrate"]
        case .recenter: ["recenter", "recentre", "resenter", "recentered", "recentred"]
        }
    }

    /// What was asked for, if anything.
    static func spoken(in transcript: String) -> VoiceCommand? {
        let spoken = normalise(transcript)
        return allCases.first { $0.phrases.contains(where: spoken.contains) }
    }

    /// Lowercased with everything but letters removed, so "re-center" and
    /// "re center" match the same phrase as "recenter". It lets a few odd
    /// things through — but the cost of a false match here is a setup screen
    /// opening, which one look undoes.
    static func normalise(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter }
    }
}
