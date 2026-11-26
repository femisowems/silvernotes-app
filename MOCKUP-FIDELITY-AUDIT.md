# SilverNotes — Mockup Fidelity Audit (refreshed)

**Date:** Thu Nov 26, 2026
**App inspected:** SilverNotes v0.4.0 code (`~/workspace/silvernotes-app/Sources/SilverNotes/*.swift`, all 17 files read end to end)
**Design truth:** "SilverNotes Mockup Designs" package — built page `index.html` (CSS extracted directly) + the package's own spec prose (audit text, 2026-11-25T20-42-20Z). The package is byte-identical to the one used for the Nov 25 audit; every design-side value below is unchanged unless noted.
**Previous audit:** Nov 25, 2026, against v0.3.0 code — 138 items: 65 match / 43 mismatch / 19 missing / 7 extra / 4 unverifiable. v0.4.0 claimed (ROADMAP item 26) to fix everything fixable from that list. This audit re-verifies that claim item by item against the current code.

**Method:** same scheme as Nov 25 so the two audits are comparable. Every value is quoted from both sides — the mockup's rendered CSS where it exists, otherwise its spec prose (marked *prose*) — against the app's Swift constants. Where the package contradicts itself (prose vs its own rendered CSS), the verdict is graded against the **rendered** mockup, and the prose value is noted. Verdicts: **MATCH** / **MISMATCH** (both values quoted) / **MISSING IN APP** / **EXTRA IN APP** / **CANNOT VERIFY** (reason given). Approximations are graded MISMATCH, not MATCH. Each Nov 25 item also carries a delta: **fixed** / **partially fixed** / **still open** / **unchanged** / **re-graded** (with the reason). Items first graded in this audit are in §8. README and ROADMAP claims were treated as claims, not evidence; where a claim and the code disagree, the code wins and the disagreement is flagged.

---

## 1. Summary

