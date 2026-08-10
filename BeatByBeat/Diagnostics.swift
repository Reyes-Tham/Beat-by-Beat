//
//  Diagnostics.swift
//  BeatByBeat
//

import Foundation
import QuartzCore

/// Times a step on the main thread and says so when it was slow.
///
/// Added because the app was reported hanging on the way out of the game and
/// none of the candidates reproduced in the Simulator — the transition stops
/// audio, tears down every live target and resizes the window in one turn, and
/// guessing which of those blocks on device was not converging. Silent unless
/// something takes long enough for a person to notice, so it can stay.
enum Diagnostics {
    /// Roughly three dropped frames at 90 Hz. Below this nobody feels it.
    static let hitchThreshold: TimeInterval = 0.033

    @discardableResult
    static func time<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
        let started = CACurrentMediaTime()
        defer {
            let elapsed = CACurrentMediaTime() - started
            if elapsed >= hitchThreshold {
                print(String(format: "[Hitch] %@ took %.0f ms", label, elapsed * 1000))
            }
        }
        return try work()
    }
}
