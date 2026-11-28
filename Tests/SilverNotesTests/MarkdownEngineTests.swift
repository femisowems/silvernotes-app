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

    // MARK: Task line editing (v0.7.2)

    /// The pure TaskLineEditing helpers carry the checklist
    /// keystroke behaviour (Enter / Backspace / Tab / toggle), so
    /// they are pinned here directly on source strings. The view
    /// layer still applies the results through the text view's own
    /// editing path (undoable, persisted like typing) — what these
    /// tests pin is the edit computation itself.

    func testEnterContinuesTaskAtLineEnd() throws {
        let edit = try XCTUnwrap(TaskLineEditing.enterOnTask(source: "- [ ] Buy milk", cursor: 14))
        XCTAssertEqual(edit.source, "- [ ] Buy milk\n- [ ] ")
        XCTAssertEqual(edit.cursor, 21)
        XCTAssertEqual(edit.range, NSRange(location: 14, length: 0))
        XCTAssertEqual(edit.replacement, "\n- [ ] ")
    }

    func testEnterSplitsTaskAtCursor() throws {
        let edit = try XCTUnwrap(TaskLineEditing.enterOnTask(source: "- [ ] Buy milk", cursor: 10))
        XCTAssertEqual(edit.source, "- [ ] Buy \n- [ ] milk")
        XCTAssertEqual(edit.cursor, 17)
    }

    func testEnterKeepsTaskIndentation() throws {
        let edit = try XCTUnwrap(TaskLineEditing.enterOnTask(source: "  - [ ] Task", cursor: 12))
        XCTAssertEqual(edit.source, "  - [ ] Task\n  - [ ] ")
        XCTAssertEqual(edit.cursor, 21)
    }

    func testEnterOnEmptyTaskEndsTheList() throws {
        let solo = try XCTUnwrap(TaskLineEditing.enterOnTask(source: "- [ ] ", cursor: 6))
        XCTAssertEqual(solo.source, "")
        XCTAssertEqual(solo.cursor, 0)

        // The middle task of three: its line becomes a plain empty
        // line, the surrounding tasks are untouched.
        let middle = try XCTUnwrap(TaskLineEditing.enterOnTask(
            source: "- [ ] a\n- [ ] \n- [ ] b", cursor: 14))
        XCTAssertEqual(middle.source, "- [ ] a\n\n- [ ] b")
        XCTAssertEqual(middle.cursor, 8)
    }

    func testEnterDeclinesNonTaskLinesAndMarkerInterior() {
        XCTAssertNil(TaskLineEditing.enterOnTask(source: "hello", cursor: 5))
        XCTAssertNil(TaskLineEditing.enterOnTask(source: "- [ ] Buy", cursor: 2),
                     "a caret inside the marker keeps the plain newline")
        XCTAssertNil(TaskLineEditing.enterOnTask(source: "- a bullet", cursor: 10))
    }

    func testBackspaceAtTaskStartStripsMarker() throws {
        let edit = try XCTUnwrap(TaskLineEditing.backspaceAtTaskStart(source: "- [ ] Buy milk", cursor: 6))
        XCTAssertEqual(edit.source, "Buy milk")
        XCTAssertEqual(edit.cursor, 0)

        let indented = try XCTUnwrap(TaskLineEditing.backspaceAtTaskStart(source: "  - [ ] Buy", cursor: 8))
        XCTAssertEqual(indented.source, "Buy")
        XCTAssertEqual(indented.cursor, 0)
    }

    func testBackspaceDeclinesAwayFromContentStart() {
        XCTAssertNil(TaskLineEditing.backspaceAtTaskStart(source: "- [ ] Buy milk", cursor: 7))
        XCTAssertNil(TaskLineEditing.backspaceAtTaskStart(source: "- [ ] Buy milk", cursor: 0))
        XCTAssertNil(TaskLineEditing.backspaceAtTaskStart(source: "plain", cursor: 0))
    }

    func testToggleTaskFlipsCheckbox() throws {
        let source = "- [ ] a\n- [x] b"
        XCTAssertEqual(TaskLineEditing.toggleTask(atLine: 0, in: source)?.source, "- [x] a\n- [x] b")
        XCTAssertEqual(TaskLineEditing.toggleTask(atLine: 1, in: source)?.source, "- [x] a\n- [ ] b")
        XCTAssertNil(TaskLineEditing.toggleTask(atLine: 0, in: "plain line"))
        XCTAssertNil(TaskLineEditing.toggleTask(atLine: 5, in: source))
    }

    func testIndentAndOutdentTask() throws {
        let indented = try XCTUnwrap(TaskLineEditing.indentTask(atLine: 0, in: "- [ ] a"))
        XCTAssertEqual(indented.source, "  - [ ] a")
        // The renderer's parser tolerates leading spaces: the
        // indented line still parses as exactly one task.
        let rendered = MarkdownEngine.render(source: indented.source, mode: .standard, showMarkup: false)
        XCTAssertEqual(rendered.tasks.count, 1)
        XCTAssertEqual(rendered.tasks.first?.isChecked, false)

        let outdented = try XCTUnwrap(TaskLineEditing.outdentTask(atLine: 0, in: "  - [ ] a"))
        XCTAssertEqual(outdented.source, "- [ ] a")
        XCTAssertNil(TaskLineEditing.outdentTask(atLine: 0, in: "- [ ] a"),
                     "a flush-left task cannot outdent")
        XCTAssertNil(TaskLineEditing.indentTask(atLine: 0, in: "plain line"))
        XCTAssertNil(TaskLineEditing.outdentTask(atLine: 0, in: "  plain line"))
    }
}
