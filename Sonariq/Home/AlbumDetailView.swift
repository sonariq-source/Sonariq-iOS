import SwiftUI

/// An album's songs. Tap a song to play the album from there; the header
/// button plays it from the top.
struct AlbumDetailView: View {
    @EnvironmentObject var player: PlayerService
    let album: Album

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        AlbumArtwork(album: album, size: 110)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title)
                                .font(.title2).bold()
                                .foregroundColor(Theme.text)
                            Text(album.artist)
                                .foregroundColor(Theme.coral)
                            Text("\(album.songs.count) songs")
                                .font(.caption)
                                .foregroundColor(Theme.textDim)
                        }
                        Spacer()
                    }

                    Button {
                        player.play(songs: album.songs, startingAt: 0)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.coral, in: Capsule())
                    }

                    VStack(spacing: 2) {
                        ForEach(Array(album.songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                player.play(songs: album.songs, startingAt: index)
                            } label: {
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(Theme.textDim)
                                        .frame(width: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .foregroundColor(Theme.text)
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.caption)
                                            .foregroundColor(Theme.textDim)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(Theme.formatTime(song.duration))
                                        .font(.caption)
                                        .foregroundColor(Theme.textDim)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A playlist's songs, playable as a queue.
struct PlaylistDetailView: View {
    @EnvironmentObject var player: PlayerService
    let playlist: Playlist

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        AlbumArtwork(artwork: playlist.artwork, size: 110)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.title2).bold()
                                .foregroundColor(Theme.text)
                            Text("\(playlist.songs.count) songs")
                                .font(.caption)
                                .foregroundColor(Theme.textDim)
                        }
                        Spacer()
                    }

                    Button {
                        player.play(songs: playlist.songs, startingAt: 0)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.coral, in: Capsule())
                    }

                    VStack(spacing: 2) {
                        ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                player.play(songs: playlist.songs, startingAt: index)
                            } label: {
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(Theme.textDim)
                                        .frame(width: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .foregroundColor(Theme.text)
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.caption)
                                            .foregroundColor(Theme.textDim)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(Theme.formatTime(song.duration))
                                        .font(.caption)
                                        .foregroundColor(Theme.textDim)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
