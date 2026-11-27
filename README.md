<p align="center">
  <img src="AppIcon-1024.png" width="160" alt="SilverNotes app icon — a white note card with a pale-yellow highlight line on a silver panel">
</p>

<h1 align="center">SilverNotes for Mac</h1>

<p align="center"><strong>Notes that live at the edge of your screen — one gesture away, never in your way.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.6.2-e4572e.svg" alt="Latest version">
  <img src="https://img.shields.io/badge/macOS-13%2B-silver" alt="macOS 13 or later">
  <img src="https://img.shields.io/badge/Swift-AppKit-orange" alt="Swift and AppKit">
  <img src="https://img.shields.io/badge/dependencies-none-brightgreen" alt="No dependencies">
</p>

SilverNotes is a tiny macOS app that keeps your notes in a panel docked to
the edge of your screen. The panel stays hidden — just a thin silver sliver
at the edge — and slides in over whatever you are doing, including
full-screen apps, when you push your pointer to the edge, press a global
shortcut, or click the sliver. Click anywhere else and it slides away,
handing focus back to the app you were in. It is **local-first: no account,
no server, no sync, no tracking** — your notes are a file on your Mac and
nothing ever leaves the machine.

*(Silver, for the light silver-grey panel the notes live on.)*

> 🚧 **Work in progress** — SilverNotes is at **v0.6.2**: the
> everything-expanded default, corrected — every note in a
> list renders as its full card at once, in every density
> (v0.6.1's Compact accordion, top note only, was superseded
> the same day), on top of v0.6.0, the
> Variation A visual pass (header pill, cards, folder rows, bottom
> bar, gear menu, formatting toolbar and Settings aligned to the
> final mockup's exact values; the search field no longer clips
> its "Search all notes" placeholder; notes now load expanded —
> folding is session-only) on top of v0.5.1, the
> bug-fix release (Standard-density lists render again, the panel
> takes keyboard focus on open, Compact double-click expansion
> works) on top of v0.4.0, the full
> mockup-fidelity release — every fixable item from a 138-point
> audit against the design package (custom gear menu, folder home
> with All Notes/Pinned, bottom-bar actions, five-pane Settings,
> Compact density, the Wide step with folder rail, drawn checklist
> ticks and progress bar, marker-band highlights, linked file
> drops, drag-reorder) — on top of v0.3.0's Check for Updates and
> launch loading screen.
> The MVP is **confirmed working** on a real Mac (MacBook Air,
> macOS 26) as of November 25, 2026 — with a few first-use bugs,
> which are tracked in [ROADMAP.md](ROADMAP.md).
> v0.5.0 was installed and used on a real Mac on November 26, 2026,
> via the app's own Check for Updates — the self-update path
> confirmed working end to end. v0.5.1, v0.6.0, v0.6.1 and v0.6.2 are CI-built;
> their on-device confirmation is pending in the milestone capture
> round (see the [status notes](#honest-status)). Features, behaviour
> and this README may change between versions, and things may break.
> Nothing below claims a feature "works" beyond what the code does;
> the [status notes](#honest-status) are kept current.

---

## Features

- **Accessory app, no Dock icon** — SilverNotes lives as a note icon in
  your menu bar plus the edge sliver. First launch shows the panel once
  so you can see it; after that it starts hidden, the way it is meant to
  be used.

### Summoning the panel

- **Hot Side** — push the pointer into the last 1–2 pt of the screen edge
  and hold for ~200 ms; the panel slides in. Suppressed while you are
  dragging anything (drags have their own path, below), and can be
  switched off in Settings.
- **Global hotkey ⌃⌥⌘Space** — works from any app, registered through the
  Carbon hot-key API, so there is **no Accessibility permission prompt**.
  If another app already owns the combo, the failure is logged instead of
  failing silently.
- **Click the sliver** — the thin strip at the docked edge, mid-height.
- **Menu-bar icon** — left-click toggles the panel; right-click opens a
  menu (New Note, Hot Side toggle, dock side, Settings, About, Quit).
- **Double-click the app** in Finder/Applications while it is already
  running — the panel opens (relaunching a hidden accessory app should
  never be a no-op).
- **Drag-in auto-reveal** — drag a file toward the edge and hold ~250 ms
  in the wider 12 pt zone; the panel slides in ready to receive the drop.

### The panel itself

- **~34% of the screen wide** (clamped to 300–560 pt), full height below
  the menu bar, docked right by default or left if you prefer, with a
  rounded screen-away corner and the silver-grey surface the app is
  named for. Light and dark appearance both supported.
- **Overlays everything** — `canJoinAllSpaces + fullScreenAuxiliary`, so
  it appears in every Space and over full-screen apps.
- **Click outside to dismiss** — with an allow-list: while a menu,
  popover, share picker, save panel, alert, or the Settings window is
  open, auto-hide is suspended so the panel never vanishes mid-action.
- **Pin it open** — pin the panel open from Settings → General or
  the bottom-bar overflow menu; pinning disables auto-hide when you
  want the panel to stay put. (There is no header pin.)
- **Esc closes the panel in one press** — a deliberate deviation
  from the design package, made at the user's direction: Esc does
  not ladder through the formatting toolbar or the text selection
  first.
- **Focus is borrowed, not stolen** — the app you were in is remembered
  and re-activated when the panel hides.
- **Hides on screen lock**, always. Notes never stay exposed on a locked
  Mac.
- Slide-in verifies itself: after the animation the panel's frame is
  checked against the screen, and snapped into place if the animation
  did not land — a safety net, kept even though the first build's
  "double-click and nothing happens" behaviour turned out to be a
  launch crash, not an animation problem (see
  [Honest status](#honest-status)).

### Notes and folders

- **Folder home** — flat folder rows (pinned first) with note counts and
  colour dots; right-click a row to pin, rename, or delete it. Deleting
  a folder sends its notes to the Trash — it never destroys them.
- **Card stack** — notes are cards in a scrolling column; a new note
  lands at the **top**, already focused. Header carries back, folder
  title, search, and +.
- **Search across all folders**, title matches first, then body matches.
- **Per-note footer on every card** — **Aa** (formatting popover), pin,
  gear menu, timestamp, share (`NSSharingServicePicker`), trash.
- **Gear menu** — Pin (⌥⌘P), Fold (⌥⌘⏎), Color (7 swatches + Default),
  Mode (Standard ⌥⌘1 / Plain Text ⌥⌘2 / Code ⌥⌘3), Clear Completed
  Tasks, Export Note as Markdown.
- **Panel shortcuts** ⌥⌘P / ⌥⌘⏎ / ⌥⌘1–3 act on the card you most
  recently edited.

### The editor — the card is the editor

- **Hidden Markdown, honestly implemented.** In Standard mode you type
  Markdown and it renders in place — but rendering is **attribute-only
  over the source text**. Marker characters are visually concealed,
  never removed: the file on disk and the text in the editor are always
  your exact source, undo contains only *your* edits, and switching a
  note between Standard, Plain, and Code modes is byte-identical.
- **The subset:** headings (#–###), **bold**, *italic*,
  ~~strikethrough~~, ==underline==, ::highlight::, `inline code`,
  fenced code blocks, [links](url), > quotes, bullet and numbered
  lists, `- [ ]` task lists, `---` separators. Tables are deliberately
  excluded in the MVP.
- **::highlight::** renders as a pale-yellow highlight — and only with
  non-alphanumeric boundaries, so `std::vector` in your code notes never
  triggers it, and an unclosed `::` renders literally instead of
  swallowing your paragraph.
- **Clickable task checkboxes** — click the glyph to tick a task (an
  ordinary undoable source edit); the card footer shows done/total
  progress.
- **Floating formatting toolbar** on any selection — Bold, Italic,
  Underline, Strikethrough, Highlight (a yellow chip), Link,
  Checklist, Inline Code — every action implemented as a source
  edit, so nothing the toolbar does can be erased by the next
  render pass.
- **IME-safe** — rendering suspends while composed (marked) text is
  active and re-applies on commit. Non-negotiable for CJK input.
- **Paste is always plain text** — what lands is the text you copied,
  not a blob of web HTML (HTML→Markdown conversion is on the deferred
  list, stated plainly below).
- **Plain mode** renders literally; **Code mode** is monospaced with
  spellcheck and substitutions off.

### Files in notes

- Drag any file onto a card (or drag to the edge to reveal the panel,
  then drop) and it appears as a file card above the note text, with
  an "Open in Quick Look" row. The rule since v0.4.0: dropped
  **images are embedded** — copied into the app's Attachments
  folder, so an image card can never break because the original
  moved — while dropped **files of other kinds are linked**: the
  card records the original's path and no copy is made.
- The linked half of that rule has an honest cost: if a linked
  original moves or is deleted, its card renders a missing-file
  state instead of the file. Embedding everything would avoid that
  but duplicate every dropped file on disk; the split is stated
  here rather than hidden.

### Trash

- Deleted notes go to a Trash view and are **kept for 30 days**, then
  purged automatically on launch. Restore puts a note back — and if its
  folder was deleted meanwhile, it is re-homed instead of lost.

## Requirements

- macOS 13 (Ventura) or later, Apple silicon or Intel (Universal).
- To build from source: **Xcode** (the package targets the macOS 13 SDK).
  No Apple Developer account, no App Store, no paid enrolment — the
  build is ad-hoc signed for your own machine.

## Building from source

```bash
git clone https://github.com/femisowems/silvernotes-app.git
cd silvernotes-app
./build-app.sh   # runs the tests, then builds the release binary and assembles dist/SilverNotes.app
```

`build-app.sh` first runs the test suite (`swift test`) and
**aborts the build if any test fails**; only then does it run
`swift build -c release`, wrap the binary in a `SilverNotes.app`
bundle (bundle id `io.starterdev.silvernotes`, `LSUIElement`,
minimum macOS 13.0, app icon included), and ad-hoc codesign it.
Or open `Package.swift` in Xcode and press ⌘R — the package has
**zero dependencies** to resolve.

The test suite (`Tests/SilverNotesTests/`, 19 XCTest cases) covers
the store (counts, lifecycle, persistence), the Markdown engine's
render invariants, and list population — the panel controller
driven headlessly, asserting the card stack actually fills. It
runs in CI on every build, ahead of the app build itself.

> **Restoring from this repo:** the icon binaries (`AppIcon.icns`, the
> icon source PNGs) are stored as base64 text (`*.b64`) because the
> backup channel is text-only. Decode them back before building —
> see [RESTORE-NOTES.md](RESTORE-NOTES.md). Everything else in the
> repo is the file itself.

## Installing

1. Build from source (above), or unzip a release build someone handed
   you, so you have a `SilverNotes.app`.
2. Drag **SilverNotes.app** into your Applications folder and
   double-click it. The app is ad-hoc signed (not notarized), so on
   first launch macOS may block it — right-click the app and choose
   **Open**, then **Open** again in the dialog, or use System Settings →
   Privacy & Security → **Open Anyway**. You only do this once.
3. On first launch the panel slides in once, so you can see it. After
   that it starts hidden: look for the **thin sliver at the right edge
   of your screen, mid-height**, and the **note icon in the menu bar**.

**Updating:** use **Check for Updates** (in Settings, or the
menu-bar menu) — it downloads the new release, verifies its
SHA-256 against the digest GitHub publishes, swaps the app bundle
with a backup that rolls back if the swap fails, and relaunches.
The manual route still works as a fallback: quit the old copy
(`pkill -x SilverNotes` works), replace the app in Applications
with the new build, launch it. Either way, your notes are not
inside the app — they live in Application Support (below) and are
untouched by replacing the app.

## How to use it

| Action | What it does |
| --- | --- |
| **⌃⌥⌘Space** | Show / hide the panel, from any app |
| **Push pointer to the screen edge** (~200 ms) | Show the panel (Hot Side) |
| **Click the sliver** | Show the panel |
| **Click the menu-bar note icon** | Toggle the panel |
| **Right-click the menu-bar icon** | Menu: New Note, Hot Side, dock side, Settings, Quit |
| **Double-click the app** (already running) | Show the panel |
| **Click outside the panel** | Hide it (unless pinned open) |
| **Esc** (panel open) | Hide the panel (one press) |
| **⌘N** (app focused) | New note |
| **⌥⌘P** (editing a card) | Pin / unpin the note |
| **⌥⌘⏎** (editing a card) | Fold / unfold the note |
| **Double-click a card's footer strip** | Fold / unfold that note |
| **⌥⌘1 / ⌥⌘2 / ⌥⌘3** | Note mode: Standard / Plain Text / Code |
| **Drag a file onto a card** | Add a file card — images are embedded, other files linked |
| **Click a task's checkbox glyph** | Tick / untick the task |
| **⌘,** | Open Settings |

### Good to know

- **The panel's width is a proportion, not a preference** — ~34% of
  your screen, clamped between 300 and 560 pt. A Wide (~48%) step
  is built (Settings → Appearance); resizing by dragging the
  panel's edge remains planned, not built.
- **Modes never rewrite your text.** Standard, Plain, and Code are
  renderings of one stored source. Switch freely; the bytes do not
  change.
- **Your data folder is yours:** delete `~/Library/Application
  Support/SilverNotes` and everything — notes, attachments, backups —
  is gone. Quitting the app changes nothing on disk.
- **Backups are automatic:** the store snapshots itself at most hourly,
  keeping the newest 7. A corrupt store file is quarantined (renamed,
  never deleted) and the newest backup restored.

## What's next

- **CloudKit sync (V1.1)** — the MVP is local-first by decision; sync
  arrives as an opt-in layer over the same store, with the
  conflicted-copy strategy designed before it ships, not after.
- **iOS companion** — planned as a companion for Mac owners; the Mac
  app is the product, the phone app is the satellite.
- **Edge drag-resize** — dragging the panel's screen-away edge to
  resize it, alongside the built Standard and Wide steps.
- **Folder drag-reorder** — notes already reorder by dragging;
  folders do not yet.
- **Bulk export/import** — a whole library out (and back in) in one
  action, beyond the per-note Markdown export.
- **HTML→Markdown paste conversion**, a dedicated **VoiceOver
  audit**, and **syntax highlighting** in code blocks.

## What it deliberately does not do

- **No sync yet.** Local-first is the MVP's defining decision, not an
  omission. (This is the established apps' real advantage — noted
  honestly.)
- **No account, no telemetry, no network calls at all.** There is no
  server to phone home to.
- **No tables in Markdown** — excluded from the MVP subset by decision;
  pasted tables arrive as plain-text lines. Revisit in V2.
- **No nested folders in the UI** — the schema reserves
  `parentFolderID` from day one so nesting needs no data migration
  when it lands.

## How it works

SilverNotes is a dependency-free Swift Package (AppKit, macOS 13+),
~7,300 lines across 17 source files, each concern in one file:

- **Panel** — an `NSPanel` (borderless, non-activating, floating)
  docked to the screen edge, plus a second tiny panel for the sliver.
  Show/hide is a frame animation with a post-animation on-screen
  verification. Triggers (Hot Side, drag-in, click-outside, Esc)
  are `NSEvent` monitors; the global hotkey is Carbon, so no
  Accessibility permission is involved anywhere.
- **Editor** — each card hosts an `NSTextView` holding the note's
  source. `MarkdownEngine` renders by computing an attributed copy and
  copying *attributes only* onto the editor's storage, so characters
  are never touched by rendering.
- **Store** — one versioned JSON document (`store.json`,
  `schemaVersion: 1`) in Application Support, written atomically,
  saved on a debounce while typing and immediately for structural
  changes, with rotating backup snapshots. The models are Codable and
  storage-agnostic — the register's SQLite recommendation can still be
  adopted later as a store-layer change only. Attachments follow the
  split rule above: dropped images are embedded copies under
  `Attachments/<noteID>/`; other dropped files are linked to their
  originals by path.

## Project layout

```
silvernotes-app/
├── Sources/SilverNotes/
│   ├── App.swift                  # entry point, main menu, menu-bar item
│   ├── PanelController.swift      # panel + sliver, show/hide, triggers
│   ├── PanelContentController.swift # folder home, card stack, search, trash views
│   ├── NoteCardView.swift         # one card: editor host, footer, gear menu, attachments
│   ├── NoteTextView.swift         # the editor; attribute-only rendering glue
│   ├── MarkdownEngine.swift       # hidden-Markdown renderer (subset above)
│   ├── SNLayoutManager.swift      # draws the ::highlight:: marker band
│   ├── FormattingToolbar.swift    # floating selection toolbar
│   ├── GearMenu.swift             # the custom per-note gear menu
│   ├── NoteStore.swift            # JSON store, trash retention, attachments, backups
│   ├── Models.swift               # folder / note / attachment / store document
│   ├── HotKeyManager.swift        # Carbon ⌃⌥⌘Space registration
│   ├── SettingsController.swift   # settings window, launch-at-login (SMAppService)
│   ├── Preferences.swift          # UserDefaults keys and accessors
│   ├── LaunchSplash.swift         # launch loading screen
│   ├── UpdateChecker.swift        # Check for Updates (download, SHA-256 verify, swap)
│   └── Theme.swift                # colour and font tokens (light + dark)
├── Tests/SilverNotesTests/        # 19 XCTest cases: store, Markdown engine, list population
├── IconSource/                    # icon artwork (binaries stored as .b64 — see RESTORE-NOTES.md)
├── AppIcon.icns                   # bundled app icon (stored as AppIcon.icns.b64 in this repo)
├── Package.swift                  # dependency-free Swift Package, macOS 13+
├── build-app.sh                   # test suite first, then release build → dist/SilverNotes.app, ad-hoc signed
├── README.md
├── VISUAL-AUDIT-RUBRIC.md         # the Variation A grading rubric (109 rows, 15 states)
├── CAPTURE-SCRIPT.md              # the guided on-Mac capture script for milestone rounds
└── ROADMAP.md                     # improvement list, version arc, confirmation checklist
```

## Privacy

SilverNotes collects nothing. There is no analytics, no account, no
tracking, and no network code in the app at all. Your notes, folders,
and attachments live in `~/Library/Application Support/SilverNotes/`
on your Mac, in a JSON file you can open and read yourself. Delete
that folder and everything is gone.

## Troubleshooting

- **The app won't open, or opens and instantly vanishes** — check for a
  crash report: `ls -t ~/Library/Logs/DiagnosticReports/ | grep -i
  silver`. The exception type and the first frames of the crashed
  thread say exactly where it died; that is how the v0.1.0 launch
  crash below was found.
- **Something fails silently — no crash, the app just misbehaves** —
  since v0.5.1 the app catches uncaught exceptions and writes them
  to `~/Library/Application Support/SilverNotes/last-exception.log`
  (timestamp, exception name and reason, call stack). Check there
  first; it names the culprit a silent failure would otherwise hide.
- **Gatekeeper blocks the first open** — the build is ad-hoc signed,
  not notarized (yet — see ROADMAP.md). Right-click the app → Open →
  Open. Needed once.
- **Quit it fully** — menu-bar note icon → Quit SilverNotes, or
  `pkill -x SilverNotes` in Terminal.
- **Run it from Terminal to see its log lines** —
  `/Applications/SilverNotes.app/Contents/MacOS/SilverNotes`. It logs
  its detected screen, sliver frame, and the panel's settled frame on
  every show.
- **Start from a clean slate** — quit the app and delete
  `~/Library/Application Support/SilverNotes/`; the next launch
  re-seeds the starter folders and notes.

## Honest status

- **Working — confirmed on a real Mac (November 25, 2026).** v0.1.0
  runs on the developer's MacBook Air: the panel opens, notes and
  folders work. In the developer's words, "a working version with a
  few bugs" — those first-use bugs are being collected in
  [ROADMAP.md](ROADMAP.md), which is also where the version arc lives.
- **v0.6.2 (November 27, 2026) — the everything-expanded default,
  corrected, CI-built, on-device confirmation pending.** Every
  note in a list now renders as its full card at once, in every
  density; v0.6.1 had read the rule for Compact as an accordion
  (top note expanded, the rest collapsed rows), which Femi
  flagged live the same day. Folding remains a manual, per-note,
  session-only action. Suite now 21 tests, including one pinning
  that every note renders expanded on open, even after switching
  views.
- **v0.6.1 (November 27, 2026) — the everything-expanded default
  reaches Compact, CI-built, on-device confirmation pending.** A
  Compact list now opens with the top note expanded into its full
  card instead of every note collapsed to a one-line row; the
  v0.6.0 expanded default had only ever applied to Standard cards.
  First release shipped through the new develop-branch flow
  (PR #1, CI-gated); the test suite is now 20 tests.
- **v0.6.0 (November 26, 2026) — the Variation A visual pass,
  CI-built, on-device confirmation pending.** 73 properties were
  measured against the final mockup and 56 aligned: the solid
  marker-highlight band, the formatting toolbar in the design's
  order with its yellow Highlight chip, 50 pt folder rows, full
  card footers (a folded card shows an unfold chevron), the 236 pt
  Settings sidebar in the package's surface colour, a shadow under
  the sliver, accent-tinted text selection. The search field now
  flexes across the header while open, so "Search all notes" no
  longer clips. Notes load expanded — folding is session-only.
  Every build is now gated on the 19-test suite (see Building from
  source); this release's CI run passed all 19. The remaining
  rubric items are rendering judgements (blur, shadow softness)
  that only the milestone capture round on a real Mac can settle;
  that round covers v0.5.1 and v0.6.0 together.
- **v0.5.1 (November 26, 2026) — the bug-fix release, CI-built,
  on-device confirmation pending.** Fixes the blank Standard-density
  lists (card population is now a deterministic rebuild — the
  pattern the Compact and folder views already proved), the panel
  never taking keyboard focus on open (it now becomes the key
  window, so Esc, Compact navigation and the ⌥⌘ shortcuts actually
  receive keys), and Compact rows rebuilding on selection, which
  ate the double-click that expands a row. Adds an
  uncaught-exception log at `~/Library/Application
  Support/SilverNotes/last-exception.log`, so the next silent
  failure names itself instead of needing a guessing pass.
- **v0.5.0 (November 26, 2026) — installed and used on a real Mac
  the same day.** It reached the developer's Mac through the app's
  own Check for Updates, confirming the self-update path end to end
  (download, SHA-256 verify, bundle swap, relaunch). A screen
  recording taken that day, running v0.5.0, is what exposed the
  Standard-density blank-lists bug — note counts were right, the
  cards never appeared — which v0.5.1 fixes above. The release
  itself carried the Compact width fix, the Underline formatting
  action, the first-run welcome empty state, and the Wide rail's
  New Folder row.
- **v0.4.0 (November 25, 2026) — the full mockup-fidelity release.**
  Its dedicated on-device checklist round never ran as such; the
  feature set reached a real Mac as part of v0.5.0 (installed and
  used there, above), and per-release checklist rounds have since
  been replaced by the automated suite plus milestone capture
  rounds (see v0.6.0). A 138-item audit of the
  app against the approved mockup package (65 match / 43 mismatch /
  19 missing) drove this release; every fixable mismatch and
  missing element is addressed. The designed chrome is now real:
  a custom gear menu (the package's own surface, type and swatch
  row — eight colours kept, in the package's order), folder home
  leading with All Notes and Pinned, a working bottom bar
  (fold-all, sort, folder export), and a five-pane Settings window
  (General / Appearance / Editor / Backups / Shortcuts) carrying
  Panel width and Pin-panel-open. Checklists get drawn round
  ticks, strikethrough done text and the progress bar; highlights
  render as a marker band; file cards sit above the note text
  with an "Open in Quick Look" row and honest provenance. Compact
  density and the Wide step (folder rail) arrive as the package
  drew them, along with drag-reorder, per-display side memory,
  cursor-leave grace and the drop-target state. New file drops
  are linked, not copied (images still embed; existing
  attachments untouched). Esc now closes the panel in one press
  from editing — a deliberate deviation from the package, made at
  the user's direction. The one audit item not built: the
  package's "three built-in themes" exist only as a prose
  mention, with no names or values to build to. The confirmation
  checklist in [ROADMAP.md](ROADMAP.md) carries the v0.4.0 checks.
- **v0.3.0 (November 25, 2026) — Check for Updates + launch loading
  screen, CI-built, not yet confirmed on a Mac.** Settings and the
  menu-bar menu both carry a "Check for Updates…" option; the app
  also checks silently once after launch and notes an available
  version on the menu item. An available update installs in one
  click: the release zip downloads, its SHA-256 is verified against
  the digest GitHub publishes for that file, and only then is the
  app bundle swapped (with a backup that rolls back if the swap
  fails) and relaunched. Nothing downloads or installs without a
  click. The check reads the GitHub releases directly — no separate
  update feed to keep in sync. Separately, a cold launch now opens
  with a brief loading screen (icon, name, "Loading your notes…")
  tied to the panel's first appearance; it never delays launch
  beyond ~1.6s and stays out of the way on hidden login starts.
  The confirmation checklist in [ROADMAP.md](ROADMAP.md) carries
  the v0.3.0 checks.
- **v0.2.1 (November 25, 2026) — Settings crash hotfix, CI-built,
  not yet confirmed on a Mac.** Opening Settings crashed the app on
  first open — a bug present since v0.1.0: the window refreshed its
  "Launch at login" status before the status label it writes to had
  been created, and writing to the still-missing label trapped. The
  label is now created before the refresh runs. Found in the Mac's
  crash reports (three hits: Nov 25 at 4:35 PM, 5:09 PM and
  8:08 PM); a full sweep of the reports the same evening found no
  other live bug — the only other cluster was the v0.1.0 launch
  crash, already fixed. No other changes from v0.2.0.
- **v0.2.0 (November 25, 2026) — mockup-fidelity visual pass,
  CI-built, not yet confirmed on a Mac.** Presentation only — no
  behaviour, data or feature changes. The token layer now carries the
  design package's exact values (panel #EDEEF1 at 88% over the blur,
  dark #222226 at 90%; steel accent #3F6EA5; marker highlight; note
  colours as full card backgrounds with dedicated dark variants), the
  type scale matches the spec (13pt body at 1.5 line height, the
  first line of each note as a 13.5pt semibold title, footers at
  10.5–11pt, code at 12pt), the header is the mockup's pill with the
  "Local only — sync arrives in V1.1" caption, card footers follow
  the spec order with hover states and a gold pinned pin, the gear
  menu matches the mockup (swatch row, mode checks), folder rows are
  plain with counts, the empty state teaches the three capture
  paths, the edge sliver is the 22×118pt Open Bar, and the panel
  slides on the spec's 280ms curve with a Reduce Motion crossfade.
  The confirmation checklist in [ROADMAP.md](ROADMAP.md) carries the
  v0.2.0 checks.
- **v0.1.1 (November 25, 2026) — performance pass, CI-built, not yet
  confirmed on a Mac.** No new features and no behaviour changes by
  design: the card stack is diffed by note ID (a structural change no
  longer rebuilds every card, and each card renders exactly once per
  configuration), typing no longer forces a layout pass per keystroke,
  attachment images display from downscaled thumbnails behind a decode
  cache instead of re-decoding the full original on every rebuild, the
  global mouse monitors behind Hot Side are removed entirely while
  the feature is off (and read cached preferences while on), theme
  fonts are built once, the JSON store writes compactly and is no
  longer rewritten on a clean launch, and search is debounced. The
  confirmation checklist in [ROADMAP.md](ROADMAP.md) carries the
  v0.1.1 checks.
- v0.1.0 was authored on a Linux VM (no AppKit), then compiled on a
  MacBook Air: the first compile surfaced three errors, all fixed.
- The road here was not straight, and the record matters: the first
  build ran but showed nothing. A reopen handler added while
  debugging then made it worse — AppKit calls
  `applicationOpenUntitledFile` during a *cold* launch, before
  `applicationDidFinishLaunching` has set anything up, and routing it
  to `show()` trapped on the still-nil panel (`EXC_BREAKPOINT`,
  confirmed from the crash reports, not guessed). An animation-based
  theory was investigated first and turned out to be wrong; the
  self-verifying slide-in it produced stays in the code as a safety
  net. The actual fix: every public entry point on the panel
  controller runs a self-guarding `ensureSetUp()` first, and the
  untitled-file hook was removed entirely. It shipped in the current
  v0.1.0 release build (SHA-256 `c22a132e…a34`) and is the build
  confirmed working above.
- A full audit of all 13 source files (November 25, 2026) found no
  force-unwraps, force-casts, or `fatalError`s; one Auto Layout defect
  (width constraints activated before the views entered the stack,
  which macOS dropped with a "no common ancestor" warning) was found
  from the app's own console output and fixed.

---

Built by [Femi Sowemimo](https://github.com/femisowems) (StarterDev).
