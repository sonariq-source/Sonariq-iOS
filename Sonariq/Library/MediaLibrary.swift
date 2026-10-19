import Foundation
import MediaPlayer

/// An album on the device.
struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let songs: [Song]

    var artwork: MPMediaItemArtwork? { songs.first?.artwork }

    static func == (lhs: Album, rhs: Album) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A playlist on the device.
struct Playlist: Identifiable, Hashable {
    let id: UInt64
    let name: String
    let songs: [Song]

    var artwork: MPMediaItemArtwork? { songs.first?.artwork }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Reads the device's music library. Everything here is real on-device data.
enum MediaLibrary {
    static func allSongs() -> [Song] {
        (MPMediaQuery.songs().items ?? []).map(Song.init(from:))
    }

    static func albums() -> [Album] {
        (MPMediaQuery.albums().collections ?? []).compactMap { collection in
            guard let rep = collection.representativeItem else { return nil }
            let title = rep.albumTitle ?? "Unknown album"
            let artist = rep.albumArtist ?? rep.artist ?? "Unknown artist"
            let songs = collection.items.map(Song.init(from:))
            guard !songs.isEmpty else { return nil }
            return Album(id: "\(title)@@\(artist)", title: title, artist: artist, songs: songs)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func playlists() -> [Playlist] {
        (MPMediaQuery.playlists().collections ?? []).compactMap { collection in
            guard let playlist = collection as? MPMediaPlaylist else { return nil }
            let songs = playlist.items.map(Song.init(from:))
            guard !songs.isEmpty else { return nil }
            return Playlist(id: playlist.persistentID, name: playlist.name ?? "Untitled", songs: songs)
        }
    }

    static func artistCount() -> Int {
        Set((MPMediaQuery.artists().collections ?? []).compactMap { $0.representativeItem?.artist }).count
    }
}
