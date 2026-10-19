import SwiftUI

/// Sonariq Prism design tokens: matte midnight/plum, coral primary,
/// orchid secondary, cyan highlights.
enum Theme {
    static let background = Color(red: 0.07, green: 0.06, blue: 0.10)
    static let surface = Color(red: 0.12, green: 0.10, blue: 0.16)
    static let surface2 = Color(red: 0.17, green: 0.14, blue: 0.22)
    static let coral = Color(red: 1.00, green: 0.44, blue: 0.38)
    static let orchid = Color(red: 0.76, green: 0.47, blue: 1.00)
    static let cyan = Color(red: 0.38, green: 0.89, blue: 1.00)
    static let text = Color.white
    static let textDim = Color.white.opacity(0.62)

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
