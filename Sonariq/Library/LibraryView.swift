import SwiftUI
import MediaPlayer

/// Device music library: song list, tap to play.
struct LibraryView: View {
    @EnvironmentObject var player: PlayerService
    @State private var songs: [Song] = []
    @State private var status: MPMediaLibraryAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Group {
                switch status {
                case .authorized:
                    List(songs) { song in
                        Button { play(song) } label: {
                            HStack {
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
                                Text(Theme.formatTime(song.duration))
                                    .foregroundColor(Theme.textDim)
                                    .font(.subheadline)
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                default:
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundColor(Theme.textDim)
                        Text("Sonariq needs access to your music library to play your songs.")
                            .foregroundColor(Theme.textDim)
                            .multilineTextAlignment(.center)
                        Button("Allow access") { requestAccess() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.coral)
                    }
                    .padding()
                }
            }
            .navigationTitle("Library")
            .background(Theme.background.ignoresSafeArea())
        }
        .onAppear { refreshStatus() }
    }

    private func refreshStatus() {
        status = MPMediaLibrary.authorizationStatus()
        if status == .authorized { loadSongs() }
    }

    private func requestAccess() {
        MPMediaLibrary.requestAuthorization { newStatus in
            Task { @MainActor in
                status = newStatus
                if newStatus == .authorized { loadSongs() }
            }
        }
    }

    private func loadSongs() {
        songs = (MPMediaQuery.songs().items ?? []).map(Song.init(from:))
    }

    private func play(_ song: Song) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            player.play(songs: songs, startingAt: index)
        }
    }
}

/// Small square artwork thumbnail with a music-note fallback.
struct ArtworkThumb: View {
    let song: Song

    var body: some View {
        Group {
            if let art = song.artwork,
               let img = art.image(at: CGSize(width: 96, height: 96)) {
                Image(uiImage: img).resizable()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surface2)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(Theme.coral)
                    )
            }
        }
        .frame(width: 48, height: 48)
        .cornerRadius(8)
    }
}
