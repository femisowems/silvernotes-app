import AppKit
import UniformTypeIdentifiers

/// One note card in the stack. The card is the editor: it hosts a
/// NoteTextView, an attachments area, and the per-note footer
/// (Aa · pin · gear · timestamp · share · trash).
///
/// Decision 6 lives here: double-clicking the FOOTER STRIP folds/unfolds the
/// card; double-clicking the body is standard macOS word selection (handled
/// by NSTextView, untouched).
final class NoteCardView: NSView, NSTextViewDelegate, NSMenuDelegate {

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

    private let textView = NoteTextView()
    private let textScroll = NSScrollView()
    private let foldedLabel = NSTextField(labelWithString: "")
    private let attachmentsStack = NSStackView()
    private let footerView = FooterStripView()
    private let timestampLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private var pinButton: NSButton!
    private var textHeightConstraint: NSLayoutConstraint!
    private var progressHeightConstraint: NSLayoutConstraint!
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Footer timestamp in the design package's shape: "Today · 9:12 AM",
    /// "Yesterday · 6:47 PM", "Nov 21 · 2:15 PM".
    private static func timestampText(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(time)" }
        return "\(dayFormatter.string(from: date)) · \(time)"
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
        layer?.borderWidth = 1
        layer?.borderColor = SNTheme.cardBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 4
        layer?.shadowOffset = NSSize(width: 0, height: -1)

        // Text view inside a non-scrolling scroll view (the card grows with
        // its content; the panel's outer scroll view does the scrolling).
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = false
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
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

        attachmentsStack.orientation = .vertical
        attachmentsStack.spacing = 6
        attachmentsStack.alignment = .leading
        attachmentsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(attachmentsStack)

        // Task progress sits in the body area, above the footer rule —
        // its row collapses to zero height on notes without tasks.
        progressLabel.font = NSFont.systemFont(ofSize: 10.5)
        progressLabel.textColor = SNTheme.secondaryText
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressLabel)
        progressHeightConstraint = progressLabel.heightAnchor.constraint(equalToConstant: 0)

        buildFooter()
        addSubview(footerView)

        // Hairline rule above the footer, per the design package.
        let footerRule = NSView()
        footerRule.wantsLayer = true
        footerRule.layer?.backgroundColor = SNTheme.hairline.cgColor
        footerRule.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(footerRule)

        textHeightConstraint = textScroll.heightAnchor.constraint(equalToConstant: 60)
        NSLayoutConstraint.activate([
            // 12 pt card padding: 6 here + the text view's own 6 pt inset.
            textScroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            textScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            textScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            textHeightConstraint,

            foldedLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            foldedLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            foldedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            attachmentsStack.topAnchor.constraint(equalTo: textScroll.bottomAnchor, constant: 4),
            attachmentsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            attachmentsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            progressLabel.topAnchor.constraint(equalTo: attachmentsStack.bottomAnchor, constant: 2),
            progressLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            progressHeightConstraint,

            footerView.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 2),
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 28),

