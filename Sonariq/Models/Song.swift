import Foundation
import MediaPlayer

/// A playable track: either from the device library or streamed through the
/// engine. Remote tracks carry a videoId and resolve to a cached file at play
/// time; everything downstream (queue, EQ, lyrics, Live Activity) treats both
/// the same once the file exists.
struct Song: Identifiable {
    let id: UInt64
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    /// Device-library file. Nil for remote tracks until resolved.
    let assetURL: URL?
    let artwork: MPMediaItemArtwork?

    // Remote (streamed) support.
    let videoId: String?
    let remoteArtworkURL: URL?
    var isRemote: Bool { videoId != nil }

    init(from item: MPMediaItem) {
        id = item.persistentID
        title = item.title ?? "Unknown title"
        artist = item.artist ?? "Unknown artist"
        album = item.albumTitle ?? ""
        duration = item.playbackDuration
        assetURL = item.assetURL
        artwork = item.artwork
        videoId = nil
        remoteArtworkURL = nil
    }

    init(remote track: RemoteTrack) {
        // Session-stable identity from the videoId.
        var hasher = Hasher()
        hasher.combine(track.videoId)
        id = UInt64(bitPattern: Int64(hasher.finalize()))
        title = track.title
        artist = track.artist.isEmpty ? "Unknown artist" : track.artist
        album = track.album
        duration = track.duration
        assetURL = nil
        artwork = nil
        videoId = track.videoId
        remoteArtworkURL = track.artworkURL
    }
}
