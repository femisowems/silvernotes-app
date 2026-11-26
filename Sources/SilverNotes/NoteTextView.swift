import AppKit

/// The in-card editor for SilverNotes v0.1.0. The card IS the editor:
/// this text view holds the note's source text and renders hidden Markdown
/// by applying attributes only (see MarkdownEngine). Characters are never
/// added, removed, or rewritten by rendering, so:
/// - undo/redo only ever contains the user's own edits, never parser work;
/// - mode switches (Standard/Plain/Code) cannot mutate the source;
/// - IME composition is safe: rendering is suspended while marked text is
///   active and re-applied on commit (register §3.8, non-negotiable).
final class NoteTextView: NSTextView {

    var noteID: UUID?
    var mode: NoteMode = .standard {
        didSet {
            applyModeSettings()
            if !suppressesRenderOnPropertyChange { refreshRendering() }
        }
    }
    var showMarkup: Bool = false {
        didSet { if !suppressesRenderOnPropertyChange { refreshRendering() } }
    }

    /// While true, the `mode` / `showMarkup` observers above do NOT trigger
    /// a render. NoteCardView sets this during `configure(with:)` so a
    /// configuration pass renders exactly once (its own explicit call)
    /// instead of once per property assignment plus once more explicitly.
    var suppressesRenderOnPropertyChange = false
    private(set) var taskMarkers: [TaskMarker] = []

    /// Called when the user toggles a task checkbox by clicking it.
    var onTaskToggled: (() -> Void)?

    /// Plain initializer used by NoteCardView; NSTextView does not inherit
    /// a no-argument initializer once init(frame:textContainer:) is overridden.
    init() {
        super.init(frame: .zero, textContainer: nil)
        commonSetup()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        isRichText = false               // source is plain text; styling is ours
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        drawsBackground = false
        defaultParagraphStyle = SNTheme.bodyParagraphStyle
        textContainerInset = NSSize(width: 6, height: 6)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        applyModeSettings()
    }

    private func applyModeSettings() {
        switch mode {
        case .standard, .plain:
            font = SNTheme.bodyFont
            // Typing attributes mirror the render pass (1.5 line height
            // included) so freshly typed text doesn't jump when the
            // debounced re-render lands.
            typingAttributes = [.font: SNTheme.bodyFont,
                                .foregroundColor: SNTheme.primaryText,
                                .paragraphStyle: SNTheme.bodyParagraphStyle]
            isAutomaticQuoteSubstitutionEnabled = false
            isAutomaticDashSubstitutionEnabled = false
            isContinuousSpellCheckingEnabled = true
        case .code:
            font = SNTheme.codeFont
            typingAttributes = [.font: SNTheme.codeFont,
                                .foregroundColor: SNTheme.primaryText]
            isAutomaticQuoteSubstitutionEnabled = false
            isAutomaticDashSubstitutionEnabled = false
            isAutomaticTextReplacementEnabled = false
            isContinuousSpellCheckingEnabled = false
        }
    }

    // MARK: Rendering

    /// Recomputes attributes from the current source. Skipped entirely while
    /// IME marked text is active; `unmarkText` triggers it on commit.
    func refreshRendering() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let result = MarkdownEngine.render(source: string, mode: mode, showMarkup: showMarkup)
        taskMarkers = result.tasks
        let selection = selectedRange()
        storage.beginEditing()
        // Copy attributes run-by-run from the rendered copy onto our storage.
        // Characters are identical, so this is a pure attribute pass.
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes([.font: SNTheme.bodyFont, .foregroundColor: SNTheme.primaryText], range: full)
        result.attributed.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            storage.addAttributes(attrs, range: range)
        }
        storage.endEditing()
        if selection.location + selection.length <= storage.length {
            setSelectedRange(selection)
        }
    }

    override func unmarkText() {
        super.unmarkText()
        refreshRendering()
    }

    // MARK: Task checkbox clicks

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, mode == .standard, let layoutManager = layoutManager, let container = textContainer {
            let point = convert(event.locationInWindow, from: nil)
            var pointInContainer = point
            pointInContainer.x -= textContainerInset.width
            pointInContainer.y -= textContainerInset.height
            var fraction: CGFloat = 0
            let charIndex = layoutManager.characterIndex(for: pointInContainer, in: container,
                                                         fractionOfDistanceBetweenInsertionPoints: &fraction)
            if let marker = taskMarkers.first(where: { NSLocationInRange(charIndex, $0.markerRange) }) {
                toggleTask(marker)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func toggleTask(_ marker: TaskMarker) {
        let replacement = marker.isChecked ? " " : "x"
        // Route through insertText so the toggle is a normal undoable edit.
        if shouldChangeText(in: marker.checkboxCharRange, replacementString: replacement) {
            insertText(replacement, replacementRange: marker.checkboxCharRange)
            didChangeText()
        }
        onTaskToggled?()
    }

    // MARK: Paste

    /// Paste always lands as plain text. Rich HTML from browsers therefore
    /// degrades to its text (links/formatting in the HTML are not converted
    /// in this build — documented in the README deferred list), and pasted
    /// tables arrive as plain-text rows (Decision 7). "Paste and Match
    /// Style" behaves identically, which is correct for a source-based editor.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}

// MARK: - Formatting actions on a selection

/// Implements the Aa popover and the floating selection toolbar by editing
/// the SOURCE (wrapping the selection in markers) — never by applying
/// attributes directly, which the next render pass would erase.
enum EditorActions {

    static func wrapSelection(_ textView: NoteTextView, prefix: String, suffix: String) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        let selected = (textView.string as NSString).substring(with: range)
        let replacement = prefix + selected + suffix
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textView.insertText(replacement, replacementRange: range)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length,
                                              length: (selected as NSString).length))
        }
    }

    static func bold(_ tv: NoteTextView) { wrapSelection(tv, prefix: "**", suffix: "**") }
    static func italic(_ tv: NoteTextView) { wrapSelection(tv, prefix: "*", suffix: "*") }
    static func strikethrough(_ tv: NoteTextView) { wrapSelection(tv, prefix: "~~", suffix: "~~") }
    static func highlight(_ tv: NoteTextView) { wrapSelection(tv, prefix: "::", suffix: "::") }
    static func inlineCode(_ tv: NoteTextView) { wrapSelection(tv, prefix: "`", suffix: "`") }

    static func insertLink(_ tv: NoteTextView) {
        let range = tv.selectedRange()
        let selected = range.length > 0 ? (tv.string as NSString).substring(with: range) : ""
        let alert = NSAlert()
        alert.messageText = "Insert Link"
        alert.informativeText = "Enter the URL for the selected text."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        let label = selected.isEmpty ? url : selected
        let replacement = "[\(label)](\(url))"
        let targetRange = range.length > 0 ? range : NSRange(location: range.location, length: 0)
        if tv.shouldChangeText(in: targetRange, replacementString: replacement) {
            tv.insertText(replacement, replacementRange: targetRange)
            tv.didChangeText()
        }
    }

    static func makeTaskList(_ tv: NoteTextView) {
        // Prefix the line containing the cursor (or selection start) with "- [ ] ".
        let ns = tv.string as NSString
        let cursor = tv.selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: min(cursor, ns.length), length: 0))
        let line = ns.substring(with: lineRange)
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("- [") { return }
        let insertion = NSRange(location: lineRange.location, length: 0)
        if tv.shouldChangeText(in: insertion, replacementString: "- [ ] ") {
            tv.insertText("- [ ] ", replacementRange: insertion)
            tv.didChangeText()
        }
    }
}
