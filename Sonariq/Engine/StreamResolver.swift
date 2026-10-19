import Foundation
import JavaScriptCore

/// A verified playable stream: the URL plus the exact headers its bytes must
/// be fetched with (googlevideo compares them against the minting request).
struct ResolvedStream {
    let url: URL
    let headers: [String: String]
    let mimeType: String
    let bitrate: Int
    let loudnessDb: Double?
    /// Cache file extension for the container.
    let fileExtension: String
}

/// Turns a videoId into a URL the player can actually use, the way the
/// engine does it: IOS player request → best AAC audio format → decipher when
/// ciphered → probe bytes before trusting it.
actor StreamResolver {
    static let shared = StreamResolver()

    /// YouTube's public web-client key, embedded in YouTube's own public web
    /// app — not a secret, the same value every public client ships.
    private static let apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"

    private static let iosClient: [String: Any] = [
        "clientName": "IOS",
        "clientVersion": "21.26.4",
        "userAgent": "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        "osName": "iOS",
        "osVersion": "18.3.2.22D82",
        "deviceMake": "Apple",
        "deviceModel": "iPhone16,2",
        "platform": "MOBILE",
        "hl": "en",
        "gl": "US",
    ]
    private static let iosUA = "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
    private static let androidMusicUA =
        "com.google.android.apps.youtube.music/8.39.42 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002) gzip"

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    /// Bitrate ceiling in kbps; Int.max means no user limit.
    var maxKbps = Int.max

    private var cipherConfig: CipherConfig?
    private var cipherConfigTask: Task<CipherConfig?, Never>?
    private var playerHashCache: [String: String] = [:]
    private var baseJsCache: [String: String] = [:]
    /// videoIds whose URLs are known-dead for a while (10 min TTL).
    private var deadUntil: [String: Date] = [:]

    // MARK: - Resolve

    func resolve(videoId: String) async throws -> ResolvedStream {
        if let until = deadUntil[videoId], until > Date() {
            throw StreamError.unplayable("This track isn't available right now.")
        }
        let sts = await signatureTimestamp(for: videoId)
        let formats = try await playerFormats(videoId: videoId, sts: sts)
        // iOS must have AAC-in-MP4: AVAudioEngine cannot read Opus/WebM.
        let audio = formats.filter { $0.mime.hasPrefix("audio/") }
        let mp4 = audio.filter { $0.mime.contains("audio/mp4") }
        let pool = mp4.isEmpty ? audio : mp4
        guard !pool.isEmpty else { throw StreamError.unplayable("No playable audio found.") }
        // Highest bitrate at/under the ceiling, else the lowest rung.
        let sorted = pool.sorted { $0.bitrate < $1.bitrate }
        let pick = sorted.last(where: { $0.bitrate / 1000 <= maxKbps }) ?? sorted.first!
        return try await finalize(format: pick, videoId: videoId)
    }

    // MARK: - Player request

    private struct Format {
        let mime: String
        let bitrate: Int
        let url: String?
        let cipher: String?
        let loudnessDb: Double?
    }

    private func playerFormats(videoId: String, sts: Int?) async throws -> [Format] {
        let url = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(Self.apiKey)&prettyPrint=false")!
        var client = Self.iosClient
        if let v = await InnerTube.shared.ensureVisitorData() { client["visitorData"] = v }
        var playback: [String: Any] = ["html5Preference": "HTML5_PREF_WANTS"]
        if let sts { playback["signatureTimestamp"] = sts }
        let body: [String: Any] = [
            "context": ["client": client, "request": ["useSsl": true]],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": ["contentPlaybackContext": playback],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.iosUA, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamError.badResponse
        }
        let status = J.dict(json["playabilityStatus"])
        let state = J.str(status?["status"]) ?? ""
        if state == "LOGIN_REQUIRED" {
            // One fresh visitorData, then one retry — a burned session stays burned.
            throw StreamError.loginRequired(J.str(status?["reason"]))
        }
        if state != "OK" {
            let reason = J.str(status?["reason"]) ?? "This track can't be played."
            if reason.lowercased().contains("unavailable") {
                deadUntil[videoId] = Date().addingTimeInterval(600)
            }
            throw StreamError.unplayable(reason)
        }
        let formats = J.arr(J.dict(json["streamingData"])?["adaptiveFormats"]) ?? []
        return formats.compactMap { f -> Format? in
            guard let d = J.dict(f),
                  let mime = J.str(d["mimeType"]),
                  let bitrate = J.int(d["bitrate"]) else { return nil }
            return Format(mime: mime, bitrate: bitrate,
                          url: J.str(d["url"]),
                          cipher: J.str(d["signatureCipher"]) ?? J.str(d["signature_cipher"]) ?? J.str(d["cipher"]),
                          loudnessDb: J.dbl(d["loudnessDb"]))
        }
    }

    // MARK: - Finalize: decipher, n-transform, probe

    private func finalize(format: Format, videoId: String) async throws -> ResolvedStream {
        var urlString: String
        if let u = format.url {
            urlString = u
        } else if let c = format.cipher {
            urlString = try await decipher(cipher: c, videoId: videoId)
        } else {
            throw StreamError.badResponse
        }
        urlString = await descrambleN(in: urlString, videoId: videoId)
        guard var components = URLComponents(string: urlString),
              let url = components.url else { throw StreamError.badResponse }
        let headers = Self.mediaHeaders(for: url)
        try await probe(url: url, headers: headers)
        let ext = format.mime.contains("audio/mp4") ? "m4a" : "webm"
        return ResolvedStream(url: url, headers: headers, mimeType: format.mime,
                              bitrate: format.bitrate, loudnessDb: format.loudnessDb,
                              fileExtension: ext)
    }

    // MARK: - Cipher

    private struct CipherConfig: Decodable {
        struct Entry: Decodable {
            let sig: String?
            let nClass: String?
            let sts: Int?
            let aliases: [String]?
        }
        let players: [String: Entry]
    }

    private func cipherConfigValue() async -> CipherConfig? {
        if let c = cipherConfig { return c }
        if let t = cipherConfigTask { return await t.value }
        let task = Task<CipherConfig?, Never> { [session] in
            do {
                let url = URL(string: "https://raw.githubusercontent.com/ZemerTeam/zemer-cipher/master/library/src/main/assets/player_configs.json")!
                let (data, _) = try await session.data(from: url)
                return try JSONDecoder().decode(CipherConfig.self, from: data)
            } catch { return nil }
        }
        cipherConfigTask = task
        let c = await task.value
        cipherConfigTask = nil
        cipherConfig = c
        return c
    }

    /// The current base.js player hash, from the watch page.
    private func playerHash(for videoId: String) async -> String? {
        if let h = playerHashCache[videoId] { return h }
        do {
            var req = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoId)")!)
            req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
                         forHTTPHeaderField: "User-Agent")
            let (data, _) = try await session.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""
            if let r = html.range(of: "/s/player/([\\w\\-\\.]+)/", options: .regularExpression) {
                var h = String(html[r])
                h = h.replacingOccurrences(of: "/s/player/", with: "").replacingOccurrences(of: "/", with: "")
                playerHashCache[videoId] = h
                return h
            }
        } catch {}
        return nil
    }

    private func baseJs(for hash: String) async -> String? {
        if let js = baseJsCache[hash] { return js }
        do {
            let url = URL(string: "https://www.youtube.com/s/player/\(hash)/player_ias.vflset/en_US/base.js")!
            let (data, _) = try await session.data(from: url)
            guard let js = String(data: data, encoding: .utf8), !js.isEmpty else { return nil }
            baseJsCache[hash] = js
            return js
        } catch { return nil }
    }

    private func signatureTimestamp(for videoId: String) async -> Int? {
        guard let hash = await playerHash(for: videoId),
              let config = await cipherConfigValue() else { return nil }
        if let e = config.players[hash] ?? config.players.values.first(where: { $0.aliases?.contains(hash) == true }) {
            return e.sts
        }
        return nil
    }

    /// Deciphers a signatureCipher query string into a playable URL.
    private func decipher(cipher: String, videoId: String) async throws -> String {
        var comps = URLComponents()
        comps.query = cipher
        let items = comps.queryItems ?? []
        guard let s = items.first(where: { $0.name == "s" })?.value,
              let base = items.first(where: { $0.name == "url" })?.value else {
            throw StreamError.badResponse
        }
        let sp = items.first(where: { $0.name == "sp" })?.value ?? "sig"
        let sig = try await descrambleSignature(s, videoId: videoId)
        var urlComps = URLComponents(string: base) ?? URLComponents()
        var qi = urlComps.queryItems ?? []
        qi.append(URLQueryItem(name: sp, value: sig))
        urlComps.queryItems = qi
        guard let out = urlComps.url?.absoluteString else { throw StreamError.badResponse }
        return out
    }

    /// Runs YouTube's descramble function on `s` inside JavaScriptCore.
    private func descrambleSignature(_ s: String, videoId: String) async throws -> String {
        guard let hash = await playerHash(for: videoId),
              let js = await baseJs(for: hash),
              let config = await cipherConfigValue(),
              let entry = config.players[hash] ?? config.players.values.first(where: { $0.aliases?.contains(hash) == true }),
              let template = entry.sig else {
            throw StreamError.decipherFailed
        }
        // Template looks like "Tl(48,5831,INPUT)".
        guard let open = template.firstIndex(of: "("), template.hasSuffix(",INPUT)") else {
            throw StreamError.decipherFailed
        }
        let name = String(template[..<open])
        let argsStart = template.index(after: open)
        let argsEnd = template.index(template.endIndex, offsetBy: -7) // strip ",INPUT)"
        guard argsEnd >= argsStart, name.range(of: "^\\w+$", options: .regularExpression) != nil else {
            throw StreamError.decipherFailed
        }
        let args = String(template[argsStart..<argsEnd])
        return try await runJs(baseJs: js, call: "\(name)(\(args),__input)", input: s)
    }

    /// Best-effort `n`-param transform. Skipping it doesn't break playback —
    /// it throttles the download — so failure here is non-fatal.
    private func descrambleN(in urlString: String, videoId: String) async -> String {
        guard var comps = URLComponents(string: urlString),
              var items = comps.queryItems,
              let nIdx = items.firstIndex(where: { $0.name == "n" }),
              let n = items[nIdx].value,
              let hash = await playerHash(for: videoId),
              let js = await baseJs(for: hash),
              let config = await cipherConfigValue(),
              let entry = config.players[hash] ?? config.players.values.first(where: { $0.aliases?.contains(hash) == true }),
              let nClass = entry.nClass else { return urlString }
        // nClass names the object holding the transform; try it as a function first.
        for candidate in ["\(nClass)('\(n)')", "\(nClass).n('\(n)')"] {
            if let out = try? await runJs(baseJs: js, call: candidate, input: n), !out.isEmpty, out != n {
                items[nIdx].value = out
                comps.queryItems = items
                return comps.url?.absoluteString ?? urlString
            }
        }
        return urlString
    }

    private func runJs(baseJs: String, call: String, input: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let ctx = JSContext() else {
                    cont.resume(throwing: StreamError.decipherFailed)
                    return
                }
                ctx.evaluateScript(baseJs)
                let escaped = input
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                ctx.evaluateScript("var __input='\(escaped)';")
                let result = ctx.evaluateScript("var __out=\(call); __out;")
                if let s = result?.toString(), !s.isEmpty, s != "undefined" {
                    cont.resume(returning: s)
                } else {
                    cont.resume(throwing: StreamError.decipherFailed)
                }
            }
        }
    }

    // MARK: - Probe

    /// Never trust a URL until bytes come back. Probes a real-sized range —
    /// googlevideo serves small ranges to a distrusted session and 403s the
    /// ranges playback actually uses.
    private func probe(url: URL, headers: [String: String]) async throws {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let length = comps?.queryItems?.first(where: { $0.name == "clen" })?.value.flatMap(Int.init)
        let chunk = Self.rangeBytes(for: url)
        let start: Int
        if let length, length > 1_048_576 + 16_384 {
            start = 1_048_576 // past 1 MiB: some clients authorize only the first MiB
        } else {
            start = 0
        }
        let end: Int
        if let length { end = min(start + chunk, length) - 1 } else { end = start + chunk - 1 }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 6
        do {
            let (data, response) = try await URLSession(configuration: config).data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if [403, 404, 410].contains(code) { throw StreamError.refused }
            guard (200...299).contains(code) || code == 206 else { throw StreamError.unreachable }
            let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard type.hasPrefix("audio/") else { throw StreamError.refused }
            guard data.count >= 16_384 else { throw StreamError.unreachable }
        } catch let e as StreamError {
            throw e
        } catch {
            throw StreamError.unreachable
        }
    }

    // MARK: - Media headers

    /// Headers the byte fetch must carry, matching the client baked into the
    /// URL's `c`/`cver` params. Native clients send User-Agent only.
    static func mediaHeaders(for url: URL) -> [String: String] {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let name = comps?.queryItems?.first(where: { $0.name == "c" })?.value?.uppercased() ?? "IOS"
        var headers: [String: String] = [:]
        if name.hasPrefix("WEB_REMIX") {
            headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
            headers["Origin"] = "https://music.youtube.com"
            headers["Referer"] = "https://music.youtube.com/"
        } else if name.hasPrefix("WEB") || name == "MWEB" {
            headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
            headers["Origin"] = "https://www.youtube.com"
            headers["Referer"] = "https://www.youtube.com/"
        } else if name == "ANDROID_MUSIC" {
            headers["User-Agent"] = androidMusicUA
        } else if name.hasPrefix("ANDROID") {
            headers["User-Agent"] = "com.google.android.youtube/21.26.364 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002; Cronet/132.0.6834.79) gzip"
        } else {
            headers["User-Agent"] = iosUA
        }
        return headers
    }

    private static func rangeBytes(for url: URL) -> Int {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let name = comps?.queryItems?.first(where: { $0.name == "c" })?.value?.uppercased() ?? ""
        if name == "ANDROID_VR" || name.hasPrefix("TVHTML5_SIMPLY") { return 512 * 1024 }
        return 1024 * 1024
    }
}

enum StreamError: Error, LocalizedError {
    case badResponse
    case loginRequired(String?)
    case unplayable(String)
    case decipherFailed
    case refused
    case unreachable

    var errorDescription: String? {
        switch self {
        case .badResponse: return "The music service answered in a way we couldn't read."
        case .loginRequired(let r): return r ?? "Sign in to confirm you're not a bot."
        case .unplayable(let r): return r
        case .decipherFailed: return "Couldn't unlock this track's stream."
        case .refused: return "The music service refused this track."
        case .unreachable: return "Couldn't reach the music service. Check your connection."
        }
    }
}
