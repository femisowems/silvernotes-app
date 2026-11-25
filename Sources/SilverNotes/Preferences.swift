import Foundation

/// UserDefaults keys + typed accessors for SilverNotes v0.1.0 preferences.
enum Preferences {
    static let panelSideKey = "panelSide"          // "right" | "left"
    static let panelPinnedKey = "panelPinned"      // Bool: disable auto-hide
    static let hotSideEnabledKey = "hotSideEnabled" // Bool
    static let showMarkupKey = "showMarkup"        // Bool: reveal Markdown markers
    static let didOnboardKey = "didOnboard"        // Bool

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            panelSideKey: "right",
            panelPinnedKey: false,
            hotSideEnabledKey: true,
            showMarkupKey: false,
        ])
    }

    static var panelSide: PanelSide {
        get { PanelSide(rawValue: UserDefaults.standard.string(forKey: panelSideKey) ?? "right") ?? .right }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: panelSideKey) }
    }

    static var panelPinned: Bool {
        get { UserDefaults.standard.bool(forKey: panelPinnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: panelPinnedKey) }
    }

    static var hotSideEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: hotSideEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: hotSideEnabledKey) }
    }
}

enum PanelSide: String {
    case left
    case right
}
