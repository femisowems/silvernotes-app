# SilverNotes v0.1.0 MVP — first build

SilverNotes is an original macOS edge-notes app: a panel that lives hidden at
the edge of your screen and slides in over whatever you are doing — including
full-screen apps — so a note is always one gesture away. Local-first, no
account, no server: your notes never leave your Mac.

**Version:** v0.1.0 MVP (first build)
**Platform:** macOS 13+, Universal (Apple silicon + Intel)
**Stack:** Swift + AppKit, a single dependency-free Swift Package.

> **Honest status — read this first.** This code was authored on a Linux VM,
> where AppKit does not exist, so **it has never been compiled or run**. It is
> written to compilable intent with care around the AppKit APIs it uses, but
> the first Mac compile may need small fixes (see the checklist at the
> bottom). Nothing in this README claims a feature "works" — it describes
> what is *implemented in code*; you are the first person who will see it run.

---

## Build & run on your Mac

You need Xcode 14+ (for the macOS 13 SDK) on macOS 13 or later.

**Option A — Xcode (recommended for the first build):**

1. Copy this `silvernotes-app` folder to your Mac.
2. Open `Package.swift` in Xcode (double-click it, or File → Open).
3. Wait for the package to resolve (there are no dependencies to fetch).
4. Choose the **SilverNotes** scheme, destination **My Mac**.
5. Press **Run** (⌘R). The app launches as an accessory app: no Dock icon.
   Look for the thin sliver at the right edge of your screen and the
   note icon in the menu bar.

**Option B — command line:**

```sh
cd silvernotes-app
swift build            # debug build
swift run SilverNotes  # build + launch
# or, release:
swift build -c release
./.build/release/SilverNotes
```

To quit: right-click the menu-bar note icon → **Quit SilverNotes**
(or `pkill SilverNotes` from Terminal).

**Your data** lives in `~/Library/Application Support/SilverNotes/`:
`store.json` (all folders + notes), `Attachments/` (embedded file copies),
`Backups/` (rotating snapshots, newest 7, taken at most hourly).

---

## How the two specs were used

This build follows **both** source documents; where they conflicted, the
Ambiguity Register and the adopted decisions won.

**From the Mockup Designs spec (visual geometry & tokens):**

- Panel width ~34% of the screen, Wide step ~48% noted as a future step
  (not in MVP — see Deferred), panel/card corner radii, spacing scale,
  card-stack layout with per-note footer, light + dark token palette,
  type scale (14 pt body, 20/17/15 headings), slide animation in the
  350–500 ms band (400 ms in, 350 ms out, cubic-bezier 0.25/0.1/0.25/1).

**From the Ambiguity Register + the 8 adopted decisions (behaviour, data,
platform):**

- Everything the mockups can't show: hide/show rules, Hot Side tuning,
  editor semantics, storage, Trash, modes, shortcuts, lock behaviour,
  focus return, and all 8 decisions listed below.

No conflicts required a judgement call beyond that rule: the mockups'
34% width and the register's 300–560 pt floor/cap combine as
"34%, clamped to 300–560 pt", which is what the code does.

---

## The 8 adopted decisions — where each lives in code

| # | Decision | Implementation |
|---|----------|----------------|
| 1 | Trash with 30-day retention | `NoteStore.moveToTrash / restoreFromTrash / purgeExpiredTrash` (soft-delete via `deletedAt`, auto-purge on launch), Trash view in `PanelContentController` |
| 2 | Flat folders; nesting reserved | `SNFolder.parentFolderID` exists in the schema, always nil in the MVP UI |
| 3 | $19.99 / major version, 30-day trial | Product fact only — noted in Settings; **no licensing or paywall is built into the MVP** |
| 4 | Name: SilverNotes | Throughout |
| 5 | Local-first MVP, no sync | JSON store on disk only; no CloudKit code anywhere (V1.1) |
| 6 | Double-click footer folds; body double-click selects a word | `FooterStripView.mouseDown` (clickCount == 2) in `NoteCardView.swift`; body untouched |
| 7 | Tables excluded from Markdown | `MarkdownEngine` has no table support; pasted tables land as plain-text lines |
| 8 | macOS 13+, Universal | `Package.swift` platform `.macOS(.v13)` |

---

## What is implemented (in code)

**Panel & triggers**

