import AppKit

/// Layout manager with two custom background passes, both driven by
/// ranges the MarkdownEngine collected during its attribute-only render
/// — the source string and every offset in it stay exactly as typed:
///
/// - Highlight bands (audit 2.13): ::highlight:: ranges are drawn as a
///   marker band — a soft-edged gradient covering 55%→96% of the line
///   height — instead of a full-line-height background wash.
/// - Checklist ticks (audit 4.19): each task's checkbox character (made
///   invisible by the render) gets a drawn 15×15 circle over its cell:
///   a 1.5 pt #B9B9C2 ring when open, a #34C759 fill with a white check
///   when done.
final class SNLayoutManager: NSLayoutManager {

    /// Task markers from the latest render (empty unless ticks show).
    var tickMarkers: [TaskMarker] = []
    /// ::highlight:: ranges from the latest render.
    var highlightRanges: [NSRange] = []

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first else { return }
        let charsToShow = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // MARK: Highlight marker bands
        let highlight = SNTheme.highlightBackground
        let clearHighlight = highlight.withAlphaComponent(0)
        for range in highlightRanges {
            let intersection = NSIntersectionRange(range, charsToShow)
            guard intersection.length > 0 else { continue }
            let glyphRange = glyphRange(forCharacterRange: intersection, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, fragmentGlyphs, _ in
                let overlap = NSIntersectionRange(fragmentGlyphs, glyphRange)
                guard overlap.length > 0 else { return }
                let bounds = self.boundingRect(forGlyphRange: overlap, in: container)
                let band = NSRect(x: bounds.minX + origin.x,
                                  y: rect.minY + origin.y + rect.height * 0.55,
                                  width: bounds.width,
                                  height: rect.height * 0.41)
                let gradient = NSGradient(colors: [clearHighlight, highlight, clearHighlight])
                gradient?.draw(in: band, angle: -90)
            }
        }

        // MARK: Checklist ticks
        for marker in tickMarkers {
            let intersection = NSIntersectionRange(marker.checkboxCharRange, charsToShow)
            guard intersection.length > 0 else { continue }
            let glyphRange = glyphRange(forCharacterRange: marker.checkboxCharRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            let glyphIndex = glyphRange.location
            let fragment = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let bounds = boundingRect(forGlyphRange: glyphRange, in: container)
            let centre = NSPoint(x: bounds.midX + origin.x, y: fragment.midY + origin.y)
            let circle = NSRect(x: centre.x - 7.5, y: centre.y - 7.5, width: 15, height: 15)
            let path = NSBezierPath(ovalIn: circle)
            if marker.isChecked {
                SNTheme.taskDone.setFill()
                path.fill()
                // White check, drawn in the text view's flipped space:
                // mid-left → dip → top-right.
                let check = NSBezierPath()
                check.move(to: NSPoint(x: centre.x - 4.2, y: centre.y + 0.4))
                check.line(to: NSPoint(x: centre.x - 1.3, y: centre.y + 3.1))
                check.line(to: NSPoint(x: centre.x + 4.6, y: centre.y - 3.4))
                check.lineWidth = 1.8
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                SNTheme.taskRing.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }
}
