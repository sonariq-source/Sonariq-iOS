import Foundation

// MARK: - JSON navigation helpers

/// Null-safe JSON accessors that never throw; the responses are deeply nested
/// and their layout drifts, so every hop is optional.
enum J {
    static func dict(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
    static func arr(_ v: Any?) -> [Any]? { v as? [Any] }
    static func str(_ v: Any?) -> String? { v as? String }
    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }
    static func dbl(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    /// `node.text.runs[].text` joined — the standard YouTube text shape.
    static func runsText(_ node: Any?) -> String {
        guard let runs = arr(dict(node)?["runs"]) else { return "" }
        return runs.compactMap { str(dict($0)?["text"]) }.joined()
    }

    /// Last (largest) thumbnail URL under `thumbnail.musicThumbnailRenderer`.
    static func lastThumb(_ node: Any?) -> String? {
        guard let thumbs = thumbList(node) else { return nil }
        return thumbs.compactMap { str(dict($0)?["url"]) }.last
    }

    /// Last thumbnail's width/height, when present.
    static func lastThumbSize(_ node: Any?) -> (w: Double, h: Double)? {
        guard let last = dict(thumbList(node)?.last),
              let w = dbl(last["width"]), let h = dbl(last["height"]), h > 0 else { return nil }
        return (w, h)
    }

    private static func thumbList(_ node: Any?) -> [Any]? {
        guard let thumb = dict(node)?["thumbnail"],
              let renderer = dict(thumb)?["musicThumbnailRenderer"],
              let inner = dict(renderer)?["thumbnail"] else { return nil }
        return arr(inner["thumbnails"])
    }

    /// Depth-first collection of every renderer object named `name`.
    static func collectRenderers(_ root: Any, named name: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                if d[name] != nil, let r = d[name] as? [String: Any] { out.append(r) }
                for child in d.values { walk(child) }
            } else if let a = v as? [Any] {
                for child in a { walk(child) }
            }
        }
        walk(root)
        return out
    }

    /// True when any string key or value in the subtree mentions `needle`.
    static func subtreeMentions(_ root: Any, _ needle: String) -> Bool {
        if let d = root as? [String: Any] {
            for (k, v) in d {
                if k.contains(needle) { return true }
                if subtreeMentions(v, needle) { return true }
            }
        } else if let a = root as? [Any] {
            for v in a { if subtreeMentions(v, needle) { return true } }
        } else if let s = root as? String, s.contains(needle) {
            return true
        }
        return false
    }
}

// MARK: - Models

/// A streamable song found through search or browse.
struct RemoteTrack: Identifiable, Hashable {
    let videoId: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkURL: URL?
    let isExplicit: Bool
    var id: String { videoId }
}

/// An album, artist or playlist row.
struct BrowseItem: Identifiable, Hashable {
    enum Kind: Hashable { case album, artist, playlist, other }
    let browseId: String
    let title: String
    let subtitle: String
    let kind: Kind
    let artworkURL: URL?
    var id: String { browseId }
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case all, songs, videos, albums, artists, playlists
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Fixed base64 filter params (omit for All).
    var params: String? {
        switch self {
        case .all: return nil
        case .songs: return "EgWKAQIIAWoKEAkQChAFEAMQBA=="
        case .videos: return "EgWKAQIQAWoKEAkQChAFEAMQBA=="
        case .albums: return "EgWKAQIYAWoKEAkQChAFEAMQBA=="
        case .artists: return "EgWKAQIgAWoKEAkQChAFEAMQBA=="
        case .playlists: return "EgWKAQIoAWoKEAkQChAFEAMQBA=="
        }
    }
}

struct SearchResults {
    let topTrack: RemoteTrack?
    let tracks: [RemoteTrack]
    let items: [BrowseItem]
}

struct BrowseResult {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let tracks: [RemoteTrack]
}

// MARK: - InnerTube client

