import Foundation

/// Apple Music's word-timed lyric format (ported from the Android engine).
///
/// A document is `<p>` per sung line, each holding one `<span>` per syllable
/// with its own `begin`/`end`:
///
/// ```xml
/// <p begin="27.395" end="28.960">
///   <span begin="27.395" end="27.549">I</span>
///   <span begin="27.549" end="27.740">been</span>
/// </p>
/// ```
///
/// Syllables of one word are written as adjacent spans with no whitespace
/// between them ("e" + "nough"), so whitespace — not the span boundary — is
/// what separates words. That is the whole trick to reading this format.
enum TtmlLyrics {

    /// Roles that are not this line at all: translations and romanisations
    /// are alternate renderings of the same words and would double the line up.
    private static let skippedRoles: Set<String> = ["x-translation", "x-roman"]

    /// The answering vocal, kept apart from the lead so it never drags the
    /// word sweep along.
    private static let backgroundRole = "x-bg"

    static func parse(_ ttml: String) -> [LyricsLine] {
        guard let data = ttml.data(using: .utf8) else { return [] }
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root = builder.root else { return [] }
        var lines: [LyricsLine] = []
        for p in root.descendants(named: "p") {
            lines.append(contentsOf: linesFrom(p))
        }
        lines.sort { $0.timeMs < $1.timeMs }
        return withInstrumentalGaps(lines)
    }

    private static func linesFrom(_ p: TtmlNode) -> [LyricsLine] {
        var pieces: [Piece] = []
        var backingPieces: [Piece] = []
        collect(p, into: &pieces, backing: &backingPieces)
        let words = mergeIntoWords(pieces)
        var result: [LyricsLine] = []

        if words.isEmpty {
            // Line-synced TTML: a <p> with a stamp and bare text, no spans.
            let text = p.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let begin = time(p.attributes["begin"]), !text.isEmpty else { return [] }
            // The paragraph's own end is the only thing that says when the
            // singing stops, so carry it — a break can't be found without it.
            let end = time(p.attributes["end"]).flatMap { $0 > begin ? $0 : nil }
            result.append(LyricsLine(timeMs: begin, text: text, sungUntilMs: end))
        } else {
            // Prefer the paragraph's own stamp: it sits a hair before the
            // first syllable on lines that open with a soft consonant, and
            // that lead-in is when the line should appear.
            let begin = time(p.attributes["begin"]) ?? words[0].startMs
            result.append(LyricsLine(
                timeMs: min(begin, words[0].startMs),
                text: words.map { $0.text }.joined(separator: " "),
                words: words
            ))
        }

        let backingWords = mergeIntoWords(backingPieces)
        if !backingWords.isEmpty {
            result.append(LyricsLine(
                timeMs: backingWords[0].startMs,
                text: "(" + backingWords.map { $0.text }.joined(separator: " ") + ")",
                words: backingWords
            ))
        }
        return result
    }

    /// Flattens a paragraph into timed spans and the whitespace between them.
    /// Nested spans recurse to their leaves, so only the innermost timings —
    /// the ones actually per-syllable — survive. Spans marked [backgroundRole]
    /// and everything under them go to [backing] instead.
    private static func collect(_ node: TtmlNode, into sink: inout [Piece], backing: inout [Piece]) {
        for child in node.children {
            switch child {
            case .element(let el):
                let role = el.attributes["ttm:role"] ?? el.attributes["role"] ?? ""
                if skippedRoles.contains(role) { continue }
                if role == backgroundRole {
                    collect(el, into: &backing, backing: &backing)
                    continue
                }
                let begin = time(el.attributes["begin"])
                let end = time(el.attributes["end"])
                if let b = begin, let e = end, !hasTimedChild(el) {
                    sink.append(.timed(text: el.textContent, start: b, end: e))
                } else {
                    collect(el, into: &sink, backing: &backing)
                }
            case .text(let t):
                if !t.isEmpty { sink.append(.text(t)) }
            }
        }
    }

    private static func hasTimedChild(_ el: TtmlNode) -> Bool {
        for child in el.children {
            if case .element(let c) = child {
                if !(c.attributes["begin"] ?? "").isEmpty { return true }
                if hasTimedChild(c) { return true }
            }
        }
        return false
    }

