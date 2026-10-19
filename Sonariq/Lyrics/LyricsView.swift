import SwiftUI

/// Synced lyrics: highlights the current line and auto-scrolls as the song plays.
/// Word highlighting appears ONLY when the provider truly timed the words —
/// where only line timings exist, the player shows clean line sync.
struct LyricsView: View {
    @EnvironmentObject var player: PlayerService

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if player.lyricsLoading && player.currentLyrics.isEmpty {
                ProgressView()
                    .tint(Theme.coral)
            } else if player.currentLyrics.isEmpty {
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
                            ForEach(player.currentLyrics) { line in
                                lineView(line)
                                    .id(line.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: currentLineIndex) { _, idx in
                        if let idx, player.currentLyrics.indices.contains(idx) {
                            withAnimation {
                                proxy.scrollTo(player.currentLyrics[idx].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Lyrics")
    }

    private var positionMs: Int64 { Int64(player.progress * 1000) }

    private var currentLineIndex: Int? {
        player.currentLyrics.lastIndex(where: { $0.timeMs <= positionMs })
    }

    @ViewBuilder
    private func lineView(_ line: LyricsLine) -> some View {
        if line.isGap {
            // Instrumental break marker.
            HStack(spacing: 8) {
                Rectangle().fill(Theme.textDim.opacity(0.35)).frame(height: 1)
                Image(systemName: "music.note")
                    .foregroundColor(Theme.textDim)
                    .font(.caption)
                Rectangle().fill(Theme.textDim.opacity(0.35)).frame(height: 1)
            }
            .padding(.vertical, 8)
        } else if line.isWordSynced {
            wordText(line)
                .font(.title3)
                .bold(isCurrentLine(line))
                .multilineTextAlignment(.center)
        } else {
            Text(line.text)
                .font(.title3)
                .bold(isCurrentLine(line))
                .foregroundColor(isCurrentLine(line) ? Theme.coral : Theme.textDim)
                .multilineTextAlignment(.center)
        }
    }

    /// Discrete word landing: a word lights when sung and the highlight holds
    /// through the gap until the next word starts.
    private func wordText(_ line: LyricsLine) -> Text {
        var text = Text("")
        let active = line.words.lastIndex(where: { $0.startMs <= positionMs })
        for (i, word) in line.words.enumerated() {
            let sung = active.map { i <= $0 } ?? false
            text = text + Text(word.text + (i < line.words.count - 1 ? " " : ""))
                .foregroundColor(sung ? Theme.coral : Theme.textDim)
        }
        return text
    }

    private func isCurrentLine(_ line: LyricsLine) -> Bool {
        guard let idx = currentLineIndex else { return false }
        return player.currentLyrics[idx].id == line.id
    }
}
