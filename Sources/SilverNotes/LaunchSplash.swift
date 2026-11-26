import AppKit

/// The cold-launch splash: a small centred card (app icon, name, spinner)
/// that rides along with the panel's first presentation shortly after
/// launch. It loads nothing — the store and panel set up exactly as they
/// always have underneath it — and it never gates anything: PanelController
/// .show() merely notes the presentation here and proceeds untouched.
///
/// Timing: at least ~700 ms on screen (so it never reads as a subliminal
/// flash), gone by ~1.6 s at the very latest, and dropped at once if the
/// user summons the panel again while it's up. A launch whose first panel
/// presentation comes more than ~20 s in (a login launch, typically) never
/// sees it at all.
final class LaunchSplash {

    static let shared = LaunchSplash()

    private var window: NSPanel?
    private var spinner: NSProgressIndicator?
    private var launchDate: Date?
    private var consumed = false
    private var isUp = false
    private var dismissWorkItem: DispatchWorkItem?
    private var capWorkItem: DispatchWorkItem?

    private init() {}

    /// Records the launch moment. Called once from
    /// applicationDidFinishLaunching, AFTER PanelController.setUp() — the
    /// splash arms here but shows nothing yet, and it must never precede
    /// or delay the setUp path the launch-crash fix depends on.
    func arm() {
        if launchDate == nil { launchDate = Date() }
    }

    /// Called from PanelController.show() on every presentation; only the
    /// first one within ~20 s of launch brings the splash up. A further
    /// presentation while it's visible dismisses it immediately.
    func panelPresented() {
        if isUp {
            dismiss()
            return
        }
        guard !consumed else { return }
        consumed = true
        guard let launchDate = launchDate,
              Date().timeIntervalSince(launchDate) <= 20 else { return }
        show()
    }

    private func show() {
        if window == nil { buildWindow() }
        guard let window = window else { return }
        window.center()
        window.alphaValue = 1
        window.orderFrontRegardless()
        spinner?.startAnimation(nil)
        isUp = true
        // Floor: ~700 ms minimum. The panel's first content is built
        // during setUp(), so the presentation that triggered us is itself
        // the readiness signal — nothing else to wait for.
        let dismiss = DispatchWorkItem { [weak self] in self?.beginFade() }
        dismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: dismiss)
        // Ceiling: whatever went wrong above, never linger past ~1.6 s.
        let cap = DispatchWorkItem { [weak self] in self?.forceHide() }
        capWorkItem = cap
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: cap)
    }

    private func dismiss() {
        dismissWorkItem?.cancel()
        beginFade()
    }

    private func beginFade() {
        guard isUp, let window = window else { return }
        isUp = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.16
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            self.capWorkItem?.cancel()
            self.window?.orderOut(nil)
            self.window?.alphaValue = 1
            self.spinner?.stopAnimation(nil)
        }
    }

    private func forceHide() {
        guard let window = window else { return }
        dismissWorkItem?.cancel()
        isUp = false
        window.orderOut(nil)
        window.alphaValue = 1
        spinner?.stopAnimation(nil)
    }

    private func buildWindow() {
        let size = NSSize(width: 280, height: 180)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let content = SplashContentView(frame: NSRect(origin: .zero, size: size))

        let icon = NSImageView(frame: NSRect(x: (size.width - 64) / 2, y: size.height - 22 - 64,
                                             width: 64, height: 64))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        let title = NSTextField(labelWithString: "SilverNotes")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        title.textColor = SNTheme.primaryText
        title.alignment = .center
        title.frame = NSRect(x: 20, y: 62, width: size.width - 40, height: 24)
        content.addSubview(title)

        let spinner = NSProgressIndicator(frame: NSRect(x: (size.width - 16) / 2, y: 38,
                                                        width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        content.addSubview(spinner)
        self.spinner = spinner

        let caption = NSTextField(labelWithString: "Loading your notes…")
        caption.font = NSFont.systemFont(ofSize: 11)
        caption.textColor = SNTheme.secondaryText
        caption.alignment = .center
        caption.frame = NSRect(x: 20, y: 14, width: size.width - 40, height: 14)
        content.addSubview(caption)

        panel.contentView = content
        window = panel
    }
}

/// The splash's surface: the panel's silver on a 16 pt rounded card.
/// Drawn rather than layered, so the dynamic colour resolves against the
/// current appearance at draw time — the same approach as the sliver's
/// view in PanelController.
private final class SplashContentView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        SNTheme.panelBackground.setFill()
        path.fill()
        SNTheme.cardBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
