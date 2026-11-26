import AppKit
import ServiceManagement

/// Settings window for SilverNotes (audit 4.45): a sidebar window with
/// five panes — General / Appearance / Editor / Backups / Shortcuts.
///
/// General carries launch at login (real, via SMAppService on macOS
/// 13+), Hot Side, panel side (per-display, audit 6.13), the
/// Standard/Wide width step (7.2), pin panel open (4.50), Check for
/// Updates (GitHub Releases, via UpdateChecker), and the version
/// footer. Appearance carries the note-colour style
/// (2.19) and the Compact density (7.1). Editor carries Show Markdown
/// markup and the body font size (3.14). Backups surfaces the store's
/// backup rotation read-only (4.52). Shortcuts is a read-only list.
///
/// HARD DISCIPLINE (the v0.2.1 crash): buildWindow creates EVERY
/// control in EVERY pane first, and only then runs any refresh —
/// refreshLaunchAtLoginState() writes statusLabel in every branch, and
/// refreshing before the label exists trapped on first open in
/// v0.1.0–v0.2.0.
final class SettingsController: NSObject, NSWindowDelegate {

    static let shared = SettingsController()

    private var window: NSWindow?
    private var paneViews: [NSView] = []
    private var sidebarButtons: [NSButton] = []

    // General pane
    private var launchAtLoginCheckbox: NSButton!
    private var statusLabel: NSTextField!
    private var updateButton: NSButton!
    private var updateStatusLabel: NSTextField!
    /// Non-nil while the update button means "install this version"
    /// rather than "check"; set by a check that found a newer release.
    private var pendingInstallVersion: String?

    // Editor pane
    private var fontSizeLabel: NSTextField!
    private var fontSizeStepper: NSStepper!

    // Backups pane
    private var backupsCountLabel: NSTextField!
    private var backupsRecentLabel: NSTextField!

    private override init() { super.init() }

