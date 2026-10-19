import Foundation

/// lrc.red — Apple Music TTML, per-syllable, filed by ISRC.
///
/// Every document lives at `https://lrc.red/s/{ISRC}.ttml`, so a track whose
/// recording is already known costs one request and cannot come back as the
/// wrong edit. Without an ISRC, lrc.red's own search (`/search.json?q=`) is
/// asked, and the hits are matched here rather than trusted in order.
enum LrcRed {

    private static let base = "https://lrc.red/"

    /// How far a hit's length may be from the playing track's.
    private static let durationToleranceSeconds = 3.0

    /// `CC-XXX-YY-NNNNN` without the dashes — and nothing else goes into a path.
    private static let isrcPattern = try! NSRegularExpression(pattern: #"^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$"#)

    static func documentUrl(isrc: String) -> String? {
        let clean = isrc.trimmingCharacters(in: .whitespaces).uppercased()
        let range = NSRange(location: 0, length: (clean as NSString).length)
        guard isrcPattern.firstMatch(in: clean, range: range) != nil else { return nil }
        return "\(base)s/\(clean).ttml"
    }

    static func fetch(title: String, artist: String, durationMs: Int64, isrc: String? = nil) async -> (lines: [LyricsLine], rawText: String)? {
        if let known = isrc.flatMap(documentUrl),
           let doc = await LyricsHTTP.get(urlString: known) {
            let lines = TtmlLyrics.parse(doc)
            if !lines.isEmpty { return (lines, doc) }
        }
        // A known recording lrc.red doesn't have still gets a search: the
        // same song is often catalogued under a sibling release's code.
        guard let hit = await search(title: title, artist: artist, durationMs: durationMs),
              let found = hit.isrc.flatMap(documentUrl),
              found != isrc.flatMap(documentUrl),
              let doc = await LyricsHTTP.get(urlString: found) else { return nil }
        let lines = TtmlLyrics.parse(doc)
        return lines.isEmpty ? nil : (lines, doc)
    }

    // MARK: - Search + matching

    private struct Hit {
        let isrc: String?
        let title: String?
        let artist: String?
        let duration: Double?
    }

    private static func search(title: String, artist: String, durationMs: Int64) async -> Hit? {
        var components = URLComponents(string: "\(base)search.json")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(title) \(artist)".trimmingCharacters(in: .whitespaces))]
        guard let url = components.url?.absoluteString,
              let body = await LyricsHTTP.get(urlString: url),
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawHits = json["hits"] as? [[String: Any]] else { return nil }
        let hits = rawHits.map { dict in
            Hit(isrc: dict["isrc"] as? String,
                title: dict["title"] as? String,
                artist: dict["artist"] as? String,
                duration: (dict["duration"] as? Double) ?? (dict["duration"] as? Int).map(Double.init))
        }
        return best(hits, title: title, artist: artist, durationMs: durationMs)
    }

    /// The hit that is this recording, or nil if none of them is sure to be.
    /// A miss here is recoverable — the sources behind this one get their
    /// turn — and the wrong words scrolling in time with the right song is
    /// not, so every test is a requirement rather than a score.
    static func best(_ hits: [Hit], title: String, artist: String, durationMs: Int64) -> Hit? {
        let wantedTitle = coreOf(title)
        let wantedVersion = versionOf(title)
        let wantedArtists = artistsOf(artist)
        let seconds = Double(durationMs) / 1000.0

        func distance(_ hit: Hit) -> Double {
            guard durationMs > 0, let d = hit.duration else { return 0 }
            return abs(d - seconds)
        }

        return hits
            .filter { hit in
                guard let name = hit.title,
                      hit.isrc.flatMap(documentUrl) != nil,
                      coreOf(name) == wantedTitle,
                      versionOf(name) == wantedVersion,
                      (wantedArtists.isEmpty || artistsOf(hit.artist ?? "").intersection(wantedArtists).isEmpty == false),
                      distance(hit) <= durationToleranceSeconds else { return false }
                return true
            }
            .min(by: { distance($0) < distance($1) })
    }

    /// "Song (Live) - 2011 Remaster" → "song".
    private static func coreOf(_ title: String) -> String {
        let noBrackets = bracketed.stringByReplacingMatches(
            in: title, range: NSRange(location: 0, length: (title as NSString).length), withTemplate: " ")
        let core = noBrackets.components(separatedBy: " - ").first ?? noBrackets
        let n = normalized(core)
        return n.isEmpty ? normalized(title) : n
    }

    /// The version words in the parts [coreOf] throws away.
    private static func versionOf(_ title: String) -> Set<String> {
        let ns = title as NSString
        let bracketedWords = bracketed.matches(in: title, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }.joined(separator: " ")
        let afterDash: String
        if let dash = title.range(of: " - ") {
            afterDash = String(title[dash.upperBound...])
        } else {
            afterDash = ""
        }
        return Set(normalized(bracketedWords + " " + afterDash)
            .split(separator: " ").map(String.init).filter { versionWords.contains($0) })
    }

    private static func artistsOf(_ artist: String) -> Set<String> {
        Set(artistSeparators.stringByReplacingMatches(
            in: artist, range: NSRange(location: 0, length: (artist as NSString).length), withTemplate: "\u{1F}")
            .split(separator: "\u{1F}").map { normalized(String($0)) }.filter { !$0.isEmpty })
    }

    /// Lower case, accents off ("ROSÉ" is "rose"), and only letters and digits.
    private static func normalized(_ value: String) -> String {
        let nfd = value.decomposedStringWithCanonicalMapping
        let stripped = nfd.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }
        let mapped = String(String.UnicodeScalarView(stripped)).lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : " "
        }
        return String(mapped).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    private static let bracketed = try! NSRegularExpression(pattern: #"[(\[][^)\]]*[)\]]"#)
    private static let artistSeparators = try! NSRegularExpression(
        pattern: #"\s*(?:,|&|;|/|\s+and\s+|\s+x\s+|\s+with\s+|\s+feat\.?\s+|\s+ft\.?\s+)\s*"#,
        options: .caseInsensitive)

    /// Bracket words that make it a different recording, not a different label.
    private static let versionWords: Set<String> = [
        "live", "remix", "remixed", "mix", "acoustic", "unplugged", "instrumental",
        "karaoke", "cappella", "acapella", "demo", "edit", "version", "cover",
        "sped", "slowed", "reverb", "nightcore", "lofi", "orchestral", "extended",
    ]
}

private extension Array where Element == LyricsLine {
    var nilIfEmpty: [LyricsLine]? { isEmpty ? nil : self }
}
