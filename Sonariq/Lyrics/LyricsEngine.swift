import Foundation
import CryptoKit

// MARK: - Query / result

struct LyricsQuery {
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int64
    let isrc: String?

    init(song: Song) {
        title = song.title
        artist = song.artist
        album = song.album.isEmpty ? nil : song.album
        durationMs = Int64(song.duration * 1000)
        isrc = nil // MediaPlayer does not expose the ISRC; lrc.red falls back to search.
    }
}

enum LyricsFormat: String, Codable {
    case ttml
    case lrc
}

/// What a provider fetched: parsed lines plus the raw document, so the disk
/// cache can store the document and re-parse it on load.
struct FetchedLyrics {
    let lines: [LyricsLine]
    let rawText: String
    let format: LyricsFormat
}

struct LyricsResult {
    let lines: [LyricsLine]
    let sourceName: String
    let rawText: String
    let format: LyricsFormat
    var hasWordTimings: Bool { lines.contains(where: { $0.isWordSynced }) }
}

protocol LyricsProvider {
    var name: String { get }
    func fetch(_ query: LyricsQuery) async -> FetchedLyrics?
}

private struct LrcRedProvider: LyricsProvider {
    let name = "lrc.red"
    func fetch(_ query: LyricsQuery) async -> FetchedLyrics? {
        guard let fetched = await LrcRed.fetch(title: query.title, artist: query.artist,
                                               durationMs: query.durationMs, isrc: query.isrc) else { return nil }
        return FetchedLyrics(lines: fetched.lines, rawText: fetched.rawText, format: .ttml)
    }
}

private struct LrcLibProvider: LyricsProvider {
    let name = "LRCLIB"
    func fetch(_ query: LyricsQuery) async -> FetchedLyrics? {
        guard let fetched = await LrcLib.fetch(title: query.title, artist: query.artist,
                                               durationMs: query.durationMs) else { return nil }
        return FetchedLyrics(lines: fetched.lines, rawText: fetched.rawText, format: .lrc)
    }
}

// MARK: - Engine

/// Asks every provider in parallel and takes the best answer: a result with
/// true word timings wins immediately; otherwise the first line-synced
/// result. Results are cached on disk.
enum LyricsEngine {
    private static let providers: [any LyricsProvider] = [LrcRedProvider(), LrcLibProvider()]
    private static let timeoutSeconds = 12.0

    static func fetch(for song: Song) async -> LyricsResult? {
        let query = LyricsQuery(song: song)
        if let cached = LyricsCache.load(query: query) { return cached }
        let result: LyricsResult?? = await withTimeout(timeoutSeconds) {
            await withTaskGroup(of: LyricsResult?.self, returning: LyricsResult?.self) { group in
                for provider in providers {
                    group.addTask {
                        guard let fetched = await provider.fetch(query), !fetched.lines.isEmpty else { return nil }
                        return LyricsResult(lines: fetched.lines, sourceName: provider.name,
                                            rawText: fetched.rawText, format: fetched.format)
                    }
                }
                var fallback: LyricsResult?
                for await candidate in group {
                    guard let candidate else { continue }
                    if candidate.hasWordTimings {
                        group.cancelAll()
                        return candidate
                    }
                    if fallback == nil { fallback = candidate }
                }
                return fallback
            }
        }
        let unwrapped = result ?? nil
        if let unwrapped { LyricsCache.save(unwrapped, query: query) }
        return unwrapped
    }

    /// Runs [work], giving up after [seconds] and returning nil.
    private static func withTimeout<T>(_ seconds: Double, work: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self, returning: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            for await value in group {
                group.cancelAll()
                return value
            }
            return nil
        }
    }
}

// MARK: - HTTP

enum LyricsHTTP {
    static func get(urlString: String, userAgent: String? = nil) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

// MARK: - Disk cache

/// Caches fetched lyrics documents (re-parsed on load) under a SHA-256 key,
/// like the Android engine. Hits live 30 days.
private enum LyricsCache {
    private static let ttl: TimeInterval = 30 * 24 * 3600

    private struct Entry: Codable {
        let source: String
        let format: String // "ttml" or "lrc"
        let text: String
        let fetchedAt: Date
    }

    private static var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sonariq-lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func key(for query: LyricsQuery) -> String {
        // Duration bucketed to 5s so small differences still hit.
        let raw = "\(query.artist.lowercased())|\(query.title.lowercased())|\(query.durationMs / 5000)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func load(query: LyricsQuery) -> LyricsResult? {
        let url = directory.appendingPathComponent(key(for: query) + ".json")
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              Date().timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        let lines = entry.format == "ttml" ? TtmlLyrics.parse(entry.text) : LRCParser.parse(entry.text)
        guard !lines.isEmpty else { return nil }
        return LyricsResult(lines: lines, sourceName: entry.source)
    }

    static func save(_ result: LyricsResult, query: LyricsQuery) {
        // The raw document is what was fetched; it is re-parsed on load.
        let entry = Entry(source: result.sourceName,
                          format: result.format.rawValue,
                          text: result.rawText,
                          fetchedAt: Date())
        guard !entry.text.isEmpty,
              let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: directory.appendingPathComponent(key(for: query) + ".json"))
    }
}
