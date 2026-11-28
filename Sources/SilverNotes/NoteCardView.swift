import AppKit
import UniformTypeIdentifiers
import Quartz

extension NSPasteboard.PasteboardType {
    /// Drag-reorder payload: a note's UUID string (audit 6.14).
    static let snNote = NSPasteboard.PasteboardType("com.starterdev.silvernotes.note")
}

/// One note card in the stack. The card is the editor: it hosts a
/// NoteTextView, an attachments area, and the per-note footer
/// (Aa · pin · gear · timestamp · share · trash).
///
/// Decision 6 lives here: double-clicking the FOOTER STRIP folds/unfolds the
/// card; double-clicking the body is standard macOS word selection (handled
/// by NSTextView, untouched).
final class NoteCardView: NSView, NSTextViewDelegate, NSDraggingSource {

    private(set) var noteID: UUID
    private var folderID: UUID
    private let store = NoteStore.shared

    /// In Trash mode cards are read-only with Restore / Delete Forever actions.
    var isTrashMode: Bool = false {
        didSet { applyTrashMode() }
    }

    /// The content controller tracks the most recently edited card so panel
    /// keyboard shortcuts (⌥⌘P, ⌥⌘⏎, ⌥⌘1/2/3) act on it.
    var onBecomeActive: ((NoteCardView) -> Void)?

    /// Press-hold-drag on the footer strip starts a reorder drag
    /// (audit 6.14); the content controller runs the session's drop side.
    var onReorderDragBegan: ((NoteCardView, NSEvent) -> Void)?

    /// Compact density renders the footer icon-only (audit 7.1): the
    /// timestamp is hidden.
    var isCompactFooter: Bool = false {
        didSet { timestampLabel.isHidden = isCompactFooter }
    }

    private let textView = NoteTextView()
    private let textScroll = NSScrollView()
    private let foldedLabel = NSTextField(labelWithString: "")
    private let attachmentsStack = NSStackView()
    private let footerView = FooterStripView()
    private let timestampLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let progressBar = ProgressBarView()
    /// Left-bar colour strip (Appearance → colour as a left bar, 2.19).
    private let colorStrip = NSView()
    /// Second shadow layer: CALayer supports one shadow, the package
    /// specifies two (audit 2.29), so the soft outer shadow lives on
    /// this backing layer filled with the card's surface colour.
    private let softShadowLayer = CALayer()
    private var surfaceColor: NSColor = SNTheme.cardBackground
    private var pinButton: NSButton!
    /// Footer elements whose visibility depends on the fold state
    /// (rubric §2 A5): the rule and share/trash hide on a folded card,
    /// the unfold chevron shows only there.
    private var shareButton: NSButton!
    private var trashButton: NSButton!
    private var unfoldButton: NSButton!
    private let footerRule = NSView()
    private var textHeightConstraint: NSLayoutConstraint!
    private var progressHeightConstraint: NSLayoutConstraint!
    private var progressBarHeightConstraint: NSLayoutConstraint!
    private var textTopConstraint: NSLayoutConstraint!
    /// "+ Add item" row (v0.7.2): sits between the progress label and
    /// the footer on notes that contain tasks; its height constraint
    /// collapses it away otherwise, and the footer's top constraint
    /// compensates so a hidden row costs no extra space.
    private let addItemButton = NSButton(title: "+ Add item", target: nil, action: nil)
    private var addItemHeightConstraint: NSLayoutConstraint!
    private var footerTopConstraint: NSLayoutConstraint!
    /// Hover delete for task lines (v0.7.2): a small × floated at the
    /// card's right edge, vertically aligned with the hovered task.
    private let taskDeleteButton = NSButton(title: "×", target: nil, action: nil)
    private var hoveredTaskLineRange: NSRange?
    private var taskTrackingArea: NSTrackingArea?
    private var lastColorStyle: NoteColorStyle?
    private var isEditing = false
    private var renderWorkItem: DispatchWorkItem?
    /// The note this card was last configured with. `configure(with:)`
    /// is a no-op when handed the same note again — most reloads follow
    /// a change to some OTHER note in the folder.
    private var lastConfiguredNote: SNNote?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Footer timestamp in the design package's shape: "Today · 9:12 AM",
    /// "Yesterday · 6:47 PM", and the weekday form "Mon · 2:15 PM" for
    /// anything older (audit 4.10).
    private static func timestampText(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(time)" }
        return "\(weekdayFormatter.string(from: date)) · \(time)"
    }

    init(note: SNNote) {
        self.noteID = note.id
        self.folderID = note.folderID
        super.init(frame: .zero)
        buildSubviews()
        configure(with: note)
    }

    required init?(coder: NSCoder) {
        // Cards are only ever built in code; this exists to satisfy NSCoding.
        self.noteID = UUID()
        self.folderID = UUID()
        super.init(coder: coder)
    }

    // MARK: Build

