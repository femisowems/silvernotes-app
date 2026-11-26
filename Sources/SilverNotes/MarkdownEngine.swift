import AppKit

/// One clickable task checkbox found during rendering. Ranges are in SOURCE
/// coordinates — rendering is attribute-only, so the displayed string is
/// always identical to the stored source and ranges line up 1:1.
struct TaskMarker {
    /// Range of the whole "- [ ]" marker.
    let markerRange: NSRange
    /// Range of the single character between the brackets (" " or "x").
    let checkboxCharRange: NSRange
    let isChecked: Bool
}

struct MarkdownRenderResult {
    let attributed: NSAttributedString
    let tasks: [TaskMarker]
    /// Source ranges wrapped in ::highlight:: — drawn as a marker band
    /// by the layout manager (audit 2.13), not as a background attribute.
    let highlightRanges: [NSRange]
}

/// Hidden-Markdown renderer for SilverNotes v0.1.0 (Standard mode).
///
/// Design rules (from the Ambiguity Register, all non-negotiable):
/// - Rendering is DERIVED from the source and never rewrites it. This engine
///   only computes attributes over the exact source string; the editor
///   applies those attributes without touching characters, so saving is
///   always byte-identical to what the user typed.
/// - Malformed or unclosed markers render literally — no guessing, no repair.
/// - `::highlight::` requires non-alphanumeric boundaries so real text like
///   `std::vector` or `10:30` can never trigger it.
/// - Tables are NOT part of the subset (Decision 7): pasted table rows are
///   just lines of text and render as plain text.
/// - Supported: headings (#..###), **bold**, *italic* / _italic_,
///   ~~strikethrough~~, ==underline==, ::highlight::, `inline code`,
///   fenced code blocks, [links](url), > quotes, - / 1. lists,
///   - [ ] tasks, --- separators.
enum MarkdownEngine {