    /// Glues syllables back into words. A word ends at the first whitespace
    /// after it — whether that whitespace is a text node between two spans or
    /// part of a span's own text — and its span runs from the first syllable's
    /// start to the last one's end.
    private static func mergeIntoWords(_ pieces: [Piece]) -> [LyricWord] {
        var words: [LyricWord] = []
        var current = ""
        var syllables: [LyricSyllable] = []
        var start: Int64 = 0
        var end: Int64 = 0
        // Untimed text is punctuation hanging off a span, or a line that was
        // never word-timed at all. Either way it can't carry a word of its
        // own — a word needs a span to get its timing from.
        var timed = false

        func flush() {
            let text = current.trimmingCharacters(in: .whitespaces)
            current = ""
            if !text.isEmpty && timed {
                words.append(LyricWord(startMs: start, endMs: end, text: text,
                                       syllables: LyricSyllable.normalized(syllables, length: text.count)))
            }
            syllables = []
            timed = false
        }

        for piece in pieces {
            switch piece {
            case .text(let t):
                if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    flush()
                } else if timed {
                    // Trailing punctuation belongs to the word it follows.
                    current.append(t)
                }
            case .timed(let t, let s, let e):
                if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                // Leading whitespace closes off whatever came before it.
                if t.first?.isWhitespace ?? false { flush() }
                if current.isEmpty { start = s }
                let from = current.count
                current.append(t.trimmingCharacters(in: .whitespaces))
                syllables.append(LyricSyllable(startMs: s, endMs: e, startChar: from, endChar: current.count))
                end = e
                timed = true
                if t.last?.isWhitespace ?? false { flush() }
            }
        }
        flush()
        return words
    }

    /// TTML clock values: `27.395`, `1:05.20`, `1:02:03.4`, or a plain number
    /// with an `s`/`ms` unit. Returned in milliseconds.
    static func time(_ value: String?) -> Int64? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.hasSuffix("ms") { return Int64((Double(raw.dropLast(2)) ?? 0).rounded()) }
        let stripped = raw.hasSuffix("s") ? String(raw.dropLast()) : raw
        let parts = stripped.split(separator: ":")
        let seconds: Double?
        switch parts.count {
        case 1:
            seconds = Double(parts[0])
        case 2:
            seconds = Double(parts[0]).flatMap { m in Double(parts[1]).map { m * 60 + $0 } }
        case 3:
            seconds = Double(parts[0]).flatMap { h in
                Double(parts[1]).flatMap { m in Double(parts[2]).map { h * 3600 + m * 60 + $0 } }
            }
        default:
            seconds = nil
        }
        guard let s = seconds else { return nil }
        return Int64((s * 1000).rounded())
    }

    /// Marks the instrumental stretches with blank lines. A break is only
    /// drawn where the line before it says when its singing stopped.
    private static func withInstrumentalGaps(_ lines: [LyricsLine]) -> [LyricsLine] {
        guard !lines.isEmpty else { return lines }
        var out: [LyricsLine] = []
        // Nothing stands for the intro, so give the run-up its own break.
        if lines[0].timeMs >= lyricsMinGapMs { out.append(LyricsLine(timeMs: 0, text: "")) }
        for (index, line) in lines.enumerated() {
            out.append(line)
            guard let next = lines[safe: index + 1], line.hasKnownEnd else { continue }
            let silence = next.timeMs - line.endMs
            // A marker sharing its line's stamp could never be reached, so it
            // is only drawn when it sits strictly after the line ends.
            if silence >= lyricsMinGapMs && line.endMs > line.timeMs {
                out.append(LyricsLine(timeMs: line.endMs, text: ""))
            }
        }
        return out
    }

    private enum Piece {
        case text(String)
        case timed(text: String, start: Int64, end: Int64)
    }
}

// MARK: - Minimal DOM for the parser above

private final class TtmlNode {
    let name: String
    var attributes: [String: String]
    var children: [TtmlChild] = []

    init(name: String, attributes: [String: String]) {
        self.name = name.contains(":") ? String(name.split(separator: ":").last!) : name
        var attrs = attributes
        // Address attributes by qualified or local name alike.
        for (k, v) in attributes where k.contains(":") {
            attrs[String(k.split(separator: ":").last!)] = v
        }
        self.attributes = attrs
    }

    var textContent: String {
        children.map { child -> String in
            switch child {
            case .element(let el): return el.textContent
            case .text(let t): return t
            }
        }.joined()
    }

    func descendants(named: String) -> [TtmlNode] {
        var found: [TtmlNode] = []
        for child in children {
            if case .element(let el) = child {
                if el.name == named { found.append(el) }
                found.append(contentsOf: el.descendants(named: named))
            }
        }
        return found
    }
}

private enum TtmlChild {
    case element(TtmlNode)
    case text(String)
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var root: TtmlNode?
    private var stack: [TtmlNode] = []

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let node = TtmlNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(.element(node))
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.children.append(.text(string))
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}
