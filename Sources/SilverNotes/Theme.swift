import AppKit

/// Token-based colours for SilverNotes. Everything in the UI reads colours
/// from here (never hard-coded at the call site) so the palette can be
/// remapped without touching views. Light/dark variants follow the system
/// appearance automatically via dynamic providers.
///
/// v0.2.0: values lifted from the approved design package (Variation A) —
/// steel accent, exact text greys, note colours as FULL card backgrounds.
enum SNTheme {

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// Exact sRGB colour from a 0xRRGGBB design-package hex value.
    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                green: CGFloat((value >> 8) & 0xFF) / 255.0,
                blue: CGFloat(value & 0xFF) / 255.0,
                alpha: alpha)
    }

    /// The light silver-grey panel surface — the "Silver" in SilverNotes.
    /// Translucent over the panel's blur, per the design package.
    static var panelBackground: NSColor {
        dynamic(light: hex(0xEDEEF1, alpha: 0.88),
                dark: hex(0x222226, alpha: 0.90))
    }

    static var cardBackground: NSColor {
        dynamic(light: hex(0xFFFFFF),
                dark: hex(0x2E2E33))
    }

    /// Background of the card currently being edited. Only dark lifts a
    /// step; in light the focus cue is the accent ring instead.
    static var cardFocusedBackground: NSColor {
        dynamic(light: hex(0xFFFFFF),
                dark: hex(0x3A3A41))
    }

    static var cardBorder: NSColor {
        dynamic(light: NSColor(calibratedWhite: 0, alpha: 0.08),
                dark: NSColor(calibratedWhite: 1, alpha: 0.10))
    }

    /// 1 pt separators (card footer rule, panel bottom rule).
    static var hairline: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.16),
                dark: NSColor(calibratedWhite: 1, alpha: 0.10))
    }

    /// The floating header pill's surface.
    static var headerPillBackground: NSColor {
        dynamic(light: hex(0xFFFFFF, alpha: 0.85),
                dark: hex(0x3A3A40, alpha: 0.90))
    }

    /// Circular icon buttons inside the header pill.
    static var pillButtonBackground: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.14),
                dark: NSColor(calibratedWhite: 1, alpha: 0.12))
    }

    /// Hover wash for footer buttons.
    static var hoverBackground: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.15),
                dark: NSColor(calibratedWhite: 1, alpha: 0.12))
    }

    static var primaryText: NSColor {
        dynamic(light: hex(0x1D1D1F),
                dark: hex(0xF2F2F5))
    }

    static var secondaryText: NSColor {
        dynamic(light: hex(0x6E6E73),
                dark: hex(0x9A9AA3))
    }

    /// Steel accent (links, focus ring, New Note, folder glyphs).
    static var accent: NSColor {
        dynamic(light: hex(0x3F6EA5),
                dark: hex(0x7AA7D9))
    }

    /// The accent at ring strength, for the focused card's border.
    static var accentRing: NSColor {
        dynamic(light: hex(0x3F6EA5, alpha: 0.55),
                dark: hex(0x7AA7D9, alpha: 0.55))
    }

    /// The accent as a soft tile wash (folder-row icon tiles).
    static var accentSoftBackground: NSColor {
        dynamic(light: hex(0x3F6EA5, alpha: 0.13),
                dark: hex(0x7AA7D9, alpha: 0.18))
    }

    /// The gold of a pinned note's pin (same in both appearances).
    static var pinnedActive: NSColor { hex(0xB8860B) }

    /// Marker highlight used by ::highlight::.
    static var highlightBackground: NSColor {
        dynamic(light: hex(0xFFE58A),
                dark: hex(0xFFCC00, alpha: 0.5))
    }

    static var codeBackground: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.16),
                dark: NSColor(calibratedWhite: 1, alpha: 0.10))
    }

    static var taskDone: NSColor {
        dynamic(light: hex(0x34C759),
                dark: hex(0x4BE07A))
    }

    /// The Open Bar (collapsed sliver) surface and edge.
    static var sliverBackground: NSColor {
        dynamic(light: hex(0xF0F0F4, alpha: 0.75),
                dark: hex(0x28282E, alpha: 0.80))
    }

    static var sliverBorder: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.24, green: 0.24, blue: 0.27, alpha: 0.20),
                dark: NSColor(calibratedWhite: 1, alpha: 0.14))
    }

    /// Full card background for a note colour token (v0.2.0: colours are
    /// the whole card, not a soft tint).
    static func tint(for token: NoteColorToken) -> NSColor {
        switch token {
        case .none:
            return cardBackground
        case .yellow:
            return dynamic(light: hex(0xFFE9A8),
                           dark: hex(0x3D3A28))
        case .orange:
            return dynamic(light: hex(0xFFD9B0),
                           dark: hex(0x453723))
        case .pink:
            return dynamic(light: hex(0xFFC9C2),
                           dark: hex(0x453034))
        case .purple:
            return dynamic(light: hex(0xE3CDF5),
                           dark: hex(0x3A2E4A))
        case .blue:
            return dynamic(light: hex(0xBCD7F5),
                           dark: hex(0x2A3648))
        case .green:
            return dynamic(light: hex(0xCDEAC0),
                           dark: hex(0x2C3E2A))
        case .gray:
            return dynamic(light: hex(0xE3E3E8),
                           dark: hex(0x333338))
        }
    }

    /// Solid swatch colour shown in the gear menu's colour row: the LIGHT
    /// card colours in both appearances, per the design package.
    static func swatch(for token: NoteColorToken) -> NSColor {
        switch token {
        case .none: return hex(0xFFFFFF)
        case .yellow: return hex(0xFFE9A8)
        case .orange: return hex(0xFFD9B0)
        case .pink: return hex(0xFFC9C2)
        case .purple: return hex(0xE3CDF5)
        case .blue: return hex(0xBCD7F5)
        case .green: return hex(0xCDEAC0)
        case .gray: return hex(0xE3E3E8)
        }
    }

    // MARK: Fonts

    // Fonts are immutable value objects handed out on every render pass;
    // build each one once instead of re-creating it per access.
    static let bodyFont: NSFont = NSFont.systemFont(ofSize: 13)
    /// First line of a note — its title (also the folded card's label).
    static let titleFont: NSFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    static let boldBodyFont: NSFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    static let codeFont: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let headingFonts: [NSFont] = [
        NSFont.systemFont(ofSize: 17, weight: .bold),
        NSFont.systemFont(ofSize: 15, weight: .semibold),
        NSFont.systemFont(ofSize: 14, weight: .semibold),
    ]
    static func headingFont(level: Int) -> NSFont {
        headingFonts[min(max(level, 1), 3) - 1]
    }

    /// Body copy runs at 1.5 line height, in the render pass and in the
    /// editor's typing attributes alike, so text never jumps as it renders.
    static let bodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.5
        return style
    }()
}
