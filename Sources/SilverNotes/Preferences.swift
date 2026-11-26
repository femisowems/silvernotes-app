import Foundation
import AppKit

/// UserDefaults keys + typed accessors for SilverNotes preferences.
enum Preferences {
    static let panelSideKey = "panelSide"          // "right" | "left" (global fallback)
    static let panelSidesByDisplayKey = "panelSidesByDisplay" // [displayID: "right"|"left"]
    static let panelPinnedKey = "panelPinned"      // Bool: disable auto-hide
    static let hotSideEnabledKey = "hotSideEnabled" // Bool
    static let showMarkupKey = "showMarkup"        // Bool: reveal Markdown markers
    static let didOnboardKey = "didOnboard"        // Bool
    static let panelWidthKey = "panelWidth"        // "standard" | "wide"
    static let densityKey = "density"              // "standard" | "compact"
    static let bodyFontSizeKey = "bodyFontSize"    // Double, default 12.5
    static let colorStyleKey = "colorStyle"        // "fullCard" | "leftBar"
    static let sortModeKey = "sortMode"            // "manual" | "newest" | "title"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            panelSideKey: "right",
            panelPinnedKey: false,
            hotSideEnabledKey: true,
            showMarkupKey: false,
            panelWidthKey: "standard",
            densityKey: "standard",
            bodyFontSizeKey: 12.5,
            colorStyleKey: "fullCard",
            sortModeKey: "manual",
        ])
    }

    // MARK: Panel side — global fallback + per-display memory (audit 6.13)

    /// The global fallback side, used for displays with no remembered side.
    static var panelSide: PanelSide {
        get {
            // Legacy call sites (Settings, status menu) mean "the main
            // display's side": a remembered side for it wins.
            if let main = NSScreen.main, let remembered = panelSide(for: main) {
                return remembered
            }
            return PanelSide(rawValue: UserDefaults.standard.string(forKey: panelSideKey) ?? "right") ?? .right
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: panelSideKey)
            if let main = NSScreen.main {
                setPanelSide(newValue, for: main)
            }
        }
    }

    /// The remembered side for a specific display, if one was ever set.
    static func panelSide(for screen: NSScreen) -> PanelSide? {
        guard let id = screen.displayID else { return nil }
        let map = UserDefaults.standard.dictionary(forKey: panelSidesByDisplayKey) as? [String: String] ?? [:]
        guard let raw = map[id] else { return nil }
        return PanelSide(rawValue: raw)
    }

    /// The effective side for a display: remembered, else the global fallback.
    static func effectivePanelSide(for screen: NSScreen) -> PanelSide {
        if let remembered = panelSide(for: screen) { return remembered }
        return PanelSide(rawValue: UserDefaults.standard.string(forKey: panelSideKey) ?? "right") ?? .right
    }

    static func setPanelSide(_ side: PanelSide, for screen: NSScreen) {
        guard let id = screen.displayID else {
            UserDefaults.standard.set(side.rawValue, forKey: panelSideKey)
            return
        }
        var map = UserDefaults.standard.dictionary(forKey: panelSidesByDisplayKey) as? [String: String] ?? [:]
        map[id] = side.rawValue
        UserDefaults.standard.set(map, forKey: panelSidesByDisplayKey)
    }

    static var panelPinned: Bool {
        get { UserDefaults.standard.bool(forKey: panelPinnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: panelPinnedKey) }
    }

    static var hotSideEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: hotSideEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: hotSideEnabledKey) }
    }

    // MARK: v0.4.0 preferences

    static var panelWidth: PanelWidth {
        get { PanelWidth(rawValue: UserDefaults.standard.string(forKey: panelWidthKey) ?? "standard") ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: panelWidthKey) }
    }

    static var density: PanelDensity {
        get { PanelDensity(rawValue: UserDefaults.standard.string(forKey: densityKey) ?? "standard") ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: densityKey) }
    }

    /// Body text size in points (audit 3.14): ⌘+ / ⌘− adjust it in the
    /// panel; default 12.5, step 0.5, clamped 11–16.
    static var bodyFontSize: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: bodyFontSizeKey)
            return stored == 0 ? 12.5 : min(max(stored, 11), 16)
        }
        set { UserDefaults.standard.set(min(max(newValue, 11), 16), forKey: bodyFontSizeKey) }
    }

    static var colorStyle: NoteColorStyle {
        get { NoteColorStyle(rawValue: UserDefaults.standard.string(forKey: colorStyleKey) ?? "fullCard") ?? .fullCard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: colorStyleKey) }
    }

    static var sortMode: NoteSortMode {
        get { NoteSortMode(rawValue: UserDefaults.standard.string(forKey: sortModeKey) ?? "manual") ?? .manual }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sortModeKey) }
    }
}

enum PanelSide: String {
    case left
    case right
}

enum PanelWidth: String {
    case standard
    case wide
}

enum PanelDensity: String {
    case standard
    case compact
}

enum NoteColorStyle: String {
    case fullCard
    case leftBar
}

enum NoteSortMode: String {
    case manual
    case newest
    case title
}

extension NSScreen {
    /// Stable per-display key for the side-memory map (CGDirectDisplayID).
    var displayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return number.stringValue
    }
}
