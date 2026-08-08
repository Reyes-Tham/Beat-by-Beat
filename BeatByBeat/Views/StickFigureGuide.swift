//
//  StickFigureGuide.swift
//  BeatByBeat
//

import SwiftUI

/// Shows which way to reach, as a stick figure.
///
/// Drawn from **behind**, so the patient's left is the diagram's left. A
/// front-facing figure would mirror every instruction, and "reach left" landing
/// on the right of the picture is exactly the kind of thing that confuses
/// someone concentrating on a movement that is already hard.
///
/// Forward and back switch to a side profile, because depth can't be shown
/// honestly head-on — an arm pointing at the viewer is just a shorter arm.
struct StickFigureGuide: View {
    let axis: ReachAxis
    let hand: TrainingHand

    private var isProfile: Bool { axis == .forward || axis == .back }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height)
            let originX = (size.width - scale) / 2

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: originX + x * scale, y: y * scale)
            }

            let body = Color.secondary.opacity(0.55)
            let limb = Color.accentColor

            // MARK: Figure
            let head = isProfile ? CGPoint(x: 0.44, y: 0.17) : CGPoint(x: 0.5, y: 0.17)
            let neck = CGPoint(x: head.x, y: head.y + 0.085)
            let shoulder = CGPoint(x: head.x, y: 0.31)
            let hip = CGPoint(x: head.x, y: 0.60)

            context.stroke(
                Path { $0.addEllipse(in: CGRect(
                    x: (head.x - 0.075) , y: head.y - 0.075,
                    width: 0.15, height: 0.15
                ).applying(.init(scaleX: scale, y: scale)).offsetBy(dx: originX, dy: 0)) },
                with: .color(body),
                lineWidth: 3
            )

            context.stroke(
                Path { path in
                    path.move(to: point(neck.x, neck.y))
                    path.addLine(to: point(hip.x, hip.y))
                    // Legs
                    path.move(to: point(hip.x, hip.y))
                    path.addLine(to: point(hip.x - 0.09, 0.87))
                    path.move(to: point(hip.x, hip.y))
                    path.addLine(to: point(hip.x + 0.09, 0.87))
                    // Resting arm
                    path.move(to: point(shoulder.x, shoulder.y))
                    path.addLine(to: point(shoulder.x - (isProfile ? 0.04 : 0.11), 0.57))
                },
                with: .color(body),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )

            // MARK: Reaching arm
            let target = handTarget
            let elbow = CGPoint(
                x: shoulder.x + (target.x - shoulder.x) * 0.5,
                y: shoulder.y + (target.y - shoulder.y) * 0.5
            )
            context.stroke(
                Path { path in
                    path.move(to: point(shoulder.x, shoulder.y))
                    path.addLine(to: point(elbow.x, elbow.y))
                    path.addLine(to: point(target.x, target.y))
                },
                with: .color(limb),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

            // Hand
            let handRect = CGRect(x: target.x - 0.028, y: target.y - 0.028,
                                  width: 0.056, height: 0.056)
                .applying(.init(scaleX: scale, y: scale))
                .offsetBy(dx: originX, dy: 0)
            context.fill(Path(ellipseIn: handRect), with: .color(limb))

            // MARK: Direction arrow
            let from = CGPoint(
                x: target.x + arrow.dx * 0.06,
                y: target.y + arrow.dy * 0.06
            )
            let to = CGPoint(
                x: target.x + arrow.dx * 0.20,
                y: target.y + arrow.dy * 0.20
            )
            context.stroke(
                Path { path in
                    path.move(to: point(from.x, from.y))
                    path.addLine(to: point(to.x, to.y))
                },
                with: .color(limb.opacity(0.8)),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            // Arrowhead
            let angle = atan2(arrow.dy, arrow.dx)
            context.fill(
                Path { path in
                    path.move(to: point(to.x, to.y))
                    for offset in [2.6, -2.6] as [CGFloat] {
                        path.addLine(to: point(
                            to.x + cos(angle + offset) * 0.055,
                            to.y + sin(angle + offset) * 0.055
                        ))
                    }
                    path.closeSubpath()
                },
                with: .color(limb.opacity(0.8))
            )
        }
        .frame(height: 155)
        .accessibilityLabel(Text(axis.prompt(for: hand)))
    }

    /// Where the reaching hand ends up, in unit coordinates (y grows downward).
    private var handTarget: CGPoint {
        switch axis {
        case .left:    CGPoint(x: 0.15, y: 0.30)
        case .right:   CGPoint(x: 0.85, y: 0.30)
        case .up:      CGPoint(x: 0.68, y: 0.06)
        case .down:    CGPoint(x: 0.64, y: 0.74)
        case .forward: CGPoint(x: 0.86, y: 0.33)
        // Elbow tucked in rather than the arm simply being short — the
        // movement is pulling the hand back toward the body.
        case .back:    CGPoint(x: 0.56, y: 0.40)
        }
    }

    /// Which way the arrow points from the hand.
    private var arrow: (dx: CGFloat, dy: CGFloat) {
        switch axis {
        case .left:    (-1, 0)
        case .right:   (1, 0)
        case .up:      (0.25, -1)
        case .down:    (0.15, 1)
        case .forward: (1, 0)
        case .back:    (-1, 0.15)
        }
    }
}

#Preview {
    VStack {
        ForEach(ReachAxis.captureOrder, id: \.self) { axis in
            HStack {
                Text(axis.shortName).frame(width: 80, alignment: .leading)
                StickFigureGuide(axis: axis, hand: .right)
            }
        }
    }
    .padding()
}
