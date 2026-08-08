//
//  SongSelectionView.swift
//  BeatByBeat
//

import SwiftUI

/// Diamond used for the difficulty selector.
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

/// Song list on the left, details and difficulty on the right.
///
/// Every control here is an ordinary SwiftUI button, which on visionOS means
/// look at it and pinch. There is no gaze-only activation API — Apple keeps
/// eye position private — so the hover highlight is the gaze feedback and the
/// pinch is the click. Menus being pinch-driven is also why the *game* uses
/// direct reach instead: the affected arm shouldn't have to pinch.
struct SongSelectionView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var showSettings: Bool

    @State private var selectedIndex = 0

    private var songs: [Song] { Song.catalog }
    private var song: Song { songs[selectedIndex] }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 36)
                .padding(.top, 26)
                .padding(.bottom, 14)

            Divider()

            HStack(alignment: .top, spacing: 28) {
                songList
                    .frame(width: 300)
                details
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)

            Divider()

            HStack {
                Spacer()
                Button {
                    appModel.selectedSong = song
                    appModel.startGame()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(.vertical, 18)
        }
        .frame(width: 860)
        .onAppear {
            selectedIndex = songs.firstIndex(of: appModel.selectedSong) ?? 0
        }
        .onChange(of: selectedIndex) { appModel.selectedSong = song }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Beat By Beat")
                .font(.largeTitle)
            Text("Choose a song")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            if appModel.calibration == nil {
                Label("Not calibrated", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .help("Settings and calibration")
        }
    }

    // MARK: - Left column

    private var songList: some View {
        VStack(spacing: 10) {
            arrowButton(systemName: "chevron.up", enabled: selectedIndex > 0) {
                selectedIndex = max(0, selectedIndex - 1)
            }

            ForEach(Array(songs.enumerated()), id: \.element.id) { index, item in
                Button {
                    selectedIndex = index
                } label: {
                    HStack {
                        Text(item.title)
                            .font(index == selectedIndex ? .title3 : .body)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !item.hasAudio {
                            Image(systemName: "speaker.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, index == selectedIndex ? 16 : 11)
                    // The selected row grows sideways as well as taller, so
                    // which one is armed is obvious from the shape alone and
                    // not only from the highlight.
                    .frame(width: index == selectedIndex ? 300 : 242, alignment: .leading)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(index == selectedIndex ? AnyShapeStyle(.tint.opacity(0.28))
                                                     : AnyShapeStyle(.thinMaterial))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(index == selectedIndex ? .white.opacity(0.55) : .clear,
                                      lineWidth: 2)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .hoverEffect()
                .animation(.snappy(duration: 0.22), value: selectedIndex)
            }

            arrowButton(systemName: "chevron.down", enabled: selectedIndex < songs.count - 1) {
                selectedIndex = min(songs.count - 1, selectedIndex + 1)
            }
        }
    }

    private func arrowButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(.thinMaterial))
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
        .hoverEffect()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    // MARK: - Right column

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Past Score")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))

                if let best = appModel.bestScore {
                    Text("\(best.reached) / \(best.total) reached · \(best.rhythmPercent)% on beat")
                        .font(.title3)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("No runs yet at \(appModel.level.displayName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(song.title)
                    .font(.title2)
                Label(song.durationText, systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Movements needed")
                    .font(.headline)
                    .padding(.top, 4)
                Text(song.movementFocus)
                    .foregroundStyle(.secondary)
                Text(appModel.level.focus)
                    .foregroundStyle(.secondary)

                if !song.hasAudio {
                    Label("No audio for this track — plays to a generated beat grid.",
                          systemImage: "speaker.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))

            difficulty
        }
    }

    private var difficulty: some View {
        VStack(spacing: 10) {
            Text("Difficulty")
                .font(.headline)

            HStack(spacing: 14) {
                ForEach(ReachLevel.allCases) { level in
                    Button {
                        appModel.level = level
                    } label: {
                        Diamond()
                            .fill(level.rawValue <= appModel.level.rawValue
                                  ? AnyShapeStyle(.yellow)
                                  : AnyShapeStyle(.clear))
                            .overlay(Diamond().stroke(.white.opacity(0.8), lineWidth: 2))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .accessibilityLabel(Text("\(level.rawValue) star"))
                }
            }

            Text(appModel.level.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview(windowStyle: .automatic) {
    SongSelectionView(showSettings: .constant(false))
        .environment(AppModel())
}
