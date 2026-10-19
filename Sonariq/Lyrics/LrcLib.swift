import Foundation

/// Lyrics from LRCLIB — a free, key-less, community lyrics database.
///
/// Two calls: an exact `get` keyed on artist + title + duration, and a fuzzy
/// `search` when that misses (store titles carry "(From ...)" and
/// "| Official Video" noise that the exact endpoint won't match). Results are
/// line-synced `[mm:ss.xx]` LRC — LRCLIB has no word-level timing of its own,
/// though "enhanced" lines carry word runs the parser keeps honest.
enum LrcLib {

    private static let base = "https://lrclib.net/api"
    private static let userAgent = "Sonariq-iOS (https://github.com/sonariq-source/Sonariq-iOS)"

    /// Synced lyrics for a track, or nil when nothing usable is published.
    static func fetch(title: String, artist: String, durationMs: Int64) async -> (lines: [LyricsLine], rawText: String)? {
        let cleanTitle = clean(title)
        let cleanArtist = clean(artist)
        let seconds = Int(durationMs / 1000)

        let synced: String?
        if let exact = await exactMatch(title: cleanTitle, artist: cleanArtist, seconds: seconds) {
            synced = exact
        } else {
            synced = await bestSearchHit(title: cleanTitle, artist: cleanArtist, seconds: seconds)
        }
        guard let synced else { return nil }
        let lines = LRCParser.parse(synced)
        return lines.isEmpty ? nil : (lines, synced)
    }

    private static func exactMatch(title: String, artist: String, seconds: Int) async -> String? {
        var components = URLComponents(string: "\(base)/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(seconds)),
        ]
        guard let url = components.url?.absoluteString,
              let body = await LyricsHTTP.get(urlString: url, userAgent: userAgent),
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = json["syncedLyrics"] as? String,
              !synced.isEmpty else { return nil }
        return synced
    }

    /// Fuzzy fallback. Prefers whichever hit is closest in length to what is
    /// actually playing — same song, different edit, would drift otherwise.
    private static func bestSearchHit(title: String, artist: String, seconds: Int) async -> String? {
        var components = URLComponents(string: "\(base)/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components.url?.absoluteString,
              let body = await LyricsHTTP.get(urlString: url, userAgent: userAgent),
              let data = body.data(using: .utf8),
              let hits = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return hits
            .compactMap { dict -> (synced: String, distance: Double)? in
                guard let synced = dict["syncedLyrics"] as? String, !synced.isEmpty else { return nil }
                let d = (dict["duration"] as? Double) ?? (dict["duration"] as? Int).map(Double.init) ?? 0
                return (synced, abs(d - Double(seconds)))
            }
            .min(by: { $0.distance < $1.distance })?.synced
    }

    /// Store titles are noisy — "(From "Raees")", "| Official Video",
    /// "(Lyrical)" — and LRCLIB matches on the plain song name.
    static func clean(_ value: String) -> String {
        let ns = value as NSString
        var result = noise.stringByReplacingMatches(
            in: value, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        if let pipe = result.range(of: " | ") {
            result = String(result[..<pipe.lowerBound])
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? value : result
    }

    private static let noise = try! NSRegularExpression(
        pattern: #"\((?:from|feat\.?|official|lyrical|video|audio|remix)[^)]*\)|\[[^\]]*\]|\b(?:official (?:video|audio|music video)|lyrical|full song|4k video)\b"#,
        options: .caseInsensitive)
}
