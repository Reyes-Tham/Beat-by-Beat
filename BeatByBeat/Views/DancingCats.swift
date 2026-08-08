//
//  DancingCats.swift
//  BeatByBeat
//

import ImageIO
import SwiftUI

/// Decoded GIF frames, shared between every view showing the same file.
///
/// Decoded once and downsampled. The cat GIF is 59 frames at 297×498, which is
/// 35 MB decoded at full size — and several dance at once, so decoding per view
/// would cost hundreds of megabytes to draw something 72 points wide.
@MainActor
final class GIFCache {
    static let shared = GIFCache()
    private var cached: [String: (frames: [Image], delays: [Double])] = [:]

    func frames(named name: String, maxPixel: Int = 160) -> (frames: [Image], delays: [Double]) {
        if let hit = cached[name] { return hit }

        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            cached[name] = ([], [])
            return ([], [])
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]

        var images: [Image] = []
        var delays: [Double] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, index, options as CFDictionary
            ) else { continue }
            images.append(Image(decorative: cgImage, scale: 1))

            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            // Browsers floor very short frame delays; matching that keeps GIFs
            // authored for the web running at the speed they look like.
            delays.append(max(0.02, delay))
        }

        cached[name] = (images, delays)
        return (images, delays)
    }
}

/// Plays an animated GIF. SwiftUI's `Image` shows only the first frame, so the
/// frames are stepped through against a clock.
struct AnimatedGIF: View {
    let name: String

    @State private var frames: [Image] = []
    @State private var delays: [Double] = []

    private var loopDuration: Double { delays.reduce(0, +) }

    var body: some View {
        Group {
            if frames.isEmpty {
                Color.clear
            } else {
                TimelineView(.animation) { context in
                    frames[index(at: context.date)]
                        .resizable()
                        .scaledToFit()
                }
            }
        }
        .onAppear {
            let loaded = GIFCache.shared.frames(named: name)
            frames = loaded.frames
            delays = loaded.delays
        }
    }

    private func index(at date: Date) -> Int {
        guard loopDuration > 0 else { return 0 }
        var elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: loopDuration)
        for (index, delay) in delays.enumerated() {
            elapsed -= delay
            if elapsed <= 0 { return index }
        }
        return frames.count - 1
    }
}

/// A column of cats, dancing out of phase with each other.
///
/// Developer mode only, and deliberately so: it must never be able to appear
/// in front of a patient.
struct DancingCats: View {
    var count = 4

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                DancingCat(phase: Double(index) * 0.37)
            }
        }
        .frame(width: 100)
        .padding(.vertical, 16)
        // Purely decorative, so it must never eat a gaze or a pinch.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DancingCat: View {
    let phase: Double

    /// Checked once. A bundle lookup inside a `TimelineView` body would run
    /// every frame.
    private static let hasGIF =
        Bundle.main.url(forResource: "dancing_cat", withExtension: "gif") != nil

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 3 + phase
            let bob = sin(t) * 7
            let tilt = sin(t * 0.5) * 12
            let squash = 1 + sin(t * 2) * 0.05

            Group {
                if Self.hasGIF {
                    AnimatedGIF(name: "dancing_cat")
                } else {
                    Image(systemName: "cat.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(
                            .linearGradient(colors: [.orange, .pink, .purple],
                                            startPoint: .top, endPoint: .bottom)
                        )
                }
            }
            .frame(width: 88, height: 132)
            // The GIF already dances; the extra motion is for the drawn
            // fallback, so it's kept subtle rather than fighting the footage.
            .scaleEffect(x: squash, y: 2 - squash)
            .rotationEffect(.degrees(tilt))
            .offset(y: bob)
        }
    }
}
