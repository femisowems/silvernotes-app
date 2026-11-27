import AppKit

/// Root content of the edge panel.
/// Presentations over one scrollable column:
/// - Folder home (Standard width): All Notes + Pinned rows, flat folder
///   rows (pinned first, counts), a Trash row; Settings is a gear button
///   in the bottom bar (audit 4.34).
/// - Notes / All Notes / Pinned / Search / Trash: a card stack (or, in
///   Compact density, one-line rows with a capture field — audit 7.1).
/// - Wide width adds a folder rail on the left (audit 7.2) that replaces
///   the folder-home step.
/// The bottom bar carries the count plus fold/unfold-all and overflow
/// buttons in note views (audits 4.37, 4.38).
final class PanelContentController: NSViewController, NSMenuDelegate {

    enum Presentation: Equatable {
        case folders
        case notes(folderID: UUID)
        case allNotes
        case pinnedNotes
        case trash
        case search(query: String)
    }

    private(set) var presentation: Presentation = .folders
    weak var activeCard: NoteCardView?

    private let store: NoteStore
    private let headerView = NSView()
    private let pillView = NSView()
    private let captionLabel = NSTextField(labelWithString: "")
    private var headerHeightConstraint: NSLayoutConstraint!
    private var backButtonWidthConstraint: NSLayoutConstraint!
    /// The title's two possible leading anchors (v0.6.0, rubric §1.4):
    /// after the back chevron when it shows, at the pill's own 12 pt
    /// inset when it doesn't. Exactly one is active at a time;
    /// updateHeader toggles them with the chevron's width.
    private var titleToBackConstraint: NSLayoutConstraint!
    private var titleToPillConstraint: NSLayoutConstraint!
    /// The panel's 1 pt screen-facing edge line (rubric §1.2). Pinned
    /// to the leading edge when the panel docks right (the mockup's
    /// side), the trailing edge when it docks left; updateRoundedCorner
    /// flips the pair.
    private let panelEdgeBorder = NSView()
    private var panelEdgeLeadingConstraint: NSLayoutConstraint!
    private var panelEdgeTrailingConstraint: NSLayoutConstraint!
    private let backButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "Folders")
    private let searchField = NSSearchField()
    private let newButton = NSButton()
    /// Every button passed to stylePillButton, so an appearance
    /// change can re-bake their layer backgrounds (see
    /// refreshChromeSurfaces).
    private var pillButtons: [NSButton] = []
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let captureBar = NSView()
    private let captureField = NSTextField()
    private var captureBarHeightConstraint: NSLayoutConstraint!
    private let bottomBar = NSView()
    private let bottomLabel = NSTextField(labelWithString: "")
    private let hintsLabel = NSTextField(labelWithString: "")
    private let compactCountLabel = NSTextField(labelWithString: "")
    private let foldAllButton = NSButton()
    private let overflowButton = NSButton()
    private let gearButton = NSButton()
    /// Hairline rule above the bottom bar. Stored (not a buildLayout
    /// local) so refreshChromeSurfaces can re-bake its color.
    private let bottomRule = NSView()
    private let railView = NSView()
    /// The Wide rail's right-edge hairline. Stored (not a buildLayout
    /// local) so refreshChromeSurfaces can re-bake its color.
    private let railBorder = NSView()
    private let railStack = NSStackView()
    private var columnLeadingConstraint: NSLayoutConstraint!
    private let dropOverlay = NSView()
    private var dropOverlayLabel: NSTextField!

    private var searchWorkItem: DispatchWorkItem?
    /// Live Compact row views keyed by note ID, populated by
    /// updateCompactRows. Selection changes restyle these rows in
    /// place (see refreshCompactSelection) instead of rebuilding the
    /// list — a rebuild on selection destroyed the row view between
    /// the two clicks of a double-click, so expansion never fired.
    private var compactRowViews: [UUID: CompactRowView] = [:]
    /// The notes backing the current list presentation, in display
    /// order — fold-all, reorder, and export all act on exactly these.
    private var currentListNotes: [SNNote] = []
    /// Compact density selection (audit 7.1).
    private var compactSelectedID: UUID?
    /// Insertion index computed during a reorder drag over the stack.
    private var pendingInsertIndex: Int?

    private var isWide: Bool { Preferences.panelWidth == .wide }
    private var isCompact: Bool { Preferences.density == .compact }

    /// `store` is a test seam: production call sites use the default
    /// (the shared store); tests inject a store rooted in a temporary
    /// directory so they can seed it and drive the real controller
    /// against the seeded data.
    init(store: NoteStore = .shared) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.store = .shared
        super.init(coder: coder)
    }

    override func loadView() {
        let root = PanelRootView(frame: NSRect(x: 0, y: 0, width: 380, height: 600))
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        // Square panel corners (audit 1.17): the package draws none.
        root.layer?.cornerRadius = 0
        root.layer?.backgroundColor = SNTheme.panelBackground.cgColor
        root.onAppearanceChange = { [weak self] in self?.refreshChromeSurfaces() }
        root.onDragEntered = { [weak self] in self?.panelDragEntered() ?? [] }
        root.onDragExited = { [weak self] in self?.dropOverlay.isHidden = true }
        root.onDragPerformed = { [weak self] info in self?.panelDragPerformed(info) ?? false }
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.onStructuralChange = { [weak self] in self?.reload() }
        reload()
    }

    /// Re-bakes the controller-owned layer surfaces from the CURRENT
    /// theme colors. A layer's background/border color is a CGColor:
    /// it bakes whichever variant of a dynamic SNTheme color was
    /// current at assignment time and never re-resolves, while text
    /// colors (stored as NSColor on the fields) flip live with the
    /// appearance. Without this, a system appearance flip on the
    /// long-lived panel leaves dark-appearance text sitting on
    /// light-baked surfaces (the folder-home bug in the Nov 27
    /// screenshot). Called from the root view's
    /// viewDidChangeEffectiveAppearance; every surface is
    /// optional-chained, so firing before buildLayout has given a
    /// view its layer is a no-op.
    private func refreshChromeSurfaces() {
        view.layer?.backgroundColor = SNTheme.panelBackground.cgColor
        pillView.layer?.backgroundColor = SNTheme.headerPillBackground.cgColor
        pillView.layer?.borderColor = SNTheme.headerPillBorder.cgColor
        for button in pillButtons {
            button.layer?.backgroundColor = SNTheme.pillButtonBackground.cgColor
        }
        railBorder.layer?.backgroundColor = SNTheme.hairline.cgColor
        bottomRule.layer?.backgroundColor = SNTheme.panelBottomBorder.cgColor
        panelEdgeBorder.layer?.backgroundColor = SNTheme.panelEdgeBorder.cgColor
        dropOverlay.layer?.backgroundColor = SNTheme.dropTargetBackground.cgColor
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
        pillButtons.append(button)
    }

    /// Small square bottom-bar button (24×24, radius 6 — the package's
    /// .bbtn).
    private func styleBarButton(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.target = self
        button.action = action
        button.bezelStyle = .inline
        button.isBordered = false
        button.toolTip = tip
        button.contentTintColor = SNTheme.secondaryText
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private func buildLayout() {
        // Folder rail (Wide only, audit 7.2): a fixed 118 pt column at
        // the panel's left; the content column slides over to make room.
        railView.wantsLayer = true
        railView.layer?.backgroundColor = NSColor.clear.cgColor
        railView.translatesAutoresizingMaskIntoConstraints = false
        railView.isHidden = true
        view.addSubview(railView)
        railBorder.wantsLayer = true
        railBorder.layer?.backgroundColor = SNTheme.hairline.cgColor
        railBorder.translatesAutoresizingMaskIntoConstraints = false
        railView.addSubview(railBorder)
        railStack.orientation = .vertical
        railStack.alignment = .leading
        railStack.spacing = 1
        railStack.translatesAutoresizingMaskIntoConstraints = false
        railView.addSubview(railStack)
        NSLayoutConstraint.activate([
            railView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            railView.topAnchor.constraint(equalTo: view.topAnchor),
            railView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            railView.widthAnchor.constraint(equalToConstant: 118),
            railBorder.trailingAnchor.constraint(equalTo: railView.trailingAnchor),
            railBorder.topAnchor.constraint(equalTo: railView.topAnchor),
            railBorder.bottomAnchor.constraint(equalTo: railView.bottomAnchor),
            railBorder.widthAnchor.constraint(equalToConstant: 1),
            railStack.leadingAnchor.constraint(equalTo: railView.leadingAnchor, constant: 8),
            railStack.trailingAnchor.constraint(equalTo: railView.trailingAnchor, constant: -8),
            railStack.topAnchor.constraint(equalTo: railView.topAnchor, constant: 10),
            railStack.bottomAnchor.constraint(lessThanOrEqualTo: railView.bottomAnchor, constant: -10),
        ])

        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        columnLeadingConstraint = column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0)
        NSLayoutConstraint.activate([
            columnLeadingConstraint,
            column.topAnchor.constraint(equalTo: view.topAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        headerView.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(headerView)

        // The header is a floating pill (design package): full pill
        // radius, its own surface, the folder name in bold 13.
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = 18
        pillView.layer?.backgroundColor = SNTheme.headerPillBackground.cgColor
        pillView.layer?.borderWidth = 1
        pillView.layer?.borderColor = SNTheme.headerPillBorder.cgColor
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

        // Compact capture bar (audit 7.1): a field pinned under the
        // header; Return files the typed line as a note.
        captureBar.translatesAutoresizingMaskIntoConstraints = false
        captureBar.isHidden = true
        column.addSubview(captureBar)
        captureField.placeholderString = "Capture a thought…"
        captureField.target = self
        captureField.action = #selector(captureSubmitted)
        captureField.font = NSFont.systemFont(ofSize: 12.5)
        captureField.isBordered = false
        captureField.drawsBackground = true
        captureField.backgroundColor = SNTheme.cardBackground
        captureField.translatesAutoresizingMaskIntoConstraints = false
        captureBar.addSubview(captureField)
        let captureHint = NSTextField(labelWithString: "⌘ ⏎")
        captureHint.font = NSFont.systemFont(ofSize: 10.5)
        captureHint.textColor = SNTheme.tertiaryText
        captureHint.translatesAutoresizingMaskIntoConstraints = false
        captureBar.addSubview(captureHint)
        captureBarHeightConstraint = captureBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            captureBar.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            captureBar.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            captureBar.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            captureBarHeightConstraint,
            captureField.leadingAnchor.constraint(equalTo: captureBar.leadingAnchor, constant: 12),
            captureField.trailingAnchor.constraint(equalTo: captureHint.leadingAnchor, constant: -6),
            captureField.centerYAnchor.constraint(equalTo: captureBar.centerYAnchor),
            captureField.heightAnchor.constraint(equalToConstant: 24),
            captureHint.trailingAnchor.constraint(equalTo: captureBar.trailingAnchor, constant: -14),
            captureHint.centerYAnchor.constraint(equalTo: captureBar.centerYAnchor),
        ])

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(scrollView)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.registerForDraggedTypes([.snNote])
        documentView.onNoteDragUpdate = { [weak self] info in self?.noteDragUpdate(info) ?? [] }
        documentView.onNoteDrop = { [weak self] info in self?.noteDrop(info) ?? false }
        scrollView.documentView = documentView

        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 12, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)

        // Bottom bar: count + actions (audits 4.36–4.38, 4.34).
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(bottomBar)
        bottomLabel.font = NSFont.systemFont(ofSize: 11)
        bottomLabel.textColor = SNTheme.secondaryText
        bottomLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(bottomLabel)
        hintsLabel.stringValue = "↑↓ navigate   ⏎ open   ⌘N new   ⌘F search   esc back"
        hintsLabel.font = NSFont.systemFont(ofSize: 10.5)
        hintsLabel.textColor = SNTheme.secondaryText
        hintsLabel.translatesAutoresizingMaskIntoConstraints = false
        hintsLabel.isHidden = true
        bottomBar.addSubview(hintsLabel)
        compactCountLabel.font = NSFont.systemFont(ofSize: 11)
        compactCountLabel.textColor = SNTheme.secondaryText
        compactCountLabel.translatesAutoresizingMaskIntoConstraints = false
        compactCountLabel.isHidden = true
        bottomBar.addSubview(compactCountLabel)
        styleBarButton(foldAllButton, symbol: "chevron.up", tip: "Fold / unfold all", action: #selector(foldAllTapped))
        bottomBar.addSubview(foldAllButton)
        styleBarButton(overflowButton, symbol: "ellipsis", tip: "More", action: #selector(showOverflowMenu(_:)))
        bottomBar.addSubview(overflowButton)
        styleBarButton(gearButton, symbol: "gearshape", tip: "Settings…", action: #selector(openSettings))
        bottomBar.addSubview(gearButton)

        // Hairline rule above the bottom bar, per the design package
        // (rubric §1.13: the bottom rule is a step stronger than the
        // card-footer hairline in light mode).
        bottomRule.wantsLayer = true
        bottomRule.layer?.backgroundColor = SNTheme.panelBottomBorder.cgColor
        bottomRule.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(bottomRule)

        // Drop-target overlay (audit 6.10): dashed accent border +
        // centred label while files are dragged over the panel.
        dropOverlay.wantsLayer = true
        dropOverlay.layer?.backgroundColor = SNTheme.dropTargetBackground.cgColor
        dropOverlay.translatesAutoresizingMaskIntoConstraints = false
        dropOverlay.isHidden = true
        column.addSubview(dropOverlay)
        let dash = CAShapeLayer()
        dash.strokeColor = SNTheme.accentRing.cgColor
        dash.fillColor = NSColor.clear.cgColor
        dash.lineWidth = 2
        dash.lineDashPattern = [8, 5]
        dash.name = "dash"
        dropOverlay.layer?.addSublayer(dash)
        dropOverlayLabel = NSTextField(labelWithString: "Drop to add as a file card")
        dropOverlayLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        dropOverlayLabel.textColor = SNTheme.accent
        dropOverlayLabel.alignment = .center
        dropOverlayLabel.translatesAutoresizingMaskIntoConstraints = false
        dropOverlay.addSubview(dropOverlayLabel)

        headerHeightConstraint = headerView.heightAnchor.constraint(equalToConstant: 72)
        backButtonWidthConstraint = backButton.widthAnchor.constraint(equalToConstant: 24)
        titleToBackConstraint = titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8)
        titleToPillConstraint = titleLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 12)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: column.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            headerHeightConstraint,

            pillView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 12),
            pillView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            pillView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            pillView.heightAnchor.constraint(equalToConstant: 36),

            captionLabel.topAnchor.constraint(equalTo: pillView.bottomAnchor, constant: 6),
            captionLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            backButton.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            backButtonWidthConstraint,
            backButton.heightAnchor.constraint(equalToConstant: 24),

            titleToBackConstraint,
            titleLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),

            // The search field flexes across the space the (hidden)
            // title vacates — v0.6.0 fixes the clipped "Search all
            // no…" placeholder the fixed 110 pt width caused at
            // Standard panel width (rubric §1.4 / A8).
            searchField.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchButton.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            newButton.widthAnchor.constraint(equalToConstant: 24),
            newButton.heightAnchor.constraint(equalToConstant: 24),

            searchButton.trailingAnchor.constraint(equalTo: newButton.leadingAnchor, constant: -8),
            searchButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 24),
            searchButton.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: captureBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: column.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 38),

            bottomLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 14),
            bottomLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            hintsLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 14),
            hintsLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            compactCountLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14),
            compactCountLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            overflowButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14),
            overflowButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            foldAllButton.trailingAnchor.constraint(equalTo: overflowButton.leadingAnchor, constant: -6),
            foldAllButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            gearButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14),
            gearButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            bottomRule.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomRule.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            bottomRule.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            bottomRule.heightAnchor.constraint(equalToConstant: 1),

            dropOverlay.topAnchor.constraint(equalTo: column.topAnchor),
            dropOverlay.bottomAnchor.constraint(equalTo: column.bottomAnchor),
            dropOverlay.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            dropOverlay.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            dropOverlayLabel.centerXAnchor.constraint(equalTo: dropOverlay.centerXAnchor),
            dropOverlayLabel.centerYAnchor.constraint(equalTo: dropOverlay.centerYAnchor),
        ])

        // The panel's screen-facing edge line (rubric §1.2), added
        // last so it draws over the column and the Wide rail alike.
        // Which edge is "screen-facing" follows the dock side;
        // updateRoundedCorner flips the active constraint.
        panelEdgeBorder.wantsLayer = true
        panelEdgeBorder.layer?.backgroundColor = SNTheme.panelEdgeBorder.cgColor
        panelEdgeBorder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelEdgeBorder)
        panelEdgeLeadingConstraint = panelEdgeBorder.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        panelEdgeTrailingConstraint = panelEdgeBorder.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            panelEdgeBorder.topAnchor.constraint(equalTo: view.topAnchor),
            panelEdgeBorder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelEdgeBorder.widthAnchor.constraint(equalToConstant: 1),
            panelEdgeLeadingConstraint,
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Keep the drop overlay's dashed rect matched to its bounds.
        if let dash = dropOverlay.layer?.sublayers?.first(where: { $0.name == "dash" }) as? CAShapeLayer {
            let rect = dropOverlay.bounds.insetBy(dx: 8, dy: 8)
            dash.frame = rect
            dash.path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        }
    }

    /// Drives the panel edge line's side: PanelController calls this
    /// at setup and on every side change (the panel's corners are
    /// square now (audit 1.17), so the corner half of the original
    /// method's job no longer exists). A right-docked panel (the
    /// mockup's side) shows the line on its leading edge; a
    /// left-docked panel on its trailing edge.
    func updateRoundedCorner(for side: PanelSide) {
        // Deactivate the outgoing edge first so the pair is never
        // active at once, even transiently.
        if side == .right {
            panelEdgeTrailingConstraint?.isActive = false
            panelEdgeLeadingConstraint?.isActive = true
        } else {
            panelEdgeLeadingConstraint?.isActive = false
            panelEdgeTrailingConstraint?.isActive = true
        }
    }

    /// Header shape per presentation: the folder home drops the back
    /// chevron and the under-pill caption; note lists show both. In Wide
    /// the rail replaces the home step, so the chevron never shows.
    private func updateHeader(backVisible: Bool, captionVisible: Bool) {
        let showBack = backVisible && !isWide
        backButton.isHidden = !showBack
        backButtonWidthConstraint?.constant = showBack ? 24 : 0
        // Title leading follows the chevron (rubric §1.4): 8 pt after
        // it when it shows, the pill's own 12 pt inset when it doesn't.
        // The outgoing constraint deactivates first (same discipline
        // as the edge-line pair in updateRoundedCorner).
        if showBack {
            titleToPillConstraint?.isActive = false
            titleToBackConstraint?.isActive = true
        } else {
            titleToBackConstraint?.isActive = false
            titleToPillConstraint?.isActive = true
        }
        captionLabel.isHidden = !captionVisible
        headerHeightConstraint?.constant = captionVisible ? 72 : 56
    }

    /// Shows/hides the folder rail + capture bar for the current
    /// width/density preferences. Called on reload and whenever the
    /// preferences change in Settings.
    private func updateChrome() {
        railView.isHidden = !isWide
        columnLeadingConstraint?.constant = isWide ? 118 : 0
        if isWide { rebuildRail() }
        let showCapture = isCompact && presentation != .folders && presentation != .trash
        captureBar.isHidden = !showCapture
        captureBarHeightConstraint?.constant = showCapture ? 34 : 0
    }

    /// Bottom bar contents per presentation + density. Compact note
    /// views swap the count + buttons for the keyboard-hints bar with
    /// the count at the right (audit 7.1).
    private func updateBottomBar(countText: String) {
        bottomLabel.stringValue = countText
        compactCountLabel.stringValue = countText
        let compactNotes: Bool
        switch presentation {
        case .notes, .allNotes, .pinnedNotes, .search:
            compactNotes = isCompact
        case .folders, .trash:
            compactNotes = false
        }
        hintsLabel.isHidden = !compactNotes
        compactCountLabel.isHidden = !compactNotes
        bottomLabel.isHidden = compactNotes
        foldAllButton.isHidden = true
        overflowButton.isHidden = true
        gearButton.isHidden = true
        if compactNotes { return }
        switch presentation {
        case .folders:
            gearButton.isHidden = false
        case .trash:
            overflowButton.isHidden = false
        case .notes, .allNotes, .pinnedNotes, .search:
            foldAllButton.isHidden = false
            overflowButton.isHidden = false
            let anyUnfolded = currentListNotes.contains { !$0.isFolded }
            foldAllButton.image = NSImage(systemSymbolName: anyUnfolded ? "chevron.up" : "chevron.down",
                                          accessibilityDescription: "Fold / unfold all")
        }
    }

    // MARK: Reload

    func reload() {
        activeCard = nil
        if isWide, case .folders = presentation {
            presentation = .allNotes
        }
        // Stack rhythm per presentation (rubric §1.6/§1.12): cards sit
        // 10 pt apart with 12 pt side insets; folder-home rows sit
        // 7 pt apart (their rendered margin) with 10 pt side insets.
        let folderHome = presentation == .folders
        stackView.spacing = folderHome ? 7 : 10
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: folderHome ? 10 : 12,
                                            bottom: 12, right: folderHome ? 10 : 12)
        updateChrome()

        switch presentation {
        case .folders:
            clearStack()
            currentListNotes = []
            updateHeader(backVisible: false, captionVisible: false)
            titleLabel.stringValue = "Folders"
            newButton.toolTip = "New folder"
            let allRow = UtilityRowView(symbol: "square.grid.2x2", title: "All Notes",
                                        detail: "\(store.allNotes.count)")
            allRow.onOpen = { [weak self] in self?.openAllNotes() }
            stackView.addArrangedSubview(allRow)
            pinWidth(allRow)
            let pinnedRow = UtilityRowView(symbol: "pin", title: "Pinned",
                                           detail: "\(store.pinnedNoteCount)")
            pinnedRow.onOpen = { [weak self] in self?.openPinnedNotes() }
            stackView.addArrangedSubview(pinnedRow)
            pinWidth(pinnedRow)
            for folder in store.folders {
                let row = folderRow(folder)
                stackView.addArrangedSubview(row)
                pinWidth(row)
            }
            let trash = trashRow()
            stackView.addArrangedSubview(trash)
            pinWidth(trash)
            updateBottomBar(countText: "\(store.folders.count) folder\(store.folders.count == 1 ? "" : "s") · flat list")

        case .notes(let folderID):
            updateHeader(backVisible: true, captionVisible: true)
            titleLabel.stringValue = store.folder(id: folderID)?.name ?? "Notes"
            newButton.toolTip = "New note"
            showNotes(store.notes(in: folderID),
                      emptyState: .folder(name: store.folder(id: folderID)?.name ?? "this folder"))

        case .allNotes:
            updateHeader(backVisible: true, captionVisible: true)
            titleLabel.stringValue = "All Notes"
            newButton.toolTip = "New note"
            showNotes(store.allNotes, emptyState: .message(headline: "No notes yet",
                                                           body: "Notes from every folder will gather here."))

        case .pinnedNotes:
            updateHeader(backVisible: true, captionVisible: true)
            titleLabel.stringValue = "Pinned"
            newButton.toolTip = "New note"
            showNotes(store.pinnedNotes, emptyState: .message(headline: "Nothing pinned yet",
                                                              body: "Pin a note and it will live here."))

        case .trash:
            updateHeader(backVisible: true, captionVisible: false)
            titleLabel.stringValue = "Trash"
            newButton.toolTip = "Empty Trash"
            let trashed = store.trashedNotes
            currentListNotes = trashed
            // Bottom bar first (v0.5.1), for the same reason as showNotes.
            updateBottomBar(countText: "Notes are permanently deleted after 30 days")
            if trashed.isEmpty {
                clearStack()
                let empty = emptyMessageState(headline: "Trash is empty",
                                              body: "Deleted notes stay here for 30 days.")
                stackView.addArrangedSubview(empty)
                pinWidth(empty)
                fillViewport(empty)
            } else {
                updateCardStack(notes: trashed, trash: true)
            }

        case .search(let query):
            updateHeader(backVisible: true, captionVisible: true)
            titleLabel.stringValue = "Search"
            newButton.toolTip = "New note"
            let results = store.search(query)
            currentListNotes = results
            if results.isEmpty {
                clearStack()
                let empty = emptyMessageState(headline: "No notes match “\(query)”", body: "")
                stackView.addArrangedSubview(empty)
                pinWidth(empty)
                fillViewport(empty)
            } else if isCompact {
                updateCompactRows(notes: displaySorted(results))
            } else {
                updateCardStack(notes: displaySorted(results), trash: false)
            }
            updateBottomBar(countText: "\(results.count) result\(results.count == 1 ? "" : "s")")
        }
        if isWide { rebuildRail() }
    }

    private enum ListEmptyState {
        case folder(name: String)
        case message(headline: String, body: String)
    }

    /// Shared path for the note-list presentations: sort, remember the
    /// list, update the bottom bar, then render cards (or compact rows).
    private func showNotes(_ notes: [SNNote], emptyState: ListEmptyState) {
        let display = displaySorted(notes)
        currentListNotes = display
        // The count is applied BEFORE population (v0.5.1): if populating
        // the stack ever fails, the bottom bar still tells the truth
        // instead of keeping the previous view's stale text.
        updateBottomBar(countText: "\(display.count) note\(display.count == 1 ? "" : "s")")
        if display.isEmpty {
            clearStack()
            // An empty list's bottom bar carries the count + overflow
            // only — no fold-all (rubric §2 A9/E-05). updateBottomBar
            // ran above and showed it; hide it for this state.
            foldAllButton.isHidden = true
            let empty: NSView
            switch emptyState {
            case .folder(let name):
                empty = emptyFolderState(folderName: name)
            case .message(let headline, let body):
                empty = emptyMessageState(headline: headline, body: body)
            }
            stackView.addArrangedSubview(empty)
            pinWidth(empty)
            fillViewport(empty)
        } else if isCompact {
            updateCompactRows(notes: display)
        } else {
            updateCardStack(notes: display, trash: false)
        }
    }

    /// Applies the overflow menu's sort choice. Manual order is the
    /// store's own order; the other modes keep pinned notes first
    /// (the package's rail rule) and sort within each group.
    private func displaySorted(_ notes: [SNNote]) -> [SNNote] {
        switch Preferences.sortMode {
        case .manual:
            return notes
        case .newest:
            return notes.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.updatedAt > b.updatedAt
            }
        case .title:
            return notes.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    /// Empty states fill the viewport so their content can centre
    /// vertically in it (audit 4.42).
    private func fillViewport(_ view: NSView) {
        view.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -50).isActive = true
    }

    /// Removes every arranged subview and forgets every cached row.
    private func clearStack() {
        for sub in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        compactRowViews.removeAll()
    }

    /// Populates the card stack with `notes`, in order. v0.5.1 replaced
    /// the v0.1.1 diffed population with this deterministic rebuild —
    /// the same clear-then-add pattern the folder home and Compact rows
    /// use — after the diffed path was found to abort silently during
    /// population on a real install, leaving Standard-density lists
    /// empty while the store counts stayed correct.
    private func updateCardStack(notes: [SNNote], trash: Bool) {
        clearStack()
        for note in notes {
            let v = card(for: note, trash: trash)
            stackView.addArrangedSubview(v)
            pinWidth(v)
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
        let insets = stackView.edgeInsets
        view.widthAnchor.constraint(equalTo: stackView.widthAnchor,
                                    constant: -(insets.left + insets.right)).isActive = true
    }

    private func card(for note: SNNote, trash: Bool = false) -> NSView {
        let cardView = NoteCardView(note: note)
        cardView.isTrashMode = trash
        cardView.isCompactFooter = isCompact
        cardView.onBecomeActive = { [weak self] card in self?.activeCard = card }
        cardView.onReorderDragBegan = { [weak self] card, event in
            guard let self = self, self.reorderEnabled else { return }
            card.beginReorderDrag(with: event)
        }
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

    // MARK: Compact rows (audit 7.1)

    /// Compact density: every note renders as its full card by default
    /// (the everything-expanded default, corrected Nov 27, 2026 —
    /// v0.6.1's one-card accordion reading was wrong). A note renders
    /// as a one-line row only while folded; folding is a manual,
    /// per-note, session-only action (the store resets folds on
    /// load), and double-click or ⏎ on a row unfolds it. Rows are
    /// rebuilt per reload — Compact is a triage surface, and body
    /// edits never trigger structural reloads, so an expanded card's
    /// editor is not disturbed while typing.
    private func updateCompactRows(notes: [SNNote]) {
        clearStack()
        if compactSelectedID == nil { compactSelectedID = notes.first?.id }
        for note in notes {
            if !note.isFolded {
                let cardView = card(for: note, trash: false)
                stackView.addArrangedSubview(cardView)
                pinWidth(cardView)
            } else {
                let row = CompactRowView(note: note, selected: note.id == compactSelectedID)
                compactRowViews[note.id] = row
                row.onSelect = { [weak self] in
                    self?.compactSelectedID = note.id
                    self?.refreshCompactSelection()
                }
                row.onOpen = { [weak self] in
                    self?.compactSelectedID = note.id
                    self?.store.setNoteFolded(id: note.id, folded: false)
                }
                row.translatesAutoresizingMaskIntoConstraints = false
                stackView.addArrangedSubview(row)
                pinWidth(row)
            }
        }
    }

    /// Restyles the live Compact rows for the current selection, in
    /// place. Selection used to reload() (v0.5.1 fix): the rebuild
    /// destroyed the clicked row between the two clicks of a
    /// double-click, so the row's double-click recogniser never saw a
    /// pair and expansion into the full card never fired.
    private func refreshCompactSelection() {
        for (id, row) in compactRowViews {
            row.setSelected(id == compactSelectedID)
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

    // MARK: Folder rail (Wide, audit 7.2)

    private func rebuildRail() {
        for sub in railStack.arrangedSubviews {
            railStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        func railRow(symbol: String, title: String, count: Int?, selected: Bool, action: @escaping () -> Void) {
            let row = RailRowView(symbol: symbol, title: title, count: count, selected: selected)
            row.onOpen = action
            row.translatesAutoresizingMaskIntoConstraints = false
            railStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: railStack.widthAnchor).isActive = true
        }
        railRow(symbol: "note.text", title: "All Notes", count: store.allNotes.count,
                selected: presentation == .allNotes) { [weak self] in self?.openAllNotes() }
        railRow(symbol: "pin", title: "Pinned", count: store.pinnedNoteCount,
                selected: presentation == .pinnedNotes) { [weak self] in self?.openPinnedNotes() }
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = NSAttributedString(
            string: "FOLDERS",
            attributes: [.font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                         .foregroundColor: SNTheme.tertiaryText, .kern: 0.67])
        label.translatesAutoresizingMaskIntoConstraints = false
        railStack.addArrangedSubview(label)
        for folder in store.folders {
            var selected = false
            if case .notes(let id) = presentation, id == folder.id { selected = true }
            railRow(symbol: "folder", title: folder.name, count: store.noteCount(in: folder.id),
                    selected: selected) { [weak self] in self?.openFolder(folder.id) }
        }
        // New Folder sits between the folders and Trash in the
        // package's rendered rail (Nov 26 audit 8.3) — a plus row with
        // no count, wired to the same prompt the folder home uses.
        railRow(symbol: "plus", title: "New Folder", count: nil,
                selected: false) { [weak self] in self?.promptNewFolder() }
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        railStack.addArrangedSubview(spacer)
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        railRow(symbol: "trash", title: "Trash", count: store.trashedNotes.count,
                selected: presentation == .trash) { [weak self] in self?.openTrash() }
    }

    // MARK: Empty states

    /// The designed empty folder (design package): a 54×54 icon tile,
    /// headline, the three-capture-paths teaching line, and a flat
    /// accent New Note button — vertically centred (audits 4.40–4.43).
    /// First-run variant (audit 4.44): the same component, with the
    /// folder name in the headline swapped for a welcome line, shown
    /// until the user has created a note of their own.
    private func emptyFolderState(folderName: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 16
        tile.layer?.backgroundColor = SNTheme.emptyTileBackground.cgColor
        tile.translatesAutoresizingMaskIntoConstraints = false
        let glyph = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage())
        glyph.contentTintColor = SNTheme.tertiaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(glyph)

        let headline = NSTextField(labelWithString: store.hasUserCreatedNote
                                   ? "Nothing in \(folderName) yet"
                                   : "Welcome to SilverNotes")
        headline.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        headline.textColor = SNTheme.primaryText
        headline.alignment = .center

        let body = NSTextField(labelWithString: "Drop a file here, drag text in from any app, or start typing — the first note is one keystroke away.")
        body.font = NSFont.systemFont(ofSize: 12)
        body.textColor = SNTheme.secondaryText
        body.alignment = .center
        body.lineBreakMode = .byWordWrapping
        // The rubric's measure is ~24ch; the app's teaching line is
        // longer than the mockup's copy, so it gets the lines it needs
        // at that measure instead of truncating.
        body.maximumNumberOfLines = 5

        let button = NSButton(title: "New Note", target: self, action: #selector(emptyStateNewNote))
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = SNTheme.accentFill.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [tile, headline, body, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(4, after: tile)
        stack.setCustomSpacing(8, after: body)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 54),
            tile.heightAnchor.constraint(equalToConstant: 54),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 26),
            glyph.heightAnchor.constraint(equalToConstant: 26),
            button.widthAnchor.constraint(equalToConstant: 94),
            button.heightAnchor.constraint(equalToConstant: 30),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            body.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
        ])
        return container
    }

    /// Headline + optional line, centred — Trash and no-results states.
    private func emptyMessageState(headline: String, body: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let headlineLabel = NSTextField(labelWithString: headline)
        headlineLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
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
            bodyLabel.lineBreakMode = .byWordWrapping
            stack.addArrangedSubview(bodyLabel)
            bodyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 210).isActive = true
        }
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
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

    func openAllNotes() {
        presentation = .allNotes
        reload()
        scrollToTop()
    }

    func openPinnedNotes() {
        presentation = .pinnedNotes
        reload()
        scrollToTop()
    }

    // Internal (not private) so the population tests can drive the
    // Trash presentation directly, like openFolder/openAllNotes.
    @objc func openTrash() {
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
            titleLabel.isHidden = false
        }
        presentation = isWide ? .allNotes : .folders
        reload()
    }

    private func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    /// The folder a newly created note lands in: the open folder, or
    /// — from any other presentation — the first folder, which then
    /// becomes the presentation so the new note is on screen.
    private func creationFolderID() -> UUID? {
        switch presentation {
        case .notes(let id): return id
        case .folders, .trash, .search, .allNotes, .pinnedNotes:
            guard let first = store.folders.first else { return nil }
            presentation = .notes(folderID: first.id)
            return first.id
        }
    }

    /// Creates a note in the current folder (or the first folder) and focuses it.
    func createNoteAndFocus() {
        createNoteAndFocus(kind: .text)
    }

    /// Creates a note of the given kind (the + menu's presets) in the
    /// current folder and focuses it. A checklist note's cursor lands
    /// after the first line's "- [ ] " prefix (character 6), ready to
    /// type the first task; every other kind focuses at the end of
    /// its (empty) seed, as a plain text note always has.
    func createNoteAndFocus(kind: NoteKind) {
        guard let folderID = creationFolderID() else { return }
        let note = store.createNote(in: folderID, body: kind.seedBody, mode: kind.mode)
        reload()
        scrollToTop()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for sub in self.stackView.arrangedSubviews {
                if let cardView = self.cardView(in: sub), cardView.noteID == note.id {
                    if kind == .checklist {
                        cardView.focusEditor(cursorAt: 6)
                    } else {
                        cardView.focusEditor()
                    }
                    self.activeCard = cardView
                    return
                }
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
        case .notes, .search, .allNotes, .pinnedNotes:
            showNewNoteMenu()
        }
    }

    /// The + button in a note view offers the note kinds — the
    /// distinct note types the design shows (text, checklist, code,
    /// plain text) — plus a file picker, instead of creating a blank
    /// text note immediately. ⌘N and the empty state's button keep
    /// the instant text-note path (createNoteAndFocus()).
    private func showNewNoteMenu() {
        let menu = NSMenu()
        menu.delegate = self
        for (index, kind) in NoteKind.allCases.enumerated() {
            let item = NSMenuItem(title: kind.displayName, action: #selector(newNoteKindPicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let fileItem = NSMenuItem(title: "File Note…", action: #selector(newFileNotePicked), keyEquivalent: "")
        fileItem.target = self
        menu.addItem(fileItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: newButton.bounds.height + 4), in: newButton)
    }

    @objc private func newNoteKindPicked(_ sender: NSMenuItem) {
        guard NoteKind.allCases.indices.contains(sender.tag) else { return }
        createNoteAndFocus(kind: NoteKind.allCases[sender.tag])
    }

    /// "File Note…": one new note carrying every picked file as an
    /// attachment — images embedded, other files linked, exactly as
    /// if they had been dropped onto the panel.
    @objc private func newFileNotePicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        PanelController.shared.beginChildInteraction()
        panel.begin { [weak self] result in
            PanelController.shared.endChildInteraction()
            guard let self = self, result == .OK, !panel.urls.isEmpty else { return }
            guard let folderID = self.creationFolderID() else { return }
            let note = self.store.createNote(in: folderID)
            for url in panel.urls {
                self.store.addAttachment(noteID: note.id, from: url, origin: nil)
            }
            self.reload()
            self.scrollToTop()
        }
    }

    @objc private func toggleSearchField() {
        searchField.isHidden.toggle()
        // The field takes the title's place in the pill while open
        // (v0.6.0): that is what gives it room for the full
        // placeholder at Standard width.
        titleLabel.isHidden = !searchField.isHidden
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

    // MARK: Capture (Compact)

    @objc private func captureSubmitted() {
        let text = captureField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let folderID: UUID
        switch presentation {
        case .notes(let id): folderID = id
        default:
            guard let first = store.folders.first else { return }
            folderID = first.id
        }
        let note = store.createNote(in: folderID, body: text)
        captureField.stringValue = ""
        compactSelectedID = note.id
        reload()
    }

    // MARK: Bottom bar actions

    @objc private func foldAllTapped() {
        let anyUnfolded = currentListNotes.contains { !$0.isFolded }
        store.setFolded(ids: currentListNotes.map(\.id), folded: anyUnfolded)
    }

    /// The overflow (•••) menu. The package's component inventory names
    /// its contents as "(sort, export folder)"; combined with the pin
    /// toggle that left the header (audit 4.6) and the Settings /
    /// Check-for-Updates entries, the menu is: Pin Panel Open · Sort by
    /// Manual/Newest/Title · Export … as Markdown… · Check for
    /// Updates… · Settings….
    @objc private func showOverflowMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.delegate = self
        let pinItem = NSMenuItem(title: "Pin Panel Open", action: #selector(togglePinFromMenu), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = Preferences.panelPinned ? .on : .off
        menu.addItem(pinItem)
        menu.addItem(.separator())
        let sortTitles: [(NoteSortMode, String)] = [(.manual, "Sort by Manual Order"),
                                                    (.newest, "Sort by Newest First"),
                                                    (.title, "Sort by Title")]
        for (mode, title) in sortTitles {
            let item = NSMenuItem(title: title, action: #selector(pickSortMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = Preferences.sortMode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if presentation != .trash {
            let exportItem = NSMenuItem(title: exportMenuTitle, action: #selector(exportCurrentList), keyEquivalent: "")
            exportItem.target = self
            menu.addItem(exportItem)
            menu.addItem(.separator())
        }
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private var exportMenuTitle: String {
        switch presentation {
        case .notes: return "Export Folder as Markdown…"
        case .allNotes: return "Export All Notes as Markdown…"
        case .pinnedNotes: return "Export Pinned Notes as Markdown…"
        case .search: return "Export Results as Markdown…"
        case .folders, .trash: return "Export Notes as Markdown…"
        }
    }

    @objc private func togglePinFromMenu() {
        Preferences.panelPinned.toggle()
    }

    @objc private func pickSortMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = NoteSortMode(rawValue: raw) else { return }
        Preferences.sortMode = mode
        reload()
    }

    @objc private func checkForUpdatesFromMenu() {
        SettingsController.shared.showAndCheckForUpdates()
    }

    @objc private func exportCurrentList() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose where to write the Markdown files."
        PanelController.shared.beginChildInteraction()
        panel.begin { [weak self] result in
            PanelController.shared.endChildInteraction()
            guard let self = self, result == .OK, let directory = panel.url else { return }
            var usedNames: Set<String> = []
            for note in self.currentListNotes {
                var base = note.title
                    .replacingOccurrences(of: "/", with: "-")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if base.isEmpty { base = "Untitled note" }
                var name = base
                var counter = 2
                while usedNames.contains(name.lowercased()) {
                    name = "\(base) \(counter)"
                    counter += 1
                }
                usedNames.insert(name.lowercased())
                let url = directory.appendingPathComponent(name + ".md")
                try? note.body.write(to: url, atomically: true, encoding: .utf8)
            }
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

    // MARK: Panel-level drop target (audit 6.10)

    private func panelDragEntered() -> NSDragOperation {
        dropOverlay.isHidden = false
        return .copy
    }

    private func panelDragPerformed(_ info: NSDraggingInfo) -> Bool {
        dropOverlay.isHidden = true
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        let folderID: UUID
        switch presentation {
        case .notes(let id): folderID = id
        default:
            guard let first = store.folders.first else { return false }
            folderID = first.id
        }
        if case .folders = presentation {
            presentation = .notes(folderID: folderID)
        }
        let note = store.createNote(in: folderID)
        var added = false
        for url in urls {
            if store.addAttachment(noteID: note.id, from: url, origin: "dropped in from Finder") != nil { added = true }
        }
        reload()
        return added
    }

    // MARK: Reorder drag & drop (audit 6.14)

    /// Reorder only makes sense against the manual order in a plain
    /// note list — not in Trash/Search, not under a sort override, and
    /// not in Compact density (rows there are not cards, so the drop
    /// index math has nothing to count against).
    private var reorderEnabled: Bool {
        guard Preferences.sortMode == .manual, Preferences.density == .standard else { return false }
        switch presentation {
        case .notes, .allNotes, .pinnedNotes: return true
        case .folders, .trash, .search: return false
        }
    }

    private func noteDragUpdate(_ info: NSDraggingInfo) -> NSDragOperation {
        guard reorderEnabled,
              let raw = info.draggingPasteboard.string(forType: .snNote),
              let draggedID = UUID(uuidString: raw),
              currentListNotes.contains(where: { $0.id == draggedID }) else { return [] }
        let location = stackView.convert(info.draggingLocation, from: nil)
        var index = currentListNotes.count
        var noteIndex = 0
        for sub in stackView.arrangedSubviews {
            guard noteIndex < currentListNotes.count else { break }
            // Only card entries correspond to notes (in order).
            if cardView(in: sub) != nil || sub is NoteCardView {
                if location.y < sub.frame.midY {
                    index = noteIndex
                    break
                }
                noteIndex += 1
            }
        }
        pendingInsertIndex = index
        return .move
    }

    private func noteDrop(_ info: NSDraggingInfo) -> Bool {
        guard reorderEnabled,
              let raw = info.draggingPasteboard.string(forType: .snNote),
              let draggedID = UUID(uuidString: raw),
              let fromIndex = currentListNotes.firstIndex(where: { $0.id == draggedID }),
              let target = pendingInsertIndex else { return false }
        pendingInsertIndex = nil
        var notes = currentListNotes
        let dragged = notes.remove(at: fromIndex)
        var insertion = target
        if insertion > fromIndex { insertion -= 1 }
        // Clamp inside the dragged note's pinned group: pinned notes
        // group first, and a drag never crosses that boundary.
        let groupIndices = notes.indices.filter { notes[$0].isPinned == dragged.isPinned }
        guard let first = groupIndices.first, let last = groupIndices.last else { return false }
        insertion = min(max(insertion, first), last + 1)
        notes.insert(dragged, at: insertion)
        store.assignOrder(ids: notes.map(\.id))
        return true
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

    /// Handles ⌥⌘P (pin), ⌥⌘⏎ (fold), ⌥⌘1/2/3 (mode) for the active card,
    /// ⌘F (search), and Compact's ↑/↓/⏎ row navigation.
    /// Returns true if the key was consumed.
    func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        // Compact navigation (audit 7.1): ↑/↓ move between rows and ⏎
        // opens the selected row — but never while editing text.
        if isCompact, presentation != .folders, presentation != .trash,
           !(view.window?.firstResponder is NSTextView) {
            switch event.keyCode {
            case 126: // ↑
                moveCompactSelection(by: -1)
                return true
            case 125: // ↓
                moveCompactSelection(by: 1)
                return true
            case 36: // ⏎
                if let id = compactSelectedID, let note = store.note(id: id) {
                    store.setNoteFolded(id: id, folded: !note.isFolded)
                }
                return true
            default:
                break
            }
        }
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option),
           (event.charactersIgnoringModifiers ?? "") == "f" {
            toggleSearchField()
            return true
        }
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

    private func moveCompactSelection(by delta: Int) {
        guard !currentListNotes.isEmpty else { return }
        let current = currentListNotes.firstIndex(where: { $0.id == compactSelectedID }) ?? 0
        let next = min(max(current + delta, 0), currentListNotes.count - 1)
        compactSelectedID = currentListNotes[next].id
        refreshCompactSelection()
    }
}

/// The panel's root visual-effect view, doubling as the panel-level
/// file drop target (audit 6.10) — drops that land on a card are the
/// card's own; drops anywhere else in the panel land here.
final class PanelRootView: NSVisualEffectView {
    var onDragEntered: (() -> NSDragOperation)?
    var onDragExited: (() -> Void)?
    var onDragPerformed: ((NSDraggingInfo) -> Bool)?
    /// Fired when the panel's effective appearance flips (e.g. the
    /// system switches light/dark on a schedule): the controller
    /// re-bakes its layer-backed theme surfaces in response.
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?() ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragPerformed?(sender) ?? false
    }
}

/// NSScrollView document views are not flipped by default; this makes the
/// card stack grow downward from the top. It is also the drop target for
/// note-reorder drags (audit 6.14).
private final class FlippedView: NSView {
    var onNoteDragUpdate: ((NSDraggingInfo) -> NSDragOperation)?
    var onNoteDrop: ((NSDraggingInfo) -> Bool)?

    override var isFlipped: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onNoteDragUpdate?(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onNoteDragUpdate?(sender) ?? []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onNoteDrop?(sender) ?? false
    }
}

/// One Compact-density row (audit 7.1): pin state, first line,
/// timestamp — one line, on a translucent card surface; the selected
/// row is solid with an accent outline.
private final class CompactRowView: NSView {
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    /// The last selection state applied, so an appearance change can
    /// re-apply the same state's styling (its colors are dynamic).
    private var isSelected = false

    init(note: SNNote, selected: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        setSelected(selected)

        let pin = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") ?? NSImage())
        pin.contentTintColor = SNTheme.pinnedActive
        pin.isHidden = !note.isPinned
        pin.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: note.title)
        title.font = NSFont.systemFont(ofSize: 12.5)
        title.textColor = SNTheme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let time = NSTextField(labelWithString: CompactRowView.timeText(for: note.updatedAt))
        time.font = NSFont.systemFont(ofSize: 10.5)
        time.textColor = SNTheme.tertiaryText
        time.translatesAutoresizingMaskIntoConstraints = false

        addSubview(pin); addSubview(title); addSubview(time)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            pin.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pin.centerYAnchor.constraint(equalTo: centerYAnchor),
            pin.widthAnchor.constraint(equalToConstant: 11),
            pin.heightAnchor.constraint(equalToConstant: 11),
            title.leadingAnchor.constraint(equalTo: pin.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -8),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked))
        addGestureRecognizer(click)
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(rowDoubleClicked))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)
    }

    required init?(coder: NSCoder) {
        // Rows are only ever built in code; this exists to satisfy NSCoding.
        super.init(coder: coder)
    }

    /// Applies the selected / unselected layer styling. Extracted from
    /// init (v0.5.1) so selection changes can restyle a live row in
    /// place instead of rebuilding the row list.
    func setSelected(_ selected: Bool) {
        isSelected = selected
        if selected {
            layer?.backgroundColor = SNTheme.cardBackground.cgColor
            layer?.borderWidth = 1.5
            layer?.borderColor = SNTheme.accent.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = SNTheme.cardBackground.withAlphaComponent(0.65).cgColor
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The state styling bakes CGColors from dynamic theme
        // colors; re-apply the current state's styling so it
        // resolves under the new appearance.
        setSelected(isSelected)
    }

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

    static func timeText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return timeFormatter.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return weekdayFormatter.string(from: date)
    }

    @objc private func rowClicked() { onSelect?() }
    @objc private func rowDoubleClicked() { onOpen?() }
}

