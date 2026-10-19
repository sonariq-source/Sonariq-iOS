import SwiftUI

/// Sonariq's glass treatment: true Liquid Glass on iOS 26+, frosted material
/// on older releases. Same call everywhere, graceful everywhere.
extension View {
    @ViewBuilder
    func sonariqGlass(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Glass pill for control clusters.
    @ViewBuilder
    func sonariqGlassPill() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
