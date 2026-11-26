import AppKit

/// The note gear menu, built to the design package instead of stock
/// NSMenu chrome (audits 1.9, 2.27, 4.18, 5.3): a 218 pt custom panel,
/// radius 10, near-opaque surface, 12.5 pt items, 10.5 pt uppercase
/// section labels in the tertiary grey, accent checkmarks, 11.5 pt
/// shortcut text, an accent hover wash, and a 140 ms appear animation
/// (scale 0.97 → 1 + fade). Same items and actions as the old NSMenu:
/// Pin ⌥⌘P, Fold ⌥⌘⏎, the COLOUR swatch row, MODE Standard/Plain/Code
/// ⌥⌘1/2/3, Clear Completed Tasks, Export Note as Markdown….
final class GearMenu: NSObject {

    struct Actions {
        var onPin: () -> Void
        var onFold: () -> Void
        var onColor: (NoteColorToken) -> Void
        var onMode: (NoteMode) -> Void
        var onClearCompletedTasks: () -> Void
        var onExport: () -> Void
    }

    private static let shared = GearMenu()
    private var panel: NSPanel?
    private var actions: Actions?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var isOpen = false

    static func show(relativeTo anchor: NSView,
                     isPinned: Bool, isFolded: Bool,
                     color: NoteColorToken, mode: NoteMode,
                     actions: Actions) {
        shared.present(relativeTo: anchor, isPinned: isPinned, isFolded: isFolded,
                       color: color, mode: mode, actions: actions)
    }

    static func dismissIfOpen() {
        if shared.isOpen { shared.dismiss(runAction: nil) }
    }

    // MARK: Build