/// One folder-rail row in Wide (audit 7.2): 13 pt glyph, 12 pt name,
/// tertiary count; the selected row takes the accent wash + bold.
private final class RailRowView: NSView {
    var onOpen: (() -> Void)?
    private let isSelected: Bool

    init(symbol: String, title: String, count: Int?, selected: Bool) {
        isSelected = selected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        refreshSurfaces()

        let glyph = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        glyph.contentTintColor = selected ? SNTheme.accent : SNTheme.secondaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: title)
        name.font = NSFont.systemFont(ofSize: 12, weight: selected ? .bold : .regular)
        name.textColor = SNTheme.primaryText
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glyph); addSubview(name)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 13),
            glyph.heightAnchor.constraint(equalToConstant: 13),
            name.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 7),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if let count = count {
            let countLabel = NSTextField(labelWithString: "\(count)")
            countLabel.font = NSFont.systemFont(ofSize: 10.5)
            countLabel.textColor = SNTheme.tertiaryText
            countLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(countLabel)
            NSLayoutConstraint.activate([
                countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
                countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                name.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -4),
            ])
        } else {
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -7).isActive = true
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) {
        isSelected = false
        super.init(coder: coder)
    }

    /// The selected row's accent wash is a dynamic theme color baked
    /// into the layer; re-bake it when the appearance flips, like the
    /// other row classes (v0.7.1).
    private func refreshSurfaces() {
        if isSelected {
            layer?.backgroundColor = SNTheme.accent.withAlphaComponent(0.16).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshSurfaces()
    }

    @objc private func rowClicked() { onOpen?() }
}

