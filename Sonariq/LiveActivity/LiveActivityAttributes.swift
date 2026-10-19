import ActivityKit
import Foundation

/// Shared between the app and the widget extension: what a Sonariq
/// now-playing Live Activity carries.
struct SonariqActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var progress: Double
        var duration: Double
        var artworkData: Data?
    }

    var songId: UInt64
}