            footerRule.topAnchor.constraint(equalTo: footerView.topAnchor),
            footerRule.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            footerRule.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            footerRule.heightAnchor.constraint(equalToConstant: 1),
        ])

        footerView.onDoubleClick = { [weak self] in self?.toggleFold() }

        registerForDraggedTypes([.fileURL])
    }

    private func buildFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false

        func footerButton(symbol: String, tip: String, action: Selector) -> NSButton {
            let button = HoverFooterButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                                           target: self, action: action)
            button.bezelStyle = .inline
            button.isBordered = false
            button.toolTip = tip
            button.contentTintColor = SNTheme.secondaryText
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return button
        }

        let aaButton = footerButton(symbol: "textformat", tip: "Formatting", action: #selector(showFormattingPopover(_:)))
        pinButton = footerButton(symbol: "pin", tip: "Pin note (⌥⌘P)", action: #selector(togglePin))
        let gearButton = footerButton(symbol: "gearshape", tip: "Note options", action: #selector(showGearMenu(_:)))
        let shareButton = footerButton(symbol: "square.and.arrow.up", tip: "Share", action: #selector(shareNote(_:)))
        let trashButton = footerButton(symbol: "trash", tip: "Move to Trash", action: #selector(trashNote))

        timestampLabel.font = NSFont.systemFont(ofSize: 10.5)
        timestampLabel.textColor = SNTheme.secondaryText
        timestampLabel.alignment = .center
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        // Footer order per the design package: Aa · pin · gear ·
        // timestamp · share · trash.
        let stack = NSStackView(views: [aaButton, pinButton, gearButton, timestampLabel, shareButton, trashButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Push share/trash to the right by letting the timestamp area expand.
        timestampLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
        ])
    }

    // MARK: Configure

    func configure(with note: SNNote) {
        let markup = UserDefaults.standard.bool(forKey: Preferences.showMarkupKey)
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
           textView.string == note.body, textView.showMarkup == markup {
            timestampLabel.stringValue = NoteCardView.timestampText(for: note.updatedAt)
            lastConfiguredNote = note
            return
        }
        noteID = note.id
        folderID = note.folderID
        layer?.backgroundColor = SNTheme.tint(for: note.color).cgColor
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
        pinButton.contentTintColor = note.isPinned ? SNTheme.pinnedActive : SNTheme.secondaryText
        timestampLabel.stringValue = NoteCardView.timestampText(for: note.updatedAt)
        updateProgressLabel(note)
        rebuildAttachments(note)
        applyFold(note.isFolded, note: note)
        textView.refreshRendering()
        updateTextHeight()
        lastConfiguredNote = note
    }

    func reloadFromStore() {
        guard let note = store.note(id: noteID) else { return }
        configure(with: note)
    }

    private func updateProgressLabel(_ note: SNNote) {
        let progress = note.taskProgress
        progressLabel.stringValue = progress.total > 0 ? "\(progress.done) of \(progress.total) done" : ""
        progressHeightConstraint?.constant = progress.total > 0 ? 14 : 0
    }

    private func applyFold(_ folded: Bool, note: SNNote) {
        textScroll.isHidden = folded
        attachmentsStack.isHidden = folded
        foldedLabel.isHidden = !folded
        if folded {
            foldedLabel.stringValue = "▸ " + note.title
        }
    }

    private func applyTrashMode() {
        textView.isEditable = !isTrashMode
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
    /// appearances draw the accent-tinted ring.
    private func applyFocusAppearance() {
        guard let note = lastConfiguredNote else { return }
        if isEditing {
            layer?.backgroundColor = (note.color == .none
                ? SNTheme.cardFocusedBackground
                : SNTheme.tint(for: note.color)).cgColor
            layer?.borderColor = SNTheme.accentRing.cgColor
        } else {
            layer?.backgroundColor = SNTheme.tint(for: note.color).cgColor
            layer?.borderColor = SNTheme.cardBorder.cgColor
        }
    }

    // MARK: Text sizing

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

    func focusEditor() {
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
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
        popover.contentSize = NSSize(width: 340, height: 40)
        PanelController.shared.beginChildInteraction()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        // The popover is transient; clear the auto-hide suspension when it closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !popover.isShown { PanelController.shared.endChildInteraction() }
        }
    }

    @objc private func fmtBold() { EditorActions.bold(textView); afterFormat() }
    @objc private func fmtItalic() { EditorActions.italic(textView); afterFormat() }
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

    /// The gear menu currently on screen, if any — a click in its
    /// swatch row dismisses it explicitly (custom-view menu items do
    /// not close the menu on their own).
    private var currentGearMenu: NSMenu?

    @objc private func showGearMenu(_ sender: NSButton) {
        onBecomeActive?(self)
        let menu = NSMenu()
        menu.delegate = self
        currentGearMenu = menu
        let note = store.note(id: noteID)

        let pinItem = NSMenuItem(title: "Pin", action: #selector(togglePin), keyEquivalent: "p")
        pinItem.keyEquivalentModifierMask = [.command, .option]
        pinItem.target = self
        if note?.isPinned == true { pinItem.state = .on }
        menu.addItem(pinItem)

        let foldItem = NSMenuItem(title: "Fold", action: #selector(toggleFoldMenuItem), keyEquivalent: "\r")
        foldItem.keyEquivalentModifierMask = [.command, .option]
        foldItem.target = self
        if note?.isFolded == true { foldItem.state = .on }
        menu.addItem(foldItem)

        menu.addItem(.separator())

        // Colour: a flat row of circular swatches (Default + the 7
        // tokens), the active one ringed — the design package's menu.
        menu.addItem(sectionLabelItem("Colour"))
        let swatchItem = NSMenuItem()
        swatchItem.view = swatchRowView(active: note?.color ?? .none)
        menu.addItem(swatchItem)

        menu.addItem(.separator())

        // Mode: rendering only — switching never mutates the source (register §3.12).
        menu.addItem(sectionLabelItem("Mode"))
        let modeTitles: [NoteMode: String] = [.standard: "Standard", .plain: "Plain Text", .code: "Code"]
        for (index, mode) in NoteMode.allCases.enumerated() {
            let item = NSMenuItem(title: modeTitles[mode] ?? mode.displayName, action: #selector(pickMode(_:)), keyEquivalent: "\(index + 1)")
            item.keyEquivalentModifierMask = [.command, .option]
            item.representedObject = mode.rawValue
            item.target = self
            if note?.mode == mode { item.state = .on }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Completed Tasks", action: #selector(clearCompletedTasks), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        let exportItem = NSMenuItem(title: "Export Note as Markdown…", action: #selector(exportNote), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// A disabled, small-caps section label inside the gear menu.
    private func sectionLabelItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// The gear menu's colour row: one circular button per token
    /// (Default first), the note's current colour ringed in the accent.
    private func swatchRowView(active: NoteColorToken) -> NSView {
        let tokens: [NoteColorToken] = [.none] + NoteColorToken.swatches
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 212, height: 30))
        var x: CGFloat = 10
        for (index, token) in tokens.enumerated() {
            let ring = NSView(frame: NSRect(x: x, y: 3, width: 24, height: 24))
            ring.wantsLayer = true
            ring.layer?.cornerRadius = 12
            if token == active {
                ring.layer?.borderWidth = 2
                ring.layer?.borderColor = SNTheme.accent.cgColor
            }
            let button = NSButton(frame: NSRect(x: 2, y: 2, width: 20, height: 20))
            button.title = ""
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.layer?.backgroundColor = SNTheme.swatch(for: token).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = SNTheme.cardBorder.cgColor
            button.tag = index
            button.target = self
            button.action = #selector(pickColorFromSwatch(_:))
            button.toolTip = token.displayName
            ring.addSubview(button)
            row.addSubview(ring)
            x += 24
        }
        return row
    }

    @objc private func pickColorFromSwatch(_ sender: NSButton) {
        let tokens: [NoteColorToken] = [.none] + NoteColorToken.swatches
        guard tokens.indices.contains(sender.tag) else { return }
        store.setNoteColor(id: noteID, color: tokens[sender.tag])
        currentGearMenu?.cancelTracking()
        reloadFromStore()
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = NoteMode(rawValue: raw) else { return }
        store.setNoteMode(id: noteID, mode: mode)
        reloadFromStore()
    }

    @objc private func toggleFoldMenuItem() { toggleFold() }

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

    // MARK: NSMenuDelegate (auto-hide allow-list)

    func menuWillOpen(_ menu: NSMenu) {
        PanelController.shared.beginChildInteraction()
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === currentGearMenu { currentGearMenu = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PanelController.shared.endChildInteraction()
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
            attachmentsStack.addArrangedSubview(attachmentView(for: attachment))
        }
        attachmentsStack.isHidden = note.attachments.isEmpty || note.isFolded
    }

    /// "JPEG image · 3.8 MB" — type from the extension, size from disk.
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
        return parts.joined(separator: " · ")
    }

    private func attachmentView(for attachment: SNAttachment) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = SNTheme.codeBackground.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let url = store.attachmentURL(attachment)

        // Filename (semibold) over a secondary meta line, shared by both
        // attachment shapes, per the design package's file card.
        let nameLabel = NSTextField(labelWithString: attachment.fileName)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = SNTheme.primaryText
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        let metaLabel = NSTextField(labelWithString: attachmentMeta(for: attachment, url: url))
        metaLabel.font = NSFont.systemFont(ofSize: 11)
        metaLabel.textColor = SNTheme.secondaryText
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        let metaStack = NSStackView(views: [nameLabel, metaLabel])
        metaStack.orientation = .vertical
        metaStack.alignment = .leading
        metaStack.spacing = 2
        metaStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(metaStack)

        if attachment.isImage, let image = NoteCardView.cardImage(for: attachment, store: store) {
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 7
            imageView.layer?.masksToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
                imageView.widthAnchor.constraint(equalToConstant: 74),
                imageView.heightAnchor.constraint(equalToConstant: 62),
                metaStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
                metaStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                metaStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        } else {
            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
            icon.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 28),
                icon.heightAnchor.constraint(equalToConstant: 28),
                metaStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                metaStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                metaStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                container.heightAnchor.constraint(equalToConstant: 48),
            ])
        }

        let openButton = NSButton(title: "", target: self, action: #selector(openAttachment(_:)))
        openButton.isTransparent = true
        openButton.identifier = NSUserInterfaceItemIdentifier(attachment.id.uuidString)
        openButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(openButton)
        NSLayoutConstraint.activate([
            openButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            openButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            openButton.topAnchor.constraint(equalTo: container.topAnchor),
            openButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.widthAnchor.constraint(equalToConstant: 280).isActive = true
        return container
    }

    @objc private func openAttachment(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let note = store.note(id: noteID),
              let attachment = note.attachments.first(where: { $0.id.uuidString == raw }) else { return }
        NSWorkspace.shared.open(store.attachmentURL(attachment))
    }

    // MARK: Drag & drop (files onto a card embed a copy)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isTrashMode else { return [] }
        layer?.borderColor = SNTheme.accent.cgColor
        layer?.borderWidth = 2
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = SNTheme.cardBorder.cgColor
        layer?.borderWidth = 1
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = SNTheme.cardBorder.cgColor
        layer?.borderWidth = 1
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        var added = false
        for url in urls {
            if store.addAttachment(noteID: noteID, from: url) != nil { added = true }
        }
        if added { reloadFromStore() }
        return added
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
final class FooterStripView: NSView {
    var onDoubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }
}