/// A clickable folder row with a context menu (pin / rename / delete).
private final class FolderRowView: NSView {
    var onOpen: (() -> Void)?
    var onPin: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    /// The icon tile. Stored so refreshSurfaces can re-bake its
    /// layer color on an appearance change.
    private let tile = NSView()

    init(folder: SNFolder, count: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        // Rendered package: radius 10 (audit 1.12), NO border — the
        // row lifts on a single soft shadow, 0 1 3 rgba(20,22,30,0.06)
        // (rubric §1.12; CSS blur halved into shadowRadius as usual).
        layer?.cornerRadius = 10
        layer?.shadowColor = NSColor(srgbRed: 20/255, green: 22/255, blue: 30/255, alpha: 1).cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 1.5
        layer?.shadowOffset = NSSize(width: 0, height: -1)

        // Plain rows, no folder colours (design package): an accent-soft
        // tile with a folder glyph carries the row instead.
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        refreshSurfaces()
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
        // Rendered package: 13 pt at weight 600 (audit 3.8).
        name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        name.textColor = SNTheme.primaryText
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = NSTextField(labelWithString: "\(count)")
        countLabel.font = NSFont.systemFont(ofSize: 11)
        // Rendered package: #8E8E96 (audit 3.9).
        countLabel.textColor = SNTheme.tertiaryText
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSTextField(labelWithString: "›")
        chevron.font = NSFont.systemFont(ofSize: 14)
        chevron.textColor = SNTheme.rowChevron
        chevron.translatesAutoresizingMaskIntoConstraints = false

        // Tile + optional pin + name in a stack, so a hidden pin
        // collapses instead of leaving a gap.
        let leftStack = NSStackView(views: [tile, pin, name])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 10
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftStack); addSubview(countLabel); addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 50),
            tile.widthAnchor.constraint(equalToConstant: 30),
            tile.heightAnchor.constraint(equalToConstant: 30),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            glyph.heightAnchor.constraint(equalToConstant: 16),
            pin.widthAnchor.constraint(equalToConstant: 10),
            pin.heightAnchor.constraint(equalToConstant: 10),
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),
            countLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
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

    /// (Re)applies the layer-baked theme surfaces. A CGColor bakes
    /// the dynamic color's then-current variant, so this runs at
    /// build time and again on every appearance change — otherwise
    /// a row built in light mode keeps its white card surface under
    /// dark mode's near-white name text.
    private func refreshSurfaces() {
        layer?.backgroundColor = SNTheme.cardBackground.cgColor
        tile.layer?.backgroundColor = SNTheme.accentSoftBackground.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshSurfaces()
    }

    @objc private func rowClicked() { onOpen?() }
    @objc private func menuPin() { onPin?() }
    @objc private func menuRename() { onRename?() }
    @objc private func menuDelete() { onDelete?() }
}