    private func buildSubviews() {
        wantsLayer = true
        layer?.cornerRadius = 12
        // No card border (audit 2.28): shadow only. The border returns
        // at 2 pt in the accent ring colour while the card is edited.
        layer?.borderWidth = 0
        softShadowLayer.cornerRadius = 12
        layer?.insertSublayer(softShadowLayer, at: 0)
        applyCardSurface()

        // Left-bar colour strip (hidden unless the Appearance colour
        // style is Left bar and the note has a colour).
        colorStrip.wantsLayer = true
        colorStrip.layer?.cornerRadius = 12
        colorStrip.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        colorStrip.translatesAutoresizingMaskIntoConstraints = false
        colorStrip.isHidden = true
        addSubview(colorStrip)

        // Text view inside a non-scrolling scroll view (the card grows with
        // its content; the panel's outer scroll view does the scrolling).
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = false
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.onCommandReturn = { [weak self] in self?.toggleTaskAtCursor() ?? false }
        textView.translatesAutoresizingMaskIntoConstraints = false
        textScroll.documentView = textView
        addSubview(textScroll)

        foldedLabel.font = SNTheme.titleFont
        foldedLabel.textColor = SNTheme.primaryText
        foldedLabel.lineBreakMode = .byTruncatingTail
        foldedLabel.maximumNumberOfLines = 1
        foldedLabel.translatesAutoresizingMaskIntoConstraints = false
        foldedLabel.isHidden = true
        addSubview(foldedLabel)

        // Attachments sit ABOVE the body text (audit 4.27).
        attachmentsStack.orientation = .vertical
        attachmentsStack.spacing = 6
        attachmentsStack.alignment = .leading
        attachmentsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(attachmentsStack)

        // Task progress: the 5 pt bar (audit 4.22) over the "n of m
        // done" label, in the body area above the footer rule. Both
        // collapse to zero height on notes without tasks.
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressBar)
        progressBarHeightConstraint = progressBar.heightAnchor.constraint(equalToConstant: 0)
        progressLabel.font = NSFont.systemFont(ofSize: 10.5)
        progressLabel.textColor = SNTheme.tertiaryText
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressLabel)
        progressHeightConstraint = progressLabel.heightAnchor.constraint(equalToConstant: 0)

        // "+ Add item" (v0.7.2): one click appends a fresh task and
        // focuses it — no hunting for the end of the last task line.
        // Tertiary, borderless, left-aligned with the body text.
        addItemButton.target = self
        addItemButton.action = #selector(addTaskItem)
        addItemButton.bezelStyle = .inline
        addItemButton.isBordered = false
        addItemButton.font = NSFont.systemFont(ofSize: 11)
        addItemButton.contentTintColor = SNTheme.tertiaryText
        addItemButton.alignment = .left
        addItemButton.translatesAutoresizingMaskIntoConstraints = false
        addItemButton.isHidden = true
        addSubview(addItemButton)
        addItemHeightConstraint = addItemButton.heightAnchor.constraint(equalToConstant: 0)

        // Hover × for task lines (v0.7.2): frame-positioned over the
        // text area's right edge; updateTaskDeleteButton() places it.
        taskDeleteButton.target = self
        taskDeleteButton.action = #selector(deleteHoveredTask)
        taskDeleteButton.bezelStyle = .inline
        taskDeleteButton.isBordered = false
        taskDeleteButton.font = NSFont.systemFont(ofSize: 13)
        taskDeleteButton.contentTintColor = SNTheme.tertiaryText
        taskDeleteButton.toolTip = "Delete item"
        taskDeleteButton.isHidden = true
        addSubview(taskDeleteButton)

        buildFooter()
        addSubview(footerView)

        // Hairline rule above the footer, per the design package.
        // Stored (not a local) since v0.6.0: a folded card drops the
        // rule (rubric §2 A5), so applyFold toggles it.
        footerRule.wantsLayer = true
        footerRule.layer?.backgroundColor = SNTheme.hairline.cgColor
        footerRule.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(footerRule)

        textHeightConstraint = textScroll.heightAnchor.constraint(equalToConstant: 60)
        // The footer hangs below the (collapsible) Add-item row;
        // updateAddItemVisibility adjusts this constant so a hidden
        // row leaves the footer's spacing exactly as it was before.
        footerTopConstraint = footerView.topAnchor.constraint(equalTo: addItemButton.bottomAnchor, constant: 0)
        // Card padding per the rendered package (audit 1.6): 11 top /
        // 13 sides / 7 bottom. The text view's own 6 pt inset counts
        // toward the top and sides: 5 + 6 = 11, 7 + 6 = 13.
        textTopConstraint = textScroll.topAnchor.constraint(equalTo: attachmentsStack.bottomAnchor, constant: 0)
        NSLayoutConstraint.activate([
            attachmentsStack.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            attachmentsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            attachmentsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),

            textTopConstraint,
            textScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            textScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            textHeightConstraint,

            foldedLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            foldedLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            foldedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),

            colorStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
            colorStrip.topAnchor.constraint(equalTo: topAnchor),
            colorStrip.bottomAnchor.constraint(equalTo: bottomAnchor),
            colorStrip.widthAnchor.constraint(equalToConstant: 4),

            progressBar.topAnchor.constraint(equalTo: textScroll.bottomAnchor, constant: 7),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            progressBarHeightConstraint,

            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 3),
            progressLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            progressHeightConstraint,

            addItemButton.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 2),
            addItemButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            addItemHeightConstraint,

            footerTopConstraint,
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 36),

            footerRule.topAnchor.constraint(equalTo: footerView.topAnchor),
            footerRule.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            footerRule.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            footerRule.heightAnchor.constraint(equalToConstant: 1),
        ])

        footerView.onDoubleClick = { [weak self] in self?.toggleFold() }
        footerView.onDragInitiated = { [weak self] event in
            guard let self = self else { return }
            self.onReorderDragBegan?(self, event)
        }

        registerForDraggedTypes([.fileURL])
    }

    override func layout() {
        super.layout()
        softShadowLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardSurface()
        // The footer hairline bakes its CGColor the same way the
        // card surface does; re-apply it alongside. The configured
        // note's colour treatment (full-card tint / left-bar strip)
        // is re-applied too — applyColour re-derives surfaceColor
        // from the dynamic tint and ends in applyCardSurface.
        footerRule.layer?.backgroundColor = SNTheme.hairline.cgColor
        if let note = lastConfiguredNote {
            applyColour(note)
        }
    }

    /// Card surface + the package's dual shadow (audit 2.29): light gets
    /// 0 1 3 rgba(20,22,30,.08) on the card layer plus 0 4 14
    /// rgba(20,22,30,.05) on the backing layer; dark gets the single
    /// 0 1 3 rgba(0,0,0,.4). (CSS blur radii are halved into
    /// shadowRadius, the usual Core Animation approximation.)
    private func applyCardSurface() {
        layer?.backgroundColor = surfaceColor.cgColor
        softShadowLayer.backgroundColor = surfaceColor.cgColor
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.4
            layer?.shadowRadius = 1.5
            layer?.shadowOffset = NSSize(width: 0, height: -1)
            softShadowLayer.shadowOpacity = 0
        } else {
            let ink = NSColor(srgbRed: 20/255, green: 22/255, blue: 30/255, alpha: 1)
            layer?.shadowColor = ink.cgColor
            layer?.shadowOpacity = 0.08
            layer?.shadowRadius = 1.5
            layer?.shadowOffset = NSSize(width: 0, height: -1)
            softShadowLayer.shadowColor = ink.cgColor
            softShadowLayer.shadowOpacity = 0.05
            softShadowLayer.shadowRadius = 7
            softShadowLayer.shadowOffset = NSSize(width: 0, height: -4)
        }
    }

    private func buildFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false

        // Footer buttons are 23×23 (audit 4.8) in the footer colour
        // (audit 2.10).
        func footerButton(symbol: String, tip: String, action: Selector) -> NSButton {
            let button = HoverFooterButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                                           target: self, action: action)
            button.bezelStyle = .inline
            button.isBordered = false
            button.toolTip = tip
            button.contentTintColor = SNTheme.footerText
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 23).isActive = true
            button.heightAnchor.constraint(equalToConstant: 23).isActive = true
            return button
        }

        // The "Aa" button is the package's serif letters (Georgia, 700,
        // 11 pt), not the SF Symbol (audit 4.9).
        let aaButton = HoverFooterButton(title: "Aa", target: self, action: #selector(showFormattingPopover(_:)))
        aaButton.bezelStyle = .inline
        aaButton.isBordered = false
        aaButton.toolTip = "Formatting"
        aaButton.font = NSFont(name: "Georgia-Bold", size: 11) ?? NSFont.systemFont(ofSize: 11, weight: .bold)
        aaButton.contentTintColor = SNTheme.footerText
        aaButton.wantsLayer = true
        aaButton.layer?.cornerRadius = 6
        aaButton.translatesAutoresizingMaskIntoConstraints = false
        aaButton.widthAnchor.constraint(equalToConstant: 23).isActive = true
        aaButton.heightAnchor.constraint(equalToConstant: 23).isActive = true

        pinButton = footerButton(symbol: "pin", tip: "Pin note (⌥⌘P)", action: #selector(togglePin))
        let gearButton = footerButton(symbol: "gearshape", tip: "Note options", action: #selector(showGearMenu(_:)))
        shareButton = footerButton(symbol: "square.and.arrow.up", tip: "Share", action: #selector(shareNote(_:)))
        trashButton = footerButton(symbol: "trash", tip: "Move to Trash", action: #selector(trashNote))
        // Folded cards swap share/trash for an unfold chevron
        // (rubric §2 A5); applyFold drives its visibility.
        unfoldButton = footerButton(symbol: "chevron.down", tip: "Unfold", action: #selector(unfoldTapped))
        unfoldButton.isHidden = true

        timestampLabel.font = NSFont.systemFont(ofSize: 10.5)
        timestampLabel.textColor = SNTheme.footerText
        timestampLabel.alignment = .center
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        // Footer order per the design package: Aa · pin · gear ·
        // timestamp · share · trash (the unfold chevron rides at the
        // end, visible only while folded, where share/trash hide).
        let stack = NSStackView(views: [aaButton, pinButton, gearButton, timestampLabel, shareButton, trashButton, unfoldButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Push share/trash to the right by letting the timestamp area expand.
        timestampLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerView.addSubview(stack)
        NSLayoutConstraint.activate([
            // Footer content aligns with the card's 13 pt text inset,
            // and sits 6 pt under the footer rule (1 pt rule + 5 pt
            // padding, rubric §1.7) inside the 36 pt footer block.
            stack.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -13),
            stack.topAnchor.constraint(equalTo: footerView.topAnchor, constant: 6),
        ])
    }

    // MARK: Configure

    func configure(with note: SNNote) {
        let markup = UserDefaults.standard.bool(forKey: Preferences.showMarkupKey)
        let colorStyle = Preferences.colorStyle
        // Fast path: every render-relevant field matches the last
        // configuration, so skip the render, the attachment rebuild, and
        // the layout pass entirely. (updatedAt is deliberately excluded:
        // typing bumps it constantly, and a structural reload passing
        // over the card being edited must not re-render it — only the
        // timestamp label follows it.)
        if let last = lastConfiguredNote,
           last.id == note.id, last.body == note.body, last.mode == note.mode,
           last.color == note.color, last.isPinned == note.isPinned,
           last.isFolded == note.isFolded, last.folderID == note.folderID,
           last.attachments == note.attachments,
           lastColorStyle == colorStyle,
           textView.string == note.body, textView.showMarkup == markup {
            timestampLabel.stringValue = NoteCardView.timestampText(for: note.updatedAt)
            lastConfiguredNote = note
            return
        }
        lastColorStyle = colorStyle
        noteID = note.id
        folderID = note.folderID
        applyColour(note)
        if textView.string != note.body {
            textView.string = note.body
        }
        // Setting mode / showMarkup each fire a render from their didSet
        // observers; suppress those so this configuration renders exactly
        // once — the explicit refreshRendering() below.
        textView.suppressesRenderOnPropertyChange = true
        textView.mode = note.mode
        textView.showMarkup = markup
        textView.suppressesRenderOnPropertyChange = false
        textView.isEditable = !isTrashMode
        pinButton.image = NSImage(systemSymbolName: note.isPinned ? "pin.fill" : "pin", accessibilityDescription: "Pin")
        pinButton.contentTintColor = note.isPinned ? SNTheme.pinnedActive : SNTheme.footerText
        timestampLabel.stringValue = NoteCardView.timestampText(for: note.updatedAt)
        updateProgressLabel(note)
        rebuildAttachments(note)
        applyFold(note.isFolded, note: note)
        textView.refreshRendering()
        updateTextHeight()
        lastConfiguredNote = note
        updateAddItemVisibility(for: note)
    }

    func reloadFromStore() {
        guard let note = store.note(id: noteID) else { return }
        configure(with: note)
    }

    private func updateProgressLabel(_ note: SNNote) {
        let progress = note.taskProgress
        progressLabel.stringValue = progress.total > 0 ? "\(progress.done) of \(progress.total) done" : ""
        progressHeightConstraint?.constant = progress.total > 0 ? 14 : 0
        progressBarHeightConstraint?.constant = progress.total > 0 ? 5 : 0
        progressBar.fraction = progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0
    }

    private func applyFold(_ folded: Bool, note: SNNote) {
        textScroll.isHidden = folded
        attachmentsStack.isHidden = folded
        foldedLabel.isHidden = !folded
        // Folded footer per the package's render (rubric §2 A5): no
        // top rule, and an unfold chevron where share/trash sat.
        footerRule.isHidden = folded
        shareButton.isHidden = folded
        trashButton.isHidden = folded
        unfoldButton.isHidden = !folded
        if folded {
            // Plain first line, no disclosure prefix (audit 4.12).
            foldedLabel.stringValue = note.title
        }
        hideTaskDeleteButton()
        updateAddItemVisibility(for: note)
    }

    /// Applies the note's colour in the Appearance pane's chosen style:
    /// a full card background (the package's default), or a left bar —
    /// a 4 pt strip in the colour on the card's left edge over the
    /// plain card surface (audit 2.19's Settings option).
    private func applyColour(_ note: SNNote) {
        if Preferences.colorStyle == .leftBar, note.color != .none {
            colorStrip.isHidden = false
            colorStrip.layer?.backgroundColor = SNTheme.tint(for: note.color).cgColor
            surfaceColor = isEditing ? SNTheme.cardFocusedBackground : SNTheme.cardBackground
        } else {
            colorStrip.isHidden = true
            surfaceColor = (isEditing && note.color == .none)
                ? SNTheme.cardFocusedBackground
                : SNTheme.tint(for: note.color)
        }
        applyCardSurface()
    }

    private func applyTrashMode() {
        textView.isEditable = !isTrashMode
        if isTrashMode { hideTaskDeleteButton() }
        if let note = lastConfiguredNote { updateAddItemVisibility(for: note) }
    }

    /// The "+ Add item" row shows only where appending a task makes
    /// sense: a Standard-mode note that already contains at least one
    /// task, unfolded, and not in the Trash. Its height collapses to
    /// zero otherwise, with the footer's top constant compensating so
    /// the card's spacing is unchanged.
    private func updateAddItemVisibility(for note: SNNote?) {
        let visible = !isTrashMode
            && note?.isFolded == false
            && note?.mode == .standard
            && (note?.taskProgress.total ?? 0) > 0
        addItemButton.isHidden = !visible
        addItemHeightConstraint?.constant = visible ? 16 : 0
        footerTopConstraint?.constant = visible ? 2 : 0
    }

    /// Appends a fresh empty task at the end of the body and puts the
    /// caret in it, through the text view's own editing path so the
    /// change is undoable and persists like typed text.
    @objc private func addTaskItem() {
        guard !isTrashMode else { return }
        let ns = textView.string as NSString
        let insertion = ns.length == 0 ? "- [ ] " : (textView.string.hasSuffix("\n") ? "- [ ] " : "\n- [ ] ")
        let endRange = NSRange(location: ns.length, length: 0)
        if textView.shouldChangeText(in: endRange, replacementString: insertion) {
            textView.insertText(insertion, replacementRange: endRange)
            textView.didChangeText()
        }
        focusEditor(cursorAt: (textView.string as NSString).length)
    }

    // MARK: Focus appearance

    func textDidBeginEditing(_ notification: Notification) {
        isEditing = true
        applyFocusAppearance()
    }

    func textDidEndEditing(_ notification: Notification) {
        isEditing = false
        applyFocusAppearance()
    }

    /// The card being edited gets the design package's focus treatment:
    /// dark lifts the card a step (#3A3A41 on uncoloured notes); both
    /// appearances draw the 2 pt accent ring (audit 2.6). Unedited
    /// cards have no border at all (audit 2.28).
    private func applyFocusAppearance() {
        guard let note = lastConfiguredNote else { return }
        if isEditing {
            layer?.borderWidth = 2
            layer?.borderColor = SNTheme.accentRing.cgColor
        } else {
            layer?.borderWidth = 0
        }
        applyColour(note)
    }

    // MARK: Text sizing

    /// The card's text area has no scroller of its own — the outer
    /// list scrolls whole cards — so the card's height must always
    /// equal the text's full laid-out height. That height depends on
    /// the width the text was laid out at: when the card's width
    /// changes (panel resize, density or width switch) the text
    /// re-wraps, and a height measured at the old width would clip
    /// lines with no way to scroll to them. Re-measure on every real
    /// width change. Folded cards skip it: their text is hidden and
    /// configure() re-measures when they unfold.
    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        guard newSize.width > 0, newSize.width != oldWidth,
              lastConfiguredNote?.isFolded == false else { return }
        updateTextHeight()
    }

    private func updateTextHeight() {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = ceil(used.height) + textView.textContainerInset.height * 2
        textHeightConstraint.constant = max(28, height)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        onBecomeActive?(self)
        hideTaskDeleteButton()
        store.updateNoteBody(id: noteID, body: textView.string)
        // Everything derived from the text — the (attribute-only)
        // re-render, the height pass, the timestamp, the task progress —
        // is debounced together, so a keystroke does NO layout work at
        // all; the card catches up once typing pauses for 0.25 s.
        renderWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.textView.refreshRendering()
            self.updateTextHeight()
            if let note = self.store.note(id: self.noteID) {
                self.timestampLabel.stringValue = NoteCardView.timestampText(for: note.updatedAt)
                self.updateProgressLabel(note)
                self.updateAddItemVisibility(for: note)
            }
        }
        renderWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if textView.selectedRange().length > 0, !isTrashMode {
            FormattingToolbar.shared.show(for: textView)
        } else {
            FormattingToolbar.shared.hide()
        }
    }

    // MARK: Task line keys (v0.7.2)

    /// The editor's command seam: Enter, Backspace, Tab and
    /// Shift-Tab get checklist behaviour on task lines, computed by
    /// the pure TaskLineEditing helpers and applied through the text
    /// view's own editing path (undoable, persisted like typing).
    /// Anything the helpers decline falls through to the standard
    /// command, untouched.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !isTrashMode, self.textView.mode == .standard,
              self.textView.selectedRange().length == 0 else { return false }
        let source = self.textView.string
        let cursor = self.textView.selectedRange().location

        if commandSelector == #selector(NSTextView.insertNewline(_:)) {
            guard let edit = TaskLineEditing.enterOnTask(source: source, cursor: cursor) else { return false }
            applyTaskLineEdit(edit)
            return true
        }
        if commandSelector == #selector(NSTextView.deleteBackward(_:)) {
            guard let edit = TaskLineEditing.backspaceAtTaskStart(source: source, cursor: cursor) else { return false }
            applyTaskLineEdit(edit)
            return true
        }
        if commandSelector == #selector(NSTextView.insertTab(_:))
            || commandSelector == #selector(NSTextView.insertBacktab(_:)) {
            let lineIndex = TaskLineEditing.lineIndex(at: cursor, in: source)
            let edit: TaskLineEdit?
            if commandSelector == #selector(NSTextView.insertTab(_:)) {
                edit = TaskLineEditing.indentTask(atLine: lineIndex, in: source)
            } else {
                edit = TaskLineEditing.outdentTask(atLine: lineIndex, in: source)
            }
            guard let edit = edit else { return false }
            // The caret keeps its position relative to the line's
            // content: it shifts by the indentation delta, clamped
            // to the line's start.
            let ns = source as NSString
            let lineStart = ns.lineRange(for: NSRange(location: min(cursor, ns.length), length: 0)).location
            let delta = (edit.replacement as NSString).length - edit.range.length
            let newCursor = min(max(cursor + delta, lineStart), (edit.source as NSString).length)
            if self.textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
                self.textView.insertText(edit.replacement, replacementRange: edit.range)
                self.textView.didChangeText()
            }
            self.textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            return true
        }
        return false
    }

    /// Applies one helper edit and lands the caret where the helper
    /// says it belongs in the new source.
    private func applyTaskLineEdit(_ edit: TaskLineEdit) {
        if textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            textView.insertText(edit.replacement, replacementRange: edit.range)
            textView.didChangeText()
        }
        textView.setSelectedRange(NSRange(location: min(edit.cursor, (textView.string as NSString).length), length: 0))
    }

    /// ⌘⏎ (wired from NoteTextView.keyDown): toggles the task on the
    /// caret's line, flipping its checkbox character through the same
    /// editing path a checkbox click uses. False when the caret is
    /// not on a task line, so the key keeps its default meaning.
    private func toggleTaskAtCursor() -> Bool {
        guard !isTrashMode, textView.mode == .standard else { return false }
        let ns = textView.string as NSString
        let cursor = min(textView.selectedRange().location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
        guard let marker = textView.taskMarkers.first(where: {
            NSLocationInRange($0.markerRange.location, lineRange)
        }) else { return false }
        let replacement = marker.isChecked ? " " : "x"
        if textView.shouldChangeText(in: marker.checkboxCharRange, replacementString: replacement) {
            textView.insertText(replacement, replacementRange: marker.checkboxCharRange)
            textView.didChangeText()
        }
        return true
    }

    // MARK: Task hover delete (v0.7.2)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = taskTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        taskTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateTaskDeleteButton(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideTaskDeleteButton()
    }

    /// While this card is being edited, hovering a task line floats
    /// the × at the card's right edge, aligned with that line. The
    /// hit-test mirrors the checkbox click path in NoteTextView:
    /// window point → container coordinates → character index →
    /// the line's task marker.
    private func updateTaskDeleteButton(for event: NSEvent) {
        guard isEditing, !isTrashMode, textView.mode == .standard,
              let note = lastConfiguredNote, !note.isFolded,
              let layoutManager = textView.layoutManager, let container = textView.textContainer
        else { hideTaskDeleteButton(); return }
        let pointInCard = convert(event.locationInWindow, from: nil)
        guard textScroll.frame.contains(pointInCard) else { hideTaskDeleteButton(); return }
        var pointInContainer = textView.convert(event.locationInWindow, from: nil)
        pointInContainer.x -= textView.textContainerInset.width
        pointInContainer.y -= textView.textContainerInset.height
        layoutManager.ensureLayout(for: container)
        var fraction: CGFloat = 0
        let charIndex = layoutManager.characterIndex(for: pointInContainer, in: container,
                                                     fractionOfDistanceBetweenInsertionPoints: &fraction)
        let ns = textView.string as NSString
        guard charIndex <= ns.length else { hideTaskDeleteButton(); return }
        let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
        guard let marker = textView.taskMarkers.first(where: {
            NSLocationInRange($0.markerRange.location, lineRange)
        }) else { hideTaskDeleteButton(); return }

        // The line's fragment rect, in container coordinates like
        // the layout manager's tick drawing; offset by the text
        // inset (the same correction the click path applies in
        // reverse), then converted up into card coordinates.
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: marker.markerRange.location)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let rectInText = NSRect(x: fragment.minX + textView.textContainerInset.width,
                                y: fragment.minY + textView.textContainerInset.height,
                                width: fragment.width, height: fragment.height)
        let rectInCard = textView.convert(rectInText, to: self)
        hoveredTaskLineRange = lineRange
        taskDeleteButton.frame = NSRect(x: bounds.width - 13 - 18,
                                        y: rectInCard.midY - 8,
                                        width: 18, height: 16)
        taskDeleteButton.isHidden = false
    }

    private func hideTaskDeleteButton() {
        taskDeleteButton.isHidden = true
        hoveredTaskLineRange = nil
    }

    /// Removes the hovered task's whole line — including its line
    /// terminator, or the preceding one when it is the final line —
    /// through the text view's editing path.
    @objc private func deleteHoveredTask() {
        guard let lineRange = hoveredTaskLineRange else { return }
        let ns = textView.string as NSString
        var deletion = lineRange
        if deletion.location + deletion.length >= ns.length, deletion.location > 0,
           !textView.string.hasSuffix("\n") {
            deletion = NSRange(location: deletion.location - 1, length: deletion.length + 1)
        }
        hideTaskDeleteButton()
        if textView.shouldChangeText(in: deletion, replacementString: "") {
            textView.insertText("", replacementRange: deletion)
            textView.didChangeText()
        }
        window?.makeFirstResponder(textView)
    }

    /// Focuses the editor, placing the cursor at the end of the text —
    /// or at `cursorAt` (a character offset, clamped to the text) when
    /// the caller knows a better spot: a fresh checklist note wants
    /// the cursor right after the first line's "- [ ] " prefix, ready
    /// to type the first task.
    func focusEditor(cursorAt: Int? = nil) {
        window?.makeFirstResponder(textView)
        let length = (textView.string as NSString).length
        let location = cursorAt.map { min(max($0, 0), length) } ?? length
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    // MARK: Footer actions

    @objc private func showFormattingPopover(_ sender: NSButton) {
        guard !isTrashMode else { return }
        onBecomeActive?(self)
        let popover = NSPopover()
        popover.behavior = .transient
        let controller = NSViewController()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let specs: [(String, Selector)] = [
            ("Bold", #selector(fmtBold)),
            ("Italic", #selector(fmtItalic)),
            ("Underline", #selector(fmtUnderline)),
            ("Highlight", #selector(fmtHighlight)),
            ("Strike", #selector(fmtStrike)),
            ("Code", #selector(fmtCode)),
            ("Link", #selector(fmtLink)),
            ("☑ Task", #selector(fmtTask)),
        ]
        for (title, action) in specs {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.font = NSFont.systemFont(ofSize: 12)
            stack.addArrangedSubview(button)
        }
        controller.view = stack
        popover.contentViewController = controller
        // Width grew 340 → 420 in v0.5.0 to fit the Underline button
        // (Nov 26 audit 8.1) alongside the existing seven.
        popover.contentSize = NSSize(width: 420, height: 40)
        PanelController.shared.beginChildInteraction()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        // The popover is transient; clear the auto-hide suspension when it closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !popover.isShown { PanelController.shared.endChildInteraction() }
        }
    }

    @objc private func fmtBold() { EditorActions.bold(textView); afterFormat() }
    @objc private func fmtItalic() { EditorActions.italic(textView); afterFormat() }
    @objc private func fmtUnderline() { EditorActions.underline(textView); afterFormat() }
    @objc private func fmtHighlight() { EditorActions.highlight(textView); afterFormat() }
    @objc private func fmtStrike() { EditorActions.strikethrough(textView); afterFormat() }
    @objc private func fmtCode() { EditorActions.inlineCode(textView); afterFormat() }
    @objc private func fmtLink() { EditorActions.insertLink(textView); afterFormat() }
    @objc private func fmtTask() { EditorActions.makeTaskList(textView); afterFormat() }

    private func afterFormat() {
        store.updateNoteBody(id: noteID, body: textView.string)
        textView.refreshRendering()
        updateTextHeight()
    }

    @objc private func togglePin() {
        // No reloadFromStore() here: the store change fires
        // onStructuralChange, and the controller's diffed reload
        // reconfigures this card with its new pin state and order.
        // Reloading here too would re-render a card the reload may have
        // just detached, for nothing.
        store.toggleNotePin(id: noteID)
    }

    @objc private func showGearMenu(_ sender: NSButton) {
        onBecomeActive?(self)
        let note = store.note(id: noteID)
        GearMenu.show(relativeTo: sender,
                      isPinned: note?.isPinned ?? false,
                      isFolded: note?.isFolded ?? false,
                      color: note?.color ?? .none,
                      mode: note?.mode ?? .standard,
                      actions: GearMenu.Actions(
                        onPin: { [weak self] in self?.togglePin() },
                        onFold: { [weak self] in self?.toggleFold() },
                        onDuplicate: isTrashMode ? nil : { [weak self] in
                            guard let self = self else { return }
                            // The store change fires onStructuralChange;
                            // the controller's reload shows the copy
                            // below the original.
                            self.store.duplicateNote(id: self.noteID)
                        },
                        onColor: { [weak self] token in
                            guard let self = self else { return }
                            self.store.setNoteColor(id: self.noteID, color: token)
                            self.reloadFromStore()
                        },
                        onMode: { [weak self] mode in
                            guard let self = self else { return }
                            // Mode is rendering only — switching never
                            // mutates the source (register §3.12).
                            self.store.setNoteMode(id: self.noteID, mode: mode)
                            self.reloadFromStore()
                        },
                        onClearCompletedTasks: { [weak self] in self?.clearCompletedTasks() },
                        onExport: { [weak self] in self?.exportNote() }
                      ))
    }

    /// The folded card's unfold chevron (rubric §2 A5) needs an
    /// @objc entry point; the fold itself is the same toggleFold()
    /// the footer double-click runs.
    @objc private func unfoldTapped() { toggleFold() }

    func toggleFold() {
        guard let note = store.note(id: noteID) else { return }
        let folded = !note.isFolded
        store.setNoteFolded(id: noteID, folded: folded)
        if let updated = store.note(id: noteID) {
            // 200 ms ease-in-out, per the design package's motion table.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                applyFold(folded, note: updated)
                layoutSubtreeIfNeeded()
            }
        }
    }

    @objc private func clearCompletedTasks() {
        guard let note = store.note(id: noteID) else { return }
        let kept = note.body.components(separatedBy: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !(t.hasPrefix("- [x]") || t.hasPrefix("- [X]"))
        }
        textView.string = kept.joined(separator: "\n")
        store.updateNoteBody(id: noteID, body: textView.string)
        textView.refreshRendering()
        updateTextHeight()
        reloadProgress()
    }

    private func reloadProgress() {
        if let note = store.note(id: noteID) { updateProgressLabel(note) }
    }

    @objc private func exportNote() {
        guard let note = store.note(id: noteID) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = note.title + ".md"
        panel.allowedContentTypes = [.plainText]
        PanelController.shared.beginChildInteraction()
        panel.begin { [weak self] result in
            PanelController.shared.endChildInteraction()
            guard result == .OK, let url = panel.url else { return }
            try? note.body.write(to: url, atomically: true, encoding: .utf8)
            _ = self
        }
    }

    @objc private func shareNote(_ sender: NSButton) {
        guard let note = store.note(id: noteID) else { return }
        var items: [Any] = [note.body]
        for attachment in note.attachments {
            items.append(store.attachmentURL(attachment))
        }
        let picker = NSSharingServicePicker(items: items)
        PanelController.shared.beginChildInteraction()
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            PanelController.shared.endChildInteraction()
        }
    }

    @objc private func trashNote() {
        if isTrashMode {
            store.deletePermanently(id: noteID)
        } else {
            store.moveToTrash(id: noteID)
        }
    }

    // MARK: Attachments UI

    /// Decoded card images keyed by attachment ID, so attachment rebuilds
    /// never decode the same image twice.
    private static let imageCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    /// The image a card displays for an attachment: the store-written
    /// thumbnail when one exists (attachments added in v0.1.1+), else the
    /// original file — decoded once, then served from the cache.
    private static func cardImage(for attachment: SNAttachment, store: NoteStore) -> NSImage? {
        let key = attachment.id as NSUUID
        if let cached = imageCache.object(forKey: key) { return cached }
        let thumbURL = store.thumbnailURL(for: attachment)
        let url = FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : store.attachmentURL(attachment)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    private func rebuildAttachments(_ note: SNNote) {
        for sub in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        for attachment in note.attachments {
            let view = attachmentView(for: attachment)
            attachmentsStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: attachmentsStack.widthAnchor).isActive = true
        }
        attachmentsStack.isHidden = note.attachments.isEmpty || note.isFolded
        // Text starts 5 pt below the card top when there is no file
        // block (5 + the text view's 6 pt inset = the package's 11);
        // below a file block it gets a small gap instead.
        textTopConstraint?.constant = note.attachments.isEmpty ? -6 : 7
    }

    /// "JPEG image · 3.8 MB · dropped in from Finder" — type from the
    /// extension, size from disk, and the provenance segment recorded
    /// at capture time (audit 4.25). Attachments recorded before
    /// origins existed show no provenance segment — never a fabricated
    /// one.
    private func attachmentMeta(for attachment: SNAttachment, url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let typeName: String
        switch ext {
        case "jpg", "jpeg": typeName = "JPEG image"
        case "png": typeName = "PNG image"
        case "gif": typeName = "GIF image"
        case "heic", "heif": typeName = "HEIC image"
        case "tiff", "tif": typeName = "TIFF image"
        case "pdf": typeName = "PDF document"
        case "txt", "md": typeName = "Text file"
        case "": typeName = "File"
        default: typeName = "\(ext.uppercased()) file"
        }
        var parts = [typeName]
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let origin = attachment.origin, !origin.isEmpty {
            parts.append(origin)
        }
        return parts.joined(separator: " · ")
    }

    /// The package's file card (audits 4.24–4.28): no container — the
    /// thumbnail and text sit directly on the card. Filename 12.5 pt at
    /// weight 700 over the meta line, with the "Open in Quick Look" link
    /// row under the meta. A linked file that has gone missing renders
    /// a graceful missing-file state instead of a dead link.
    private func attachmentView(for attachment: SNAttachment) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let url = store.attachmentURL(attachment)
        let exists = store.attachmentFileExists(attachment)

        let nameLabel = NSTextField(labelWithString: attachment.fileName)
        nameLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        nameLabel.textColor = SNTheme.primaryText
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let metaLabel = NSTextField(labelWithString: exists ? attachmentMeta(for: attachment, url: url)
                                                            : "Original file not found")
        metaLabel.font = NSFont.systemFont(ofSize: 11)
        metaLabel.textColor = SNTheme.tertiaryText
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        let metaStack = NSStackView(views: [nameLabel, metaLabel])
        metaStack.orientation = .vertical
        metaStack.alignment = .leading
        metaStack.spacing = 2
        metaStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(metaStack)

        // "Open in Quick Look" link row under the meta (audit 4.26),
        // aligned with the name/meta column.
        let quickLookButton = NSButton(title: "Open in Quick Look", target: self, action: #selector(openQuickLook(_:)))
        quickLookButton.bezelStyle = .inline
        quickLookButton.isBordered = false
        quickLookButton.font = NSFont.systemFont(ofSize: 11)
        quickLookButton.contentTintColor = SNTheme.link
        quickLookButton.alignment = .left
        quickLookButton.identifier = NSUserInterfaceItemIdentifier(attachment.id.uuidString)
        quickLookButton.translatesAutoresizingMaskIntoConstraints = false
        quickLookButton.isHidden = !exists
        container.addSubview(quickLookButton)

        let leadingAnchor: NSLayoutXAxisAnchor
        if exists, attachment.isImage, let image = NoteCardView.cardImage(for: attachment, store: store) {
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 7
            imageView.layer?.masksToBounds = true
            imageView.layer?.borderWidth = 1
            imageView.layer?.borderColor = SNTheme.fileThumbBorder.cgColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 74),
                imageView.heightAnchor.constraint(equalToConstant: 62),
                metaStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            ])
            leadingAnchor = imageView.trailingAnchor
            NSLayoutConstraint.activate([
                metaStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            ])
        } else {
            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
            icon.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
                icon.widthAnchor.constraint(equalToConstant: 28),
                icon.heightAnchor.constraint(equalToConstant: 28),
                metaStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            ])
            leadingAnchor = icon.trailingAnchor
            NSLayoutConstraint.activate([
                metaStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            ])
        }
        NSLayoutConstraint.activate([
            metaStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            quickLookButton.leadingAnchor.constraint(equalTo: metaStack.leadingAnchor),
            quickLookButton.topAnchor.constraint(equalTo: metaStack.bottomAnchor, constant: 5),
            quickLookButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Clicking the thumbnail/meta opens the file in its default app
        // (unchanged behaviour); the Quick Look row sits below the
        // covered area and keeps its own action.
        if exists {
            let openButton = NSButton(title: "", target: self, action: #selector(openAttachment(_:)))
            openButton.isTransparent = true
            openButton.identifier = NSUserInterfaceItemIdentifier(attachment.id.uuidString)
            openButton.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(openButton)
            NSLayoutConstraint.activate([
                openButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                openButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                openButton.topAnchor.constraint(equalTo: container.topAnchor),
                openButton.bottomAnchor.constraint(equalTo: metaStack.bottomAnchor, constant: 2),
            ])
        }
        return container
    }

    @objc private func openAttachment(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let note = store.note(id: noteID),
              let attachment = note.attachments.first(where: { $0.id.uuidString == raw }) else { return }
        NSWorkspace.shared.open(store.attachmentURL(attachment))
    }

    @objc private func openQuickLook(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let note = store.note(id: noteID),
              let attachment = note.attachments.first(where: { $0.id.uuidString == raw }) else { return }
        QuickLookPresenter.shared.present(url: store.attachmentURL(attachment))
    }

    // MARK: Reorder drag (audit 6.14)

    /// Begins a drag session carrying this note's ID. Called by the
    /// content controller when the footer strip reports a
    /// press-hold-drag; the controller owns the drop side.
    func beginReorderDrag(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(noteID.uuidString, forType: .snNote)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            draggingItem.setDraggingFrame(bounds, contents: image)
        } else {
            draggingItem.setDraggingFrame(bounds, contents: nil)
        }
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    // MARK: Drag & drop (files onto a card: images embed, files link)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isTrashMode else { return [] }
        // Temporary accent ring while a drag hovers (cards otherwise
        // carry no border, audit 2.28).
        layer?.borderColor = SNTheme.accent.cgColor
        layer?.borderWidth = 2
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        restoreDragBorder()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        restoreDragBorder()
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        var added = false
        for url in urls {
            if store.addAttachment(noteID: noteID, from: url, origin: "dropped in from Finder") != nil { added = true }
        }
        if added { reloadFromStore() }
        return added
    }

    private func restoreDragBorder() {
        if isEditing {
            layer?.borderColor = SNTheme.accentRing.cgColor
            layer?.borderWidth = 2
        } else {
            layer?.borderWidth = 0
        }
    }
}

/// The checklist progress bar (audit 4.22): 5 pt, rounded, track
/// rgba(120,120,135,0.2), fill in the task green.
final class ProgressBarView: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5)
        SNTheme.progressTrack.setFill()
        track.fill()
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return }
        let width = max(bounds.height, bounds.width * CGFloat(clamped))
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
                                xRadius: 2.5, yRadius: 2.5)
        SNTheme.taskDone.setFill()
        fill.fill()
    }
}