    func show() {
        if window == nil { buildWindow() }
        PanelController.shared.beginChildInteraction()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The status menu's "Check for Updates…" path: open Settings and
    /// start the same check the button runs.
    func showAndCheckForUpdates() {
        show()
        selectPane(0)
        runUpdateCheck()
    }

    func windowWillClose(_ notification: Notification) {
        PanelController.shared.endChildInteraction()
    }

    // MARK: Window construction

    private func buildWindow() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 430))
        content.wantsLayer = true
        content.layer?.backgroundColor = SNTheme.settingsWindowBackground.cgColor

        // Sidebar: five rows, the selected one on the accent (the
        // package's .srow.sel). Width is the package's 38% of the
        // window (rubric §1.16); its surface and right border are the
        // package's #ECECF1 / #DDDDE3.
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 236, height: 430))
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = SNTheme.settingsSidebarBackground.cgColor
        content.addSubview(sidebar)
        let paneSpecs: [(String, String)] = [
            ("gearshape", "General"),
            ("paintpalette", "Appearance"),
            ("list.bullet", "Editor"),
            ("clock.arrow.circlepath", "Backups"),
            ("command", "Shortcuts"),
        ]
        for (index, spec) in paneSpecs.enumerated() {
            let symbol = NSImage(systemSymbolName: spec.0, accessibilityDescription: spec.1) ?? NSImage()
            let button = NSButton(title: "  \(spec.1)",
                                  image: symbol,
                                  target: self, action: #selector(paneButtonClicked(_:)))
            button.tag = index
            button.bezelStyle = .inline
            button.isBordered = false
            button.alignment = .left
            button.imagePosition = .imageLeading
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.frame = NSRect(x: 8, y: 430 - 34 - 26 - index * 26, width: 220, height: 26)
            sidebar.addSubview(button)
            sidebarButtons.append(button)
        }
        let sidebarBorder = NSView(frame: NSRect(x: 235, y: 0, width: 1, height: 430))
        sidebarBorder.wantsLayer = true
        sidebarBorder.layer?.backgroundColor = SNTheme.settingsSidebarBorder.cgColor
        content.addSubview(sidebarBorder)

        // Panes — ALL built before any refresh runs (see header note).
        let paneFrame = NSRect(x: 236, y: 0, width: 384, height: 430)
        paneViews = [buildGeneralPane(frame: paneFrame),
                     buildAppearancePane(frame: paneFrame),
                     buildEditorPane(frame: paneFrame),
                     buildBackupsPane(frame: paneFrame),
                     buildShortcutsPane(frame: paneFrame)]
        for pane in paneViews {
            pane.isHidden = true
            content.addSubview(pane)
        }

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "SilverNotes Settings"
        win.contentView = content
        win.delegate = self
        win.isReleasedWhenClosed = false
        window = win

        selectPane(0)
        // Refreshes run LAST, once every control they can touch exists.
        refreshLaunchAtLoginState()
        refreshBackupsPane()
        refreshFontSizeLabel()
    }

    @objc private func paneButtonClicked(_ sender: NSButton) {
        selectPane(sender.tag)
    }

    private func selectPane(_ index: Int) {
        for (i, pane) in paneViews.enumerated() {
            pane.isHidden = i != index
        }
        for (i, button) in sidebarButtons.enumerated() {
            let selected = i == index
            button.layer?.backgroundColor = selected ? SNTheme.accentFill.cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? .white : SNTheme.primaryText
        }
        if index == 3 { refreshBackupsPane() }
    }

    // MARK: Pane builders

    /// Vertical space helpers for the frame-based panes (y measured
    /// from the pane's bottom, as in AppKit).
    private func paneLabel(_ text: String, in pane: NSView, y: CGFloat, bold: Bool = false, size: CGFloat = 12) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size)
        field.textColor = SNTheme.primaryText
        field.frame = NSRect(x: 14, y: y, width: 336, height: 18)
        pane.addSubview(field)
        return field
    }

    private func paneCheckbox(_ title: String, in pane: NSView, y: CGFloat, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.font = NSFont.systemFont(ofSize: 12)
        button.frame = NSRect(x: 14, y: y, width: 336, height: 20)
        pane.addSubview(button)
        return button
    }

    private func paneTitle(_ text: String, in pane: NSView) {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        field.textColor = SNTheme.primaryText
        field.frame = NSRect(x: 14, y: 392, width: 336, height: 20)
        pane.addSubview(field)
    }

    private func buildGeneralPane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        paneTitle("General", in: pane)

        // Created before refreshLaunchAtLoginState() can ever run —
        // the refresh writes this label in every branch (v0.2.1 fix).
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = SNTheme.secondaryText
        statusLabel.frame = NSRect(x: 14, y: 330, width: 336, height: 18)
        pane.addSubview(statusLabel)

        launchAtLoginCheckbox = paneCheckbox("Launch at login (starts hidden, panel closed)",
                                             in: pane, y: 354, action: #selector(launchAtLoginChanged(_:)))

        // Title shortened in v0.6.0 so it fits the narrower pane the
        // package's 38% sidebar leaves — same meaning, fewer words.
        let hotSide = paneCheckbox("Hot Side — hold the pointer at the screen edge to open",
                                   in: pane, y: 302, action: #selector(hotSideChanged(_:)))
        hotSide.state = Preferences.hotSideEnabled ? .on : .off

        _ = paneLabel("Dock panel to (remembered per display):", in: pane, y: 272)
        let sideControl = NSSegmentedControl(labels: ["Left", "Right"], trackingMode: .selectOne,
                                             target: self, action: #selector(sideChanged(_:)))
        let mainScreen = NSScreen.main ?? NSScreen.screens[0]
        sideControl.selectedSegment = Preferences.effectivePanelSide(for: mainScreen) == .right ? 1 : 0
        sideControl.frame = NSRect(x: 14, y: 244, width: 160, height: 24)
        pane.addSubview(sideControl)

        let pin = paneCheckbox("Pin panel open (disables click-outside hide)",
                               in: pane, y: 210, action: #selector(pinChanged(_:)))
        pin.state = Preferences.panelPinned ? .on : .off

        _ = paneLabel("Panel width:", in: pane, y: 180)
        let widthControl = NSSegmentedControl(labels: ["Standard", "Wide"], trackingMode: .selectOne,
                                              target: self, action: #selector(widthChanged(_:)))
        widthControl.selectedSegment = Preferences.panelWidth == .wide ? 1 : 0
        widthControl.frame = NSRect(x: 14, y: 152, width: 160, height: 24)
        pane.addSubview(widthControl)

        // The update row moved up in v0.5.0 to close the gap left by a
        // removed block, so the pane keeps its spacing rhythm instead
        // of leaving a hole above the version footer.
        updateButton = NSButton(title: "Check for Updates…", target: self,
                                action: #selector(updateButtonClicked))
        updateButton.bezelStyle = .rounded
        updateButton.frame = NSRect(x: 14, y: 102, width: 168, height: 24)
        pane.addSubview(updateButton)

        updateStatusLabel = NSTextField(labelWithString: "")
        updateStatusLabel.font = NSFont.systemFont(ofSize: 11)
        updateStatusLabel.textColor = SNTheme.secondaryText
        updateStatusLabel.frame = NSRect(x: 190, y: 105, width: 180, height: 18)
        pane.addSubview(updateStatusLabel)

        let version = NSTextField(labelWithString: "SilverNotes v0.6.0")
        version.font = NSFont.systemFont(ofSize: 11)
        version.textColor = SNTheme.secondaryText
        version.frame = NSRect(x: 14, y: 16, width: 336, height: 16)
        pane.addSubview(version)
        return pane
    }

    private func buildAppearancePane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        paneTitle("Appearance", in: pane)

        _ = paneLabel("Note colour shows as:", in: pane, y: 354)
        let colorControl = NSSegmentedControl(labels: ["Full card", "Left bar"], trackingMode: .selectOne,
                                              target: self, action: #selector(colorStyleChanged(_:)))
        colorControl.selectedSegment = Preferences.colorStyle == .leftBar ? 1 : 0
        colorControl.frame = NSRect(x: 14, y: 326, width: 200, height: 24)
        pane.addSubview(colorControl)
        // Note copy shortened in v0.6.0 to fit the narrower pane at
        // two lines (same information, fewer words).
        let colorNote = paneLabel("Full card tints the whole note; Left bar draws the colour as a strip on the card's left edge.", in: pane, y: 288)
        colorNote.textColor = SNTheme.secondaryText
        colorNote.maximumNumberOfLines = 2
        colorNote.lineBreakMode = .byWordWrapping
        colorNote.frame = NSRect(x: 14, y: 282, width: 336, height: 32)

        _ = paneLabel("Panel density:", in: pane, y: 238)
        let densityControl = NSSegmentedControl(labels: ["Standard", "Compact"], trackingMode: .selectOne,
                                                target: self, action: #selector(densityChanged(_:)))
        densityControl.selectedSegment = Preferences.density == .compact ? 1 : 0
        densityControl.frame = NSRect(x: 14, y: 210, width: 200, height: 24)
        pane.addSubview(densityControl)
        let densityNote = paneLabel("Compact turns note lists into one-line rows with a capture field and keyboard hints — a triage view.", in: pane, y: 162)
        densityNote.textColor = SNTheme.secondaryText
        densityNote.maximumNumberOfLines = 2
        densityNote.lineBreakMode = .byWordWrapping
        densityNote.frame = NSRect(x: 14, y: 156, width: 336, height: 32)
        return pane
    }

    private func buildEditorPane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        paneTitle("Editor", in: pane)

        let markup = paneCheckbox("Show Markdown markup (reveal **, ::, # while editing)",
                                  in: pane, y: 354, action: #selector(markupChanged(_:)))
        markup.state = UserDefaults.standard.bool(forKey: Preferences.showMarkupKey) ? .on : .off

        _ = paneLabel("Body text size:", in: pane, y: 316)
        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue = 11
        fontSizeStepper.maxValue = 16
        fontSizeStepper.increment = 0.5
        fontSizeStepper.doubleValue = Preferences.bodyFontSize
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeChanged(_:))
        fontSizeStepper.frame = NSRect(x: 14, y: 288, width: 20, height: 24)
        pane.addSubview(fontSizeStepper)
        fontSizeLabel = NSTextField(labelWithString: "")
        fontSizeLabel.font = NSFont.systemFont(ofSize: 12)
        fontSizeLabel.textColor = SNTheme.primaryText
        fontSizeLabel.frame = NSRect(x: 42, y: 290, width: 200, height: 18)
        pane.addSubview(fontSizeLabel)
        let note = paneLabel("Also adjustable in the panel with ⌘+ and ⌘−.", in: pane, y: 262)
        note.textColor = SNTheme.secondaryText
        return pane
    }

    private func buildBackupsPane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        paneTitle("Backups", in: pane)

        _ = paneLabel("SilverNotes snapshots its store as you work and keeps the 7 newest copies.", in: pane, y: 354)
        backupsCountLabel = NSTextField(labelWithString: "")
        backupsCountLabel.font = NSFont.systemFont(ofSize: 12)
        backupsCountLabel.textColor = SNTheme.primaryText
        backupsCountLabel.frame = NSRect(x: 14, y: 322, width: 336, height: 18)
        pane.addSubview(backupsCountLabel)
        backupsRecentLabel = NSTextField(labelWithString: "")
        backupsRecentLabel.font = NSFont.systemFont(ofSize: 12)
        backupsRecentLabel.textColor = SNTheme.primaryText
        backupsRecentLabel.frame = NSRect(x: 14, y: 298, width: 336, height: 18)
        pane.addSubview(backupsRecentLabel)

        let openButton = NSButton(title: "Open Backups Folder", target: self, action: #selector(openBackupsFolder))
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 14, y: 258, width: 180, height: 24)
        pane.addSubview(openButton)
        return pane
    }

    private func buildShortcutsPane(frame: NSRect) -> NSView {
        let pane = NSView(frame: frame)
        paneTitle("Shortcuts", in: pane)

        let lines = """
        Control + Option + Command + Space — show / hide the panel
        Esc — close the toolbar, then the panel
        ⌘+ / ⌘− — body text size up / down
        ⌘F — search
        ⌘N — new note

        On the active note card:
        ⌥⌘P — pin / unpin the note
        ⌥⌘⏎ — fold / unfold the note
        ⌥⌘1 / ⌥⌘2 / ⌥⌘3 — Standard / Plain Text / Code mode
        Double-click a card's bottom strip — fold / unfold
        Press and hold a card's bottom strip, then drag — reorder

        In Compact density:
        ↑ / ↓ — move between rows
        ⏎ — open the selected row into its card
        Return in the capture field — file the note
        """
        let field = NSTextField(labelWithString: lines)
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = SNTheme.primaryText
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.frame = NSRect(x: 14, y: 36, width: 336, height: 348)
        pane.addSubview(field)
        return pane
    }

    // MARK: Actions

    @objc private func sideChanged(_ sender: NSSegmentedControl) {
        let side: PanelSide = sender.selectedSegment == 1 ? .right : .left
        // Per-display memory (audit 6.13): the segmented control sets
        // the side for the display the panel lives on (the main
        // display here); other displays keep their remembered side.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        Preferences.setPanelSide(side, for: screen)
        PanelController.shared.sideDidChange()
    }

    @objc private func hotSideChanged(_ sender: NSButton) {
        Preferences.hotSideEnabled = sender.state == .on
        PanelController.shared.hotSidePreferenceDidChange()
    }

    @objc private func pinChanged(_ sender: NSButton) {
        Preferences.panelPinned = sender.state == .on
    }

    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        Preferences.panelWidth = sender.selectedSegment == 1 ? .wide : .standard
        PanelController.shared.panelWidthPreferenceDidChange()
    }

    @objc private func colorStyleChanged(_ sender: NSSegmentedControl) {
        Preferences.colorStyle = sender.selectedSegment == 1 ? .leftBar : .fullCard
        PanelController.shared.contentController.reload()
    }

    @objc private func densityChanged(_ sender: NSSegmentedControl) {
        Preferences.density = sender.selectedSegment == 1 ? .compact : .standard
        PanelController.shared.panelWidthPreferenceDidChange()
    }

    @objc private func markupChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Preferences.showMarkupKey)
        PanelController.shared.contentController.reload()
    }

    @objc private func fontSizeChanged(_ sender: NSStepper) {
        Preferences.bodyFontSize = sender.doubleValue
        refreshFontSizeLabel()
        PanelController.shared.contentController.reload()
    }

    private func refreshFontSizeLabel() {
        let size = Preferences.bodyFontSize
        fontSizeLabel?.stringValue = size.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(size)) pt"
            : String(format: "%.1f pt", size)
    }

    private func refreshBackupsPane() {
        guard backupsCountLabel != nil, backupsRecentLabel != nil else { return }
        let info = NoteStore.shared.backupInfo()
        backupsCountLabel.stringValue = "Snapshots: \(info.count) of 7 kept"
        if let recent = info.mostRecent {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            backupsRecentLabel.stringValue = "Most recent: \(formatter.string(from: recent))"
        } else {
            backupsRecentLabel.stringValue = "Most recent: none yet"
        }
    }

    @objc private func openBackupsFolder() {
        NSWorkspace.shared.open(NoteStore.shared.backupsDirectory)
    }

    private func refreshLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLoginCheckbox.state = (status == .enabled) ? .on : .off
        switch status {
        case .enabled:
            statusLabel.stringValue = "Launch at login is on."
        case .requiresApproval:
            statusLabel.stringValue = "Launch at login needs approval in System Settings → Login Items."
        default:
            statusLabel.stringValue = "Launch at login is off."
        }
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusLabel.stringValue = "Could not change launch at login: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginState()
    }

    // MARK: Updates

    @objc private func updateButtonClicked() {
        if let version = pendingInstallVersion {
            installUpdate(version: version)
        } else {
            runUpdateCheck()
        }
    }

    private func runUpdateCheck() {
        updateButton.isEnabled = false
        updateStatusLabel.stringValue = "Checking…"
        UpdateChecker.shared.check { [weak self] result in
            guard let self = self else { return }
            self.updateButton.isEnabled = true
            switch result {
            case .upToDate:
                self.pendingInstallVersion = nil
                self.updateButton.title = "Check for Updates…"
                self.updateStatusLabel.stringValue = "You're up to date (v\(UpdateChecker.shared.currentVersion))."
            case .updateAvailable(let version):
                self.pendingInstallVersion = version
                self.updateButton.title = "Install v\(version)…"
                self.updateStatusLabel.stringValue = "Version \(version) is available."
            case .failed(let message):
                self.pendingInstallVersion = nil
                self.updateButton.title = "Check for Updates…"
                self.updateStatusLabel.stringValue = message
            }
        }
    }

    private func installUpdate(version: String) {
        updateButton.isEnabled = false
        updateStatusLabel.stringValue = "Downloading & installing…"
        UpdateChecker.shared.downloadAndInstall { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.updateButton.isEnabled = true
                self.updateButton.title = "Install v\(version)…"
                self.updateStatusLabel.stringValue = error
            } else {
                // The checker is quitting the app so its swap script can
                // replace the bundle; this is the last thing shown.
                self.updateStatusLabel.stringValue = "Restarting to install…"
            }
        }
    }
}
