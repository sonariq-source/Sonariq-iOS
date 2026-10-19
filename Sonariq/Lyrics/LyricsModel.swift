import Foundation

/// One timed lyric line.
struct LyricsLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

/// Minimal LRC parser: "[mm:ss.xx] line". Produces real line timings;
/// word-level timings arrive with the provider work.
enum LRCParser {
    static func parse(_ lrc: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        let pattern = #"\[(\d+):(\d+(?:\.\d+)?)\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for raw in lrc.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            guard let m = regex.firstMatch(in: raw, range: range),
                  let minR = Range(m.range(at: 1), in: raw),
                  let secR = Range(m.range(at: 2), in: raw),
                  let txtR = Range(m.range(at: 3), in: raw),
                  let min = Double(raw[minR]),
                  let sec = Double(raw[secR]) else { continue }
            let text = raw[txtR].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(LyricsLine(time: min * 60 + sec, text: text))
        }
        return lines.sorted { $0.time < $1.time }
    }
}

/// Fetches timed lyrics for a track. No providers are bundled yet — the view
/// shows an honest empty state until one lands.
protocol LyricsProvider {
    func lyrics(for song: Song) async -> [LyricsLine]
}
