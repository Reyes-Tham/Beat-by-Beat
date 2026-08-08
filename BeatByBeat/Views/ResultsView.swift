//
//  ResultsView.swift
//  BeatByBeat
//

import SwiftUI

/// End-of-run summary. Fades itself away after five seconds.
///
/// Leads with targets reached, not rhythm accuracy. Getting the arm there is
/// the movement goal; how close it landed to the beat is a separate, softer
/// number, and putting it first would tell a slow mover they had failed at the
/// thing they actually succeeded at.
struct ResultsView: View {
    let score: SessionScore
    let onDismiss: () -> Void

    @State private var visible = false

    var body: some View {
        VStack(spacing: 22) {
            Text("Congratulations!!")
                .font(.system(size: 52, weight: .bold, design: .rounded))

            Text("Your score is \(score.reached)")
                .font(.largeTitle)

            SmileyFace()
                .frame(width: 190, height: 190)
                .padding(.vertical, 6)

            VStack(spacing: 6) {
                Text("\(score.reached) of \(score.total) targets reached")
                    .font(.title3)
                    .monospacedDigit()
                Text("\(score.rhythmPercent)% of those landed on the beat")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .task {
            withAnimation(.easeOut(duration: 0.45)) { visible = true }
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeIn(duration: 0.6)) { visible = false }
            try? await Task.sleep(for: .milliseconds(600))
            onDismiss()
        }
    }
}

/// Simple drawn face, so the summary reads as encouragement before any of the
/// numbers are parsed.
private struct SmileyFace: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let inset = side * 0.06
            let face = CGRect(x: inset, y: inset,
                              width: side - inset * 2, height: side - inset * 2)

            context.stroke(Path(ellipseIn: face),
                           with: .color(.primary), lineWidth: side * 0.035)

            let eyeY = face.minY + face.height * 0.36
            let eyeR = side * 0.035
            for x in [face.minX + face.width * 0.32, face.minX + face.width * 0.68] {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - eyeR, y: eyeY - eyeR * 1.4,
                                           width: eyeR * 2, height: eyeR * 2.8)),
                    with: .color(.primary)
                )
            }

            var smile = Path()
            smile.move(to: CGPoint(x: face.minX + face.width * 0.30,
                                   y: face.minY + face.height * 0.58))
            smile.addQuadCurve(
                to: CGPoint(x: face.minX + face.width * 0.70,
                            y: face.minY + face.height * 0.58),
                control: CGPoint(x: face.midX, y: face.minY + face.height * 0.86)
            )
            context.stroke(smile, with: .color(.primary),
                           style: StrokeStyle(lineWidth: side * 0.035, lineCap: .round))
        }
    }
}

#Preview(windowStyle: .automatic) {
    ResultsView(
        score: SessionScore(reached: 100, total: 110, excellent: 40, good: 35, date: Date())
    ) {}
    .frame(width: 620, height: 640)
}
