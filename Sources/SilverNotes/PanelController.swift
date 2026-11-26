import AppKit
import QuartzCore

/// Owns the edge panel, the collapsed sliver, and every show/hide trigger
/// for SilverNotes v0.1.0:
/// - Hot Side: 1–2 pt edge strip, ~200 ms dwell, suppressed while dragging
///   (register §1.4); drag-in uses a wider zone + ~250 ms dwell (§2.4).
/// - Carbon global hotkey (⌃⌥⌘Space) via HotKeyManager.
/// - Click-outside auto-hide with an allow-list: while a menu, popover,
///   share picker, or save panel belonging to the panel is up, auto-hide is
///   suspended (childInteractionCount > 0). Pin-open disables auto-hide.
/// - Esc hides innermost-first: formatting toolbar → panel
///   (menus/popovers consume their own Esc natively).
/// - Focus is captured before showing and restored to the previously
///   active app on hide (register §2.9).
/// - The panel hides on screen lock, always (register §1.9).
final class PanelController: NSObject {

    static let shared = PanelController()

    let contentController = PanelContentController()
    private var panel: NSPanel!
    private var sliver: NSPanel!
    private var didSetUp = false
    private var isPanelVisible = false
    private var previousApp: NSRunningApplication?

    private var mouseMonitor: Any?
    private var dragMonitor: Any?
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    /// Cached preference values. The global mouse handlers run on every
    /// pointer event system-wide, so they must not hit UserDefaults per
    /// event; these are refreshed at setUp and at every point where the
    /// corresponding preference is written (see hotSidePreferenceDidChange
    /// and sideDidChange).
    private var hotSideEnabledCached = false
    private var panelSideCached: PanelSide = .right
    private var hotSideTimer: Timer?
    private var dragRevealTimer: Timer?
    private var childInteractionCount = 0

    /// How the panel was most recently revealed — the cursor-leave
    /// grace (audit 6.12) applies only to edge reveals (Hot Side /
    /// drag-in), and only until the user clicks or types into the panel.
    private enum ShowSource { case edge, direct }
    private var showSource: ShowSource = .direct
    private var cursorLeaveTimer: Timer?

    private override init() { super.init() }

    // MARK: Setup

    /// Lazily runs setUp() on first use. CRITICAL: AppKit can deliver
    /// launch-time events (e.g. the open/reopen Apple event) that reach
    /// show() BEFORE applicationDidFinishLaunching has called setUp() —
    /// with panel/sliver still nil, touching them traps (EXC_BREAKPOINT,
    /// crash reports 2026-11-25 16:55). Every public entry point routes
    /// through here first, so the IUOs below are never touched unset.
    private func ensureSetUp() {
        if !didSetUp { setUp() }
    }

