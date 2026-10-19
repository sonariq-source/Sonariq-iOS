import SwiftUI

/// Synced lyrics: highlights the current line and auto-scrolls as the song plays.
struct LyricsView: View {
    let song: Song
    @EnvironmentObject var player: PlayerService
    @State private var lines: [LyricsLine] = []

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if lines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.quote")
                        .font(.largeTitle)
                        .foregroundColor(Theme.textDim)
                    Text("No synced lyrics for this track yet.")
                        .foregroundColor(Theme.textDim)
                }
                .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.title3)
                                    .bold(isCurrent(line))
                                    .foregroundColor(isCurrent(line) ? Theme.coral : Theme.textDim)
                                    .multilineTextAlignment(.center)
                                    .id(line.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: currentIndex) { _, idx in
                        if let idx, lines.indices.contains(idx) {
                            withAnimation {
                                proxy.scrollTo(lines[idx].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Lyrics")
    }

    private var currentIndex: Int? {
        lines.lastIndex(where: { $0.time <= player.progress })
    }

    private func isCurrent(_ line: LyricsLine) -> Bool {
        guard let idx = currentIndex else { return false }
        return lines[idx].id == line.id
    }
}
