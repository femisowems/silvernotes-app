import AppKit
import ServiceManagement

/// Minimal Settings window for SilverNotes v0.1.0:
/// dock side, Hot Side on/off, panel pin, "show markup", launch at login
/// (real, via SMAppService on macOS 13+), plus the product/pricing facts.
final class SettingsController: NSObject, NSWindowDelegate {

    static let shared = SettingsController()

    private var window: NSWindow?
    private var launchAtLoginCheckbox: NSButton!
    private var statusLabel: NSTextField!

    private override init() { super.init() }

    func show() {
        if window == nil { buildWindow() }
        PanelController.shared.beginChildInteraction()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        PanelController.shared.endChildInteraction()
    }

    private func buildWindow() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 300))

        func label(_ text: String, y: CGFloat, bold: Bool = false) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = bold ? NSFont.systemFont(ofSize: 13, weight: .semibold) : NSFont.systemFont(ofSize: 12)
            field.textColor = SNTheme.primaryText
            field.frame = NSRect(x: 20, y: y, width: 340, height: 18)
            content.addSubview(field)
            return field
        }
        func checkbox(_ title: String, y: CGFloat, action: Selector) -> NSButton {
            let button = NSButton(checkboxWithTitle: title, target: self, action: action)
            button.frame = NSRect(x: 20, y: y, width: 340, height: 20)
            content.addSubview(button)
            return button
        }

        _ = label("SilverNotes Settings", y: 262, bold: true)

        _ = label("Dock panel to:", y: 232)
        let sideControl = NSSegmentedControl(labels: ["Left", "Right"], trackingMode: .selectOne,
                                             target: self, action: #selector(sideChanged(_:)))
        sideControl.selectedSegment = Preferences.panelSide == .right ? 1 : 0
        sideControl.frame = NSRect(x: 20, y: 204, width: 160, height: 24)
        content.addSubview(sideControl)

        let hotSide = checkbox("Hot Side — open the panel by holding the pointer at the screen edge",
                               y: 172, action: #selector(hotSideChanged(_:)))
        hotSide.state = Preferences.hotSideEnabled ? .on : .off

        let markup = checkbox("Show Markdown markup (reveal **, ::, # while editing)",
                              y: 146, action: #selector(markupChanged(_:)))
        markup.state = UserDefaults.standard.bool(forKey: Preferences.showMarkupKey) ? .on : .off

        // The status label must exist BEFORE refreshLaunchAtLoginState()
        // runs — the refresh writes statusLabel.stringValue in every
        // branch, and the label is an implicitly unwrapped optional:
        // refreshing first trapped on first open (v0.1.0–v0.2.0).
        statusLabel = label("", y: 92)
        statusLabel.textColor = SNTheme.secondaryText

        launchAtLoginCheckbox = checkbox("Launch at login (starts hidden, panel closed)",
                                         y: 120, action: #selector(launchAtLoginChanged(_:)))
        refreshLaunchAtLoginState()

        _ = label("Toggle the panel from anywhere: Control + Option + Command + Space.", y: 62)
        let version = label("SilverNotes v0.2.1 — $19.99 per major version, 30-day trial (licensing is not enforced in this build). Local-first: your notes never leave this Mac.", y: 16)
        version.textColor = SNTheme.secondaryText
        version.maximumNumberOfLines = 2
        version.lineBreakMode = .byWordWrapping
        version.frame = NSRect(x: 20, y: 8, width: 340, height: 34)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "SilverNotes Settings"
        win.contentView = content
        win.delegate = self
        win.isReleasedWhenClosed = false
        window = win
    }

    // MARK: Actions

    @objc private func sideChanged(_ sender: NSSegmentedControl) {
        let side: PanelSide = sender.selectedSegment == 1 ? .right : .left
        UserDefaults.standard.set(side.rawValue, forKey: Preferences.panelSideKey)
        PanelController.shared.sideDidChange()
    }

    @objc private func hotSideChanged(_ sender: NSButton) {
        Preferences.hotSideEnabled = sender.state == .on
        PanelController.shared.hotSidePreferenceDidChange()
    }

    @objc private func markupChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Preferences.showMarkupKey)
        PanelController.shared.contentController.reload()
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
}
