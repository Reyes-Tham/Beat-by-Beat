//
//  ShuffleBag.swift
//  BeatByBeat
//

import Foundation

/// Draws at random, without letting anything go missing.
///
/// Plain random is wrong for a short run: with three movements ticked and
/// twenty targets, one of them can simply never come up, and a patient can be
/// handed five grips in a row. Plain cycling is wrong too — it is what put every
/// pour on one arm and every reach on the other, because the cycle and the
/// alternating hands came round in step.
///
/// A bag gives both: every option comes up once before any comes up twice, and
/// the order within that is shuffled.
struct ShuffleBag<Element: Equatable> {
    private let items: [Element]
    private var remaining: [Element] = []
    private var last: Element?

    init(_ items: [Element]) {
        self.items = items
    }

    var isEmpty: Bool { items.isEmpty }

    mutating func next() -> Element? {
        guard !items.isEmpty else { return nil }

        if remaining.isEmpty {
            remaining = items.shuffled()
            // One bag can end on the same element the next one starts with,
            // which is the one repeat a bag was supposed to rule out. Swapping
            // it away costs nothing and keeps the seam invisible.
            if items.count > 1, remaining.first == last {
                remaining.swapAt(0, Int.random(in: 1..<remaining.count))
            }
        }

        let drawn = remaining.removeFirst()
        last = drawn
        return drawn
    }
}
