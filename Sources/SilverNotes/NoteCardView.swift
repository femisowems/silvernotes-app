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
    private var renderWorkItem: DispatchWorkItem?

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

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

        foldedLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
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

        buildFooter()
        addSubview(footerView)

        textHeightConstraint = textScroll.heightAnchor.constraint(equalToConstant: 60)
        NSLayoutConstraint.activate([
            textScroll.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textHeightConstraint,

            foldedLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            foldedLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            foldedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            attachmentsStack.topAnchor.constraint(equalTo: textScroll.bottomAnchor, constant: 4),
            attachmentsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            attachmentsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            footerView.topAnchor.constraint(equalTo: attachmentsStack.bottomAnchor, constant: 4),
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 28),
        ])

        footerView.onDoubleClick = { [weak self] in self?.toggleFold() }

        registerForDraggedTypes([.fileURL])
    }

    private func buildFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false

        func footerButton(symbol: String, tip: String, action: Selector) -> NSButton {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                                  target: self, action: action)
            button.bezelStyle = .inline
            button.isBordered = false
            button.toolTip = tip
            button.contentTintColor = SNTheme.secondaryText
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            return button
        }

        let aaButton = footerButton(symbol: "textformat", tip: "Formatting", action: #selector(showFormattingPopover(_:)))
        pinButton = footerButton(symbol: "pin", tip: "Pin note (⌥⌘P)", action: #selector(togglePin))
        let gearButton = footerButton(symbol: "gearshape", tip: "Note options", action: #selector(showGearMenu(_:)))
        let shareButton = footerButton(symbol: "square.and.arrow.up", tip: "Share", action: #selector(shareNote(_:)))
        let trashButton = footerButton(symbol: "trash", tip: "Move to Trash", action: #selector(trashNote))

        timestampLabel.font = NSFont.systemFont(ofSize: 10)
        timestampLabel.textColor = SNTheme.secondaryText
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        progressLabel.textColor = SNTheme.secondaryText
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [aaButton, pinButton, gearButton, progressLabel, timestampLabel, shareButton, trashButton])
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
        noteID = note.id
        folderID = note.folderID
        layer?.backgroundColor = SNTheme.tint(for: note.color).cgColor
        if textView.string != note.body {
            textView.string = note.body
        }
        textView.mode = note.mode
        textView.showMarkup = UserDefaults.standard.bool(forKey: Preferences.showMarkupKey)
        textView.isEditable = !isTrashMode
        pinButton.image = NSImage(systemSymbolName: note.isPinned ? "pin.fill" : "pin", accessibilityDescription: "Pin")
        pinButton.contentTintColor = note.isPinned ? SNTheme.accent : SNTheme.secondaryText
        timestampLabel.stringValue = NoteCardView.timestampFormatter.string(from: note.updatedAt)
        updateProgressLabel(note)
        rebuildAttachments(note)
        applyFold(note.isFolded, note: note)
        textView.refreshRendering()
        updateTextHeight()
    }

    func reloadFromStore() {
        guard let note = store.note(id: noteID) else { return }
        configure(with: note)
    }

    private func updateProgressLabel(_ note: SNNote) {
        let progress = note.taskProgress
        progressLabel.stringValue = progress.total > 0 ? "\(progress.done)/\(progress.total) ✓" : ""
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
        if let note = store.note(id: noteID) {
            timestampLabel.stringValue = NoteCardView.timestampFormatter.string(from: note.updatedAt)
            updateProgressLabel(note)
        }
        // Debounce the (attribute-only) re-render so typing stays fluid.
        renderWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.textView.refreshRendering()
            self?.updateTextHeight()
        }
        renderWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        updateTextHeight()
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
        store.toggleNotePin(id: noteID)
        reloadFromStore()
    }

    @objc private func showGearMenu(_ sender: NSButton) {
        onBecomeActive?(self)
        let menu = NSMenu()
        menu.delegate = self

        let pinItem = NSMenuItem(title: "Pin", action: #selector(togglePin), keyEquivalent: "p")
        pinItem.keyEquivalentModifierMask = [.command, .option]
        if let note = store.note(id: noteID), note.isPinned { pinItem.state = .on }
        menu.addItem(pinItem)

        let foldItem = NSMenuItem(title: "Fold", action: #selector(toggleFoldMenuItem), keyEquivalent: "\r")
        foldItem.keyEquivalentModifierMask = [.command, .option]
        if let note = store.note(id: noteID), note.isFolded { foldItem.state = .on }
        menu.addItem(foldItem)

        menu.addItem(.separator())

        // Color row: a submenu of named colour tokens (7 swatches + Default).
        let colorMenu = NSMenu()
        let defaultItem = NSMenuItem(title: NoteColorToken.none.displayName, action: #selector(pickColor(_:)), keyEquivalent: "")
        defaultItem.representedObject = NoteColorToken.none.rawValue
        if store.note(id: noteID)?.color == NoteColorToken.none { defaultItem.state = .on }
        colorMenu.addItem(defaultItem)
        for token in NoteColorToken.swatches {
            let item = NSMenuItem(title: token.displayName, action: #selector(pickColor(_:)), keyEquivalent: "")
            item.representedObject = token.rawValue
            item.image = swatchImage(for: token)
            if store.note(id: noteID)?.color == token { item.state = .on }
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(.separator())

        // Mode: rendering only — switching never mutates the source (register §3.12).
        let modeMenu = NSMenu()
        for (index, mode) in NoteMode.allCases.enumerated() {
            let item = NSMenuItem(title: mode.displayName, action: #selector(pickMode(_:)), keyEquivalent: "\(index + 1)")
            item.keyEquivalentModifierMask = [.command, .option]
            item.representedObject = mode.rawValue
            if store.note(id: noteID)?.mode == mode { item.state = .on }
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Clear Completed Tasks", action: #selector(clearCompletedTasks), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Export Note as Markdown…", action: #selector(exportNote), keyEquivalent: ""))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func swatchImage(for token: NoteColorToken) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        SNTheme.swatch(for: token).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 12, height: 12)).fill()
        NSColor(calibratedWhite: 0, alpha: 0.15).setStroke()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 12, height: 12)).stroke()
        image.unlockFocus()
        return image
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let token = NoteColorToken(rawValue: raw) else { return }
        store.setNoteColor(id: noteID, color: token)
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
            applyFold(folded, note: updated)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PanelController.shared.endChildInteraction()
        }
    }

    // MARK: Attachments UI

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

    private func attachmentView(for attachment: SNAttachment) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = SNTheme.codeBackground.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let url = store.attachmentURL(attachment)
        if attachment.isImage, let image = NSImage(contentsOf: url) {
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)
            let caption = NSTextField(labelWithString: attachment.fileName)
            caption.font = NSFont.systemFont(ofSize: 10)
            caption.textColor = SNTheme.secondaryText
            caption.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(caption)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                imageView.heightAnchor.constraint(equalToConstant: 110),
                caption.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 3),
                caption.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                caption.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
            ])
        } else {
            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
            icon.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(icon)
            let label = NSTextField(labelWithString: attachment.fileName)
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = SNTheme.primaryText
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 28),
                icon.heightAnchor.constraint(equalToConstant: 28),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                container.heightAnchor.constraint(equalToConstant: 44),
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