/// Presents one file in Quick Look (the file card's link row, 4.26).
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()
    private var url: URL?

    func present(url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = 0
        PanelController.shared.beginChildInteraction()
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let url = url else { return nil }
        return url as NSURL
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        PanelController.shared.endChildInteraction()
    }
}

/// A footer icon button with the design package's hover treatment:
/// a soft wash in a 6 pt-radius rounded rect while the pointer is over it.
final class HoverFooterButton: NSButton {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        layer?.backgroundColor = SNTheme.hoverBackground.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// The footer strip: a plain area whose double-click toggles fold
/// (Decision 6). Buttons inside it consume their own clicks first.
/// It is also the drag handle for reordering (audit 6.14): a press
/// held ~150 ms that then moves past ~4 pt starts a reorder drag.
final class FooterStripView: NSView {
    var onDoubleClick: (() -> Void)?
    var onDragInitiated: ((NSEvent) -> Void)?
    private var downTimestamp: TimeInterval = 0
    private var downLocation: NSPoint = .zero
    private var dragStarted = false

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        downTimestamp = event.timestamp
        downLocation = event.locationInWindow
        dragStarted = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if !dragStarted,
           event.timestamp - downTimestamp >= 0.15,
           hypot(event.locationInWindow.x - downLocation.x,
                 event.locationInWindow.y - downLocation.y) > 4 {
            dragStarted = true
            onDragInitiated?(event)
            return
        }
        super.mouseDragged(with: event)
    }
}
