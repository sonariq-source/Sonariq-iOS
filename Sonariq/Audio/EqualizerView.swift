import SwiftUI

/// 7-band equalizer screen with presets.
struct EqualizerView: View {
    @EnvironmentObject var player: PlayerService
    @State private var selectedPreset = "Flat"

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Toggle("Equalizer", isOn: $player.equalizer.enabled)
                        .tint(Theme.coral)
                        .foregroundColor(Theme.text)
                        .padding()

                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(Array(Equalizer.presets.keys.sorted()), id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedPreset) { _, name in
                        player.equalizer.applyPreset(name)
                    }

                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            VStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(player.equalizer.gains[i]) },
                                        set: { player.equalizer.setGain(Float($0), band: i) }
                                    ),
                                    in: -12...12
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 110, height: 30)
                                Text("\(Int(Equalizer.frequencies[i]))")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textDim)
                            }
                            .frame(height: 170)
                        }
                    }
                    .padding(.top, 24)

                    Spacer()

                    Text("Bands and presets drive a real AVAudioUnitEQ — engine wiring lands next.")
                        .font(.footnote)
                        .foregroundColor(Theme.textDim)
                        .padding()
                }
            }
            .navigationTitle("Equalizer")
        }
    }
}