    static func render(source: String, mode: NoteMode, showMarkup: Bool) -> MarkdownRenderResult {
        let attr = NSMutableAttributedString(string: source)
        let full = NSRange(location: 0, length: attr.length)

        switch mode {
        case .plain:
            attr.addAttributes([.font: SNTheme.bodyFont, .foregroundColor: SNTheme.bodyText,
                                .paragraphStyle: SNTheme.bodyParagraphStyle], range: full)
            if let titleRange = firstContentLineRange(in: source) {
                attr.addAttributes([.font: SNTheme.titleFont, .foregroundColor: SNTheme.primaryText,
                                    .paragraphStyle: SNTheme.titleParagraphStyle], range: titleRange)
            }
            return MarkdownRenderResult(attributed: attr, tasks: [], highlightRanges: [])
        case .code:
            attr.addAttributes([.font: SNTheme.codeFont, .foregroundColor: SNTheme.primaryText], range: full)
            return MarkdownRenderResult(attributed: attr, tasks: [], highlightRanges: [])
        case .standard:
            break
        }

        // Body copy renders in the package's body colour (audit 2.8);
        // titles and headings keep the primary token.
        attr.addAttributes([.font: SNTheme.bodyFont, .foregroundColor: SNTheme.bodyText,
                            .paragraphStyle: SNTheme.bodyParagraphStyle], range: full)
        var highlights: [NSRange] = []

        // The note's first content line is its title (design package):
        // styled inside this same pass — a heading on that line wins.
        let titleRange = firstContentLineRange(in: source)

        let ns = source as NSString
        var tasks: [TaskMarker] = []
        var inFence = false

        // Walk line by line, tracking each line's range in the source.
        var lineStart = 0
        let totalLength = ns.length
        while lineStart <= totalLength {
            let remaining = NSRange(location: lineStart, length: totalLength - lineStart)
            let newlineRange = ns.range(of: "\n", options: [], range: remaining)
            let lineLength = (newlineRange.location == NSNotFound) ? remaining.length : newlineRange.location - lineStart
            let lineRange = NSRange(location: lineStart, length: lineLength)
            let line = ns.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let leadingSpaces = line.prefix(while: { $0 == " " }).count

            if trimmed.hasPrefix("```") {
                inFence.toggle()
                conceal(attr, range: lineRange, showMarkup: showMarkup)
            } else if inFence {
                attr.addAttributes([.font: SNTheme.codeFont,
                                    .backgroundColor: SNTheme.codeBackground], range: lineRange)
            } else if trimmed.isEmpty {
                // blank line: nothing to do
            } else if isHorizontalRule(trimmed) {
                attr.addAttributes([.foregroundColor: SNTheme.secondaryText], range: lineRange)
            } else if let heading = headingLevel(trimmed) {
                let markerLength = heading + 1 // '#'s plus the space
                let contentStart = lineStart + leadingSpaces + markerLength
                let contentRange = NSRange(location: contentStart,
                                           length: max(0, lineStart + lineLength - contentStart))
                conceal(attr, range: NSRange(location: lineStart + leadingSpaces, length: markerLength),
                        showMarkup: showMarkup)
                if contentRange.length > 0 {
                    attr.addAttributes([.font: SNTheme.headingFont(level: heading),
                                        .foregroundColor: SNTheme.primaryText], range: contentRange)
                    applyInline(attr, ns: ns, range: contentRange, showMarkup: showMarkup, highlights: &highlights)
                }
            } else if let task = parseTaskLine(line: line, lineRange: lineRange, lineStart: lineStart,
                                                leadingSpaces: leadingSpaces) {
                tasks.append(task.marker)
                styleTaskLine(attr, task: task, showMarkup: showMarkup)
                let contentRange = NSRange(location: task.contentStart,
                                           length: max(0, lineStart + lineLength - task.contentStart))
                if contentRange.length > 0 {
                    if task.marker.isChecked {
                        // Done tasks read tertiary + struck through (4.20).
                        attr.addAttributes([.foregroundColor: SNTheme.tertiaryText,
                                            .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                                           range: contentRange)
                    }
                    applyInline(attr, ns: ns, range: contentRange, showMarkup: showMarkup, highlights: &highlights)
                }
            } else if trimmed.hasPrefix(">") {
                let markerRange = NSRange(location: lineStart + leadingSpaces, length: 1)
                conceal(attr, range: markerRange, showMarkup: showMarkup)
                attr.addAttributes([.foregroundColor: SNTheme.secondaryText,
                                    .font: italicFont()], range: lineRange)
                applyInline(attr, ns: ns, range: lineRange, showMarkup: showMarkup, highlights: &highlights)
            } else if isListLine(trimmed) {
                // Keep the bullet/number visible; inline-format the rest.
                if titleRange?.location == lineStart {
                    attr.addAttributes([.font: SNTheme.titleFont, .foregroundColor: SNTheme.primaryText,
                                        .paragraphStyle: SNTheme.titleParagraphStyle], range: lineRange)
                }
                applyInline(attr, ns: ns, range: lineRange, showMarkup: showMarkup, highlights: &highlights)
            } else {
                if titleRange?.location == lineStart {
                    attr.addAttributes([.font: SNTheme.titleFont, .foregroundColor: SNTheme.primaryText,
                                        .paragraphStyle: SNTheme.titleParagraphStyle], range: lineRange)
                }
                applyInline(attr, ns: ns, range: lineRange, showMarkup: showMarkup, highlights: &highlights)
            }

            if newlineRange.location == NSNotFound { break }
            lineStart = newlineRange.location + 1
            if lineStart > totalLength { break }
        }

        return MarkdownRenderResult(attributed: attr, tasks: tasks, highlightRanges: highlights)
    }

    // MARK: Line classification

    private static func headingLevel(_ trimmed: String) -> Int? {
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 3 else { return nil }
        let after = trimmed.dropFirst(level)
        return after.hasPrefix(" ") ? level : nil
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    private static func isListLine(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return true }
        // Numbered list: digits followed by ". "
        var digits = 0
        for ch in trimmed {
            if ch.isNumber { digits += 1 } else { break }
        }
        if digits > 0 {
            let rest = trimmed.dropFirst(digits)
            return rest.hasPrefix(". ")
        }
        return false
    }

    private struct TaskLineInfo {
        let marker: TaskMarker
        let contentStart: Int
    }

    private static func parseTaskLine(line: String, lineRange: NSRange, lineStart: Int, leadingSpaces: Int) -> TaskLineInfo? {
        let nsLine = line as NSString
        let markerText = "- ["
        let start = lineStart + leadingSpaces
        guard nsLine.substring(from: leadingSpaces).hasPrefix(markerText) else { return nil }
        // Layout: "- [" (3) + checkChar (1) + "]" (1) = 5 chars, then optional space + content.
        let checkIndex = leadingSpaces + 3
        guard nsLine.length > checkIndex + 1 else { return nil }
        let checkChar = nsLine.substring(with: NSRange(location: checkIndex, length: 1))
        guard checkChar == " " || checkChar == "x" || checkChar == "X" else { return nil }
        let closeChar = nsLine.substring(with: NSRange(location: checkIndex + 1, length: 1))
        guard closeChar == "]" else { return nil }
        let marker = TaskMarker(
            markerRange: NSRange(location: start, length: 5),
            checkboxCharRange: NSRange(location: start + 3, length: 1),
            isChecked: checkChar == "x" || checkChar == "X"
        )
        var contentStart = start + 5
        if nsLine.length > checkIndex + 2, nsLine.substring(with: NSRange(location: checkIndex + 2, length: 1)) == " " {
            contentStart += 1
        }
        return TaskLineInfo(marker: marker, contentStart: contentStart)
    }

    private static func styleTaskLine(_ attr: NSMutableAttributedString, task: TaskLineInfo, showMarkup: Bool) {
        // With markup shown, the marker stays literal — the old tinted
        // cell treatment, and the layout manager draws no tick.
        if showMarkup {
            let checked = task.marker.isChecked
            attr.addAttributes([
                .font: SNTheme.boldBodyFont,
                .foregroundColor: checked ? NSColor.white : SNTheme.secondaryText,
                .backgroundColor: checked ? SNTheme.taskDone : SNTheme.codeBackground
            ], range: task.marker.checkboxCharRange)
            return
        }
        // Conceal "- [" and "]", and make the checkbox character itself
        // invisible: the layout manager's draw pass paints the package's
        // round tick (15×15 ring / green fill + white check, audit 4.19)
        // over its cell. The kern after the character leaves room for
        // the drawn circle before the task text starts. Source text and
        // offsets are untouched, as everywhere in this engine.
        let dashRange = NSRange(location: task.marker.markerRange.location, length: 3)
        let closeRange = NSRange(location: task.marker.markerRange.location + 4, length: 1)
        conceal(attr, range: dashRange, showMarkup: false)
        conceal(attr, range: closeRange, showMarkup: false)
        attr.addAttributes([
            .font: SNTheme.boldBodyFont,
            .foregroundColor: NSColor.clear,
            .kern: 7.0
        ], range: task.marker.checkboxCharRange)
    }

    // MARK: Inline parsing

    /// Scans `range` for paired inline markers. Only complete pairs are
    /// styled; anything unclosed is left literal. Inline code spans are
    /// consumed first so markers inside them are never interpreted.
    private static func applyInline(_ attr: NSMutableAttributedString, ns: NSString, range: NSRange, showMarkup: Bool, highlights: inout [NSRange]) {
        var i = range.location
        let end = range.location + range.length

        while i < end {
            let ch = ns.character(at: i)

            // Inline code: `...`
            if ch == 0x60 { // backtick
                if let close = findChar(ns, char: 0x60, from: i + 1, to: end) {
                    let inner = NSRange(location: i + 1, length: close - i - 1)
                    if inner.length > 0 {
                        attr.addAttributes([.font: SNTheme.inlineCodeFont,
                                            .backgroundColor: SNTheme.codeBackground], range: inner)
                    }
                    conceal(attr, range: NSRange(location: i, length: 1), showMarkup: showMarkup)
                    conceal(attr, range: NSRange(location: close, length: 1), showMarkup: showMarkup)
                    i = close + 1
                    continue
                }
            }

            // Link: [text](url)
            if ch == 0x5B { // [
                if let parsed = parseLink(ns, at: i, to: end) {
                    // The package draws links in the link colour with
                    // NO underline (rubric §1.5) — colour + the link
                    // attribute only.
                    attr.addAttributes([.foregroundColor: SNTheme.link,
                                        .link: parsed.url], range: parsed.textRange)
                    conceal(attr, range: NSRange(location: i, length: 1), showMarkup: showMarkup)
                    conceal(attr, range: NSRange(location: parsed.textRange.location + parsed.textRange.length,
                                                  length: parsed.totalLength - parsed.textRange.length - 1),
                            showMarkup: showMarkup)
                    i += parsed.totalLength
                    continue
                }
            }

            // Paired markers, longest first.
            if let pair = matchPair(ns, at: i, to: end) {
                stylePair(attr, pair: pair, showMarkup: showMarkup, highlights: &highlights)
                // Recurse into the content so **bold with *italic* inside** works.
                applyInline(attr, ns: ns, range: pair.contentRange, showMarkup: showMarkup, highlights: &highlights)
                i = pair.contentRange.location + pair.contentRange.length + pair.markerLength
                continue
            }

            i += 1
        }
    }

    private struct PairMatch {
        let kind: String // "**", "*", "_", "~~", "==", "::"
        let markerLength: Int
        let contentRange: NSRange
    }

    private static func isAlphanumeric(_ ch: unichar) -> Bool {
        guard let scalar = UnicodeScalar(UInt32(ch)) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func matchPair(_ ns: NSString, at i: Int, to end: Int) -> PairMatch? {
        let two = (i + 1 < end) ? ns.substring(with: NSRange(location: i, length: 2)) : ""
        let candidates: [String] = ["**", "~~", "==", "::"]
        if candidates.contains(two) {
            // `::` needs non-alphanumeric boundaries (register §3.2).
            if two == "::" {
                if i > 0, isAlphanumeric(ns.character(at: i - 1)) { return nil }
            }
            if let close = findPair(ns, marker: two, from: i + 2, to: end) {
                // Empty content (e.g. "****") is not a pair.
                guard close > i + 2 else { return nil }
                if two == "::" {
                    let after = close + 2
                    if after < ns.length, isAlphanumeric(ns.character(at: after)) { return nil }
                }
                return PairMatch(kind: two, markerLength: 2,
                                 contentRange: NSRange(location: i + 2, length: close - (i + 2)))
            }
            return nil
        }
        let one = ns.character(at: i)
        if one == 0x2A || one == 0x5F { // * or _
            // Single * must not be part of ** (handled above) and the opener
            // must not be followed by whitespace.
            if i + 1 < end, ns.character(at: i + 1) != 0x20 {
                if let close = findSingle(ns, char: one, from: i + 1, to: end) {
                    guard close > i + 1 else { return nil }
                    return PairMatch(kind: ns.substring(with: NSRange(location: i, length: 1)), markerLength: 1,
                                     contentRange: NSRange(location: i + 1, length: close - (i + 1)))
                }
            }
        }
        return nil
    }

    private static func stylePair(_ attr: NSMutableAttributedString, pair: PairMatch, showMarkup: Bool, highlights: inout [NSRange]) {
        let openRange = NSRange(location: pair.contentRange.location - pair.markerLength, length: pair.markerLength)
        let closeRange = NSRange(location: pair.contentRange.location + pair.contentRange.length, length: pair.markerLength)
        conceal(attr, range: openRange, showMarkup: showMarkup)
        conceal(attr, range: closeRange, showMarkup: showMarkup)
        guard pair.contentRange.length > 0 else { return }
        switch pair.kind {
        case "**":
            attr.addAttributes([.font: SNTheme.boldBodyFont], range: pair.contentRange)
        case "*", "_":
            attr.addAttributes([.font: italicFont()], range: pair.contentRange)
        case "~~":
            attr.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue], range: pair.contentRange)
        case "==":
            attr.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue], range: pair.contentRange)
        case "::":
            // No background attribute: the range is collected and the
            // layout manager draws the marker band behind the text
            // (audit 2.13).
            highlights.append(pair.contentRange)
        default:
            break
        }
    }

    private struct LinkParts {
        let textRange: NSRange
        let url: String
        let totalLength: Int
    }

    private static func parseLink(_ ns: NSString, at i: Int, to end: Int) -> LinkParts? {
        guard let closeBracket = findChar(ns, char: 0x5D, from: i + 1, to: end) else { return nil } // ]
        guard closeBracket + 1 < end, ns.character(at: closeBracket + 1) == 0x28 else { return nil } // (
        guard let closeParen = findChar(ns, char: 0x29, from: closeBracket + 2, to: end) else { return nil } // )
        let urlRange = NSRange(location: closeBracket + 2, length: closeParen - (closeBracket + 2))
        let url = ns.substring(with: urlRange).trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, url.rangeOfCharacter(from: .whitespaces) == nil else { return nil }
        let textRange = NSRange(location: i + 1, length: closeBracket - (i + 1))
        guard textRange.length > 0 else { return nil }
        return LinkParts(textRange: textRange, url: url, totalLength: closeParen - i + 1)
    }

    // MARK: Helpers

    /// Range of the first line with any non-whitespace content — the
    /// note's title line. Nil for an empty note.
    private static func firstContentLineRange(in source: String) -> NSRange? {
        let ns = source as NSString
        var lineStart = 0
        while lineStart < ns.length {
            let remaining = NSRange(location: lineStart, length: ns.length - lineStart)
            let newlineRange = ns.range(of: "\n", options: [], range: remaining)
            let lineLength = (newlineRange.location == NSNotFound) ? remaining.length : newlineRange.location - lineStart
            let line = ns.substring(with: NSRange(location: lineStart, length: lineLength))
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                return NSRange(location: lineStart, length: lineLength)
            }
            if newlineRange.location == NSNotFound { break }
            lineStart = newlineRange.location + 1
        }
        return nil
    }

    /// Hides a marker range visually (tiny, transparent) without removing the
    /// characters — the source stays intact and editable. When the user has
    /// "show markup" on, markers stay visible in a muted colour instead.
    private static func conceal(_ attr: NSMutableAttributedString, range: NSRange, showMarkup: Bool) {
        guard range.location != NSNotFound, range.length > 0,
              range.location + range.length <= attr.length else { return }
        if showMarkup {
            attr.addAttributes([.foregroundColor: SNTheme.secondaryText,
                                .font: NSFont.systemFont(ofSize: 11)], range: range)
        } else {
            attr.addAttributes([.foregroundColor: NSColor.clear,
                                .font: NSFont.systemFont(ofSize: 0.01)], range: range)
        }
    }

    /// Resolved once: the NSFontManager family/traits query is far too
    /// expensive to run for every italic run of every render.
    private static let italicFontCached: NSFont = {
        let base = SNTheme.bodyFont
        if let italic = NSFontManager.shared.font(withFamily: base.familyName ?? ".AppleSystemUIFont",
                                                  traits: .italicFontMask, weight: 5, size: base.pointSize) {
            return italic
        }
        return base
    }()

    private static func italicFont() -> NSFont { italicFontCached }

    private static func findChar(_ ns: NSString, char: unichar, from: Int, to end: Int) -> Int? {
        var i = from
        while i < end {
            if ns.character(at: i) == char { return i }
            i += 1
        }
        return nil
    }

    private static func findPair(_ ns: NSString, marker: String, from: Int, to end: Int) -> Int? {
        let first = (marker as NSString).character(at: 0)
        let second = (marker as NSString).character(at: 1)
        var i = from
        while i + 1 < end {
            if ns.character(at: i) == first && ns.character(at: i + 1) == second { return i }
            i += 1
        }
        return nil
    }

    private static func findSingle(_ ns: NSString, char: unichar, from: Int, to end: Int) -> Int? {
        var i = from
        while i < end {
            if ns.character(at: i) == char {
                // Closer must not be preceded by whitespace.
                if i > from, ns.character(at: i - 1) == 0x20 { i += 1; continue }
                return i
            }
            i += 1
        }
        return nil
    }
}
