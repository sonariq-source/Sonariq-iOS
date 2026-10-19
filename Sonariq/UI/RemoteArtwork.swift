import SwiftUI

/// Artwork loaded from a URL (streamed tracks), with the music-note fallback
/// while it loads or when it fails.
struct RemoteThumb: View {
    let url: URL?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure, .empty:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(cornerRadius)
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.surface2)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundColor(Theme.coral)
            )
    }
}