/// A folder-home row in the same plain style as FolderRowView, for the
/// fixed destinations (All Notes, Pinned, Trash): icon tile, name, an
/// optional secondary detail at the right, chevron.
private final class UtilityRowView: NSView {
    var onOpen: (() -> Void)?

    /// The icon tile. Stored so refreshSurfaces can re-bake its
    /// layer color on an appearance change.
    private let tile = NSView()

    init(symbol: String, title: String, detail: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        // Same no-border + soft-shadow treatment as FolderRowView
        // (rubric §1.12).
        layer?.shadowColor = NSColor(srgbRed: 20/255, green: 22/255, blue: 30/255, alpha: 1).cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 1.5
        layer?.shadowOffset = NSSize(width: 0, height: -1)

        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        refreshSurfaces()
        tile.translatesAutoresizingMaskIntoConstraints = false
        let glyph = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        glyph.contentTintColor = SNTheme.accent
        glyph.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(glyph)

        let name = NSTextField(labelWithString: title)
        name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        name.textColor = SNTheme.primaryText
        name.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail ?? "")
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = SNTheme.tertiaryText
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSTextField(labelWithString: "›")
        chevron.font = NSFont.systemFont(ofSize: 14)
        chevron.textColor = SNTheme.rowChevron
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tile); addSubview(name); addSubview(detailLabel); addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 50),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 30),
            tile.heightAnchor.constraint(equalToConstant: 30),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 16),
            glyph.heightAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) {
        // Rows are only ever built in code; this exists to satisfy NSCoding.
        super.init(coder: coder)
    }

    /// (Re)applies the layer-baked theme surfaces — see
    /// FolderRowView.refreshSurfaces for why this must run again on
    /// every appearance change, not just at build time.
    private func refreshSurfaces() {
        layer?.backgroundColor = SNTheme.cardBackground.cgColor
        tile.layer?.backgroundColor = SNTheme.accentSoftBackground.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshSurfaces()
    }

    @objc private func rowClicked() { onOpen?() }
}
