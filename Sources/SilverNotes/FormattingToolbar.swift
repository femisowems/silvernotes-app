import AppKit

/// Floating quick-formatting toolbar shown above a non-empty text selection
/// in a note (Bold / Italic / Underline / Highlight / Strikethrough / Code /
/// Link / Task). One shared instance; it retargets whichever NoteTextView
/// is active.
final class FormattingToolbar: NSPanel {

    static let shared = FormattingToolbar()

    private weak var target: NoteTextView?
    private var buttons: [NSButton] = []

    // NSWindow's init(coder:) is unavailable by design, so no coder init is
    // provided; this panel is only ever created in code. init() here is a
    // new designated initializer, not an override (NSResponder's init() is
    // a convenience initializer).
    private init() {
        // Width grew 252 → 272 in v0.5.0 to fit the Underline button
        // (Nov 26 audit 8.1) without squeezing the others.
        super.init(contentRect: NSRect(x: 0, y: 0, width: 272, height: 32),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 272, height: 32))
        bar.material = .hudWindow
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 9
        bar.layer?.masksToBounds = true

        let stack = NSStackView(frame: NSRect(x: 6, y: 3, width: 260, height: 26))
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY

        // Button order follows the design package's toolbar
        // (B I U S ｜ Highlight Link Checklist — rubric §1.15), with
        // the app's Inline code button kept after Highlight as a
        // deliberate extra the package doesn't list. Buttons are
        // 25 pt tall, min 25 wide, radius 5, near-white text; the
        // Highlight button is the package's yellow chip.
        let specs: [(title: String, tip: String, action: Selector)] = [
            ("B", "Bold", #selector(actBold)),
            ("I", "Italic", #selector(actItalic)),
            ("U", "Underline", #selector(actUnderline)),
            ("S", "Strikethrough", #selector(actStrike)),
            ("H", "Highlight", #selector(actHighlight)),
            ("<>", "Inline code", #selector(actCode)),
            ("Link", "Insert link", #selector(actLink)),
            ("☑", "Make checklist item", #selector(actTask)),
        ]
        for (index, spec) in specs.enumerated() {
            let button = NSButton(title: spec.title, target: self, action: spec.action)
            button.bezelStyle = .inline
            button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            button.toolTip = spec.tip
            button.focusRingType = .none
            button.contentTintColor = NSColor(srgbRed: 0xF2/255, green: 0xF2/255, blue: 0xF5/255, alpha: 1)
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 25).isActive = true
            button.heightAnchor.constraint(equalToConstant: 25).isActive = true
            if spec.tip == "Highlight" {
                // The package's chip: #FFD60A fill, dark text, 3 pt
                // corners, bold letter (rubric §1.15).
                button.font = NSFont.systemFont(ofSize: 12, weight: .bold)
                button.contentTintColor = NSColor(srgbRed: 0x26/255, green: 0x26/255, blue: 0x2B/255, alpha: 1)
                button.layer?.backgroundColor = NSColor(srgbRed: 0xFF/255, green: 0xD6/255, blue: 0x0A/255, alpha: 1).cgColor
                button.layer?.cornerRadius = 3
            }
            buttons.append(button)
            stack.addArrangedSubview(button)
            if index == 3 {
                // The package's 1×16 separator between Strikethrough
                // and Highlight (rubric §1.15).
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.22).cgColor
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 16).isActive = true
            }
        }
        bar.addSubview(stack)
        contentView = bar
    }

    /// Shows the toolbar just above the selection in `textView`, in screen
    /// coordinates. Hides itself if the selection is empty.
    func show(for textView: NoteTextView) {
        let selection = textView.selectedRange()
        guard selection.length > 0, let window = textView.window,
              let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            hide()
            return
        }
        target = textView
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x += textView.textContainerInset.width
        rect.origin.y += textView.textContainerInset.height
        let rectInWindow = textView.convert(rect, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        var origin = NSPoint(x: screenRect.midX - frame.width / 2,
                             y: screenRect.maxY + 6)
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - frame.width - 4)
            if origin.y + frame.height > visible.maxY {
                origin.y = screenRect.minY - frame.height - 6
            }
        }
        // Appear with a 120 ms fade + 2 pt rise (audit 5.4).
        let targetOrigin = origin
        setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y - 2))
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrameOrigin(targetOrigin)
        }
    }

    func hide() {
        if isVisible { orderOut(nil) }
        target = nil
    }

    // MARK: Actions (operate on the source text via EditorActions)

    @objc private func actBold() { if let t = target { EditorActions.bold(t); refresh(t) } }
    @objc private func actItalic() { if let t = target { EditorActions.italic(t); refresh(t) } }
    @objc private func actUnderline() { if let t = target { EditorActions.underline(t); refresh(t) } }
    @objc private func actHighlight() { if let t = target { EditorActions.highlight(t); refresh(t) } }
    @objc private func actStrike() { if let t = target { EditorActions.strikethrough(t); refresh(t) } }
    @objc private func actCode() { if let t = target { EditorActions.inlineCode(t); refresh(t) } }
    @objc private func actLink() { if let t = target { EditorActions.insertLink(t); refresh(t) } }
    @objc private func actTask() { if let t = target { EditorActions.makeTaskList(t); refresh(t) } }

    private func refresh(_ textView: NoteTextView) {
        textView.refreshRendering()
        show(for: textView)
    }
}
