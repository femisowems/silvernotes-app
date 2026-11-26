<p align="center">
  <img src="AppIcon-1024.png" width="160" alt="SilverNotes app icon — a white note card with a pale-yellow highlight line on a silver panel">
</p>

<h1 align="center">SilverNotes for Mac</h1>

<p align="center"><strong>Notes that live at the edge of your screen — one gesture away, never in your way.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.2.1-e4572e" alt="Latest version">
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

> 🚧 **Work in progress** — SilverNotes is at **v0.2.1**: the v0.2.0
> mockup-fidelity visual pass (the panel, cards and chrome now follow
> the approved design package's tokens, type scale and anatomy) plus
> a hotfix for a crash on opening Settings. The MVP is **confirmed
> working** on a real Mac (MacBook Air, macOS 26) as of
> November 25, 2026 — with a few first-use bugs, which are tracked in
> [ROADMAP.md](ROADMAP.md).
> v0.2.1 itself is CI-built and awaiting its on-device confirmation
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
- **Pin it open** — the header pin (or Settings) disables auto-hide when
  you want the panel to stay put.
- **Esc closes innermost-first** — formatting toolbar, then text
  selection, then the panel.
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
  title, search, +, and the panel pin.
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
  Highlight, Strikethrough, Code, Link, Task — every action implemented
  as a source edit, so nothing the toolbar does can be erased by the
  next render pass.
- **IME-safe** — rendering suspends while composed (marked) text is
  active and re-applies on commit. Non-negotiable for CJK input.
- **Paste is always plain text** — what lands is the text you copied,
  not a blob of web HTML (HTML→Markdown conversion is on the deferred
  list, stated plainly below).
- **Plain mode** renders literally; **Code mode** is monospaced with
  spellcheck and substitutions off.

### Files in notes

- Drag any file onto a card (or drag to the edge to reveal the panel,
  then drop): the file is **copied into** the app's Attachments folder
  and shown as a preview card — thumbnail for images, Finder icon for
  everything else. Click a preview to open the copy.
- Embedded copies are a deliberate choice over security-scoped
  bookmarks: a note can never break because the original file moved.
  The cost is disk use, and it is stated here rather than hidden.

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
./build-app.sh   # builds the release binary and assembles dist/SilverNotes.app
```

`build-app.sh` runs `swift build -c release`, wraps the binary in a
`SilverNotes.app` bundle (bundle id `io.starterdev.silvernotes`,
`LSUIElement`, minimum macOS 13.0, app icon included), and ad-hoc
codesigns it. Or open `Package.swift` in Xcode and press ⌘R — the
package has **zero dependencies** to resolve.

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

**Updating:** quit the old copy (`pkill -x SilverNotes` works), replace
the app in Applications with the new build, launch it. Your notes are
not inside the app — they live in Application Support (below) and are
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
| **Esc** (panel open) | Close toolbar → clear selection → hide panel |
| **⌘N** (app focused) | New note |
| **⌥⌘P** (editing a card) | Pin / unpin the note |
| **⌥⌘⏎** (editing a card) | Fold / unfold the note |
| **Double-click a card's footer strip** | Fold / unfold that note |
| **⌥⌘1 / ⌥⌘2 / ⌥⌘3** | Note mode: Standard / Plain Text / Code |
| **Drag a file onto a card** | Embed a copy of the file in the note |
| **Click a task's checkbox glyph** | Tick / untick the task |
| **⌘,** | Open Settings |

### Good to know

- **The panel's width is a proportion, not a preference** — ~34% of
  your screen, clamped between 300 and 560 pt. Drag-resizing and a
  Wide (~48%) step are planned, not built.
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
- **iOS companion** — planned as a bundled/discounted companion for Mac
  owners; the Mac app is the product, the phone app is the satellite.
- **Drag-resize + Wide step**, folder/note drag-reorder, per-display
  dock-side memory, bulk export, HTML→Markdown paste conversion, a
  dedicated VoiceOver audit, syntax highlighting in code blocks.
- **Licensing** — SilverNotes is planned at **$19.99 per major
  version** with a 30-day trial. No paywall or licence enforcement
  exists in the MVP build; the price is a product decision recorded
  here, not a gate in the code.

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
~3,400 lines across 13 source files, each concern in one file:

- **Panel** — an `NSPanel` (borderless, non-activating, floating)
  docked to the screen edge, plus a second tiny panel for the sliver.
  Show/hide is a frame animation with a post-animation on-screen
  verification. Triggers (Hot Side, drag-in, click-outside, Esc
  layering) are `NSEvent` monitors; the global hotkey is Carbon, so no
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
  adopted later as a store-layer change only. Attachments are embedded
  file copies under `Attachments/<noteID>/`.

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
│   ├── FormattingToolbar.swift    # floating selection toolbar
│   ├── NoteStore.swift            # JSON store, trash retention, attachments, backups
│   ├── Models.swift               # folder / note / attachment / store document
│   ├── HotKeyManager.swift        # Carbon ⌃⌥⌘Space registration
│   ├── SettingsController.swift   # settings window, launch-at-login (SMAppService)
│   ├── Preferences.swift          # UserDefaults keys and accessors
│   └── Theme.swift                # colour and font tokens (light + dark)
├── IconSource/                    # icon artwork (binaries stored as .b64 — see RESTORE-NOTES.md)
├── AppIcon.icns                   # bundled app icon (stored as AppIcon.icns.b64 in this repo)
├── Package.swift                  # dependency-free Swift Package, macOS 13+
├── build-app.sh                   # release build → dist/SilverNotes.app, ad-hoc signed
├── README.md
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