    private func present(relativeTo anchor: NSView,
                         isPinned: Bool, isFolded: Bool,
                         color: NoteColorToken, mode: NoteMode,
                         actions: Actions) {
        dismiss(runAction: nil)
        self.actions = actions

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = SNTheme.gearMenuBackground.cgColor
        content.layer?.cornerRadius = 10
        content.layer?.borderWidth = 1
        content.layer?.borderColor = SNTheme.gearMenuBorder.cgColor
        content.layer?.shadowColor = NSColor(srgbRed: 15/255, green: 20/255, blue: 35/255, alpha: 1).cgColor
        content.layer?.shadowOpacity = 0.28
        content.layer?.shadowRadius = 20
        content.layer?.shadowOffset = NSSize(width: 0, height: -14)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -5),
            stack.widthAnchor.constraint(equalToConstant: 208),
        ])

        func row(_ title: String, checked: Bool, shortcut: String?, action: @escaping () -> Void) {
            let item = GearMenuRowView(title: title, checked: checked, shortcut: shortcut)
            item.onClick = { [weak self] in self?.dismiss(runAction: action) }
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        func separator() {
            // The package's separator carries its 5 pt margin on both
            // sides (rubric §1.11). NSStackView only sets custom
            // spacing AFTER a view, so the top margin is applied to
            // the preceding row here; the bottom one is set after the
            // line itself, below.
            if let previous = stack.arrangedSubviews.last {
                stack.setCustomSpacing(5, after: previous)
            }
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = SNTheme.gearMenuSeparator.cgColor
            line.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(line)
            NSLayoutConstraint.activate([
                line.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
                line.heightAnchor.constraint(equalToConstant: 1),
            ])
            // Separators carry the package's vertical rhythm via the
            // stack's custom spacing after them. (The stack left-aligns
            // the line; its width above insets the right side to match.)
            stack.setCustomSpacing(5, after: line)
        }
        func sectionLabel(_ title: String) {
            let label = NSTextField(labelWithString: "")
            label.attributedStringValue = NSAttributedString(
                string: title.uppercased(),
                attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                             .foregroundColor: SNTheme.tertiaryText,
                             .kern: 0.63])
            label.translatesAutoresizingMaskIntoConstraints = false
            let padded = NSView()
            padded.translatesAutoresizingMaskIntoConstraints = false
            padded.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: padded.leadingAnchor, constant: 8),
                label.topAnchor.constraint(equalTo: padded.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: padded.bottomAnchor, constant: -2),
            ])
            stack.addArrangedSubview(padded)
            padded.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        row("Pin", checked: isPinned, shortcut: "⌥⌘P") { [weak self] in self?.actions?.onPin() }
        row("Fold", checked: isFolded, shortcut: "⌥⌘⏎") { [weak self] in self?.actions?.onFold() }
        separator()
        sectionLabel("Colour")
        stack.addArrangedSubview(swatchRow(active: color))
        separator()
        sectionLabel("Mode")
        let modeTitles: [NoteMode: String] = [.standard: "Standard", .plain: "Plain Text", .code: "Code"]
        for (index, noteMode) in NoteMode.allCases.enumerated() {
            row(modeTitles[noteMode] ?? noteMode.displayName,
                checked: mode == noteMode,
                shortcut: "⌥⌘\(index + 1)") { [weak self] in self?.actions?.onMode(noteMode) }
        }
        separator()
        row("Clear Completed Tasks", checked: false, shortcut: nil) { [weak self] in self?.actions?.onClearCompletedTasks() }
        row("Export Note as Markdown…", checked: false, shortcut: nil) { [weak self] in self?.actions?.onExport() }

        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: 218, height: content.fittingSize.height)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.isReleasedWhenClosed = false
        self.panel = panel

        position(panel, size: size, relativeTo: anchor)
        PanelController.shared.beginChildInteraction()
        isOpen = true

        // Appear: 140 ms, scale 0.97 → 1 + fade (audit 5.3).
        panel.alphaValue = 0
        content.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            content.layer?.transform = CATransform3DIdentity
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.dismiss(runAction: nil)
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isOpen else { return event }
            if event.keyCode == 53 { // Esc dismisses the menu first
                self.dismiss(runAction: nil)
                return nil
            }
            return event
        }
    }

    /// Below the anchor button, flipped above it when the screen's
    /// bottom is too close; shifted left if it would run off the edge.
    private func position(_ panel: NSPanel, size: NSSize, relativeTo anchor: NSView) {
        guard let window = anchor.window else { return }
        let anchorScreen = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? anchorScreen
        var x = anchorScreen.minX
        if x + size.width > visible.maxX - 4 { x = visible.maxX - size.width - 4 }
        var y = anchorScreen.minY - 4 - size.height
        if y < visible.minY + 4 { y = anchorScreen.maxY + 4 }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    private func swatchRow(active: NoteColorToken) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        let tokens = NoteColorToken.gearMenuOrder
        var x: CGFloat = 8
        for token in tokens {
            let frame = NSRect(x: x, y: 2, width: 19, height: 19)
            let button = NSButton(frame: frame)
            button.title = ""
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 9.5
            button.layer?.backgroundColor = SNTheme.swatch(for: token).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = SNTheme.swatchBorder.cgColor
            button.toolTip = token.displayName
            button.target = self
            button.action = #selector(swatchClicked(_:))
            button.identifier = NSUserInterfaceItemIdentifier(token.rawValue)
            rowView.addSubview(button)
            if token == active {
                // Selected: 2 pt accent ring outset 4 pt (audit 4.14) —
                // an overlay ring, so the swatch itself stays 19×19.
                let ring = NSView(frame: frame.insetBy(dx: -4, dy: -4))
                ring.wantsLayer = true
                ring.layer?.cornerRadius = 13.5
                ring.layer?.borderWidth = 2
                ring.layer?.borderColor = SNTheme.accent.cgColor
                rowView.addSubview(ring)
            }
            x += 19 + 6
        }
        rowView.heightAnchor.constraint(equalToConstant: 27).isActive = true
        return rowView
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let token = NoteColorToken(rawValue: raw) else { return }
        dismiss(runAction: { [weak self] in self?.actions?.onColor(token) })
    }

    private func dismiss(runAction: (() -> Void)?) {
        guard isOpen else { return }
        isOpen = false
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor); globalClickMonitor = nil }
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor); localKeyMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
        // Keep the panel's auto-hide suspended a beat past dismissal so
        // the click that closed the menu doesn't also close the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            PanelController.shared.endChildInteraction()
        }
        runAction?()
        if runAction != nil { actions = nil }
    }
}

/// One clickable row of the custom gear menu: accent check slot, title,
/// right-aligned shortcut, accent hover wash.
private final class GearMenuRowView: NSView {
    var onClick: (() -> Void)?

    init(title: String, checked: Bool, shortcut: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false

        let check = NSTextField(labelWithString: checked ? "✓" : "")
        check.font = NSFont.systemFont(ofSize: 12.5, weight: .heavy)
        check.textColor = SNTheme.accent
        check.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5)
        titleLabel.textColor = SNTheme.gearMenuText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(check)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if let shortcut = shortcut {
            let label = NSTextField(labelWithString: shortcut)
            label.font = NSFont.systemFont(ofSize: 11.5)
            label.textColor = SNTheme.tertiaryText
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) {
        // Rows are only ever built in code; this exists to satisfy NSCoding.
        super.init(coder: coder)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        layer?.backgroundColor = SNTheme.gearMenuHover.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
