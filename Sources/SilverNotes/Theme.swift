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

    /// The panel bottom bar's top rule (v0.6.0 rubric §1.13): a touch
    /// stronger than the card-footer hairline in light mode —
    /// rgba(120,120,135,0.20); dark matches the hairline's white 0.10.
    static var panelBottomBorder: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.20),
                dark: NSColor(calibratedWhite: 1, alpha: 0.10))
    }

    /// The header pill's 1 pt border (rubric §1.4): rgba(60,60,70,0.10)
    /// light, rgba(255,255,255,0.09) dark — distinct from cardBorder.
    static var headerPillBorder: NSColor {
        dynamic(light: NSColor(srgbRed: 60/255, green: 60/255, blue: 70/255, alpha: 0.10),
                dark: NSColor(calibratedWhite: 1, alpha: 0.09))
    }

    /// The panel's screen-facing edge line (rubric §1.2):
    /// rgba(60,60,70,0.18) light, rgba(255,255,255,0.12) dark.
    static var panelEdgeBorder: NSColor {
        dynamic(light: NSColor(srgbRed: 60/255, green: 60/255, blue: 70/255, alpha: 0.18),
                dark: NSColor(calibratedWhite: 1, alpha: 0.12))
    }

    /// Text selection wash inside a note (rubric §1.5):
    /// rgba(63,110,165,0.32) in both appearances.
    static var selectionBackground: NSColor { hex(0x3F6EA5, alpha: 0.32) }

    /// File-card thumbnail border (rubric §1.9): rgba(60,60,70,0.12);
    /// the package gives no dark override.
    static var fileThumbBorder: NSColor {
        NSColor(srgbRed: 60/255, green: 60/255, blue: 70/255, alpha: 0.12)
    }

    /// Gear-menu swatch border (rubric §1.10): rgba(60,60,70,0.15);
    /// no dark override in the package.
    static var swatchBorder: NSColor {
        NSColor(srgbRed: 60/255, green: 60/255, blue: 70/255, alpha: 0.15)
    }

    /// Folder-row chevron (rubric §1.12): #B9B9C2, no dark override.
    static var rowChevron: NSColor { hex(0xB9B9C2) }

    /// Drop-target overlay fill (rubric §2 A14): rgba(255,255,255,0.6)
    /// light; dark is unspecified in the package, so the dark card
    /// surface at the same alpha stands in.
    static var dropTargetBackground: NSColor {
        dynamic(light: NSColor(calibratedWhite: 1, alpha: 0.6),
                dark: hex(0x2E2E33, alpha: 0.6))
    }

    /// Settings window surfaces (rubric §1.16). The package renders
    /// Settings in light only; the dark values are the nearest neutral
    /// steps, unverifiable against the package.
    static var settingsWindowBackground: NSColor {
        dynamic(light: hex(0xF5F5F7),
                dark: hex(0x1E1E21))
    }

    static var settingsSidebarBackground: NSColor {
        dynamic(light: hex(0xECECF1),
                dark: hex(0x2C2C31))
    }

    static var settingsSidebarBorder: NSColor {
        dynamic(light: hex(0xDDDDE3),
                dark: NSColor(calibratedWhite: 1, alpha: 0.10))
    }

    /// The floating header pill's surface.
    static var headerPillBackground: NSColor {
        dynamic(light: hex(0xFFFFFF, alpha: 0.85),
                dark: hex(0x3A3A40, alpha: 0.90))
    }

    /// Circular icon buttons inside the header pill. The design package
    /// gives the wash as rgba(120,120,135,0.14) with no dark override
    /// (audit 2.24), so both appearances use it.
    static var pillButtonBackground: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.14),
                dark: NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.14))
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

    /// Body copy as rendered in the package's notes (`.note p`) — a step
    /// softer than the primary token, which titles/headings keep (2.8).
    static var bodyText: NSColor {
        dynamic(light: hex(0x333338),
                dark: hex(0xD7D7DD))
    }

    /// Tertiary text: folder counts, progress labels, menu shortcuts,
    /// done-task text. The package uses #8E8E96 in both appearances (3.9).
    static var tertiaryText: NSColor { hex(0x8E8E96) }

    /// Card footer text and icons (`.note-foot`, audit 2.10).
    static var footerText: NSColor {
        dynamic(light: hex(0x7A7A83),
                dark: hex(0x9D9DA7))
    }

    /// Link colour for note links and the file card's Quick Look row
    /// (audit 2.22) — the same in both appearances.
    static var link: NSColor { hex(0x2C6FBB) }

    /// The Open Bar's chevron colour (audit 2.26).
    static var sliverIcon: NSColor {
        dynamic(light: hex(0x55565E),
                dark: hex(0xC9C9D1))
    }

    /// Custom gear-menu surfaces (audit 2.27): near-opaque, blurred.
    static var gearMenuBackground: NSColor {
        dynamic(light: NSColor(srgbRed: 250/255, green: 250/255, blue: 252/255, alpha: 0.96),
                dark: NSColor(srgbRed: 44/255, green: 44/255, blue: 50/255, alpha: 0.97))
    }

    static var gearMenuBorder: NSColor {
        dynamic(light: NSColor(calibratedRed: 0.24, green: 0.24, blue: 0.27, alpha: 0.14),
                dark: NSColor(calibratedWhite: 1, alpha: 0.12))
    }

    static var gearMenuText: NSColor {
        dynamic(light: hex(0x26262B),
                dark: hex(0xEEEEF2))
    }

    /// Row hover wash inside the custom gear menu.
    static var gearMenuHover: NSColor { hex(0x3F6EA5, alpha: 0.14) }

    /// Hairline separators inside the custom gear menu.
    static var gearMenuSeparator: NSColor {
        NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.22)
    }

    /// Checklist tick ring for an open task (audit 4.19).
    static var taskRing: NSColor { hex(0xB9B9C2) }

    /// Progress-bar track (audit 4.22).
    static var progressTrack: NSColor {
        NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.20)
    }

    /// Empty-state icon tile wash (audit 4.40).
    static var emptyTileBackground: NSColor {
        NSColor(calibratedRed: 0.47, green: 0.47, blue: 0.53, alpha: 0.13)
    }

    /// The flat accent fill of the empty state's New Note button (4.43):
    /// the package draws #3F6EA5 in both appearances.
    static var accentFill: NSColor { hex(0x3F6EA5) }

    /// Steel accent (links, focus ring, New Note, folder glyphs).
    static var accent: NSColor {
        dynamic(light: hex(0x3F6EA5),
                dark: hex(0x7AA7D9))
    }

    /// The focus ring: 2 pt, #3F6EA5 @ 0.55 in BOTH appearances
    /// (audit 2.6 — the dark appearance does not switch to the light
    /// steel). Drawn at 2 pt by the card while editing.
    static var accentRing: NSColor { hex(0x3F6EA5, alpha: 0.55) }

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

    /// Task green — the package's rule is the same in both appearances
    /// (audit 2.15).
    static var taskDone: NSColor { hex(0x34C759) }

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

    // The body size is a user preference (audit 3.14: ⌘+ / ⌘−, default
    // 12.5 per the rendered package, audit 3.1), so the body-derived
    // fonts are computed from it rather than fixed lets.
    static var bodyFont: NSFont { NSFont.systemFont(ofSize: CGFloat(Preferences.bodyFontSize)) }
    /// First line of a note — its title (also the folded card's label):
    /// body + 1 pt at weight 700 (audit 3.3, 3.4).
    static var titleFont: NSFont { NSFont.systemFont(ofSize: CGFloat(Preferences.bodyFontSize) + 1, weight: .bold) }
    static var boldBodyFont: NSFont { NSFont.systemFont(ofSize: CGFloat(Preferences.bodyFontSize), weight: .bold) }
    static let codeFont: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// Inline `code` chips render a step smaller than block code (3.12).
    static let inlineCodeFont: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
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

    /// The title line runs tighter than the body: 1.3 (audit 3.5).
    static let titleParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        return style
    }()
}
