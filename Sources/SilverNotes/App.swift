import AppKit

/// SilverNotes v0.1.0 MVP — entry point.
/// Accessory app: no Dock icon; presence is the edge sliver + a menu-bar item.
@main
enum SilverNotesMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        NoteStore.shared.load()
        PanelController.shared.setUp()
        buildMainMenu()
        buildStatusItem()
        print("SilverNotes: launched (status item + sliver ready)")
        // First launch ever: show the panel once so the user sees the app
        // exists. An accessory app that launches fully hidden reads as
        // "nothing happens" — this is the onboarding moment.
        if !UserDefaults.standard.bool(forKey: Preferences.didOnboardKey) {
            UserDefaults.standard.set(true, forKey: Preferences.didOnboardKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                PanelController.shared.show()
            }
        }
    }

    /// Double-clicking the app in Finder/Applications while it is already
    /// running lands here. Without this, relaunching a hidden accessory
    /// app visibly does nothing at all.
    ///
    /// NOTE: there is deliberately NO applicationOpenUntitledFile here.
    /// AppKit calls that during a COLD launch (via _doOpenUntitled,
    /// before applicationDidFinishLaunching), and routing it to show()
    /// crashed the app on launch — EXC_BREAKPOINT in PanelController.show()
    /// before setUp() had run (crash reports 2026-11-25 16:55). Panel
    /// show() is now also self-guarding via ensureSetUp(), but the
    /// untitled-file hook stays removed: a cold launch is already covered
    /// by the first-launch auto-show in applicationDidFinishLaunching.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.show()
        return false
    }

    // MARK: Main menu
    //
    // An accessory app still needs a main menu: without one, the standard
    // Edit shortcuts (⌘Z ⌘X ⌘C ⌘V ⌘A) never reach the note editor, and the
    // Settings window has no menus at all. The App menu also carries About,
    // which shows the app icon and version.

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About SilverNotes",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide SilverNotes", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit SilverNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New Note", action: #selector(menuNewNote), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu — actions route through the responder chain to the
        // active NoteTextView, which is what makes editing shortcuts work.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let toggleItem = NSMenuItem(title: "Show / Hide Panel", action: #selector(menuToggle), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        viewMenu.addItem(toggleItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.save()
        HotKeyManager.shared.unregister()
    }

    // MARK: Menu-bar item (fallback summon path, register §1.11)

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "SilverNotes")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            PanelController.shared.toggle()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        // Left-clicking the icon toggles the panel; this menu is the
        // right-click path, and it now appears on left-click too if the
        // button is ever given a menu permanently — keep items complete.
        let toggleItem = NSMenuItem(title: "Show / Hide Panel", action: #selector(menuToggle), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem(title: "New Note", action: #selector(menuNewNote), keyEquivalent: "n"))
        menu.addItem(.separator())
        let hotSideItem = NSMenuItem(title: "Hot Side (open from screen edge)", action: #selector(menuHotSide), keyEquivalent: "")
        hotSideItem.state = Preferences.hotSideEnabled ? .on : .off
        menu.addItem(hotSideItem)
        let sideItem = NSMenuItem(title: Preferences.panelSide == .right ? "Dock to Left Edge" : "Dock to Right Edge",
                                  action: #selector(menuFlipSide), keyEquivalent: "")
        menu.addItem(sideItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About SilverNotes", action: #selector(menuAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SilverNotes", action: #selector(menuQuit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Detach again so the next left-click toggles instead of opening the menu.
        DispatchQueue.main.async { [weak self] in self?.statusItem?.menu = nil }
    }

    @objc private func menuToggle() { PanelController.shared.toggle() }
    @objc private func menuNewNote() { PanelController.shared.createNoteShortcut() }
    @objc private func menuSettings() { SettingsController.shared.show() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func menuHotSide() {
        Preferences.hotSideEnabled.toggle()
        PanelController.shared.hotSidePreferenceDidChange()
    }
    @objc private func menuFlipSide() {
        Preferences.panelSide = Preferences.panelSide == .right ? .left : .right
        PanelController.shared.sideDidChange()
    }
}
