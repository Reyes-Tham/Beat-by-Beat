//
//  ContentView.swift
//  BeatByBeat
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Beat By Beat")
                    .font(.extraLargeTitle2)
                Spacer()
                Text("Reached: \(appModel.hitCount)")
                    .font(.title2)
                    .monospacedDigit()
            }

            Label(trackingLabel, systemImage: trackingSymbol)
                .font(.callout)
                .foregroundStyle(trackingIsHealthy ? Color.secondary : Color.orange)

            Picker("Hand", selection: $appModel.trainingHand) {
                ForEach(TrainingHand.allCases, id: \.self) { hand in
                    Text(hand.displayName).tag(hand)
                }
            }
            .pickerStyle(.segmented)

            Picker("Layout", selection: $appModel.layout) {
                ForEach(TargetLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }
            .pickerStyle(.segmented)

            slider("Height", value: $appModel.centerHeight, range: 0.70...1.70, unit: "cm")
            slider("Distance", value: $appModel.centerDistance, range: 0.25...1.00, unit: "cm")
            slider("Spread", value: $appModel.spread, range: 0.4...2.0, unit: "×")

            Stepper("Live targets: \(appModel.targetCount)",
                    value: $appModel.targetCount, in: 1...12)

            Toggle("Show volume outline", isOn: $appModel.showOutline)
            Toggle("Show hand proxy", isOn: $appModel.showHandProxy)

            HStack {
                ToggleImmersiveSpaceButton()
                Button("Respawn") { appModel.requestRespawn() }
                    .disabled(appModel.immersiveSpaceState != .open)
            }
        }
        .padding(40)
        .frame(width: 480)
    }

    // MARK: - Tracking readout

    private var trackingIsHealthy: Bool {
        appModel.handTrackingStatus == .running
    }

    private var trackingSymbol: String {
        trackingIsHealthy ? "hand.raised" : "exclamationmark.triangle"
    }

    private var trackingLabel: String {
        switch appModel.handTrackingStatus {
        case .idle: "Hand tracking not started"
        case .running: "Hand tracking active"
        case .unsupported: "Hand tracking unavailable — run on Vision Pro"
        case .denied: "Hand tracking permission denied"
        case .failed(let message): "Hand tracking failed: \(message)"
        }
    }

    @ViewBuilder
    private func slider(
        _ title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(unit == "×"
                 ? "\(title): \(value.wrappedValue, specifier: "%.1f")×"
                 : "\(title): \(Int(value.wrappedValue * 100)) cm")
                .font(.title3)
            Slider(value: value, in: range)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
