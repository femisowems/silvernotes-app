import XCTest
import AppKit
@testable import SilverNotes

/// MarkdownEngine render invariants. The engine's core promise is
/// that rendering is attribute-only: the rendered string is always
/// the exact source string, so source ranges (tasks, highlights)
/// line up 1:1 with what the editor shows and saving is
/// byte-identical to what was typed.
final class MarkdownEngineTests: XCTestCase {

    private func assertLengthInvariant(_ source: String,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        for mode in [NoteMode.standard, .plain, .code] {
            for showMarkup in [false, true] {
                let result = MarkdownEngine.render(source: source, mode: mode, showMarkup: showMarkup)
                XCTAssertEqual(result.attributed.length, (source as NSString).length,
                               "rendered length must equal source length (mode \(mode), showMarkup \(showMarkup))",
                               file: file, line: line)
                XCTAssertEqual(result.attributed.string, source,
                               "rendering must never rewrite the source text",
                               file: file, line: line)
            }
        }
    }

    func testRenderLengthInvariant() {
        let inputs = [
            "",
            "plain text, no marks",
            "# A heading",
            "Some **bold** and *italic* words",
            "Type ::around a phrase:: to highlight it",
            "An ==underlined== phrase",
            "- [ ] an open task\n- [x] a done task",
            "::highlight at the very start",
            "highlight at the very end ::",
            "**bold at start** and ::end highlight::",
            "café ☕ notes",
        ]
        for input in inputs {
            assertLengthInvariant(input)
        }
    }

    /// `::…::` sets no background attribute — the engine collects the
    /// content range in `highlightRanges` and the layout manager
    /// draws the marker band. The range must cover the phrase only,
    /// never the markers.
    func testHighlightRangesCoverThePhraseOnly() throws {
        let source = "Type ::around a phrase:: to highlight it"
        let result = MarkdownEngine.render(source: source, mode: .standard, showMarkup: false)

        XCTAssertEqual(result.highlightRanges.count, 1)
        let range = try XCTUnwrap(result.highlightRanges.first)
        XCTAssertEqual((source as NSString).substring(with: range), "around a phrase")
    }

    /// The register's word-boundary rule: `std::vector` and times
    /// like `10:30` must never trigger a highlight.
    func testHighlightRequiresWordBoundaries() {
        let result = MarkdownEngine.render(source: "std::vector is a type",
                                           mode: .standard, showMarkup: false)
        XCTAssertTrue(result.highlightRanges.isEmpty)
    }

    func testTaskMarkersParsed() {
        let source = "- [ ] open task\n- [x] done task\nnot a task"
        let result = MarkdownEngine.render(source: source, mode: .standard, showMarkup: false)

        XCTAssertEqual(result.tasks.count, 2)
        XCTAssertEqual(result.tasks.map(\.isChecked), [false, true])
        // The checkbox character ranges point at the single character
        // between the brackets — the character a toggle would flip.
        let ns = source as NSString
        XCTAssertEqual(ns.substring(with: result.tasks[0].checkboxCharRange), " ")
        XCTAssertEqual(ns.substring(with: result.tasks[1].checkboxCharRange), "x")
    }

    func testUnderlineAttributeApplied() {
        let source = "An ==underlined== phrase"
        let result = MarkdownEngine.render(source: source, mode: .standard, showMarkup: false)

        let contentRange = (source as NSString).range(of: "underlined")
        var found = false
        result.attributed.enumerateAttribute(.underlineStyle, in: contentRange) { value, _, _ in
            if let style = value as? Int, style == NSUnderlineStyle.single.rawValue {
                found = true
            }
        }
        XCTAssertTrue(found, "==…== must apply a single underline over its content")
    }

    // NOTE: there is deliberately no task-toggle test here. Toggling
    // a checklist item is not an engine or store API — it lives in
    // the view layer (NoteTextView.toggleTask flips the checkbox
    // character through the text view's own editing path), so there
    // is nothing at this layer to pin.
}
