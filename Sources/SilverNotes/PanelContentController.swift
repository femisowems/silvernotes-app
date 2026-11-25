import AppKit

/// Root content of the edge panel for SilverNotes v0.1.0.
/// Three presentations over one scrollable column:
/// - Folder home: flat folder rows (pinned first, counts, colour dots),
///   a Trash row, and a settings button.
/// - Notes: header (back, title, search, +) over a vertical stack of cards.
/// - Search results / Trash: the same card stack, different source.
final class PanelContentController: NSViewController {

    enum Presentation {
        case folders
        case notes(folderID: UUID)
        case trash
        case search(query: String)
    }

    private(set) var presentation: Presentation = .folders
    weak var activeCard: NoteCardView?

    private let store = NoteStore.shared
    private let headerView = NSView()
    private let backButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "Folders")
    private let searchField = NSSearchField()
    private let newButton = NSButton()
    private let pinPanelButton = NSButton()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let bottomLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        // Rounded corner on the screen-away side; refreshed by PanelController
        // whenever the dock side changes.
        root.layer?.cornerRadius = 14
        root.layer?.maskedCorners = [.layerMinXMinYCorner]
        root.layer?.backgroundColor = SNTheme.panelBackground.cgColor
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.onStructuralChange = { [weak self] in self?.reload() }
        reload()
    }

    // MARK: Layout

    private func buildLayout() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.bezelStyle = .inline
        backButton.isBordered = false
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = SNTheme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        searchField.placeholderString = "Search all notes"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.isHidden = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(searchField)

        let searchButton = NSButton(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") ?? NSImage(),
                                    target: self, action: #selector(toggleSearchField))
        searchButton.bezelStyle = .inline
        searchButton.isBordered = false
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(searchButton)

        pinPanelButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Keep panel open")
        pinPanelButton.bezelStyle = .inline
        pinPanelButton.isBordered = false
        pinPanelButton.target = self
        pinPanelButton.action = #selector(togglePanelPin)
        pinPanelButton.toolTip = "Keep the panel open (disables auto-hide)"
        pinPanelButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(pinPanelButton)

        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New")
        newButton.bezelStyle = .inline
        newButton.isBordered = false
        newButton.target = self
        newButton.action = #selector(primaryAddAction)
        newButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(newButton)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        stackView.orientation = .vertical
        stackView.spacing = 12
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)

        bottomLabel.font = NSFont.systemFont(ofSize: 11)
        bottomLabel.textColor = SNTheme.secondaryText
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            searchField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 120),

            newButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            newButton.widthAnchor.constraint(equalToConstant: 24),

            pinPanelButton.trailingAnchor.constraint(equalTo: newButton.leadingAnchor, constant: -4),
            pinPanelButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            pinPanelButton.widthAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomLabel.topAnchor, constant: -4),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            bottomLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            bottomLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        updatePinPanelButton()
    }

    func updateRoundedCorner(for side: PanelSide) {
        // Docked right: round the top-left. Docked left: round the top-right.
        view.layer?.maskedCorners = side == .right ? [.layerMinXMinYCorner] : [.layerMaxXMinYCorner]
    }

    // MARK: Reload

    func reload() {
        for sub in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        activeCard = nil

        switch presentation {
        case .folders:
            backButton.isHidden = true
            titleLabel.stringValue = "Folders"
            newButton.toolTip = "New folder"
            for folder in store.folders {
                let row = folderRow(folder)
                stackView.addArrangedSubview(row)
                pinWidth(row)
            }
            stackView.addArrangedSubview(trashRow())
            stackView.addArrangedSubview(settingsRow())
            bottomLabel.stringValue = "\(store.folders.count) folders"

        case .notes(let folderID):
            backButton.isHidden = false
            titleLabel.stringValue = store.folder(id: folderID)?.name ?? "Notes"
            newButton.toolTip = "New note"
            let notes = store.notes(in: folderID)
            if notes.isEmpty {
                stackView.addArrangedSubview(emptyState(text: "No notes yet.\nPress + or drag anything here."))
            }
            for note in notes {
                let noteCard = card(for: note)
                stackView.addArrangedSubview(noteCard)
                pinWidth(noteCard)
            }
            bottomLabel.stringValue = "\(notes.count) note\(notes.count == 1 ? "" : "s")"

        case .trash:
            backButton.isHidden = false
            titleLabel.stringValue = "Trash"
            newButton.toolTip = "Empty Trash"
            let trashed = store.trashedNotes
            if trashed.isEmpty {
                stackView.addArrangedSubview(emptyState(text: "Trash is empty.\nDeleted notes stay here for 30 days."))
            }
            for note in trashed {
                let trashCard = card(for: note, trash: true)
                stackView.addArrangedSubview(trashCard)
                pinWidth(trashCard)
            }
            bottomLabel.stringValue = "Notes are permanently deleted after 30 days"

        case .search(let query):
            backButton.isHidden = false
            titleLabel.stringValue = "Search"
            newButton.toolTip = "New note"
            let results = store.search(query)
            if results.isEmpty {
                stackView.addArrangedSubview(emptyState(text: "No notes match “\(query)”."))
            }
            for note in results {
                let resultCard = card(for: note)
                stackView.addArrangedSubview(resultCard)
                pinWidth(resultCard)
            }
            bottomLabel.stringValue = "\(results.count) result\(results.count == 1 ? "" : "s")"
        }
    }

    /// Pins a stack subview's width to the stack. MUST be called only after
    /// the view is inside the stack's hierarchy — activating a cross-view
    /// constraint before then logs "no common ancestor" and drops it.
    private func pinWidth(_ view: NSView) {
        view.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -24).isActive = true
    }

    private func card(for note: SNNote, trash: Bool = false) -> NSView {
        let cardView = NoteCardView(note: note)
        cardView.isTrashMode = trash
        cardView.onBecomeActive = { [weak self] card in self?.activeCard = card }
        cardView.translatesAutoresizingMaskIntoConstraints = false
        if trash {
            // Restore / Delete Forever row under trashed cards.
            let wrapper = NSStackView()
            wrapper.orientation = .vertical
            wrapper.spacing = 4
            wrapper.alignment = .leading
            wrapper.addArrangedSubview(cardView)
            let actions = NSStackView()
            actions.orientation = .horizontal
            actions.spacing = 8
            let restore = NSButton(title: "Restore", target: self, action: #selector(restoreNote(_:)))
            restore.identifier = NSUserInterfaceItemIdentifier(note.id.uuidString)
            restore.bezelStyle = .rounded
            let forever = NSButton(title: "Delete Forever", target: self, action: #selector(deleteForever(_:)))
            forever.identifier = NSUserInterfaceItemIdentifier(note.id.uuidString)
            forever.bezelStyle = .rounded
            actions.addArrangedSubview(restore)
            actions.addArrangedSubview(forever)
            wrapper.addArrangedSubview(actions)
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            return wrapper
        }
        return cardView
    }

    @objc private func restoreNote(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        store.restoreFromTrash(id: id)
    }

    @objc private func deleteForever(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this note permanently?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete Forever")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deletePermanently(id: id)
        }
    }

    // MARK: Folder home rows

    private func folderRow(_ folder: SNFolder) -> NSView {
        let row = FolderRowView(folder: folder, count: store.noteCount(in: folder.id))
        row.onOpen = { [weak self] in self?.openFolder(folder.id) }
        row.onPin = { [weak self] in self?.store.toggleFolderPin(id: folder.id); _ = self }
        row.onRename = { [weak self] in self?.promptRenameFolder(folder) }
        row.onDelete = { [weak self] in self?.confirmDeleteFolder(folder) }
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func trashRow() -> NSView {
        let button = NSButton(title: "🗑  Trash  (\(store.trashedNotes.count))", target: self, action: #selector(openTrash))
        button.bezelStyle = .inline
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13)
        button.contentTintColor = SNTheme.secondaryText
        return button
    }

    private func settingsRow() -> NSView {
        let button = NSButton(title: "⚙  Settings…", target: self, action: #selector(openSettings))
        button.bezelStyle = .inline
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13)
        button.contentTintColor = SNTheme.secondaryText
        return button
    }

    private func emptyState(text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = SNTheme.secondaryText
        label.alignment = .center
        return label
    }

    // MARK: Navigation

    func openFolder(_ folderID: UUID) {
        presentation = .notes(folderID: folderID)
        reload()
        scrollToTop()
    }

    @objc private func openTrash() {
        presentation = .trash
        reload()
        scrollToTop()
    }

    @objc private func openSettings() {
        SettingsController.shared.show()
    }

    @objc private func goBack() {
        if case .search = presentation, searchField.isHidden == false {
            searchField.stringValue = ""
            searchField.isHidden = true
        }
        presentation = .folders
        reload()
    }

    private func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    /// Creates a note in the current folder (or the first folder) and focuses it.
    func createNoteAndFocus() {
        let folderID: UUID
        switch presentation {
        case .notes(let id): folderID = id
        case .folders, .trash, .search:
            guard let first = store.folders.first else { return }
            folderID = first.id
            presentation = .notes(folderID: folderID)
        }
        let note = store.createNote(in: folderID)
        reload()
        scrollToTop()
        DispatchQueue.main.async { [weak self] in
            if let cardView = self?.stackView.arrangedSubviews.compactMap({ $0 as? NoteCardView }).first(where: { $0.noteID == note.id }) {
                cardView.focusEditor()
                self?.activeCard = cardView
            }
        }
    }

    // MARK: Header actions

    @objc private func primaryAddAction() {
        switch presentation {
        case .folders:
            promptNewFolder()
        case .trash:
            confirmEmptyTrash()
        case .notes, .search:
            createNoteAndFocus()
        }
    }

    @objc private func toggleSearchField() {
        searchField.isHidden.toggle()
        if !searchField.isHidden {
            view.window?.makeFirstResponder(searchField)
        } else if case .search = presentation {
            goBack()
        }
    }

    @objc private func searchChanged() {
        let query = searchField.stringValue
        if query.isEmpty {
            if case .notes = presentation { reload() }
            return
        }
        presentation = .search(query: query)
        reload()
    }

    @objc private func togglePanelPin() {
        Preferences.panelPinned.toggle()
        updatePinPanelButton()
    }

    private func updatePinPanelButton() {
        pinPanelButton.image = NSImage(systemSymbolName: Preferences.panelPinned ? "pin.fill" : "pin",
                                       accessibilityDescription: "Keep panel open")
        pinPanelButton.contentTintColor = Preferences.panelPinned ? SNTheme.accent : SNTheme.secondaryText
    }

    // MARK: Folder prompts

    private func promptNewFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.createFolder(name: name)
    }

    private func promptRenameFolder(_ folder: SNFolder) {
        let alert = NSAlert()
        alert.messageText = "Rename Folder"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = folder.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.renameFolder(id: folder.id, to: name)
    }

    private func confirmDeleteFolder(_ folder: SNFolder) {
        let alert = NSAlert()
        alert.messageText = "Delete folder “\(folder.name)”?"
        alert.informativeText = "Its notes move to the Trash, where they stay for 30 days."
        alert.addButton(withTitle: "Delete Folder")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteFolder(id: folder.id)
        }
    }

    private func confirmEmptyTrash() {
        guard !store.trashedNotes.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "All notes in the Trash will be permanently deleted. This cannot be undone."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.emptyTrash()
        }
    }

    // MARK: Panel-level keyboard shortcuts (act on the active card)

    /// Handles ⌥⌘P (pin), ⌥⌘⏎ (fold), ⌥⌘1/2/3 (mode) for the active card.
    /// Returns true if the key was consumed.
    func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), event.modifierFlags.contains(.option),
              let card = activeCard, let note = store.note(id: card.noteID) else { return false }
        let chars = event.charactersIgnoringModifiers ?? ""
        switch chars {
        case "p":
            store.toggleNotePin(id: note.id)
            card.reloadFromStore()
            return true
        case "\r":
            card.toggleFold()
            return true
        case "1":
            store.setNoteMode(id: note.id, mode: .standard)
            card.reloadFromStore()
            return true
        case "2":
            store.setNoteMode(id: note.id, mode: .plain)
            card.reloadFromStore()
            return true
        case "3":
            store.setNoteMode(id: note.id, mode: .code)
            card.reloadFromStore()
            return true
        default:
            return false
        }
    }
}

