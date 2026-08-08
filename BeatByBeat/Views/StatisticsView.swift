//
//  StatisticsView.swift
//  BeatByBeat
//

import SwiftUI

/// Past sessions, one at a time, with trends against the run before.
///
/// Reads from stored records and writes nothing. Review is a separate screen
/// from play on purpose: nothing here can affect a session in progress.
struct StatisticsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var record = PatientStore.load()
    @State private var index = 0

    private var session: SessionRecord? {
        record.sessions.indices.contains(index) ? record.sessions[index] : nil
    }
    private var previous: SessionRecord? { record.previousSession(before: index) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 14)

            Divider()

            if let session {
                content(for: session)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
            } else {
                empty
                    .padding(40)
            }

            Divider()

            HStack {
                Button {
                    appModel.screen = .songSelection
                } label: {
                    Label("Songs", systemImage: "chevron.left")
                }
                Spacer()
                if let calibration = record.currentCalibration {
                    Text("Calibrated \(calibration.createdAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 980, minHeight: 820)
        .onAppear {
            record = PatientStore.load()
            index = max(0, record.sessions.count - 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                index = max(0, index - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(index <= 0)

            Spacer()

            VStack(spacing: 0) {
                Text(session == nil ? "Statistics" : "Session \(index + 1)")
                    .font(.title)
                if let session {
                    Text("\(session.songTitle) · \(session.level)★ · \(session.hand.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                index = min(record.sessions.count - 1, index + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(index >= record.sessions.count - 1)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No sessions yet")
                .font(.title3)
            Text("Play a song and its results are recorded here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for session: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                panel("Reach heatmap") {
                    ReachHeatmapView(session: session)
                    Text("Fixed view from the patient's front-right. Green where "
                         + "targets were reached, red where they were missed; "
                         + "bigger cells were asked for more often.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 360)

                panel("Session summary") {
                    row("Reach success rate", percent(session.successRate))
                    row("Reachable workspace", percent(session.workspaceCoverage))
                    row("Average reach time", String(format: "%.2fs", session.averageReachTime))
                    row("Movement consistency", String(format: "±%.2fs", session.reachTimeDeviation))
                    row("Missed targets", "\(session.missed) / \(session.presented)")
                    row("Active time", duration(session.activeSeconds))
                    row("Rest / pauses", "\(session.pauses)")
                }
            }

            panel("Reach by direction") {
                // Two columns: six regions in one list is a column of numbers
                // nobody scans.
                let regions = ReachRegion.allCases
                HStack(alignment: .top, spacing: 26) {
                    regionColumn(Array(regions.prefix(3)), session: session)
                    regionColumn(Array(regions.suffix(3)), session: session)
                }
                if session.hand == .both {
                    HStack(spacing: 26) {
                        row("Left hand", percentOrDash(session.successRate(forHand: .left)))
                        row("Right hand", percentOrDash(session.successRate(forHand: .right)))
                    }
                }
            }

            HStack(alignment: .top, spacing: 22) {
                panel("Session trend") {
                    if let previous {
                        trend("Success rate",
                              delta: session.successRate - previous.successRate,
                              format: { percentDelta($0) })
                        trend("Reachable workspace",
                              delta: session.workspaceCoverage - previous.workspaceCoverage,
                              format: { percentDelta($0) })
                        // Faster is better here, so the arrow is inverted.
                        trend("Average reach time",
                              delta: previous.averageReachTime - session.averageReachTime,
                              format: { String(format: "%.2f s", abs($0)) })
                    } else {
                        Text("First session — nothing to compare against yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                panel("Observation") {
                    Text(observation(for: session))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func regionColumn(_ regions: [ReachRegion], session: SessionRecord) -> some View {
        VStack(spacing: 6) {
            ForEach(regions, id: \.self) { region in
                row(region.displayName, percentOrDash(session.successRate(in: region)))
            }
        }
    }

    /// Plain language, and only when there is something worth saying — an
    /// observation on every session would train people to ignore it.
    private func observation(for session: SessionRecord) -> String {
        var notes: [String] = []

        let weakest = ReachRegion.allCases
            .compactMap { region -> (ReachRegion, Double)? in
                session.successRate(in: region).map { (region, $0) }
            }
            .min { $0.1 < $1.1 }
        if let weakest, weakest.1 < 0.7 {
            notes.append("Most misses were in \(weakest.0.displayName.lowercased()).")
        }

        if let fatigue = session.fatigueChange, fatigue <= -0.12 {
            notes.append(String(
                format: "Success fell %.0f%% over the run, which can mean it ran long.",
                abs(fatigue) * 100
            ))
        }

        if session.pauses >= 3 {
            notes.append("\(session.pauses) pauses — worth checking the session length.")
        }

        if notes.isEmpty {
            notes.append("Even performance across the workspace, with no drop-off late in the run.")
        }
        return notes.joined(separator: " ")
    }

    // MARK: - Pieces

    @ViewBuilder
    private func panel(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer(minLength: 12)
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func trend(
        _ label: String,
        delta: Double,
        format: (Double) -> String
    ) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer(minLength: 12)
            // Neutral below a threshold: tiny movements between two sessions
            // are noise, and arrowing them invites reading meaning into it.
            let flat = abs(delta) < 0.005
            Image(systemName: flat ? "minus" : (delta > 0 ? "arrow.up" : "arrow.down"))
                .font(.caption)
            Text(format(delta))
                .font(.callout)
                .monospacedDigit()
        }
        .foregroundStyle(abs(delta) < 0.005 ? Color.secondary
                         : (delta > 0 ? Color.green : Color.orange))
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func percentOrDash(_ value: Double?) -> String {
        value.map { percent($0) } ?? "—"
    }
    private func percentDelta(_ value: Double) -> String {
        "\(Int((abs(value) * 100).rounded()))%"
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60)m \(total % 60)s" : "\(total)s"
    }
}