    func setUp() {
        guard !didSetUp else { return }
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = contentController
        panel.isReleasedWhenClosed = false

        buildSliver()
        if let screen = NSScreen.main {
            print("SilverNotes: setUp — screen \(screen.frame), sliver frame \(sliver.frame)")
        }
        installMonitors()
        HotKeyManager.shared.onToggle = { [weak self] in self?.toggle() }
        HotKeyManager.shared.register()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sessionDidResignActive),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        didSetUp = true
    }

    private func buildSliver() {
        sliver = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 22, height: 118),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        sliver.isFloatingPanel = true
        sliver.level = .floating
        sliver.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sliver.isOpaque = false
        sliver.backgroundColor = .clear
        // The package gives the Open Bar a soft shadow (−6/18,
        // rgba(15,20,35,0.2), rubric §1.14); a window shadow follows
        // the sliver view's alpha shape, which is the closest native
        // equivalent — capture-verify.
        sliver.hasShadow = true
        let view = SliverView()
        view.onClick = { [weak self] in self?.show() }
        sliver.contentView = view
        positionSliver()
        sliver.orderFront(nil)
    }

    // MARK: Geometry (mockup spec: Standard ~34% of screen width with a
    // 300–560 pt clamp; Wide ~48% (audit 7.2). Compact is a DENSITY at
    // that same 34% width — "rows, not cards", per the design package
    // (Variation B/C prose and the spec table; Nov 26 audit item 8.2) —
    // not a third, narrower width. Height runs from below the menu bar
    // to the PHYSICAL screen bottom (audit 1.3) — a visible bottom Dock
    // does not lift it. The side is remembered per display (audit 6.13).)

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func panelFrame(on screen: NSScreen, visible: Bool) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let width: CGFloat
        if Preferences.panelWidth == .wide && Preferences.density != .compact {
            width = min(max(visibleFrame.width * 0.48, 380), 1000)
        } else {
            // Standard width — and Compact, which is a density at this
            // same width, never a narrower panel (Nov 26 audit 8.2).
            // Compact keeps its precedence over the Wide step, exactly
            // as before; only its width value changes.
            width = min(max(visibleFrame.width * 0.34, 300), 560)
        }
        let side = Preferences.effectivePanelSide(for: screen)
        let x: CGFloat
        if visible {
            x = side == .right ? visibleFrame.maxX - width : visibleFrame.minX
        } else {
            x = side == .right ? screen.frame.maxX : screen.frame.minX - width
        }
        let y = screen.frame.minY
        let height = visibleFrame.maxY - screen.frame.minY
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func positionSliver() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let side = Preferences.effectivePanelSide(for: screen)
        let height: CGFloat = 118
        let y = screen.visibleFrame.midY - height / 2
        let x = side == .right ? screen.frame.maxX - 22 : screen.frame.minX
        sliver.setFrame(NSRect(x: x, y: y, width: 22, height: height), display: true)
        (sliver.contentView as? SliverView)?.side = side
    }

    // MARK: Show / hide

    var panelIsVisible: Bool { isPanelVisible }

    func toggle() {
        ensureSetUp()
        if isPanelVisible && panelIsOnScreen { hide() } else { show() }
    }

    /// True only when the panel is ordered in AND its frame actually
    /// intersects a screen. State flag alone is not proof — a slide-in
    /// animation that never lands leaves the flag true with the panel
    /// parked fully off-screen (the v0.1.0 "nothing happens" bug).
    private var panelIsOnScreen: Bool {
        guard panel.isVisible else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(panel.frame) }
    }

    func show() {
        show(source: .direct)
    }

    private func show(source: ShowSource) {
        ensureSetUp()
        // Launch-splash bookkeeping only: it never gates, delays, or
        // alters the show — the splash is a separate window that fades
        // on its own schedule.
        LaunchSplash.shared.panelPresented()
        if isPanelVisible && panelIsOnScreen { return }
        showSource = source
        print("SilverNotes: show() — panel sliding in")
        previousApp = NSWorkspace.shared.frontmostApplication
        let screen = targetScreen()
        let target = panelFrame(on: screen, visible: true)
        contentController.updateRoundedCorner(for: Preferences.panelSide)
        isPanelVisible = true
        sliver.orderOut(nil)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            // Reduce Motion: no slide — a 120 ms crossfade in place.
            panel.setFrame(target, display: true)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            return
        }
        // Start just off-screen, order front, then animate on the NEXT
        // runloop tick: animating in the same turn as the first orderFront
        // can silently drop the animation, leaving the panel parked at
        // its off-screen start frame while state says "visible".
        panel.setFrame(panelFrame(on: screen, visible: false), display: false)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isPanelVisible else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                self.panel.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                guard let self = self, self.isPanelVisible else { return }
                // Self-heal: whatever the animation did, the panel must
                // end up exactly on target and verifiably on-screen.
                if self.panel.frame != target || !self.panelIsOnScreen {
                    self.panel.setFrame(target, display: true)
                    self.panel.makeKeyAndOrderFront(nil)
                }
                print("SilverNotes: show() settled — frame \(self.panel.frame), onScreen \(self.panelIsOnScreen)")
            }
        }
    }

    func hide() {
        ensureSetUp()
        guard isPanelVisible else { return }
        isPanelVisible = false
        cursorLeaveTimer?.invalidate()
        cursorLeaveTimer = nil
        GearMenu.dismissIfOpen()
        FormattingToolbar.shared.hide()
        guard let screen = panel.screen ?? NSScreen.main else {
            panel.orderOut(nil)
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            // Reduce Motion: no slide — a 120 ms crossfade out, then the
            // usual cleanup (alpha restored so the next show isn't
            // invisible).
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self = self, !self.isPanelVisible else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.positionSliver()
                self.sliver.orderFront(nil)
                if let app = self.previousApp, app != NSRunningApplication.current {
                    app.activate(options: [])
                }
            }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().setFrame(panelFrame(on: screen, visible: false), display: true)
        } completionHandler: { [weak self] in
            guard let self = self, !self.isPanelVisible else { return }
            self.panel.orderOut(nil)
            self.positionSliver()
            self.sliver.orderFront(nil)
            // Focus return: hand the keyboard back to the app the user
            // was in before summoning the panel.
            if let app = self.previousApp, app != NSRunningApplication.current {
                app.activate(options: [])
            }
        }
    }

    /// Re-dock after the side preference changes: geometry, sliver, corner.
    /// Both side-preference write sites (Settings, status-bar menu) route
    /// through here, so the cached side is refreshed here too. The side
    /// is per-display (audit 6.13): the cached value follows the panel's
    /// current screen.
    func sideDidChange() {
        ensureSetUp()
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        panelSideCached = Preferences.effectivePanelSide(for: screen)
        positionSliver()
        contentController.updateRoundedCorner(for: panelSideCached)
        if isPanelVisible {
            panel.setFrame(panelFrame(on: screen, visible: true), display: true)
        }
    }

    /// The Standard/Wide width step or the density changed in Settings:
    /// re-frame a visible panel and let the content rebuild its chrome
    /// (the folder rail appears/disappears with Wide).
    func panelWidthPreferenceDidChange() {
        ensureSetUp()
        contentController.reload()
        if isPanelVisible, let screen = panel.screen ?? NSScreen.main {
            panel.setFrame(panelFrame(on: screen, visible: true), display: true)
        }
    }

    func createNoteShortcut() {
        ensureSetUp()
        show()
        contentController.createNoteAndFocus()
    }

    // MARK: Auto-hide allow-list

    func beginChildInteraction() { childInteractionCount += 1 }
    func endChildInteraction() { childInteractionCount = max(0, childInteractionCount - 1) }

    private var autoHideSuspended: Bool {
        if childInteractionCount > 0 { return true }
        // Any other visible window of ours (Settings, an alert, a popover
        // window) counts as "inside" for click-outside purposes.
        return NSApp.windows.contains { window in
            window.isVisible && window !== panel && window !== sliver
                && !(window is FormattingToolbar)
        }
    }

    // MARK: Monitors

    private func installMonitors() {
        hotSideEnabledCached = Preferences.hotSideEnabled
        panelSideCached = Preferences.panelSide
        // Hot Side + drag-in: global mouse monitors need no permission for
        // mouse-moved / drag events delivered to other apps.
        updateMouseMonitors()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleGlobalClick(event)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleLocalKeyDown(event) ? nil : event
        }
        // Clicking INTO the panel cancels the cursor-leave grace: the
        // user has taken hold of it (audit 6.12).
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isPanelVisible else { return event }
            if self.panel.frame.contains(NSEvent.mouseLocation) {
                self.showSource = .direct
                self.cursorLeaveTimer?.invalidate()
                self.cursorLeaveTimer = nil
            }
            return event
        }
    }

    /// Installs or removes the global mouse-moved / drag monitors to match
    /// the Hot Side preference. When Hot Side is off the monitors are
    /// removed entirely — zero per-event cost anywhere on the system —
    /// and reinstalled when it is switched back on.
    private func updateMouseMonitors() {
        if hotSideEnabledCached {
            if mouseMonitor == nil {
                mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                    self?.handleMouseMoved()
                }
            }
            if dragMonitor == nil {
                dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
                    self?.handleMouseDragged()
                }
            }
        } else {
            if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor); mouseMonitor = nil }
            if let monitor = dragMonitor { NSEvent.removeMonitor(monitor); dragMonitor = nil }
            hotSideTimer?.invalidate(); hotSideTimer = nil
            dragRevealTimer?.invalidate(); dragRevealTimer = nil
        }
    }

    /// Called by every site that writes the Hot Side preference (the
    /// Settings checkbox and the status-bar menu) so the cached value and
    /// the monitor set stay in step with the stored preference.
    func hotSidePreferenceDidChange() {
        hotSideEnabledCached = Preferences.hotSideEnabled
        updateMouseMonitors()
    }

    private func handleMouseMoved() {
        guard hotSideEnabledCached else { return }
        if isPanelVisible {
            handleCursorLeaveGrace()
            return
        }
        // Drag suppression: never Hot-Side-trigger while a drag is in flight;
        // drags have their own reveal path with a wider zone.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
            hotSideTimer?.invalidate()
            return
        }
        let side = panelSideCached
        let distance = side == .right ? screen.frame.maxX - mouse.x : mouse.x - screen.frame.minX
        if distance <= 2 {
            if hotSideTimer == nil {
                hotSideTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                    self?.hotSideTimer = nil
                    self?.show(source: .edge)
                }
            }
        } else {
            hotSideTimer?.invalidate()
            hotSideTimer = nil
        }
    }

    /// Cursor-leave grace (audit 6.12): a panel revealed by the edge
    /// hides ~500 ms after the cursor leaves it — unless the user has
    /// clicked or typed into it (showSource flips to .direct), the
    /// panel is pinned, or a child interaction (menu, popover, save
    /// panel) is in flight. Re-entering cancels the timer.
    private func handleCursorLeaveGrace() {
        guard showSource == .edge, !Preferences.panelPinned, !autoHideSuspended else {
            cursorLeaveTimer?.invalidate()
            cursorLeaveTimer = nil
            return
        }
        if panel.frame.contains(NSEvent.mouseLocation) {
            cursorLeaveTimer?.invalidate()
            cursorLeaveTimer = nil
        } else if cursorLeaveTimer == nil {
            cursorLeaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.cursorLeaveTimer = nil
                if self.isPanelVisible, self.showSource == .edge,
                   !Preferences.panelPinned, !self.autoHideSuspended {
                    self.hide()
                }
            }
        }
    }

    private func handleMouseDragged() {
        guard !isPanelVisible else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        let side = panelSideCached
        let distance = side == .right ? screen.frame.maxX - mouse.x : mouse.x - screen.frame.minX
        if distance <= 12 {
            if dragRevealTimer == nil {
                dragRevealTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                    self?.dragRevealTimer = nil
                    self?.show(source: .edge)
                }
            }
        } else {
            dragRevealTimer?.invalidate()
            dragRevealTimer = nil
        }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        guard isPanelVisible, !Preferences.panelPinned, !autoHideSuspended else { return }
        let mouse = NSEvent.mouseLocation
        if panel.frame.contains(mouse) || sliver.frame.contains(mouse) { return }
        hide()
    }

    /// Esc layering + panel shortcuts. Local monitor: only fires for events
    /// delivered to our own app (i.e. while the panel or Settings is key).
    private func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        guard isPanelVisible, panel.isKeyWindow else { return false }
        // Typing into the panel cancels the cursor-leave grace (6.12).
        showSource = .direct
        cursorLeaveTimer?.invalidate()
        cursorLeaveTimer = nil
        if event.keyCode == 53 { // Esc
            // Ladder (audit 6.6, per the user's explicit direction): the
            // formatting toolbar first, then the panel closes. There is
            // deliberately NO selection-collapse step.
            if FormattingToolbar.shared.isVisible {
                FormattingToolbar.shared.hide()
                return true
            }
            hide()
            return true
        }
        // ⌘+ / ⌘− adjust the global body size (audit 3.14): step 0.5,
        // clamped 11–16 by the preference, persisted, and every visible
        // card re-renders at the new size.
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) {
            let chars = event.charactersIgnoringModifiers ?? ""
            if chars == "+" || chars == "=" {
                Preferences.bodyFontSize += 0.5
                contentController.reload()
                return true
            }
            if chars == "-" || chars == "_" {
                Preferences.bodyFontSize -= 0.5
                contentController.reload()
                return true
            }
        }
        return contentController.handlePanelKeyDown(event)
    }

    // MARK: Workspace events

    @objc private func sessionDidResignActive() {
        // Lock / Fast User Switching: never leave note content exposed.
        if isPanelVisible {
            isPanelVisible = false
            panel.orderOut(nil)
            positionSliver()
        }
    }

    @objc private func activeSpaceDidChange() {
        if isPanelVisible, let screen = panel.screen {
            panel.setFrame(panelFrame(on: screen, visible: true), display: true)
        }
    }
}

