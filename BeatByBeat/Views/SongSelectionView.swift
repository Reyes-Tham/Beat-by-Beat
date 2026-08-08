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
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
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

            // Two sections: the songs, and everything about the run. Splitting
            // the settings across two columns of their own read as three
            // unrelated panels rather than one choice and its options.
            HStack(alignment: .top, spacing: 28) {
                songList
                    .frame(width: 280)
                    .fixedSize(horizontal: false, vertical: true)
                runSettings
                    .frame(width: 760)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    Spacer()
                    // Play is always available. Calibration is strongly
                    // preferred, but gating on it meant skipping left the app
                    // unusable — and it has to be testable without a headset.
                    Button {
                        appModel.selectedSong = song
                        Task {
                            if appModel.immersiveSpaceState == .closed {
                                appModel.immersiveSpaceState = .inTransition
                                _ = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                            }
                            appModel.startGame()
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        appModel.startCalibration()
                    } label: {
                        Label(appModel.calibration == nil ? "Calibrate" : "Recalibrate",
                              systemImage: "figure.arms.open")
                    }
                    Spacer()
                }

                Text(workspaceSource)
                    .font(.caption)
                    .foregroundStyle(appModel.calibration == nil ? Color.orange : Color.secondary)
            }
            .padding(.vertical, 18)
        }
        .frame(minWidth: 1130, minHeight: 660)
        .onAppear {
            selectedIndex = songs.firstIndex(of: appModel.selectedSong) ?? 0
        }
        .onChange(of: selectedIndex) { appModel.selectedSong = song }
    }

    /// Says where the workspace came from. Measured and set-by-hand play very
    /// differently, and the difference is invisible once the song starts.
    private var workspaceSource: String {
        appModel.calibration == nil
            ? "Targets use the workspace set in Settings — calibrate to measure it instead."
            : "Using your measured reach. Settings can nudge it."
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
            Button { appModel.screen = .statistics } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .help("Past sessions")

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

    /// Everything about the run, in one panel.
    ///
    /// Laid out across the width rather than down: the movement and
    /// orientation choices are short and sit far better in a row than as a
    /// stack that pushes the buttons off the bottom.
    private var runSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            pastScore
            songInfo
            arms
            mobility
            movements
            // Always present, so ticking Grip doesn't shift everything below
            // it. Dimmed rather than blank: an empty gap says nothing about
            // why it's there.
            gripOrientations
                .disabled(!appModel.enabledMovements.contains(.grip))
                .opacity(appModel.enabledMovements.contains(.grip) ? 1 : 0.35)
        }
    }

    private var pastScore: some View {
        VStack(spacing: 4) {
            Text("Past Score")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))

            if let best = appModel.bestScore {
                HStack(spacing: 10) {
                    Text("\(best.points)")
                        .font(.title2)
                        .monospacedDigit()
                    Text("\(best.reached) reached · \(best.rhythmPercent)% on beat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("No runs yet at \(appModel.level.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var songInfo: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title3)
                Label(song.durationText, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !song.hasAudio {
                    Label("No audio — generated beat grid", systemImage: "speaker.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 220, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("Movements needed")
                    .font(.subheadline)
                Text(song.movementFocus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appModel.level.focus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
    }

    private var arms: some View {
        @Bindable var appModel = appModel

        return HStack(spacing: 14) {
            Text("Arm")
                .font(.headline)
                .frame(width: 92, alignment: .leading)
            Picker("Arm", selection: $appModel.trainingHand) {
                ForEach(TrainingHand.allCases, id: \.self) { hand in
                    Text(hand.displayName).tag(hand)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            Text(appModel.trainingHand == .both
                 ? "Targets alternate; each arm uses its own range."
                 : "Only the \(appModel.trainingHand.displayName.lowercased()) hand will score.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Movement choices, side by side.
    ///
    /// A row rather than a stack: three short options read fine across the
    /// width, and stacking them pushed the buttons off the bottom of the panel.
    private var movements: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Movements")
                .font(.headline)
            HStack(spacing: 10) {
                ForEach(MovementType.allCases) { movement in
                    let isOn = appModel.enabledMovements.contains(movement)
                    Button {
                        if isOn {
                            appModel.enabledMovements.remove(movement)
                        } else {
                            appModel.enabledMovements.insert(movement)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isOn ? AnyShapeStyle(.tint)
                                                      : AnyShapeStyle(.secondary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(movement.displayName)
                                    .font(.callout)
                                Text(movement.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
                    .hoverEffect()
                }
            }
        }
    }

    private var gripOrientations: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hand orientation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(GripOrientation.allCases) { orientation in
                    let isOn = appModel.enabledGripOrientations.contains(orientation)
                    Button {
                        if isOn {
                            appModel.enabledGripOrientations.remove(orientation)
                        } else {
                            appModel.enabledGripOrientations.insert(orientation)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? AnyShapeStyle(.tint)
                                                      : AnyShapeStyle(.secondary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(orientation.displayName)
                                    .font(.callout)
                                Text(orientation.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
                    .hoverEffect()
                }
            }
        }
    }

    private var mobility: some View {
        HStack(spacing: 14) {
            Text("Mobility")
                .font(.headline)
                .frame(width: 92, alignment: .leading)

            HStack(spacing: 12) {
                ForEach(ReachLevel.allCases) { level in
                    Button {
                        appModel.level = level
                    } label: {
                        Diamond()
                            .fill(level.rawValue <= appModel.level.rawValue
                                  ? AnyShapeStyle(.yellow)
                                  : AnyShapeStyle(.clear))
                            .overlay(Diamond().stroke(.white.opacity(0.8), lineWidth: 2))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .accessibilityLabel(Text("\(level.rawValue) star"))
                }
            }

            Text(appModel.level.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

#Preview(windowStyle: .automatic) {
    SongSelectionView(showSettings: .constant(false))
        .environment(AppModel())
}
