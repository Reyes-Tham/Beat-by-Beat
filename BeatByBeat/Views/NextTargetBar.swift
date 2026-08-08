//
//  NextTargetBar.swift
//  BeatByBeat
//

import QuartzCore
import SwiftUI

/// Counts down to the next sphere appearing.
///
/// Deliberately not a beat metronome. Beats run several times a second while
/// targets arrive every few seconds, so a beat indicator says nothing about
/// when to get ready — and "get ready" is the only thing worth telling someone
/// whose reach takes three seconds.
///
/// Driven by its own clock through `TimelineView`, from a deadline published
/// once per target. Nothing upstream re-renders to move the bar.
struct NextTargetBar: View {
    /// Host-clock time the next sphere appears at.
    let deadline: TimeInterval
    /// How long this gap is, so the bar knows what full means.
    let interval: TimeInterval
    let hand: TrainingHand?
    let movement: MovementType?
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation) { _ in
                let remaining = max(0, deadline - CACurrentMediaTime())
                let progress = interval > 0
                    ? min(1, max(0, 1 - remaining / interval))
                    : 0

                VStack(spacing: 8) {
                    HStack {
                        Text(label)
                            .font(.callout)
                        Spacer()
                        Text(isRunning ? countdown(remaining) : "—")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(tint)
                                .frame(width: geometry.size.width * (isRunning ? progress : 0))
                        }
                    }
                    .frame(height: 14)
                }
            }
        }
    }

    /// Says which arm is next, because that is what has to be got ready.
    private var label: String {
        guard isRunning else { return "Waiting to start" }
        guard let hand else { return "Last target" }
        let action = movement.map { $0 == .reach ? "" : " · \($0.displayName)" } ?? ""
        return "Next: \(hand.displayName) arm\(action)"
    }

    private var tint: AnyShapeStyle {
        guard isRunning, let hand else { return AnyShapeStyle(.quaternary) }
        // Matches the sphere that is coming, so the bar and the target agree
        // about which arm before it has even appeared.
        return switch hand {
        case .left: AnyShapeStyle(Color(red: 0.24, green: 0.72, blue: 1.00))
        case .right: AnyShapeStyle(Color(red: 1.00, green: 0.55, blue: 0.18))
        case .both: AnyShapeStyle(.tint)
        }
    }

    private func countdown(_ remaining: TimeInterval) -> String {
        remaining <= 0.05 ? "now" : String(format: "%.1fs", remaining)
    }
}

#Preview {
    NextTargetBar(
        deadline: CACurrentMediaTime() + 3,
        interval: 5,
        hand: .left,
        movement: .grip,
        isRunning: true
    )
    .padding(40)
    .frame(width: 360)
}
