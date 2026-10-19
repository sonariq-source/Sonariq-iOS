import Foundation
import AVFoundation
import Combine

/// 7-band equalizer (mirrors the Android app), backed by a real AVAudioUnitEQ.
/// Engine wiring (inserting the unit into the playback chain) lands with the
/// next player update; bands, gains and presets are live on the unit already.
final class Equalizer: ObservableObject {
    static let frequencies: [Float] = [60, 150, 400, 1000, 2400, 6000, 15000]

    static let presets: [String: [Float]] = [
        "Flat": [0, 0, 0, 0, 0, 0, 0],
        "Bass Boost": [6, 5, 3, 0, 0, 0, 0],
        "Treble Boost": [0, 0, 0, 0, 2, 4, 6],
        "Vocal": [-2, 0, 2, 4, 3, 1, 0],
        "Dance": [5, 3, 0, 0, 0, 3, 5],
        "Rock": [4, 3, -1, -2, 1, 3, 4],
        "Jazz": [3, 2, 0, 2, 3, 3, 2],
    ]

    @Published var gains: [Float] = Array(repeating: 0, count: 7)
    @Published var enabled = true {
        didSet { applyGains() }
    }

    let unit: AVAudioUnitEQ

    init() {
        unit = AVAudioUnitEQ(numberOfBands: 7)
        for (i, band) in unit.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Self.frequencies[i]
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        applyGains()
    }

    func setGain(_ gain: Float, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = gain
        applyGains()
    }

    func applyPreset(_ name: String) {
        guard let g = Self.presets[name], g.count == gains.count else { return }
        gains = g
        applyGains()
    }

    private func applyGains() {
        for (i, band) in unit.bands.enumerated() {
            band.gain = gains[i]
            band.bypass = !enabled
        }
    }
}