- `NSPanel` docked right by default (left selectable in Settings), width
  34% of the screen clamped to 300–560 pt, full height below the menu bar
  (`NSScreen.visibleFrame`), silver-grey translucent surface, rounded
  screen-away corner, slide animation ~400 ms with the mockup-spec easing;
  reduced-motion respected.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` so the
  panel overlays full-screen apps and appears in every Space.
- Collapsed sliver at the edge, mid-height; click opens the panel.
- Hot Side: 1–2 pt edge strip, ~200 ms dwell, suppressed while any mouse
  button is down (drag suppression), off switch in Settings.
- Drag-in auto-reveal: while dragging, entering a 12 pt edge zone for
  ~250 ms slides the panel in, ready to receive the drop.
- Global hotkey ⌃⌥⌘Space via Carbon `RegisterEventHotKey` — **no
  Accessibility permission prompt**.
- Click-outside hides, with an allow-list: menus, popovers, the share
  picker, save panels, alerts and the Settings window suspend auto-hide.
  Pin-open (header pin or Settings) disables auto-hide. Esc closes
  innermost-first (toolbar → selection → panel).
- Focus is captured before showing and restored to the previous app on hide.
- Panel hides on screen lock / session resign, always.
- Menu-bar icon: click toggles, right-click menu (New Note, Settings, Quit).

**Notes & folders**

- Folder home: flat folder rows, pinned first, note counts, colour dots,
  context menu (pin / rename / delete — deleting a folder sends its notes
  to Trash, never destroys them).
- Notes: vertical scrolling card stack; new note appears at the **top** and
  is focused. Header: back, folder title, search toggle, +, panel pin.
- Search across all folders, title matches first.
- Per-note footer: **Aa** (formatting popover), **pin**, **gear**,
  timestamp, **share** (`NSSharingServicePicker`), **trash**.
- Gear menu: Pin ⌥⌘P, Fold ⌥⌘⏎, Color (7 swatches + Default), Mode
  Standard ⌥⌘1 / Plain ⌥⌘2 / Code ⌥⌘3, Clear Completed Tasks,
  Export Note as Markdown.
- Panel-level ⌥⌘P / ⌥⌘⏎ / ⌥⌘1–3 act on the most recently edited card.

**Editor (Standard mode = hidden Markdown)**

- The card is the editor. Rendering is **attribute-only over the source
  text**: markers are visually concealed, characters never change, so
  undo contains only your edits and mode switches are byte-identical.
- Subset: headings, **bold**, *italic*, ~~strikethrough~~, ==underline==,
  ::highlight:: (pale yellow; requires non-alphanumeric boundaries so
  `std::vector` never triggers; unclosed markers render literally),
  `inline code`, fenced code blocks, [links](url), > quotes, bullet and
  numbered lists, `- [ ]` task lists, `---` separators.
- Tasks: click the checkbox glyph to tick/untick (an undoable source edit);
  the footer shows a done/total progress count.
- IME safety: rendering suspends while marked text is active and re-applies
  on commit.
- Floating quick-formatting toolbar on selection: Bold, Italic, Highlight,
  Strikethrough, Code, Link, Task — all implemented as source edits.
- Paste always lands as plain text (see Deferred for HTML conversion).
- Plain mode renders literally; Code mode is monospaced with spellcheck and
  substitutions off. Mode never mutates the stored source.

**Files**

- Drag a file onto a card (or drag to the edge to reveal the panel, then
  drop): the file is **copied into** the app's Attachments folder and shown
  as a preview card — image thumbnail + filename for images, Finder icon +
  filename for everything else. Click a preview to open the copy.
  *(Choice documented in `NoteStore.swift`: embedded copies instead of
  security-scoped bookmarks, so a note can never break when the original
  file moves; the cost is disk use.)*

**Data**

- Versioned JSON store (`schemaVersion: 1`), atomic writes, debounced
  saves while typing, rotating backup snapshots (hourly, keep 7), corrupt
  store is quarantined (never deleted) and the newest backup restored.
- Seed content on first run: a Welcome note, a build checklist, a coffee
  note, a "back burner" list — all original, written for SilverNotes.

**Settings**

- Dock side (left/right, applied immediately), Hot Side on/off, show-markup
  toggle, launch at login via `SMAppService` (real; starts hidden).

---

## Deferred to V1.1+ (not in this build — stated plainly)

- **CloudKit sync** (Decision 5) and the conflicted-copy strategy.
- **Drag-resize** of the panel and the **Wide (~48%) step**.
- **SQLite storage** — the register recommended SQLite via a third-party
  dependency; this build is deliberately dependency-free and uses a
  versioned JSON store instead (models are storage-agnostic, so the
  migration is a store-layer change).
- **Bulk export** (folder of Markdown files + JSON sidecar) and single-note
  image export. Single-note Markdown export *is* in the gear menu.
- **HTML → Markdown paste conversion**: paste is plain-text only in v0.1.0.
- **Full VoiceOver pass**: standard controls are used throughout and the
  panel is fully keyboard-reachable, but the custom editor has not had a
  dedicated VoiceOver audit.
- **Folder drag-reorder and note drag-reorder**: sorting is pinned-first,
  then stored order; new notes go to the top. Drag-reorder is not built.
- **Per-display side memory**: the panel follows the pointer's screen when
  summoned; the side setting is global, not per-display.
- **Licensing / trial enforcement** for the $19.99 pricing (Decision 3 is
  a product decision; no paywall exists in the MVP).
- Syntax highlighting inside code blocks (monospaced only in MVP).
- Pinch-to-fold, per-note fonts, tags, folder nesting UI (schema reserved).

---

## First-Mac-compile checklist

The code has never been compiled (authored on Linux; no macOS SDK there).
Expect the first build to need **small** fixes, most likely in these areas:

1. **Carbon hotkey glue** (`HotKeyManager.swift`) — the `InstallEventHandler`
   closure signature and `EventHotKeyID` construction are the most
   C-interop-sensitive lines in the project.
2. **Sliver drawing** (`PanelController.swift`, `SliverView.draw`) —
   `NSBezierPath.appendArc` angle directions may need flipping so the
   rounded corners land on the correct side.
3. **Card height updates** (`NoteCardView.updateTextHeight`) — if a card
   renders too tall/short, the fix is in the layout-manager used-rect
   calculation there.
4. **Attribute pass** (`NoteTextView.refreshRendering`) — if any styling
   looks doubled or missing, check the reset-then-apply order there.
5. General Swift 5.7+ strictness: any optionals or selector signatures the
   compiler flags. Selectors are stringly-typed in a few places
   (`#selector` targets are all `@objc` methods in the same class).

Fix loop: build in Xcode → the error list points at the file/line → the
code is organised so each concern lives in one file (panel, editor,
markdown, store, settings) → fix → ⌘R.

**Suggested first-run checks** (from the register's QA list): panel over a
full-screen app; panel in a second Space; lock the screen with the panel
open (it must hide); drag a file from Finder onto a note; type
`::these words::`, `std::vector`, and an unclosed `::` — only the first
should highlight; switch a note Standard → Code → Plain → Standard and
confirm the text is unchanged; quit and relaunch — notes, pins, folds and
Trash must be exactly as you left them.