**144 items graded** (the original 138, plus 6 new items in §8 covering surfaces the Nov 25 audit did not grade at element level: the formatting toolbar's contents, Compact's width and keyboard model, and the Wide rail's contents).

| Verdict | Nov 25 (v0.3.0) | Nov 26 (v0.4.0) |
|---------|------|------|
| MATCH | 65 | **126** |
| MISMATCH | 43 | **7** |
| MISSING IN APP | 19 | **4** |
| EXTRA IN APP | 7 | **5** |
| CANNOT VERIFY | 4 | **2** |

Of the 138 original items: **61 were fully fixed, 2 partially fixed** (2.18, 4.14 — the swatch set), 2 were re-graded on new evidence (4.44, 6.6), and the rest are unchanged. All 5 remaining extras are deliberate keeps (Export Note, folder pinning, Show Markdown markup, Check for Updates, the launch splash). Both remaining CANNOT VERIFY items are cases where the package itself supplies no values (dark note colours beyond Yellow; the heading scale).

**The headline:** the v0.4.0 claim is substantially true — the designed chrome (gear menu, Settings window, folder home, bottom bar, checklist, file cards, empty state) now exists and matches at value level, and the long tail of 1–2 pt / one-shade deltas is almost entirely gone. What remains is small but real, and two of the remaining items were *introduced or exposed by the fix pass itself* — see §4, items R1 and R2.

---

## 2. What v0.4.0 verifiably fixed

Each entry: Nov 25 verdict → Nov 26 verdict, with the code evidence.

**Geometry & panel**
- 1.3 Panel height — MISMATCH → MATCH. `PanelController.panelFrame`: `y = screen.frame.minY`, `height = visibleFrame.maxY − screen.frame.minY` — menu bar to physical screen bottom; a visible bottom Dock no longer lifts it.
- 1.6 Card padding — MISMATCH → MATCH (vs render). NoteCardView constraints engineered to the rendered 11 top / 13 sides: attachments at top 11 / sides 13; text scroll at 7 + the text view's 6 pt inset = 13 sides, and the −6 top constant + 6 inset = 11 top with no file block.
- 1.9 Gear menu radius — MISMATCH → MATCH. GearMenu is a custom panel, `cornerRadius = 10`.
- 1.12 Folder row radius — MISMATCH → MATCH (vs render). FolderRowView/UtilityRowView `cornerRadius = 10`.
- 1.17 Panel corners — MISMATCH → MATCH. Panel root `layer?.cornerRadius = 0` ("Square panel corners (audit 1.17): the package draws none"); `updateRoundedCorner` is now a no-op kept for call-site compatibility.

**Colour**
- 2.6 Focus ring — MISMATCH → MATCH. `SNTheme.accentRing` = #3F6EA5 @ 0.55 in **both** appearances; NoteCardView draws it at 2 pt while editing (as a border rather than an outline — visually equivalent).
- 2.8 Body text colour — MISMATCH → MATCH. New `SNTheme.bodyText` (#333338 / #D7D7DD) applied to body copy in all modes; titles/headings keep `primaryText`.
- 2.10 Footer text/icons — MISMATCH → MATCH. New `SNTheme.footerText` (#7A7A83 / #9D9DA7) on all footer buttons and the timestamp.
- 2.13 Highlight rendering — MISMATCH → MATCH. `SNLayoutManager.drawBackground` paints ::highlight:: ranges as a gradient marker band covering 55%→96% of the line height, from ranges the engine collects; no background attribute is set.
- 2.15 Task done, dark — MISMATCH → MATCH. `SNTheme.taskDone` = #34C759 in both appearances.
- 2.22 Link colour — MISMATCH → MATCH. New `SNTheme.link` = #2C6FBB, applied to rendered links and the file card's Quick Look row.
- 2.24 Pill button wash, dark — MISMATCH → MATCH. `pillButtonBackground` = rgba(120,120,135,0.14) in both appearances.
- 2.26 Open Bar icon colour — MISMATCH → MATCH. New `SNTheme.sliverIcon` (#55565E / #C9C9D1).
- 2.27 Gear menu surface/hover — MISMATCH → MATCH. `gearMenuBackground` rgba(250,250,252,0.96) light / rgba(44,44,50,0.97) dark (the dark value matches the rendered `.gearmenu` rule exactly); hover `gearMenuHover` = #3F6EA5 @ 0.14.
- 2.28 Card border — MISMATCH → MATCH. `layer?.borderWidth = 0` at rest; the border returns only as the 2 pt focus ring or the temporary drag-over ring.
- 2.29 Card shadow — MISMATCH → MATCH. Dual shadow per the package: light 0 1 3 rgba(20,22,30,.08) on the card layer + 0 4 14 rgba(20,22,30,.05) on a backing layer; dark 0 1 3 rgba(0,0,0,.4). (CSS blur radii are halved into `shadowRadius`, the standard Core Animation approximation — noted in the code.)

**Type**
- 3.1 Body size — MISMATCH → MATCH. Body size is now the `bodyFontSize` preference, default **12.5** (the rendered value).
- 3.4 Title weight — MISMATCH → MATCH (vs render). `titleFont` = body+1 at `.bold` (700).
- 3.5 Title line height — MISMATCH → MATCH. New `titleParagraphStyle`, lineHeightMultiple 1.3.
- 3.8 Folder row name weight — MISMATCH → MATCH (vs render). 13 pt `.semibold` (600) in FolderRowView and UtilityRowView.
- 3.9 Folder row count colour — MISMATCH → MATCH. Counts now use `tertiaryText` (#8E8E96); size unchanged at 11 pt.
- 3.12 Inline code size — MISMATCH → MATCH. New `inlineCodeFont`, SF Mono 11; block code stays 12.
- 3.13 Progress label colour — MISMATCH → MATCH. `tertiaryText` (#8E8E96); size unchanged at 10.5.
- 3.14 Global font size + ⌘+/⌘− — MISSING → MATCH. `Preferences.bodyFontSize` (default 12.5, step 0.5, clamped 11–16), ⌘+/⌘− handled in PanelController's key monitor with a full re-render, plus a stepper in Settings → Editor.

**Anatomy**
- 4.6 Header pill pin button — EXTRA → MATCH (extra removed). The pill now holds back / title / search / new-note only; Pin Panel Open moved to the overflow menu and Settings → General, where the package's model puts it.
- 4.8 Footer button size — MISMATCH → MATCH. 23×23 pt.
- 4.9 "Aa" rendering — MISMATCH → MATCH. A text button "Aa" in Georgia-Bold 11 pt, not the SF Symbol.
- 4.10 Timestamp, older notes — MISMATCH → MATCH. Weekday form: `"\(weekday) · \(time)"` ("Mon · 2:15 PM"); Today/Yesterday forms unchanged.
- 4.12 Folded card title — EXTRA → MATCH (extra removed). `foldedLabel.stringValue = note.title` — plain first line, no "▸ " prefix.
- 4.18 Gear menu typography — MISMATCH → MATCH. Custom menu: 12.5 pt items, 10.5 pt uppercase section labels in #8E8E96 with 0.63 kern, accent checkmarks (12.5 pt heavy), 11.5 pt shortcut text in the tertiary grey.
- 4.19 Checklist tick — MISMATCH → MATCH. SNLayoutManager draws a 15×15 circle over the (invisible) checkbox character: 1.5 pt #B9B9C2 ring when open (`taskRing`), #34C759 fill + white check when done.
- 4.20 Done task text — MISMATCH → MATCH. Tertiary #8E8E96 + single strikethrough, applied in MarkdownEngine.
- 4.22 Progress bar — MISSING → MATCH. `ProgressBarView`: 5 pt, track rgba(120,120,135,0.2), fill #34C759, label below the bar ("n of m done", 10.5 pt, #8E8E96) — matching the rendered `.progress` / `.progress-label` rules including the 7 pt / 3 pt spacing.
- 4.24 File name — MISMATCH → MATCH. 12.5 pt, weight .bold (700).
- 4.25 File meta provenance — MISMATCH → MATCH. Meta is "type · size · origin" with the origin recorded at capture time ("dropped in from Finder"); pre-v0.4.0 attachments show no provenance segment rather than a fabricated one.
- 4.26 Quick Look row — MISSING → MATCH. "Open in Quick Look" row under the meta, 11 pt in `link` #2C6FBB, presenting QLPreviewPanel; clicking the thumbnail/meta still opens the default app.
- 4.27 File block order — MISMATCH → MATCH. Attachments stack is anchored to the card top; the text scroll hangs below it.
- 4.28 Attachment container — MISMATCH → MATCH. No container: thumbnail + meta sit directly on the card; a non-image file shows a 28×28 workspace icon instead of the old tinted box.
- 4.29 / 4.30 All Notes / Pinned rows — MISSING → MATCH. Both rows head the folder home with live counts (and both exist in the Wide rail).
- 4.34 Settings entry — MISSING → MATCH. A gear **button** in the folder-home bottom bar; the Settings list row is gone.
- 4.37 / 4.38 Bottom-bar buttons — MISSING → MATCH. Fold/unfold-all and overflow (•••) buttons in note views; the overflow menu carries Pin Panel Open, the three sort modes, folder Markdown export, Check for Updates, Settings.
- 4.40 Empty-state icon tile — MISSING → MATCH. 54×54, radius 16, `emptyTileBackground` rgba(120,120,135,0.13), 26×26 folder glyph in #8E8E96 — the rendered `.emptybox .eic` values.
- 4.41 Empty headline — MISMATCH → MATCH. 14 pt bold.
- 4.42 Empty placement — MISMATCH → MATCH. The state fills the viewport (`fillViewport`) and its stack is centre-anchored on both axes.
- 4.43 New Note button — MISMATCH → MATCH. Flat `accentFill` #3F6EA5, white 12.5 pt semibold text, radius 8.
- 4.45 Settings structure — MISMATCH → MATCH. A 620×430 sidebar window with the package's five panes in order: General / Appearance / Editor / Backups / Shortcuts.
- 4.49 Panel width control — MISSING → MATCH. Standard/Wide segmented control in Settings → General.
- 4.50 Pin panel open in Settings — MISSING → MATCH. "Pin panel open (disables click-outside hide)" checkbox in Settings → General.
- 4.51 Licence row — MISMATCH → MATCH. A "Licence" heading + exactly "$19.99 one-time, per major version · 30-day direct trial"; the extra clauses are gone (the version footer is now just "SilverNotes v0.4.0").
- 4.52 Four panes — MISSING → MATCH. Appearance (colour style Full card / Left bar; density Standard / Compact), Editor (markup toggle, body-size stepper), Backups (snapshot count, most-recent, Open Backups Folder), Shortcuts (read-only list) all exist.

**Motion**
- 5.3 Gear menu appear — MISMATCH → MATCH. 140 ms, scale 0.97 → 1 + fade, easeOut. (Caveat: the Aa formatting *popover* still uses stock NSPopover animation — see R7.)
- 5.4 Formatting toolbar appear — MISMATCH → MATCH. 120 ms fade + 2 pt rise, easeOut.

**Behaviour**
- 6.10 Drop-target state — MISSING → MATCH. A panel-level overlay: dashed 2 pt accent border + centred "Drop to add as a file card"; drops anywhere on the panel create a note with the files attached.
- 6.11 Dropped files — MISMATCH → MATCH. `NoteStore.addAttachment`: images are copied (embedded, with thumbnails); every other file is **linked** (`linkedPath`, no copy). A linked file that moves renders "Original file not found" instead of a dead card, and deleting the attachment never touches the original.
- 6.12 Cursor-leave grace — MISSING → MATCH. Edge-revealed panels hide ~500 ms after the cursor leaves, cancelled by re-entry, any click or keypress into the panel, pin-open, or an open child interaction.
- 6.13 Per-display side memory — MISSING → MATCH. `panelSidesByDisplay` map keyed by CGDirectDisplayID, with the global preference as fallback; Settings' segmented control sets the current display's side.
- 6.14 Drag-reorder — MISSING → MATCH. Footer-strip press held ~150 ms then moved past ~4 pt starts the drag (the package's "~4 pt + 150 ms hold"); the drop permutes existing `sortIndex` values and never crosses the pinned-group boundary.

**Variations**
- 7.1 Compact density — MISSING → MATCH (existence and chrome; the width is graded separately as 8.2). Capture field pinned under the header ("Capture a thought…" + "⌘ ⏎" hint), one-line rows (pin, first line, timestamp), selected row solid with a 1.5 pt accent outline, keyboard-hints bar with the count at the right.
- 7.2 Wide step + folder rail — MISSING → MATCH (rail contents delta at 8.3). ~48% width step (clamped 380–1000) with the 118 pt folder rail replacing the drill-in home; the header chevron is suppressed in Wide.

**Partially fixed**
- 2.18 Note colour set & names — the #FFC9C2 token is now **labelled "Red"** (stored raw value "pink" unchanged, so existing notes decode identically), and the gear-menu order now leads with the package's six. But the set still carries **8 tokens** — Orange #FFD9B0 and Gray #E3E3E8 remain, where the package has 6.
- 4.14 Swatch row — size (19×19), selected ring (2 pt accent, outset 4 pt, drawn as an overlay so the swatch stays 19×19), and the order of the package's six now match. The row still shows 8 swatches, not 6 — the same delta as 2.18, kept deliberately because existing notes use Orange and Gray.

---

## 3. Full item table

### 1. Geometry & radii

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 1.1 | Panel width | 34% of screen | `visibleFrame.width * 0.34` | MATCH | unchanged |
| 1.2 | Width clamp | 300 pt / 560 pt | `min(max(…, 300), 560)` | MATCH | unchanged |
| 1.3 | Panel height | Menu bar → screen bottom (CSS `top:26px; bottom:0`) | `y = screen.frame.minY`, height to `visibleFrame.maxY` — physical bottom | MATCH | **fixed** |
| 1.4 | Panel side padding | 12 pt | stack edge insets 12 left/right | MATCH | unchanged |
| 1.5 | Card stack gap | 10 pt | `stackView.spacing = 10` | MATCH | unchanged |
| 1.6 | Card padding | rendered: 11 top / 13 sides / 7 bottom (*prose* spec table: 12) | 11 top / 13 sides by construction (see §2) | MATCH (vs render; prose says 12) | **fixed** |
| 1.7 | Note card radius | 12 pt | 12 | MATCH | unchanged |
| 1.8 | Header pill radius | 999 pt (pill) | height 36, radius 18 (full pill) | MATCH | unchanged |
| 1.9 | Gear menu radius | 10 pt | custom panel, radius 10 | MATCH | **fixed** |
| 1.10 | Formatting toolbar radius | 9 pt | 9 | MATCH | unchanged |
| 1.11 | File thumbnail radius | 7–8 pt | 7 | MATCH | unchanged |
| 1.12 | Folder row radius | rendered: 10 px (*prose*: 7–8 pt) | 10 | MATCH (vs render; matches prose no longer) | **fixed** |
| 1.13 | Footer button radius | 6 pt | 6 | MATCH | unchanged |
| 1.14 | Swatch radius | 50% | 50% (19 pt circle, radius 9.5) | MATCH | unchanged |
| 1.15 | Open Bar size | 22 × 118 pt | 22 × 118 | MATCH | unchanged |
| 1.16 | Open Bar shape | rendered: radius `10px 0 0 10px` (screen-away corners) (*prose* table: 999 pt pill) | drawn path, r = 10 on screen-away corners, square at edge | MATCH (vs render; package prose contradicts its own render) | unchanged |
| 1.17 | Panel corners | square (no radius in CSS) | `cornerRadius = 0` | MATCH | **fixed** |

### 2. Colour tokens

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 2.1 | Panel, light | #EDEEF1 @ 88% + blur | #EDEEF1 @ 0.88 over visual-effect view | MATCH | unchanged |
| 2.2 | Panel, dark | #222226 @ 90% + blur | #222226 @ 0.90 | MATCH | unchanged |
| 2.3 | Card, light | #FFFFFF | #FFFFFF | MATCH | unchanged |
| 2.4 | Card, dark | #2E2E33 | #2E2E33 | MATCH | unchanged |
| 2.5 | Card selected, dark | #3A3A41 | #3A3A41 (editing lift, uncoloured notes) | MATCH | unchanged |
| 2.6 | Focus ring | 2 px outline rgba(63,110,165,0.55), both appearances | 2 pt border, #3F6EA5 @0.55 in both appearances (`accentRing`) | MATCH | **fixed** |
| 2.7 | Text primary (token) | #1D1D1F / #F2F2F5 | #1D1D1F / #F2F2F5 | MATCH | unchanged |
| 2.8 | Body text as rendered | #333338 / #D7D7DD (`.note p`) | `bodyText` #333338 / #D7D7DD for body copy | MATCH | **fixed** |
| 2.9 | Text secondary | #6E6E73 / #9A9AA3 | #6E6E73 / #9A9AA3 | MATCH | unchanged |
| 2.10 | Footer text/icons | #7A7A83 / #9D9DA7 (`.note-foot`) | `footerText` #7A7A83 / #9D9DA7 | MATCH | **fixed** |
| 2.11 | Accent (steel) | #3F6EA5 / #7AA7D9 | #3F6EA5 / #7AA7D9 | MATCH | unchanged |
| 2.12 | Highlight value | #FFE58A / #FFCC00 @ 50% | #FFE58A / #FFCC00 @ 0.5 | MATCH | unchanged |
| 2.13 | Highlight rendering | marker band (gradient, 55%→96% of line height) | marker band drawn 55%→96% by SNLayoutManager | MATCH | **fixed** |
| 2.14 | Task done, light | #34C759 | #34C759 | MATCH | unchanged |
| 2.15 | Task done, dark | #34C759 (same rule both appearances) | #34C759 both appearances | MATCH | **fixed** |
| 2.16 | Pinned | #B8860B | #B8860B | MATCH | unchanged |
| 2.17 | Note colours — shared values | Default #FFFFFF, Yellow #FFE9A8, Red #FFC9C2, Green #CDEAC0, Blue #BCD7F5, Purple #E3CDF5 | identical hex for none/yellow/pink/green/blue/purple | MATCH | unchanged |
| 2.18 | Note colour set & names | 6 tokens: Default, Yellow, **Red**, Green, Blue, Purple | 8 tokens: the package's six (with #FFC9C2 now labelled **Red**) + **Orange** #FFD9B0, **Gray** #E3E3E8 | MISMATCH (two extra colours; name and order now match) | **partially fixed** |
| 2.19 | Note colours as full card backgrounds | yes (Settings option for left-bar exists in package) | yes, full background; the left-bar option now exists too (Settings → Appearance) | MATCH | unchanged (option added) |
| 2.20 | Note colour dark variants | only Yellow specified: #3D3A28 | Yellow #3D3A28 ✓; orange #453723, pink #453034, green #2C3E2A, blue #2A3648, purple #3A2E4A, gray #333338 (app-invented) | CANNOT VERIFY (package gives no values for the others) | unchanged |
| 2.21 | Swatches | light card colours, both appearances | light card colours, both appearances | MATCH | unchanged |
| 2.22 | Link colour | #2C6FBB (`.note a.lnk`, file-card link) | `link` #2C6FBB both appearances | MATCH | **fixed** |
| 2.23 | Header pill surface | rgba(255,255,255,0.85) / rgba(58,58,64,0.90) | #FFFFFF @0.85 / #3A3A40 @0.90 | MATCH | unchanged |
| 2.24 | Pill button wash, dark | rgba(120,120,135,0.14) (no dark override) | rgba(120,120,135,0.14) both appearances | MATCH | **fixed** |
| 2.25 | Open Bar surface + border | #F0F0F4 @75% / #28282E @80%; border rgba(60,60,70,0.20) / white 0.14 | identical values | MATCH | unchanged |
| 2.26 | Open Bar icon colour | #55565E / #C9C9D1 | `sliverIcon` #55565E / #C9C9D1 | MATCH | **fixed** |
| 2.27 | Gear menu surface/hover | rgba(250,250,252,0.96), hover rgba(63,110,165,0.14); dark surface rgba(44,44,50,0.97) | identical values in `gearMenuBackground` / `gearMenuHover` | MATCH | **fixed** |
| 2.28 | Card border | none (shadow only) | none at rest; 2 pt accent ring only while editing or drag-hovering | MATCH | **fixed** |
| 2.29 | Card shadow | dual: 0 1px 3px rgba(20,22,30,.08) + 0 4px 14px rgba(20,22,30,.05); dark 0 1px 3px rgba(0,0,0,.4) | dual, same colours/opacities/offsets (blur radii halved into `shadowRadius`, the CA approximation) | MATCH | **fixed** |
| 2.30 | Built-in themes | *prose*: "three built-in themes in the MVP" | one token palette | MISSING IN APP | still open (blocked on a spec — the package names no themes; ROADMAP item 28) |

### 3. Typography

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 3.1 | Body size | rendered 12.5 px (*prose*: 12.5–13 pt) | 12.5 pt default (`bodyFontSize`) | MATCH (vs render) | **fixed** |
| 3.2 | Body line height | 1.5 | 1.5 (`lineHeightMultiple`) | MATCH | unchanged |
| 3.3 | Title (first line) size | 13.5 pt | body+1 = 13.5 pt at default size | MATCH | unchanged |
| 3.4 | Title weight | rendered: 700 (*prose*: semibold) | `.bold` (700) | MATCH (vs render; prose says semibold) | **fixed** |
| 3.5 | Title line height | 1.3 (`.note h5`) | 1.3 (`titleParagraphStyle`) | MATCH | **fixed** |
| 3.6 | Heading sizes (H1–H3) | not specified anywhere in the package | 17 bold / 15 semibold / 14 semibold | CANNOT VERIFY (no package values exist) | unchanged |
| 3.7 | Header pill folder name | 13 pt, weight 700 | 13 pt bold | MATCH | unchanged |
| 3.8 | Folder row name | rendered: 13 px weight 600 (*prose*: medium) | 13 pt semibold (600) | MATCH (vs render; prose says medium) | **fixed** |
| 3.9 | Folder row count | 11 px, #8E8E96 | 11 pt, #8E8E96 (`tertiaryText`) | MATCH | **fixed** |
| 3.10 | Footer + timestamp size | 10.5–11 pt | 10.5 pt | MATCH | unchanged |
| 3.11 | Code mode font | SF Mono 12 pt | SF Mono 12 pt | MATCH | unchanged |
| 3.12 | Inline code chip | 11 px mono on rgba(120,120,135,0.16) | 11 pt mono (`inlineCodeFont`) on matching tint | MATCH | **fixed** |
| 3.13 | Progress label | 10.5 px, #8E8E96 | 10.5 pt, #8E8E96 (`tertiaryText`) | MATCH | **fixed** |
| 3.14 | Global font family/size setting, ⌘+/⌘− | *prose*: global settings, ⌘+/⌘− adjust | `bodyFontSize` preference (12.5 default, 11–16), ⌘+/⌘− in the panel, stepper in Settings → Editor | MATCH | **fixed** |

### 4. Anatomy per view

#### Header pill (notes view)

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.1 | Back chevron (folder view only) | yes; absent at folder home | present in folder, hidden at home (and suppressed in Wide, where the rail replaces home) | MATCH | unchanged |
| 4.2 | Folder name | 13 pt bold | 13 pt bold | MATCH | unchanged |
| 4.3 | Sync caption | "Local only — sync arrives in V1.1", 10.5 pt #6E6E73, green #34C759 dot, below the pill | identical text/size/colour, "●" glyph in #34C759, below the pill; hidden at folder home (mockup home has none) | MATCH | unchanged |
| 4.4 | Search button | yes | yes (toggles an inline search field in the pill; ⌘F also opens it) | MATCH | unchanged |
| 4.5 | New-note button | yes | yes | MATCH | unchanged |
| 4.6 | Pin-panel button | not in the pill | removed from the pill; lives in the overflow menu + Settings → General | MATCH | **fixed** (extra removed) |

#### Note card & footer

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.7 | Footer order | Aa · pin · gear · timestamp · share · trash | identical order | MATCH | unchanged |
| 4.8 | Footer button size | 23 × 23 px | 23 × 23 pt | MATCH | **fixed** |
| 4.9 | "Aa" button rendering | serif "Aa" letters (Georgia, 700, 11 px) | "Aa" text button, Georgia-Bold 11 pt | MATCH | **fixed** |
| 4.10 | Timestamp, older notes | weekday form: "Mon · 2:15 PM" | weekday form via `EEE` formatter ("Mon · 2:15 PM") | MATCH | **fixed** |
| 4.11 | Footer on folded cards | footer never disappears | footer stays visible when folded | MATCH | unchanged |
| 4.12 | Folded card title | plain first line | plain first line (`note.title`) | MATCH | **fixed** (extra prefix removed) |

#### Gear menu

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.13 | Pin / Fold items + shortcuts | Pin ⌥⌘P, Fold ⌥⌘⏎, check when active | identical items, shortcuts, state checks | MATCH | unchanged |
| 4.14 | Swatch row | 6 swatches, order Default, Yellow, Red, Green, Blue, Purple; 19 × 19 px in-menu; selected = 2 px accent ring outset 4 px | 8 swatches — the package's six first, in order, then Orange, Gray; 19 × 19 pt; selected = 2 pt accent ring outset 4 pt (overlay) | MISMATCH (count 8 vs 6; order, size, ring now match) | **partially fixed** |
| 4.15 | Mode items | Standard ✓ / Plain Text / Code, ⌥⌘1/2/3 | identical, checkmark on active mode | MATCH | unchanged |
| 4.16 | Clear Completed Tasks | in the component inventory (not drawn in the hero menu) | present | MATCH | unchanged |
| 4.17 | Export Note as Markdown… | not in the package | present, below Clear Completed | EXTRA IN APP (deliberate keep) | unchanged |
| 4.18 | Menu typography | 12.5 px items, 10.5 px uppercase section labels #8E8E96, accent checkmarks, 11.5 px shortcut text | identical values in the custom GearMenu | MATCH | **fixed** |

#### Checklist rendering

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.19 | Tick control | drawn circle 15 × 15 px, 1.5 px border #B9B9C2; done = #34C759 fill + white ✓ | drawn 15×15 circle over the checkbox character: 1.5 pt #B9B9C2 ring; done = #34C759 fill + white check | MATCH | **fixed** |
| 4.20 | Done task text | #8E8E96 + strikethrough | #8E8E96 (`tertiaryText`) + strikethrough | MATCH | **fixed** |
| 4.21 | "n of m done" label | yes, below the progress bar | yes, below the progress bar | MATCH | unchanged (bar now exists — 4.22) |
| 4.22 | Progress bar | 5 px bar, track rgba(120,120,135,0.2), fill #34C759 | 5 pt bar, identical track/fill | MATCH | **fixed** |

#### File card

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.23 | Thumbnail | 74 × 62 px, radius 7 | 74 × 62 pt, radius 7 | MATCH | unchanged |
| 4.24 | Filename | 12.5 px, weight 700 | 12.5 pt bold | MATCH | **fixed** |
| 4.25 | Meta line | "JPEG image · 3.8 MB · dropped in from Finder" | "type · size · origin", origin recorded at capture time; absent (never fabricated) on pre-v0.4.0 attachments | MATCH | **fixed** |
| 4.26 | "Open in Quick Look" row | 11 px link #2C6FBB under the meta | present, 11 pt, #2C6FBB, opens QLPreviewPanel | MATCH | **fixed** |
| 4.27 | File block vs body text order | file block first, body text below | file block first, body text below | MATCH | **fixed** |
| 4.28 | Attachment container | none — thumbnail + meta sit on the card | none — thumbnail + meta sit on the card | MATCH | **fixed** |

#### Folder home

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.29 | All Notes row (with count) | yes, first row | present, first row, live count | MATCH | **fixed** |
| 4.30 | Pinned row (with count) | yes, second row | present, second row, live count | MATCH | **fixed** |
| 4.31 | Folder rows | icon tile 30 × 30 r8, name, count, chevron | same structure (rows 44 pt; the illustration's ≈50 px is not a 1:1 pt value — see §6) | MATCH (structure) | unchanged |
| 4.32 | Trash row | "2 · kept 30 days" detail | identical detail format | MATCH | unchanged |
| 4.33 | Bottom-bar line | "5 folders · flat list" | "N folder(s) · flat list" | MATCH | unchanged |
| 4.34 | Settings entry | gear **button** in the bottom bar | gear **button** in the bottom bar | MATCH | **fixed** |
| 4.35 | Folder pinning (gold pin on rows) | not in the package | pinned folders show a gold pin; pin via context menu | EXTRA IN APP (deliberate keep) | unchanged |

#### Bottom bar (notes view)

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.36 | Note count | "4 notes" | "N note(s)" | MATCH | unchanged (Wide form differs — 8.4) |
| 4.37 | Fold / unfold all button | yes | present; icon flips with state | MATCH | **fixed** |
| 4.38 | Overflow (•••) button | yes | present; menu = Pin Panel Open · sort modes · Export … as Markdown… · Check for Updates… · Settings… | MATCH | **fixed** |

#### Empty state

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.39 | Copy | "Nothing in Recipes yet" + teaching line + New Note button | identical teaching copy, "Nothing in <folder> yet", button present | MATCH | unchanged |
| 4.40 | Icon tile | 54 × 54 px, radius 16, folder glyph | 54 × 54 pt, radius 16, 26 pt glyph | MATCH | **fixed** |
| 4.41 | Headline size | 14 px bold | 14 pt bold | MATCH | **fixed** |
| 4.42 | Placement | vertically centred | vertically centred (state fills the viewport) | MATCH | **fixed** |
| 4.43 | New Note button | flat accent fill #3F6EA5, white text, radius 8 | flat #3F6EA5 fill, white 12.5 pt semibold, radius 8 | MATCH | **fixed** |
| 4.44 | First-run welcome variant | *prose*: "The same component serves the first-run state, with the folder name swapped for a welcome line" | no variant exists: `emptyFolderState` always renders "Nothing in <folder> yet"; the store seeds a welcome **note** instead | MISSING IN APP | **re-graded** (was CANNOT VERIFY — the store and panel code are now both read; the variant is absent) |

#### Settings window

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.45 | Window structure | sidebar window, 5 panes: General / Appearance / Editor / Backups / Shortcuts | sidebar window 620 × 430, same 5 panes in order (window size itself: no package value — §6) | MATCH | **fixed** |
| 4.46 | General — Launch at login | toggle, shown ON ("on by default") | checkbox reflecting the real SMAppService state (off until enabled) + status line | MATCH (control present; default differs — the app reports the real login-item state rather than a drawn default) | unchanged |
| 4.47 | General — Hot Side trigger | toggle + "Edge strip + ~200 ms dwell" | checkbox with equivalent wording | MATCH | unchanged |
| 4.48 | General — Panel side | segmented Right / Left | segmented Left / Right, per-display | MATCH | unchanged |
| 4.49 | General — Panel width (Standard / Wide) | segmented control | present | MATCH | **fixed** |
| 4.50 | General — Pin panel open | toggle, "Disables click-outside hide" | checkbox, "Pin panel open (disables click-outside hide)" | MATCH | **fixed** |
| 4.51 | General — Licence row | "$19.99 one-time, per major version · 30-day direct trial" | identical line under a "Licence" heading | MATCH | **fixed** |
| 4.52 | Appearance / Editor / Backups / Shortcuts panes | yes | all four exist (contents graded at package level: the package names the panes and, for Appearance, the colour-style option — present) | MATCH | **fixed** |
| 4.53 | "Show Markdown markup" toggle | not in the package | present (Editor pane) | EXTRA IN APP (deliberate keep) | unchanged |
| 4.54 | Check for Updates row | not in the package | present (added at the user's request after the package) | EXTRA IN APP (deliberate keep) | unchanged |

#### Other surfaces

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 4.55 | Open Bar chevron | 13 px glyph | 13 pt semibold chevron glyph | MATCH | unchanged |
| 4.56 | Launch loading screen | no counterpart in the package | 280 × 180 splash, icon + name + spinner + "Loading your notes…" (added at the user's request after the package) | EXTRA IN APP (deliberate keep) | unchanged |

### 5. Motion

| # | Item | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 5.1 | Panel slide | 280 ms, cubic-bezier(0.32, 0.72, 0, 1) | 0.28 s, CAMediaTimingFunction(0.32, 0.72, 0, 1), both directions | MATCH | unchanged |
| 5.2 | Fold / unfold | 200 ms ease-in-out | 0.2 s easeInEaseOut animation context in `toggleFold` | MATCH | unchanged |
| 5.3 | Gear menu / popovers | 140 ms, scale 0.97 → 1 + fade | gear menu: 140 ms, scale 0.97 → 1 + fade. The Aa formatting popover still uses stock NSPopover animation | MATCH (gear menu; popover caveat at R7) | **fixed** |
| 5.4 | Formatting toolbar appear | 120 ms fade + 2 pt rise | 120 ms fade + 2 pt rise, easeOut | MATCH | **fixed** |
| 5.5 | Reduce Motion | all slides → 120 ms crossfades | panel show/hide → 120 ms crossfade; splash fade shortens to 120 ms | MATCH | unchanged |

### 6. Behaviour rules

| # | Rule | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|------|--------|-----|---------|----|
| 6.1 | Click-outside hides | yes | global mouse monitor hides on outside click | MATCH | unchanged |
| 6.2 | Allow-list (panel's own popovers don't hide it) | yes | child-interaction counter + window-based suspension (gear menu, popovers, save panels, Quick Look, Settings, splash) | MATCH | unchanged |
| 6.3 | Pin-open disables auto-hide | yes ("disables every auto-hide path") | `panelPinned` guard disables click-away and the cursor-leave grace | MATCH | unchanged |
| 6.4 | Always hides on lock | yes | session-resign + screen-locked → immediate hide | MATCH | unchanged |
| 6.5 | Focus returns to previous app | yes | previous app captured on show, reactivated on hide | MATCH | unchanged |
| 6.6 | Esc behaviour | ladder specified **for Compact**: menu → toolbar → selection → card → panel | one ladder everywhere: toolbar → panel close (no selection or card step) | MISMATCH (deliberate deviation, at the user's explicit direction — ROADMAP check 28 verifies the one-press close; not a defect to "fix" without his word) | **re-graded** (was CANNOT VERIFY — the package's Compact rule is gradeable now that Compact exists) |
| 6.7 | Footer double-click folds; body double-click selects a word | yes (register decision 6) | both implemented | MATCH | unchanged |
| 6.8 | Hot Side | 1–2 pt strip, ~200 ms dwell, off switch, suppressed during drags | ≤2 pt, 0.2 s dwell, preference off switch (monitors removed), drag suppression | MATCH | unchanged |
| 6.9 | Drag-in reveal | ~12 pt zone, ~250 ms dwell | ≤12 pt, 0.25 s dwell | MATCH | unchanged |
| 6.10 | Drop-target state | dashed accent panel "Drop to add as a file card" | panel-level overlay: dashed accent border + centred "Drop to add as a file card" | MATCH | **fixed** |
| 6.11 | Dropped files | "linked, not copied — images are embedded" | non-images linked (path recorded, no copy); images embedded with thumbnails | MATCH | **fixed** |
| 6.12 | Cursor-leave grace (Hot Side mode) | ~500 ms before the panel slides away | 0.5 s timer for edge-revealed panels; cancelled by interaction, pin, or child UI | MATCH | **fixed** |
| 6.13 | Per-display side memory | side remembered per display | `panelSidesByDisplay` keyed by display ID + global fallback | MATCH | **fixed** |
| 6.14 | Drag-reorder | ~4 pt threshold + 150 ms hold | footer-strip press ≥150 ms + >4 pt movement starts the drag | MATCH | **fixed** |

### 7. Variations

| # | Variation | Mockup | App (v0.4.0) | Verdict | Δ since Nov 25 |
|---|-----------|--------|-----|---------|----|
| 7.1 | Compact density (capture field, one-line rows, keyboard hints bar) | full design (Variation B) | built: capture field, one-line rows, hints bar, row expand on ⏎ (width graded at 8.2; keyboard model at 8.5) | MATCH | **fixed** |
| 7.2 | Wide step + folder rail (Variation C, ~48%) | full design | built: ~48% step, folder rail replaces drill-in home (rail contents delta at 8.3) | MATCH | **fixed** |

### 8. New items — first graded in this audit

Surfaces the Nov 25 audit graded only in aggregate (or not at all), graded now at element level.

| # | Item | Mockup | App (v0.4.0) | Verdict |
|---|------|--------|-----|---------|
| 8.1 | Formatting toolbar contents | B · I · **U** · S ｜ H ｜ link · checklist (rendered `.fmtbar`: "B I U S H" + link/checklist icons; *prose*: "bold, italic, underline, strikethrough, highlight, link, checklist") | B · I · H · S · **<>** · Link · ☑ — **no Underline button**; an Inline code button the package doesn't list. The Aa popover carries the same seven actions (also no Underline). The engine round-trips `==underline==`; only the buttons are missing | MISMATCH |
| 8.2 | Compact panel width | "Same 34% panel, different density" (*prose*, twice) + spec table "Same 34% width — rows, not cards" + CSS: `.panel` is 34% with no Compact override | `width = min(max(visibleFrame.width * 0.34, 272), 300)` — on a 1512 pt screen the panel narrows from ~514 pt to 300 pt in Compact | MISMATCH |
| 8.3 | Wide rail — New Folder row | rail lists "New Folder" between the folders and Trash (rendered) | rail has All Notes, Pinned, FOLDERS label, folders, Trash — no New Folder row (folder creation lives in the Standard-width home's + button) | MISSING IN APP |
| 8.4 | Wide bottom-bar count | "4 notes in Personal" (rendered, Variation C) | "N note(s)" in every width | MISMATCH (minor) |
| 8.5 | Compact keyboard model — ↑/↓ condition | *prose*: "↑/↓ move between rows **when the cursor sits at a card's first/last line**" (i.e. while editing) | ↑/↓/⏎ handled only when the first responder is **not** a text view; while a card is being edited the arrows do nothing at panel level | MISMATCH (minor, behavioural) |
| 8.6 | Open Bar vs Dock | component inventory: the Open Bar "hides when the Dock shares its edge" | sliver is ordered front unconditionally at mid-height of the visible frame; no Dock-edge hiding logic exists | MISSING IN APP (minor; inventory-level spec only) |

---

## 4. Remaining deltas, ordered by visibility / impact

**R1 — Compact narrows the panel; the package says it must not (8.2).** The widest remaining delta, and the one that most directly contradicts the "everything fixable fixed" claim: the package states three times (Variation B prose, the Variation C prose, and the spec table) that Compact is "the same 34% width — rows, not cards", and its CSS gives `.panel` a single 34% width with no Compact variant. The app clamps Compact to 272–300 pt. The code comment justifying the clamp cites "(audit 7.1)" for the 272–300 values — the Nov 25 audit contains no such values; it graded Compact only as absent. This is a new mismatch introduced by the fix pass, invisible to the current confirmation checklist: ROADMAP check 29 exercises Compact's capture field, rows and hints bar but never measures the panel's width.

**R2 — No Underline button on either formatting surface (8.1).** The mockup's toolbar (state 4, rendered) is B I **U** S ｜ H ｜ link, checklist, and its prose lists underline explicitly. The app's toolbar and Aa popover both omit Underline and include an Inline code button the package doesn't list. The omission is not a parser gap — `==underline==` round-trips in the engine — so a user can type the marks but can't discover them from the UI. The Nov 25 audit never graded toolbar contents, which is how this survived a "fix everything" pass.

**R3 — First-run welcome empty state is absent (4.44).** The package: "The same component serves the first-run state, with the folder name swapped for a welcome line." The app's empty state always names the folder, and the seeded Personal folder is empty — so the very first empty folder a new user opens says "Nothing in Personal yet" where the package designs a welcome. (The seeded welcome *note* is a different mechanism and doesn't cover this.)

**R4 — Wide rail has no New Folder row (8.3).** The rendered rail runs …folders → New Folder → Trash. The app's rail ends …folders → Trash. Creating a folder in Wide currently requires leaving the rail flow (the header + button files a *note* in Wide; folder creation exists only at the Standard-width home).

**R5 — Swatch set still carries two extra colours (2.18, 4.14).** Orange and Gray remain alongside the package's six. Naming ("Red") and order are now correct, so the residual delta is count only. This one is disclosed and deliberate — existing notes use both colours, and deleting tokens would orphan them — but side-by-side the colour row still differs from the package.

**R6 — Esc ladder (6.6).** The package's Compact ladder (menu → toolbar → selection → card → panel) vs the app's toolbar → panel everywhere. A deliberate deviation at the user's explicit direction (he asked for the one-press close; ROADMAP check 28 verifies it). Recorded as a mismatch for fidelity, not as a defect.

**R7 — Small fry.** The Aa formatting popover still animates with stock NSPopover motion where 5.3's rule covers "gear menu / popovers" (the gear menu itself now complies). Compact's ↑/↓ work only when not editing, where the package's model is cursor-at-first/last-line while editing (8.5). Wide's bottom bar reads "4 notes" where the package's Wide render reads "4 notes in Personal" (8.4). The Open Bar doesn't hide when the Dock shares its edge (8.6, inventory-level spec). The empty-state teaching line wraps at ≤210 pt where the render caps it at 24ch (≈150 pt at 12 px) — the app's line runs slightly wider.

**Not deltas:** the five extras (4.17 Export Note, 4.35 folder pinning, 4.53 Show Markdown markup, 4.54 Check for Updates, 4.56 launch splash) are post-package additions made at the user's request and read as deliberate keeps. Built-in themes (2.30) remain missing but are genuinely unbuildable from the package — it names no themes and gives no values (ROADMAP item 28 tracks the spec gap, correctly).

**Housekeeping found along the way (not graded):** `NoteColorToken.swatches` in Models.swift is now dead code with a stale comment ("7 swatches… offered as a separate 'Default' menu item") that no longer describes the gear menu, which uses `gearMenuOrder`. Harmless; worth deleting before it misleads a future edit.

---

## 5. Unverifiable — what only an on-device pass can settle

Two kinds: (a) the package supplies no value to grade against, and (b) the code states an intent whose rendered result only a running Mac can confirm. Mapped to the ROADMAP's confirmation checklist (the live round is checks 16–30 on a v0.4.0 install).

| Item | Why code can't settle it | Settled by |
|------|--------------------------|------------|
| 2.20 Dark variants for Orange/Red/Green/Blue/Purple/Gray | The package specifies only Yellow's dark value (#3D3A28); the app's other dark variants are invented and can only be judged by eye against the package's *intent* ("stays readable instead of glowing") | Check 19 (dark-mode pass) — a judgement call, not a value check |
| 3.6 Heading scale (app: 17/15/14) | No heading sizes exist anywhere in the package | Nothing in checks 16–30 grades headings; settles only if the package is amended |
| Panel translucency as rendered (2.1, 2.2) | Code sets #EDEEF1 @0.88 / #222226 @0.90 over an NSVisualEffectView (.sidebar material); the composite over a real desktop can't be derived from constants | Checks 16, 19 (light/dark visual pass) |
| Slide feel (5.1) | The curve values match exactly; the package itself calls the feel "a Spike 1 exit criterion, tuned on a real Mac" | Check 24–30 round generally; no single check names it |
| Dual shadow as rendered (2.29) | Colours/opacities/offsets match; blur is approximated (CSS blur ÷ 2 → `shadowRadius`) — whether the card's lift reads the same is visual | Checks 16–19 |
| Focus ring as border vs outline (2.6) | Values match; the app draws a border where CSS draws an outline — identical at rest, different only if the card's edge is composited against busy content | Check 17 (card anatomy read) |
| Folder row height (4.31) | The rendered illustration measures ≈50 px but is not drawn at 1:1 pt scale, so the app's 44 pt can be neither confirmed nor refuted from the package | Check 20 (folder-home read) — by eye |
| Settings window size (4.45) | The package's Settings is a framed illustration with no pt dimensions; the app's 620×430 is ungradeable | Check 29 (Settings pass) — by eye |
| Wide rail width (7.2) | The package gives no rail width in pt (its CSS rail is in illustration scale); the app uses 118 pt | Check 29 (Wide step) — by eye |
| Compact capture: does ⌘⏎ file the note? (7.1) | The package's keyboard model says the capture field "takes ⌘⏎ to file"; the app binds the field's standard action, which Return fires — whether ⌘Return also fires it is an AppKit behaviour, not visible in the code | Not covered by checks 16–30 (check 29 covers Compact's rows/hints, not its filing key) — needs a 10-second Mac test |
| Compact width (8.2) | **Not unverifiable — graded MISMATCH from code.** Listed here only to note that no current check would catch it: check 29 doesn't measure panel width | A ruler, or one line added to check 29 |
| First-run state end to end (4.44 + seeding) | The missing welcome variant is verified in code; what a genuinely fresh install *feels* like (seed folders, first empty folder, splash timing) needs a clean data folder | ROADMAP item 2 (clean-room pass), outside checks 16–30 |

---

## 6. Package-internal inconsistencies (carried from Nov 25 — all still present)

The package disagrees with itself in six places. In each case the app followed one of the two sources; this audit grades against the rendered mockup and notes the prose.

1. **Open Bar shape** — prose table says 999 pt pill; rendered CSS is `10px 0 0 10px`. The app follows the render.
2. **Folder row radius** — prose says 7–8 pt; rendered CSS is 10 px. The app now follows the render (was: prose).
3. **Folder row name weight** — prose says medium; CSS is 600. The app now follows the render (was: prose).
4. **Title weight** — prose (type table) says semibold; CSS h5 is 700. The app now follows the render (was: prose).
5. **Body size** — prose range 12.5–13 pt; CSS is exactly 12.5 px. The app now takes the render's 12.5 (was: top of range, 13).
6. **Hero yellow card** — the drawn "hallway repaint" card renders #FFF7D6, not the token Yellow #FFE9A8. The app follows the token.
7. **Card padding** — spec table says 12 pt; rendered CSS is 11 top / 13 sides / 7 bottom. The app now follows the render.

**Not extractable from the package:** dark variants for note colours other than Yellow (only #3D3A28 is given); any heading type scale (H1–H3 sizes appear nowhere); the Hot Side strip as a rendered element (prose only); exact Settings-window and Wide-rail dimensions (framed illustrations, not sized windows); per-pane Settings contents beyond General (the package names the five panes and the Appearance colour-style option, and grades nothing finer).

**Out of scope (unchanged from Nov 25):** the package's data-layer spec (SQLite/FTS5 store, bookmark-based file links, backup schedule, `silvernote://` URL scheme) was not graded — the assigned categories cover the visual and interaction surface. For the record, the app uses a JSON store and hourly/7-deep backup rotation, which the package's storage table does not describe; both are tracked as deliberate deviations in the ROADMAP (items 11 and the Backups pane) rather than here.
