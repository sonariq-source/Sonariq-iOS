import Foundation

// MARK: - Models (ported from the Android engine; timings are milliseconds)

/// One separately timed piece of a word: characters [startChar]..<[endChar]
/// of the word's text, sung from [startMs] to [endMs].
struct LyricSyllable {
    let startMs: Int64
    let endMs: Int64
    let startChar: Int
    let endChar: Int

    /// Tidies a word's syllables, as a parser collected them, into contiguous
    /// coverage of the word's characters.
    static func normalized(_ parts: [LyricSyllable], length: Int) -> [LyricSyllable] {
        let usable = parts
            .filter { $0.endChar > $0.startChar && $0.startChar < length }
            .sorted { $0.startChar < $1.startChar }
        guard usable.count >= 2 else { return [] }
        return usable.enumerated().map { index, part in
            LyricSyllable(
                startMs: part.startMs,
                endMs: max(part.startMs, part.endMs),
                startChar: index == 0 ? 0 : part.startChar,
                endChar: usable[safe: index + 1]?.startChar ?? length
            )
        }
    }
}

/// One word of a line, with the stretch of the song it is sung over.
struct LyricWord: Identifiable {
    let id = UUID()
    let startMs: Int64
    let endMs: Int64
    let text: String
    let syllables: [LyricSyllable]

    /// How many of [text]'s characters have been sung at [positionMs].
    /// Each syllable fills its own characters over its own time; a pause
    /// between two of them rests on the boundary.
    func charsSungAt(positionMs: Int64) -> Double {
        if positionMs <= startMs { return 0 }
        if positionMs >= endMs { return Double(text.count) }
        if syllables.isEmpty {
            let span = max(Int64(1), endMs - startMs)
            return Double(positionMs - startMs) / Double(span) * Double(text.count)
        }
        for s in syllables {
            if positionMs < s.startMs { return Double(s.startChar) }
            if positionMs < s.endMs {
                let span = max(Int64(1), s.endMs - s.startMs)
                let through = Double(positionMs - s.startMs) / Double(span)
                return Double(s.startChar) + through * Double(s.endChar - s.startChar)
            }
        }
        return Double(text.count)
    }
}

/// One lyric line. [words] is empty for a line-synced source — which is what
/// keeps "word sync only when the provider truly timed the words" honest.
struct LyricsLine: Identifiable {
    let id = UUID()
    let timeMs: Int64
    let text: String
    let words: [LyricWord]
    /// When the singing on this line stops, if the source said (TTML `end`).
    let sungUntilMs: Int64?

    init(timeMs: Int64, text: String, words: [LyricWord] = [], sungUntilMs: Int64? = nil) {
        self.timeMs = timeMs
        self.text = text
        self.words = words
        self.sungUntilMs = sungUntilMs
    }

    var isWordSynced: Bool { !words.isEmpty }
    /// A blank line marks an instrumental break.
    var isGap: Bool { text.isEmpty }
    var endMs: Int64 { sungUntilMs ?? timeMs }
    var hasKnownEnd: Bool { sungUntilMs != nil }
}

// MARK: - LRC parsing (ported from LrcLib)

/// Instrumental breaks shorter than this aren't worth interrupting the line for.
let lyricsMinGapMs: Int64 = 4_000

private struct TimedRun {
    let startMs: Int64
    let endMs: Int64
    let raw: String
}

