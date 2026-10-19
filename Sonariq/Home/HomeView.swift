import SwiftUI
import MediaPlayer

/// Home: library stats, albums shelf, playlists — all real on-device data.
struct HomeView: View {
    @EnvironmentObject var player: PlayerService
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var playlists: [Playlist] = []
    @State private var artistCount = 0
    @State private var authorized = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if authorized {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            header
                            statsRow
                            albumsSection
                            playlistsSection
                        }
                        .padding()
                    }
                } else {
                    authPrompt
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        }
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sonariq")
                .font(.largeTitle).bold()
                .foregroundColor(Theme.text)
            Text("Your music, in glass.")
                .foregroundColor(Theme.textDim)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(songs.count)", label: "Songs", color: Theme.coral)
            statCard(value: "\(albums.count)", label: "Albums", color: Theme.orchid)
            statCard(value: "\(artistCount)", label: "Artists", color: Theme.cyan)
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2).bold()
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .sonariqGlass()
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Albums")
                .font(.headline)
                .foregroundColor(Theme.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(albums.prefix(20)) { album in
                        NavigationLink(value: album) {
                            VStack(alignment: .leading, spacing: 6) {
                                AlbumArtwork(album: album, size: 130)
                                Text(album.title)
                                    .font(.subheadline)
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                    .frame(width: 130, alignment: .leading)
                                Text(album.artist)
                                    .font(.caption)
                                    .foregroundColor(Theme.textDim)
                                    .lineLimit(1)
                                    .frame(width: 130, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playlists")
                .font(.headline)
                .foregroundColor(Theme.text)
            VStack(spacing: 10) {
                ForEach(playlists) { playlist in
                    NavigationLink(value: playlist) {
                        HStack(spacing: 12) {
                            AlbumArtwork(artwork: playlist.artwork, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                Text("\(playlist.songs.count) songs")
                                    .font(.caption)
                                    .foregroundColor(Theme.textDim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(Theme.textDim)
                                .font(.caption)
                        }
                        .padding(10)
                        .sonariqGlass(cornerRadius: 14)
                    }
                }
            }
        }
    }

    private var authPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundColor(Theme.textDim)
            Text("Sonariq needs access to your music library.")
                .foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
            Button("Allow access") { requestAccess() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.coral)
        }
        .padding()
    }

    private func load() {
        let status = MPMediaLibrary.authorizationStatus()
        authorized = (status == .authorized)
        if authorized { refresh() }
    }

    private func requestAccess() {
        MPMediaLibrary.requestAuthorization { newStatus in
            Task { @MainActor in
                authorized = (newStatus == .authorized)
                if authorized { refresh() }
            }
        }
    }

    private func refresh() {
        songs = MediaLibrary.allSongs()
        albums = MediaLibrary.albums()
        playlists = MediaLibrary.playlists()
        artistCount = MediaLibrary.artistCount()
    }
}

/// Album artwork tile with a music-note fallback.
struct AlbumArtwork: View {
    var album: Album?
    var artwork: MPMediaItemArtwork?
    var size: CGFloat

    init(album: Album, size: CGFloat) {
        self.album = album
        self.artwork = album.artwork
        self.size = size
    }

    init(artwork: MPMediaItemArtwork?, size: CGFloat) {
        self.album = nil
        self.artwork = artwork
        self.size = size
    }

    var body: some View {
        Group {
            if let art = artwork,
               let img = art.image(at: CGSize(width: size * 2, height: size * 2)) {
                Image(uiImage: img).resizable()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface2)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(Theme.coral)
                            .font(.title2)
                    )
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(12)
    }
}
