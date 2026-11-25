import AppKit

/// Token-based colours for SilverNotes v0.1.0. Everything in the UI reads
/// colours from here (never hard-coded at the call site) so the palette can
/// be remapped later without touching views. Light/dark variants follow the
/// system appearance automatically via dynamic providers.
enum SNTheme {

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// The light silver-grey panel surface — the "Silver" in SilverNotes.
    static var panelBackground: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.95, alpha: 0.97),
                dark: NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 0.97))
    }

    static var cardBackground: NSColor {
        dynamic(light: .white,
                dark: NSColor(calibratedRed: 0.23, green: 0.23, blue: 0.25, alpha: 1))
    }

    static var cardBorder: NSColor {
        dynamic(light: NSColor(calibratedWhite: 0, alpha: 0.08),
                dark: NSColor(calibratedWhite: 1, alpha: 0.10))
    }

    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var accent: NSColor { .controlAccentColor }

    /// Pale-yellow highlight used by ::highlight:: in both appearances.
    static var highlightBackground: NSColor {
        dynamic(light: NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.55, alpha: 1),
                dark: NSColor(calibratedRed: 0.55, green: 0.47, blue: 0.13, alpha: 1))
    }

    static var codeBackground: NSColor {
        dynamic(light: NSColor(calibratedWhite: 0, alpha: 0.06),
                dark: NSColor(calibratedWhite: 1, alpha: 0.10))
    }

    static var taskDone: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.20, green: 0.66, blue: 0.32, alpha: 1),
                dark: NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.45, alpha: 1))
    }

    static var sliverBackground: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.88, alpha: 0.85),
                dark: NSColor(calibratedRed: 0.30, green: 0.30, blue: 0.33, alpha: 0.85))
    }

    /// Background tint for a note colour token (used as a soft card tint).
    static func tint(for token: NoteColorToken) -> NSColor {
        switch token {
        case .none:
            return cardBackground
        case .yellow:
            return dynamic(light: NSColor(calibratedRed: 1.00, green: 0.98, blue: 0.86, alpha: 1),
                           dark: NSColor(calibratedRed: 0.36, green: 0.33, blue: 0.18, alpha: 1))
        case .orange:
            return dynamic(light: NSColor(calibratedRed: 1.00, green: 0.93, blue: 0.83, alpha: 1),
                           dark: NSColor(calibratedRed: 0.38, green: 0.27, blue: 0.16, alpha: 1))
        case .pink:
            return dynamic(light: NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.93, alpha: 1),
                           dark: NSColor(calibratedRed: 0.38, green: 0.22, blue: 0.27, alpha: 1))
        case .purple:
            return dynamic(light: NSColor(calibratedRed: 0.94, green: 0.90, blue: 1.00, alpha: 1),
                           dark: NSColor(calibratedRed: 0.30, green: 0.24, blue: 0.40, alpha: 1))
        case .blue:
            return dynamic(light: NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.00, alpha: 1),
                           dark: NSColor(calibratedRed: 0.20, green: 0.29, blue: 0.42, alpha: 1))
        case .green:
            return dynamic(light: NSColor(calibratedRed: 0.89, green: 0.98, blue: 0.90, alpha: 1),
                           dark: NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.22, alpha: 1))
        case .gray:
            return dynamic(light: NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.95, alpha: 1),
                           dark: NSColor(calibratedRed: 0.27, green: 0.27, blue: 0.29, alpha: 1))
        }
    }

    /// Solid swatch colour shown in the gear menu's Color row.
    static func swatch(for token: NoteColorToken) -> NSColor {
        switch token {
        case .none: return .white
        case .yellow: return NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.35, alpha: 1)
        case .orange: return NSColor(calibratedRed: 0.98, green: 0.65, blue: 0.30, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.70, alpha: 1)
        case .purple: return NSColor(calibratedRed: 0.70, green: 0.55, blue: 0.95, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.40, green: 0.65, blue: 0.98, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.45, green: 0.80, blue: 0.50, alpha: 1)
        case .gray: return NSColor(calibratedRed: 0.62, green: 0.62, blue: 0.65, alpha: 1)
        }
    }

    // MARK: Fonts

    static var bodyFont: NSFont { NSFont.systemFont(ofSize: 14) }
    static var codeFont: NSFont { NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) }
    static func headingFont(level: Int) -> NSFont {
        let size: CGFloat = level == 1 ? 20 : (level == 2 ? 17 : 15)
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }
}