/// YouTube Music's internal API, as the app's engine speaks it: WEB_REMIX for
/// browse/search, native IOS for the player (stream URLs). Guest mode — no
/// login, no secrets; the visitorData token is minted, not stored.
final class InnerTube {
    static let shared = InnerTube()

    private static let musicHost = "https://music.youtube.com/youtubei/v1"
    private static let webRemixVersion = "1.20260707.12.00"
    private static let webRemixUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    private var visitorData: String?
    private var visitorTask: Task<String?, Never>?

    private init() {}

    // MARK: Visitor data

    /// Minted from sw.js_data; load-bearing — without it the player answers
    /// LOGIN_REQUIRED or hands out URLs that 403 on real reads.
    func ensureVisitorData() async -> String? {
        if let v = visitorData { return v }
        if let t = visitorTask { return await t.value }
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            do {
                var req = URLRequest(url: URL(string: "https://www.youtube.com/sw.js_data")!)
                req.setValue(Self.webRemixUA, forHTTPHeaderField: "User-Agent")
                let (data, _) = try await self.session.data(for: req)
                guard data.count > 5 else { return nil }
                let json = String(data: data.dropFirst(5), encoding: .utf8) ?? ""
                let pattern = "Cg[A-Za-z0-9_%-]{40,}"
                if let r = json.range(of: pattern, options: .regularExpression) {
                    let v = String(json[r])
                    self.visitorData = v
                    return v
                }
            } catch { /* guest still works for search */ }
            return nil
        }
        visitorTask = task
        let v = await task.value
        visitorTask = nil
        return v
    }

    // MARK: Transport

    private func musicRequest(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: "\(Self.musicHost)/\(endpoint)?prettyPrint=false&hl=en")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.webRemixUA, forHTTPHeaderField: "User-Agent")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "X-Origin")
        req.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        req.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(Self.webRemixVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        if let v = await ensureVisitorData() {
            req.setValue(v, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        var full = body
        var context = (full["context"] as? [String: Any]) ?? [:]
        var client = (context["client"] as? [String: Any]) ?? [:]
        client["clientName"] = "WEB_REMIX"
        client["clientVersion"] = Self.webRemixVersion
        client["hl"] = "en"
        client["gl"] = "US"
        if let v = visitorData { client["visitorData"] = v }
        context["client"] = client
        context["user"] = ["lockedSafetyMode": false]
        context["request"] = ["useSsl": true]
        full["context"] = context
        req.httpBody = try JSONSerialization.data(withJSONObject: full)
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.badResponse
        }
        // Harvest visitorData whenever the API offers it.
        if let v = J.str(J.dict(json["responseContext"])?["visitorData"]) {
            visitorData = v
        }
        return json
    }

    // MARK: Search

    func search(query: String, filter: SearchFilter) async throws -> SearchResults {
        var body: [String: Any] = ["query": query]
        if let p = filter.params { body["params"] = p }
        let json = try await musicRequest(endpoint: "search", body: body)
        return Self.parseSearch(json, includeVideos: filter == .videos)
    }

    /// Album / artist / playlist page: header plus its track list.
    func browse(browseId: String) async throws -> BrowseResult {
        let json = try await musicRequest(endpoint: "browse", body: ["browseId": browseId])
        var title = "", subtitle = "", artwork: URL?
        if let header = J.dict(json["header"]) {
            if let h = J.dict(header["musicDetailHeaderRenderer"]) {
                title = J.runsText(h["title"])
                subtitle = J.runsText(h["subtitle"])
                if let u = J.lastThumb(h["thumbnail"]) { artwork = URL(string: u) }
            } else if let h = J.dict(header["musicImmersiveHeaderRenderer"]) {
                title = J.runsText(h["title"])
                if let u = J.lastThumb(h["thumbnail"]) { artwork = URL(string: u) }
            }
        }
        let renderers = J.collectRenderers(json, named: "musicResponsiveListItemRenderer")
        var seen = Set<String>()
        let tracks = renderers.compactMap { Self.parseTrack($0) }.filter { seen.insert($0.videoId).inserted }
        return BrowseResult(title: title, subtitle: subtitle, artworkURL: artwork, tracks: tracks)
    }

    // MARK: Search parsing

    private static func parseSearch(_ json: [String: Any], includeVideos: Bool) -> SearchResults {
        // Promoted top result lives on the card shelf, not in a row.
        var topTrack: RemoteTrack?
        for card in J.collectRenderers(json, named: "musicCardShelfRenderer") {
            if let vid = J.str(J.dict(J.dict(card["onTap"])?["watchEndpoint"])?["videoId"]) {
                let title = J.runsText(card["title"])
                let sub = J.runsText(card["subtitle"])
                let (artist, duration) = parseSubtitle(sub)
                let art = J.lastThumb(card["thumbnail"]).flatMap(URL.init(string:))
                if !title.isEmpty, !vid.isEmpty {
                    topTrack = RemoteTrack(videoId: vid, title: title, artist: artist,
                                           album: "", duration: duration, artworkURL: art,
                                           isExplicit: false)
                }
                break
            }
        }
        let renderers = J.collectRenderers(json, named: "musicResponsiveListItemRenderer")
        var seenTracks = Set<String>()
        var seenBrowse = Set<String>()
        var tracks: [RemoteTrack] = []
        var items: [BrowseItem] = []
        for r in renderers {
            // Browse rows first: album rows carry a decoy play videoId.
            if let item = parseBrowseRow(r) {
                if seenBrowse.insert(item.browseId).inserted { items.append(item) }
                continue
            }
            if let parsed = parseTrack(r),
               parsed.isVideoIdValid,
               parsed.isVideo == includeVideos,
               seenTracks.insert(parsed.track.videoId).inserted {
                tracks.append(parsed.track)
            }
        }
        return SearchResults(topTrack: topTrack, tracks: tracks, items: items)
    }

    private struct ParsedTrack {
        let track: RemoteTrack
        var isVideo: Bool
        var isVideoIdValid: Bool { !track.videoId.isEmpty }
    }

    private static func parseTrack(_ r: [String: Any]) -> ParsedTrack? {
        let overlayVideoId: String? = {
            guard let overlay = J.dict(r["overlay"]),
                  let tiro = J.dict(overlay["musicItemThumbnailOverlayRenderer"]),
                  let content = J.dict(tiro["content"]),
                  let playBtn = J.dict(content["musicPlayButtonRenderer"]),
                  let playEp = J.dict(playBtn["playNavigationEndpoint"]),
                  let watch = J.dict(playEp["watchEndpoint"]) else { return nil }
            return J.str(watch["videoId"])
        }()
        let videoId = J.str(J.dict(r["playlistItemData"])?["videoId"]) ?? overlayVideoId ?? ""
        guard !videoId.isEmpty else { return nil }
        let columns = J.arr(r["flexColumns"])?.compactMap(J.dict) ?? []
        func columnText(_ i: Int) -> [String: Any]? {
            guard columns.indices.contains(i) else { return nil }
            return J.dict(columns[i]["musicResponsiveListItemFlexColumnRenderer"])?["text"] as? [String: Any]
        }
        let title = J.runsText(columnText(0))
        guard !title.isEmpty else { return nil }
        let subNode = columnText(1)
        let subtitle = J.runsText(subNode)
        let (artist, duration) = parseSubtitle(subtitle)
        // Duration can also sit in a fixed column (album-page rows).
        var dur = duration
        if dur == 0 {
            for fc in (J.arr(r["fixedColumns"])?.compactMap(J.dict) ?? []) {
                let t = J.runsText(J.dict(fc["musicResponsiveListItemFixedColumnRenderer"])?["text"])
                if let d = parseDuration(t) { dur = d; break }
            }
        }
        var isVideo = subtitle.split(separator: "•").first?
            .trimmingCharacters(in: .whitespaces).lowercased() == "video"
        if let size = J.lastThumbSize(r["thumbnail"]), size.h > 0 {
            let ratio = size.w / size.h
            if ratio < 0.85 || ratio > 1.15 { isVideo = true }
        }
        let art = J.lastThumb(r["thumbnail"]).flatMap(URL.init(string:))
        let explicit = J.subtreeMentions(r, "MUSIC_EXPLICIT_BADGE")
        let track = RemoteTrack(videoId: videoId, title: title, artist: artist, album: "",
                                duration: dur, artworkURL: art, isExplicit: explicit)
        return ParsedTrack(track: track, isVideo: isVideo)
    }

    /// A row is a browse row when it navigates to a browseId.
    private static func parseBrowseRow(_ r: [String: Any]) -> BrowseItem? {
        let nav = J.dict(r["navigationEndpoint"])
        let browse = J.dict(nav?["browseEndpoint"])
        guard let browseId = J.str(browse?["browseId"]) else { return nil }
        let columns = J.arr(r["flexColumns"])?.compactMap(J.dict) ?? []
        func columnText(_ i: Int) -> String {
            guard columns.indices.contains(i) else { return "" }
            let n = J.dict(columns[i]["musicResponsiveListItemFlexColumnRenderer"])?["text"]
            return J.runsText(n)
        }
        let title = columnText(0)
        guard !title.isEmpty else { return nil }
        let subtitle = columnText(1)
        if title.lowercased().contains("video") && subtitle.isEmpty { return nil }
        let pageType: String = {
            guard let browse,
                  let configs = J.dict(browse["browseEndpointContextSupportedConfigs"]),
                  let musicConfig = J.dict(configs["browseEndpointContextMusicConfig"]) else { return "" }
            return (J.str(musicConfig["pageType"]) ?? "").uppercased()
        }()
        let kind: BrowseItem.Kind
        if pageType.contains("ALBUM") { kind = .album }
        else if pageType.contains("ARTIST") { kind = .artist }
        else if pageType.contains("PLAYLIST") { kind = .playlist }
        else { kind = .other }
        let art = J.lastThumb(r["thumbnail"]).flatMap(URL.init(string:))
        return BrowseItem(browseId: browseId, title: title, subtitle: subtitle,
                          kind: kind, artworkURL: art)
    }

    // MARK: Subtitle parsing

    private static let typeWords: Set<String> =
        ["song", "video", "album", "single", "ep", "artist", "playlist", "podcast", "episode"]

    /// Splits a "Artist • Album • 3:45" subtitle into (artist, durationSeconds).
    static func parseSubtitle(_ subtitle: String) -> (artist: String, duration: TimeInterval) {
        let segments = subtitle.split(separator: "•").map { $0.trimmingCharacters(in: .whitespaces) }
        var artist = ""
        var duration: TimeInterval = 0
        let tally = try? NSRegularExpression(
            pattern: "[\\d.,]+\\s*[KMB]?\\s+(plays|views|likes|songs|tracks|subscribers|hours?|minutes?|seconds?)\\b.*",
            options: .caseInsensitive)
        for seg in segments {
            if parseDuration(seg).map({ duration = $0 }) != nil { continue }
            let low = seg.lowercased()
            if typeWords.contains(low) { continue }
            if let t = tally,
               t.firstMatch(in: seg, range: NSRange(seg.startIndex..., in: seg)) != nil { continue }
            if artist.isEmpty { artist = seg }
        }
        return (artist, duration)
    }

    static func parseDuration(_ s: String) -> TimeInterval? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard (2...3).contains(parts.count) else { return nil }
        if parts.count == 2 { return TimeInterval(parts[0] * 60 + parts[1]) }
        return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
    }
}

enum InnerTubeError: Error, LocalizedError {
    case badResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "The music service answered in a way we couldn't read."
        case .network(let e): return e.localizedDescription
        }
    }
}
