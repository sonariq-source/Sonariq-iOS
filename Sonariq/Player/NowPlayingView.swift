import SwiftUI

/// Mini player bar pinned above the tab bar.
struct MiniPlayerView: View {
    @EnvironmentObject var player: PlayerService
    let onTap: () -> Void

    var body: some View {
        if let song = player.currentSong {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ArtworkThumb(song: song)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Text(song.artist)
                            .foregroundColor(Theme.textDim)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(Theme.coral)
                            .font(.title3)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Theme.surface)
            }
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

/// Full now-playing screen: artwork, progress, transport, lyrics entry.
struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerService

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let song = player.currentSong {
                    VStack(spacing: 20) {
                        ArtworkLarge(song: song)
                            .padding(.top)

                        VStack(spacing: 4) {
                            Text(song.title)
                                .font(.title2).bold()
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            Text(song.artist)
                                .foregroundColor(Theme.textDim)
                                .lineLimit(1)
                        }

                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { player.progress },
                                    set: { player.seek(to: $0) }
                                ),
                                in: 0...max(song.duration, 1)
                            )
                            .tint(Theme.coral)
                            HStack {
                                Text(Theme.formatTime(player.progress))
                                Spacer()
                                Text(Theme.formatTime(song.duration))
                            }
                            .font(.caption)
                            .foregroundColor(Theme.textDim)
                        }

                        HStack(spacing: 44) {
                            Button { player.previous() } label: {
                                Image(systemName: "backward.fill").font(.title)
                            }
                            Button { player.toggle() } label: {
                                Image(systemName: player.isPlaying
                                      ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 64))
                            }
                            Button { player.next() } label: {
                                Image(systemName: "forward.fill").font(.title)
                            }
                        }
                        .foregroundColor(Theme.text)

                        NavigationLink {
                            LyricsView()
                        } label: {
                            Label("Synced lyrics", systemImage: "text.quote")
                                .foregroundColor(Theme.cyan)
                        }

                        Spacer()
                    }
                    .padding()
                } else {
                    Text("Nothing playing")
                        .foregroundColor(Theme.textDim)
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Large artwork with a music-note fallback.
struct ArtworkLarge: View {
    let song: Song

    var body: some View {
        Group {
            if let art = song.artwork,
               let img = art.image(at: CGSize(width: 600, height: 600)) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.surface2)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundColor(Theme.coral)
                    )
            }
        }
        .cornerRadius(16)
        .shadow(radius: 12)
    }
}
