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
    private let pillView = NSView()
    private let captionLabel = NSTextField(labelWithString: "")
    private var headerHeightConstraint: NSLayoutConstraint!
    private var backButtonWidthConstraint: NSLayoutConstraint!
    private let backButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "Folders")
    private let searchField = NSSearchField()
    private let newButton = NSButton()
    private let pinPanelButton = NSButton()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let bottomLabel = NSTextField(labelWithString: "")

    /// Live card views keyed by "<mode>:<noteID>" (the mode prefix keeps
    /// a note's Trash wrapper distinct from its plain card), plus the
    /// note each was last configured with. reload() diffs against these
    /// maps so a structural change creates, removes, and reconfigures
    /// only the cards it actually affects — v0.1.0 rebuilt every card in
    /// the folder on every change.
    private var cardViews: [String: NSView] = [:]
    private var cardNotes: [String: SNNote] = [:]
    private var searchWorkItem: DispatchWorkItem?
    /// The "show markup" preference as of the last card configuration.
    /// It lives outside the note model, so the diff tracks it separately:
    /// when it flips, every visible card reconfigures even though no
    /// note changed.
    private var lastMarkupSetting: Bool?

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

    /// Circular icon-button treatment inside the header pill.
    private func stylePillButton(_ button: NSButton) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = SNTheme.pillButtonBackground.cgColor
        button.contentTintColor = SNTheme.primaryText
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func buildLayout() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        // The header is a floating pill (design package): full pill
        // radius, its own surface, the folder name in bold 13.
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 18
        pillView.layer?.backgroundColor = SNTheme.headerPillBackground.cgColor
        pillView.layer?.borderWidth = 1
        pillView.layer?.borderColor = SNTheme.cardBorder.cgColor
        pillView.layer?.shadowColor = NSColor.black.cgColor
        pillView.layer?.shadowOpacity = 0.07
        pillView.layer?.shadowRadius = 4
        pillView.layer?.shadowOffset = NSSize(width: 0, height: -1)
        pillView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(pillView)

        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.target = self
        backButton.action = #selector(goBack)
        stylePillButton(backButton)
        pillView.addSubview(backButton)

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = SNTheme.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(titleLabel)

        searchField.placeholderString = "Search all notes"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.isHidden = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(searchField)

        let searchButton = NSButton(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") ?? NSImage(),
                                    target: self, action: #selector(toggleSearchField))
        stylePillButton(searchButton)
        pillView.addSubview(searchButton)

        pinPanelButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Keep panel open")
        pinPanelButton.target = self
        pinPanelButton.action = #selector(togglePanelPin)
        pinPanelButton.toolTip = "Keep the panel open (disables auto-hide)"
        stylePillButton(pinPanelButton)
        pillView.addSubview(pinPanelButton)

        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New")
        newButton.target = self
        newButton.action = #selector(primaryAddAction)
        stylePillButton(newButton)
        pillView.addSubview(newButton)

        // Under-pill caption: a green dot + the local-first note.
        let caption = NSMutableAttributedString(string: "●  ",
                                                attributes: [.font: NSFont.systemFont(ofSize: 10.5),
                                                             .foregroundColor: SNTheme.taskDone])
        caption.append(NSAttributedString(string: "Local only — sync arrives in V1.1",
                                          attributes: [.font: NSFont.systemFont(ofSize: 10.5),
                                                       .foregroundColor: SNTheme.secondaryText]))
        captionLabel.attributedStringValue = caption
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(captionLabel)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)

        bottomLabel.font = NSFont.systemFont(ofSize: 11)
        bottomLabel.textColor = SNTheme.secondaryText
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomLabel)

        // Hairline rule above the bottom bar, per the design package.
        let bottomRule = NSView()
        bottomRule.wantsLayer = true
        bottomRule.layer?.backgroundColor = SNTheme.hairline.cgColor
        bottomRule.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomRule)

        headerHeightConstraint = headerView.heightAnchor.constraint(equalToConstant: 72)
        backButtonWidthConstraint = backButton.widthAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerHeightConstraint,

            pillView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            pillView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            pillView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            pillView.heightAnchor.constraint(equalToConstant: 36),

            captionLabel.topAnchor.constraint(equalTo: pillView.bottomAnchor, constant: 3),
            captionLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),

            backButton.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 6),
            backButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            backButtonWidthConstraint,
            backButton.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),

            searchField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 110),

            newButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -6),
            newButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            newButton.widthAnchor.constraint(equalToConstant: 24),
            newButton.heightAnchor.constraint(equalToConstant: 24),

            pinPanelButton.trailingAnchor.constraint(equalTo: newButton.leadingAnchor, constant: -4),
            pinPanelButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            pinPanelButton.widthAnchor.constraint(equalToConstant: 24),
            pinPanelButton.heightAnchor.constraint(equalToConstant: 24),

            searchButton.trailingAnchor.constraint(equalTo: pinPanelButton.leadingAnchor, constant: -4),
            searchButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 24),
            searchButton.heightAnchor.constraint(equalToConstant: 24),

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

            bottomRule.bottomAnchor.constraint(equalTo: bottomLabel.topAnchor, constant: -4),
            bottomRule.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomRule.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomRule.heightAnchor.constraint(equalToConstant: 1),
        ])
        updatePinPanelButton()
    }

    func updateRoundedCorner(for side: PanelSide) {
        // Docked right: round the top-left. Docked left: round the top-right.
        view.layer?.maskedCorners = side == .right ? [.layerMinXMinYCorner] : [.layerMaxXMinYCorner]
    }

    /// Header shape per presentation: the folder home drops the back
    /// chevron and the under-pill caption; note lists show both.
    private func updateHeader(backVisible: Bool, captionVisible: Bool) {
        backButton.isHidden = !backVisible
        backButtonWidthConstraint?.constant = backVisible ? 24 : 0
        captionLabel.isHidden = !captionVisible
        headerHeightConstraint?.constant = captionVisible ? 72 : 56
    }

    // MARK: Reload

    func reload() {
        activeCard = nil

        switch presentation {
        case .folders:
            clearStack()
            updateHeader(backVisible: false, captionVisible: false)
            titleLabel.stringValue = "Folders"
            newButton.toolTip = "New folder"
            for folder in store.folders {
                let row = folderRow(folder)
                stackView.addArrangedSubview(row)
                pinWidth(row)
            }
            let trash = trashRow()
            stackView.addArrangedSubview(trash)
            pinWidth(trash)
            let settings = settingsRow()
            stackView.addArrangedSubview(settings)
            pinWidth(settings)
            bottomLabel.stringValue = "\(store.folders.count) folder\(store.folders.count == 1 ? "" : "s") · flat list"

        case .notes(let folderID):
            updateHeader(backVisible: true, captionVisible: true)
            titleLabel.stringValue = store.folder(id: folderID)?.name ?? "Notes"
            newButton.toolTip = "New note"
            let notes = store.notes(in: folderID)
            if notes.isEmpty {
                clearStack()
                let empty = emptyFolderState(folderName: store.folder(id: folderID)?.name ?? "this folder")
                stackView.addArrangedSubview(empty)
                pinWidth(empty)
            } else {
                updateCardStack(notes: notes, trash: false)
            }
            bottomLabel.stringValue = "\(notes.count) note\(notes.count == 1 ? "" : "s")"

        case .trash:
            updateHeader(backVisible: true, captionVisible: false)
            titleLabel.stringValue = "Trash"
            newButton.toolTip = "Empty Trash"
            let trashed = store.trashedNotes
            if trashed.isEmpty {
                clearStack()
                let empty = emptyMessageState(headline: "Trash is empty",
                                              body: "Deleted notes stay here for 30 days.")
                stackView.addArrangedSubview(empty)
                pinWidth(empty)
            } else {
                updateCardStack(notes: trashed, trash: true)
            }
            bottomLabel.stringValue = "Notes are permanently deleted after 30 days"

        case .search(let query):
            updateHeader(backVisible: true, captionVisible: true)
            titleLabel.stringValue = "Search"
            newButton.toolTip = "New note"
            let results = store.search(query)
            if results.isEmpty {
                clearStack()
                let empty = emptyMessageState(headline: "No notes match “\(query)”", body: "")
                stackView.addArrangedSubview(empty)
                pinWidth(empty)
            } else {
                updateCardStack(notes: results, trash: false)
            }
            bottomLabel.stringValue = "\(results.count) result\(results.count == 1 ? "" : "s")"
        }
    }

    /// Removes every arranged subview and forgets every cached card.
    private func clearStack() {
        for sub in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        cardViews.removeAll()
        cardNotes.removeAll()
    }

    /// Brings the card stack in line with `notes`, diffing by note ID:
    /// cards for departed notes are removed, cards for new notes are
    /// created, surviving cards keep their views (only their order in
    /// the stack is re-applied) and are reconfigured ONLY if their note
    /// changed since the last configuration.
    private func updateCardStack(notes: [SNNote], trash: Bool) {
        let prefix = trash ? "trash" : "note"
        let wantedKeys = notes.map { "\(prefix):\($0.id.uuidString)" }
        let wanted = Set(wantedKeys)
        let markup = UserDefaults.standard.bool(forKey: Preferences.showMarkupKey)
        let markupChanged = lastMarkupSetting != markup
        lastMarkupSetting = markup

        // Cards whose notes left this presentation: remove and forget.
        for key in cardViews.keys.filter({ !wanted.contains($0) }) {
            if let view = cardViews[key] {
                stackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            cardViews.removeValue(forKey: key)
            cardNotes.removeValue(forKey: key)
        }
        // Anything else in the stack (empty-state labels, folder rows)
        // does not belong in a card presentation.
        let wantedViews = Set(wantedKeys.compactMap { cardViews[$0] })
        for sub in stackView.arrangedSubviews where !wantedViews.contains(sub) {
            stackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        // Build the desired order, creating/configuring only what's new
        // or changed. (A newly created card configures itself in init.)
        var ordered: [NSView] = []
        var fresh: Set<String> = []
        for (index, note) in notes.enumerated() {
            let key = wantedKeys[index]
            if let existing = cardViews[key] {
                if (cardNotes[key] != note || markupChanged), let cardView = cardView(in: existing) {
                    cardView.configure(with: note)
                    cardNotes[key] = note
                }
                ordered.append(existing)
            } else {
                let view = card(for: note, trash: trash)
                cardViews[key] = view
                cardNotes[key] = note
                fresh.insert(key)
                ordered.append(view)
            }
        }

        // Re-apply the order: detach each surviving view from the
        // arranged list (it stays in the hierarchy, constraints intact)
        // and re-add in presentation order. Only fresh cards need their
        // width pinned — survivors kept the constraint from creation.
        for view in ordered { stackView.removeArrangedSubview(view) }
        for (index, view) in ordered.enumerated() {
            stackView.addArrangedSubview(view)
            if fresh.contains(wantedKeys[index]) { pinWidth(view) }
        }
    }

    /// The NoteCardView inside a stack entry — the entry itself for
    /// plain cards, or the first arranged subview of the Trash wrapper.
    private func cardView(in view: NSView) -> NoteCardView? {
        if let card = view as? NoteCardView { return card }
        return (view as? NSStackView)?.arrangedSubviews.first as? NoteCardView
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
        let row = UtilityRowView(symbol: "trash", title: "Trash",
                                 detail: "\(store.trashedNotes.count) · kept 30 days")
        row.onOpen = { [weak self] in self?.openTrash() }
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func settingsRow() -> NSView {
        let row = UtilityRowView(symbol: "gearshape", title: "Settings…", detail: nil)
        row.onOpen = { [weak self] in self?.openSettings() }
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    // MARK: Empty states

    /// The designed empty folder (design package): headline, the
    /// three-capture-paths teaching line, and an accent New Note button.
    private func emptyFolderState(folderName: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let headline = NSTextField(labelWithString: "Nothing in \(folderName) yet")
        headline.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        headline.textColor = SNTheme.primaryText
        headline.alignment = .center

        let body = NSTextField(labelWithString: "Drop a file here, drag text in from any app, or start typing — the first note is one keystroke away.")
        body.font = NSFont.systemFont(ofSize: 12)
        body.textColor = SNTheme.secondaryText
        body.alignment = .center
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 3

        let button = NSButton(title: "New Note", target: self, action: #selector(emptyStateNewNote))
        button.bezelStyle = .rounded
        button.bezelColor = SNTheme.accent
        button.contentTintColor = .white
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

        let stack = NSStackView(views: [headline, body, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 250),
        ])
        return container
    }

    /// Headline + optional line, centred — Trash and no-results states.
    private func emptyMessageState(headline: String, body: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let headlineLabel = NSTextField(labelWithString: headline)
        headlineLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        headlineLabel.textColor = SNTheme.primaryText
        headlineLabel.alignment = .center
        headlineLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [headlineLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        if !body.isEmpty {
            let bodyLabel = NSTextField(labelWithString: body)
            bodyLabel.font = NSFont.systemFont(ofSize: 12)
            bodyLabel.textColor = SNTheme.secondaryText
            bodyLabel.alignment = .center
            stack.addArrangedSubview(bodyLabel)
        }
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            headlineLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
        ])
        return container
    }

    @objc private func emptyStateNewNote() {
        createNoteAndFocus()
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
        // Debounced like the editor's render: NSSearchField fires its
        // action on every keystroke, and applying a search re-scans every
        // note and re-diffs the card stack — once per pause in typing is
        // plenty.
        searchWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applySearch() }
        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func applySearch() {
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
        layer?.cornerRadius = 8
        layer?.backgroundColor = SNTheme.cardBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = SNTheme.cardBorder.cgColor

        // Plain rows, no folder colours (design package): an accent-soft
        // tile with a folder glyph carries the row instead.
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        tile.layer?.backgroundColor = SNTheme.accentSoftBackground.cgColor
        tile.translatesAutoresizingMaskIntoConstraints = false
        let glyph = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage())
        glyph.contentTintColor = SNTheme.accent
        glyph.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(glyph)

        let pin = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") ?? NSImage())
        pin.contentTintColor = SNTheme.pinnedActive
        pin.isHidden = !folder.isPinned
        pin.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: folder.name)
        name.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        name.textColor = SNTheme.primaryText
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = NSTextField(labelWithString: "\(count)")
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = SNTheme.secondaryText
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSTextField(labelWithString: "›")
        chevron.font = NSFont.systemFont(ofSize: 16)
        chevron.textColor = SNTheme.secondaryText
        chevron.translatesAutoresizingMaskIntoConstraints = false

        // Tile + optional pin + name in a stack, so a hidden pin
        // collapses instead of leaving a gap.
        let leftStack = NSStackView(views: [tile, pin, name])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 8
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftStack); addSubview(countLabel); addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            tile.widthAnchor.constraint(equalToConstant: 30),
            tile.heightAnchor.constraint(equalToConstant: 30),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            glyph.heightAnchor.constraint(equalToConstant: 16),
            pin.widthAnchor.constraint(equalToConstant: 10),
            pin.heightAnchor.constraint(equalToConstant: 10),
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),
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

/// A folder-home row in the same plain style as FolderRowView, for the
/// fixed destinations (Trash, Settings): icon tile, name, an optional
/// secondary detail at the right, chevron.
private final class UtilityRowView: NSView {
    var onOpen: (() -> Void)?

    init(symbol: String, title: String, detail: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = SNTheme.cardBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = SNTheme.cardBorder.cgColor

        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        tile.layer?.backgroundColor = SNTheme.accentSoftBackground.cgColor
        tile.translatesAutoresizingMaskIntoConstraints = false
        let glyph = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        glyph.contentTintColor = SNTheme.accent
        glyph.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(glyph)

        let name = NSTextField(labelWithString: title)
        name.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        name.textColor = SNTheme.primaryText
        name.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail ?? "")
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = SNTheme.secondaryText
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSTextField(labelWithString: "›")
        chevron.font = NSFont.systemFont(ofSize: 16)
        chevron.textColor = SNTheme.secondaryText
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tile); addSubview(name); addSubview(detailLabel); addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 30),
            tile.heightAnchor.constraint(equalToConstant: 30),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            glyph.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) {
        // Rows are only ever built in code; this exists to satisfy NSCoding.
        super.init(coder: coder)
    }

    @objc private func rowClicked() { onOpen?() }
}