enum LRCParser {
    private static let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})[.:](\d{2,3})\]"#)
    private static let wordStamp = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2})[.:](\d{2,3})>"#)

    /// `[mm:ss.xx] words`. A stamp with no words marks an instrumental break;
    /// those are kept only where the silence is long enough to be worth
    /// showing. A stamp with nothing after it closes the final line.
    static func parse(_ lrc: String) -> [LyricsLine] {
        var all: [LyricsLine] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = stamp.firstMatch(in: rawLine, range: range),
                  match.numberOfRanges == 4 else { continue }
            let minutes = Int64(ns.substring(with: match.range(at: 1))) ?? 0
            let seconds = Int64(ns.substring(with: match.range(at: 2))) ?? 0
            let fraction = ns.substring(with: match.range(at: 3))
            let fractionMs: Int64
            switch fraction.count {
            case 2: fractionMs = (Int64(fraction) ?? 0) * 10
            case 3: fractionMs = Int64(fraction) ?? 0
            default: fractionMs = 0
            }
            let body = ns.substring(from: match.range.location + match.range.length)
            let text = wordStamp.stringByReplacingMatches(
                in: body, range: NSRange(location: 0, length: (body as NSString).length),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
            all.append(LyricsLine(
                timeMs: minutes * 60_000 + seconds * 1_000 + fractionMs,
                text: text,
                words: parseWordRuns(body)
            ))
        }
        all.sort { $0.timeMs < $1.timeMs }

        var kept: [LyricsLine] = []
        for (index, line) in all.enumerated() {
            if !line.isGap { kept.append(line); continue }
            // A trailing stamp closes off the last line — that's the outro.
            guard let next = all[safe: index + 1] else { kept.append(line); continue }
            if next.timeMs - line.timeMs >= lyricsMinGapMs { kept.append(line) }
        }

        // Nothing stands for the intro — LRC files start at the first sung
        // word — so give the run-up its own break when it's long enough.
        guard let first = kept.first else { return kept }
        if !first.isGap && first.timeMs >= lyricsMinGapMs {
            return [LyricsLine(timeMs: 0, text: "")] + kept
        }
        return kept
    }

    /// The `<mm:ss.xx>` runs of an "enhanced" line, as words. Each run ends
    /// where the next one starts; a run with no text is a terminator rather
    /// than a word. Empty for a plain line, which keeps [LyricsLine.isWordSynced]
    /// honest — a line-synced source stays line-synced through this.
    private static func parseWordRuns(_ body: String) -> [LyricWord] {
        let ns = body as NSString
        let matches = wordStamp.matches(in: body, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }
        var runs: [TimedRun] = []
        for (index, mark) in matches.enumerated() {
            let until = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let start = matchMs(ns, mark)
            let textStart = mark.range.location + mark.range.length
            let text = ns.substring(with: NSRange(location: textStart, length: until - textStart))
            runs.append(TimedRun(startMs: start, endMs: start, raw: text))
        }
        let timed = runs.enumerated().map { index, run in
            TimedRun(startMs: run.startMs,
                     endMs: runs[safe: index + 1]?.startMs ?? run.startMs,
                     raw: run.raw)
        }
        return wordsFromRuns(timed)
    }

    private static func matchMs(_ ns: NSString, _ mark: NSTextCheckingResult) -> Int64 {
        let minutes = Int64(ns.substring(with: mark.range(at: 1))) ?? 0
        let seconds = Int64(ns.substring(with: mark.range(at: 2))) ?? 0
        let fraction = ns.substring(with: mark.range(at: 3))
        let fractionMs: Int64
        switch fraction.count {
        case 2: fractionMs = (Int64(fraction) ?? 0) * 10
        case 3: fractionMs = Int64(fraction) ?? 0
        default: fractionMs = 0
        }
        return minutes * 60_000 + seconds * 1_000 + fractionMs
    }

    /// Glues timed runs back into words. A word ends at the first whitespace
    /// after it; a run with no space after it is one syllable of a word that
    /// carries on.
    static func wordsFromRuns(_ runs: [TimedRun]) -> [LyricWord] {
        let glue = runs.contains { $0.raw.contains(where: { $0.isWhitespace }) }
        var words: [LyricWord] = []
        var current = ""
        var parts: [LyricSyllable] = []
        var start: Int64 = 0
        var end: Int64 = 0

        func flush() {
            if !current.isEmpty {
                words.append(LyricWord(
                    startMs: start, endMs: max(start, end), text: current,
                    syllables: LyricSyllable.normalized(parts, length: current.count)
                ))
            }
            current = ""
            parts = []
        }

        for run in runs {
            let content = run.raw.trimmingCharacters(in: .whitespaces)
            if content.isEmpty { flush(); continue }
            let joins = glue && !current.isEmpty
                && !(run.raw.first?.isWhitespace ?? true)
                && !(current.last?.isUnspacedScript ?? false)
                && !(content.first?.isUnspacedScript ?? false)
            if !joins { flush() }
            if current.isEmpty { start = run.startMs; end = run.startMs }
            let from = current.count
            current.append(content)
            let runEnd = max(run.startMs, run.endMs)
            parts.append(LyricSyllable(startMs: run.startMs, endMs: runEnd,
                                       startChar: from, endChar: current.count))
            end = max(end, runEnd)
            if !glue || (run.raw.last?.isWhitespace ?? false) { flush() }
        }
        flush()
        return words
    }
}

private extension Character {
    /// Scripts written without spaces between words.
    var isUnspacedScript: Bool {
        let v = unicodeScalars.first!.value
        return (0x3400...0x9FFF).contains(v) || // Han
            (0x3040...0x30FF).contains(v) || // hiragana and katakana
            (0x3000...0x303F).contains(v) || // CJK punctuation
            (0xFF00...0xFFEF).contains(v) || // full-width forms
            (0x0E00...0x0E7F).contains(v) // Thai
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