/// NSScrollView document views are not flipped by default; this makes the
/// card stack grow downward from the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A clickable folder row with a context menu (pin / rename / delete).
private final class FolderRowView: NSView {
    var onOpen: (() -> Void)?
    var onPin: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    init(folder: SNFolder, count: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = SNTheme.cardBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = SNTheme.cardBorder.cgColor

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = (folder.color == .none ? SNTheme.accent : SNTheme.swatch(for: folder.color)).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: (folder.isPinned ? "📌 " : "") + folder.name)
        name.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        name.textColor = SNTheme.primaryText
        name.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = NSTextField(labelWithString: "\(count)")
        countLabel.font = NSFont.systemFont(ofSize: 12)
        countLabel.textColor = SNTheme.secondaryText
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSTextField(labelWithString: "›")
        chevron.font = NSFont.systemFont(ofSize: 16)
        chevron.textColor = SNTheme.secondaryText
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot); addSubview(name); addSubview(countLabel); addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            name.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked))
        addGestureRecognizer(click)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Pin Folder", action: #selector(menuPin), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Rename…", action: #selector(menuRename), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Delete Folder…", action: #selector(menuDelete), keyEquivalent: ""))
        self.menu = menu
    }

    required init?(coder: NSCoder) {
        // Rows are only ever built in code; this exists to satisfy NSCoding.
        super.init(coder: coder)
    }

    @objc private func rowClicked() { onOpen?() }
    @objc private func menuPin() { onPin?() }
    @objc private func menuRename() { onRename?() }
    @objc private func menuDelete() { onDelete?() }
}