/// The collapsed sliver: a thin, semi-transparent strip at the docked edge,
/// mid-height. Click (or the Hot Side dwell) opens the panel.
private final class SliverView: NSView {
    var onClick: (() -> Void)?
    var side: PanelSide = .right { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        let r: CGFloat = 10
        if side == .right {
            path.move(to: NSPoint(x: bounds.maxX, y: bounds.minY))
            path.line(to: NSPoint(x: bounds.minX + r, y: bounds.minY))
            path.appendArc(withCenter: NSPoint(x: bounds.minX + r, y: bounds.minY + r), radius: r, startAngle: 270, endAngle: 180, clockwise: true)
            path.line(to: NSPoint(x: bounds.minX, y: bounds.maxY - r))
            path.appendArc(withCenter: NSPoint(x: bounds.minX + r, y: bounds.maxY - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        } else {
            path.move(to: NSPoint(x: bounds.minX, y: bounds.minY))
            path.line(to: NSPoint(x: bounds.maxX - r, y: bounds.minY))
            path.appendArc(withCenter: NSPoint(x: bounds.maxX - r, y: bounds.minY + r), radius: r, startAngle: 270, endAngle: 0, clockwise: false)
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - r))
            path.appendArc(withCenter: NSPoint(x: bounds.maxX - r, y: bounds.maxY - r), radius: r, startAngle: 0, endAngle: 90, clockwise: false)
            path.line(to: NSPoint(x: bounds.minX, y: bounds.maxY))
        }
        path.close()
        SNTheme.sliverBackground.setFill()
        path.fill()
        SNTheme.sliverBorder.setStroke()
        path.lineWidth = 1
        path.stroke()

        let chevron = side == .right ? "‹" : "›"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: SNTheme.sliverIcon
        ]
        let size = (chevron as NSString).size(withAttributes: attrs)
        (chevron as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                               y: bounds.midY - size.height / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
