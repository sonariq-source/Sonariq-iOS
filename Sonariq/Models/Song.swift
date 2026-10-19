import Foundation
import MediaPlayer

/// A playable track. Device-library backed for now; streaming sources land later.
struct Song: Identifiable {
    let id: UInt64 // MPMediaItem persistentID
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let assetURL: URL?
    let artwork: MPMediaItemArtwork?

    init(from item: MPMediaItem) {
        id = item.persistentID
        title = item.title ?? "Unknown title"
        artist = item.artist ?? "Unknown artist"
        album = item.albumTitle ?? ""
        duration = item.playbackDuration
        assetURL = item.assetURL
        artwork = item.artwork
    }
}
