# SilverNotes — Roadmap & improvement list

Saved Wed Nov 25, 2026. Ordered by impact within each stretch of the
version arc. Check items off here as they ship — and only call something
fixed once it has been seen working on a real Mac (see the confirmation
checklist below).

## Improvement list

- [ ] **1. Launch-crash fix — confirmed on Femi's Mac** — v0.1.0's first on-device round found the real bug, and it was worse than "the panel doesn't appear": the app **crashed on launch**. Root cause is CONFIRMED by the crash reports in `~/Library/Logs/DiagnosticReports` (Nov 25, 16:55): `EXC_BREAKPOINT` inside `PanelController.show()`, reached via `applicationOpenUntitledFile` — AppKit calls that during a cold launch, *before* `applicationDidFinishLaunching` has run `setUp()`, so `show()` touched the still-nil panel and sliver and trapped. The fix ships in the next build: every public entry point on the panel controller routes through a self-guarding `ensureSetUp()` first, and the untitled-file hook is removed entirely (a cold launch is already covered by the first-launch auto-show; relaunching a running app still opens the panel via `applicationShouldHandleReopen`). *Status: shipped in the build after v0.1.0, awaiting Femi's confirmation — not "fixed" until he sees the panel on a fresh launch (checklist items 1–6).*
- [ ] **2. Clean-room / fresh-launch verification** — the launch bug above is exactly the class that only shows up in states a developer's machine never has: no saved preferences, no prior install, the Gatekeeper first-open path, a fresh user account. Add a standing verification pass for every release: install into a clean environment (fresh user account or a wiped data folder), launch cold, and confirm the panel, the sliver, the menu-bar icon, and an empty DiagnosticReports folder afterwards. If a rented cloud Mac or a spare local account proves practical, use it; until then, a scripted pass on Femi's Mac with the data folder temporarily moved aside is the minimum. *Why it ranks this high: every SilverNotes failure so far was a launch-state failure, and none of them could be reproduced from the build machine.*
- [ ] **3. Drag-resize + Wide width step** *(v0.2)* — the panel width is currently a fixed proportion (~34% of the screen, clamped 300–560 pt). Add edge drag-resize with the width remembered, plus a Wide (~48%) step for long-form notes. Deferred from the MVP by decision, not by accident.
- [ ] **4. Per-display dock-side memory** *(v0.2)* — remember the docked side (and ideally the panel's display) per display, so a laptop that docks to an external monitor keeps each screen's arrangement. The register flagged this as the top panel-mechanics ambiguity; the MVP docks to one side globally.
- [ ] **5. HTML→Markdown paste conversion** *(v0.2)* — paste is plain text only in the MVP, deliberately: what lands is the text you copied, never a blob of web HTML. Converting pasted rich content into the Markdown subset (headings, bold, links, lists) is the upgrade; it must degrade to plain text rather than ever inserting markup the renderer can't show back.
- [ ] **6. Drag-reorder** *(v0.2)* — drag notes within the card stack and folders within the folder home. Deferred from the MVP; ordering is currently by pin, then recency.
- [ ] **7. Keyboard navigation between notes and folders** — arrow-key movement through the folder home and the card stack, with a visible selection, so the panel is fully usable without the pointer. The panel-local shortcuts (⌥⌘P / ⌥⌘⏎ / ⌥⌘1–3) already act on the most recently edited card; this makes getting *to* a card keyboard-only too.
- [ ] **8. Bulk export (and import)** — export a folder or the whole library as Markdown files (notes already export one at a time from the gear menu). Import of a folder of Markdown files is the other half; it matters before sync exists, because export is currently the only way to move a library between Macs by hand.
- [ ] **9. Syntax highlighting in Code mode and code blocks** — Code mode is monospaced with spellcheck/substitutions off, but nothing is highlighted. Attribute-only highlighting fits the editor's rule (rendering never touches characters); it needs the same IME-safety and mode-switch-byte-identity guarantees as the rest of the renderer before it ships.
- [ ] **10. Full VoiceOver audit** — a dedicated pass over the panel, cards, gear menus, formatting toolbar and Settings with VoiceOver on: labels, rotor behaviour, focus order, and announcements for show/hide and task progress. Basic labels exist; an audited pass does not yet.
- [ ] **11. SQLite store migration** — the MVP ships a versioned JSON store (atomic writes, rotating backups, corruption quarantine) instead of the register's SQLite recommendation, as a deliberate zero-dependency deviation; the models are storage-agnostic and the migration path is documented in the README. Adopt SQLite when note counts or sync make JSON the bottleneck — a store-layer change only, no UI work.
- [ ] **12. Pinch-to-fold** — trackpad pinch to fold/unfold a note, alongside the existing double-click-footer and ⌥⌘⏎ paths. Small, deferred from the MVP.
- [ ] **13. Trademark clearance + domain** *(before any branding spend; gates v1.0)* — the name proceeds by adopted decision, but the overnight search was **not conclusive**: no live conflicting mark or same-name app was found, yet no direct USPTO/CIPO query succeeded. A proper clearance search is still owed before money goes into branding. Of the domains checked, only silvernote.io looked available; nothing has been bought.
- [ ] **14. Licensing & trial enforcement** *(v1.0)* — the adopted model: **$19.99 one-time per major version, 30-day direct trial**, future iOS companion bundled/discounted for Mac owners. No paywall or licence code exists in the MVP; v1.0 adds the trial clock and licence check, designed so a lapsed trial never locks anyone out of reading their own notes.
- [ ] **15. Developer ID signing + notarization** *(v1.0)* — builds are ad-hoc signed today, so first launch needs right-click → Open (or Open Anyway). A Developer ID build, notarized, removes that friction and is a precondition for selling direct. Needs the paid Apple Developer enrolment, which is deferred by decision.
- [ ] **16. Update mechanism for direct users** — no updater exists yet; updating is "replace the app in Applications" (notes live outside the bundle and survive it). Before v1.0 sells to anyone, decide and build how direct users learn about and install new builds, with the download verified (checksum or signature) before anything is swapped.
- [ ] **17. CloudKit sync** *(V1.1)* — the MVP is local-first by adopted decision; sync arrives as an opt-in layer over the same store. The conflict strategy (beyond last-modified-wins) gets designed and written down *before* the sync code, per the register — conflicted copies are acceptable, silent overwrites are not.
- [ ] **18. Markdown tables** *(V2)* — excluded from the MVP subset by adopted decision (pasted tables arrive as plain-text lines). Revisit for V2, including how a table renders inside a card-width editor.
- [ ] **19. Nested folders** *(V2)* — the UI is flat by adopted decision, and the schema reserves `parentFolderID` from day one, so nesting lands with no data migration when it comes.
- [ ] **20. Tags** — the register's open organisation question (folders, tags, both, or neither) was settled as "flat folders for the MVP" only. Tags stay an open question for after V1.1, to be decided on how the folder system actually gets used.
- [ ] **21. Automation surface** — note/folder URLs, a URL scheme, and Shortcuts/AppleScript hooks so other apps can create and open notes. Named in the register; unscheduled, after the core is proven.
- [ ] **22. Large-note performance pass** — rendering is attribute-only and IME-safe, but nobody has yet thrown a 10k-line note or a very long paste at it on a real Mac. Measure first (render time per keystroke on a large note), then optimise only what the numbers indict.
- [ ] **23. iOS companion exploration** *(V2)* — planned as a bundled/discounted companion for Mac owners; the Mac app is the product, the phone app is the satellite. Exploration starts once CloudKit sync (item 17) exists to carry the data.

## Version arc

- **v0.1.x — stability & confirmation.** The launch-crash fix confirmed on a real Mac, the confirmation checklist below closed out, and small fixes from the first real use. No new features until the panel's launch behaviour is boring.
- **v0.2 — panel polish.** Drag-resize + Wide step (item 3), per-display side memory (item 4), HTML→Markdown paste (item 5), drag-reorder (item 6).
- **v1.0 — commercial readiness.** Licensing & trial enforcement (item 14), Developer ID signing + notarization (item 15), trademark clearance completed (item 13), an update mechanism (item 16).
- **V1.1 — CloudKit sync.** Opt-in sync over the existing store (item 17), conflict strategy designed first.
- **V2 — bigger shapes.** Markdown tables (item 18), nested folders (item 19), iOS companion exploration (item 23).

## Settled decisions (adopted Nov 25, 2026 — all 8)

Recorded so they stop being re-litigated; each came out of the ambiguity
register's recommendations.

1. Trash with 30-day retention, then automatic purge.
2. Flat folders for the MVP; nesting reserved in the schema (`parentFolderID`).
3. $19.99 one-time per major version, 30-day direct trial; a future iOS companion bundled/discounted for Mac owners.
4. Proceed with the SilverNotes name, subject to the trademark-clearance caveat (item 13).
5. Local-first MVP; CloudKit sync in V1.1.
6. Double-click a card's footer strip folds/unfolds it; double-click in the body selects a word.
7. Tables excluded from the Markdown subset in the MVP; revisit in V2.
8. macOS 13+ minimum, Universal binary.

## Confirmation checklist — for Femi's next Mac session

Written for the build after v0.1.0 (the one carrying the launch-crash
fix). Nothing here is confirmed until it has been seen on the Mac —
that discipline is the whole point of this list.

**Launch (the crash check)**
1. Quit fully (`pkill -x SilverNotes`), then double-click the app in Applications → on this build's first launch the panel slides in once. The app must still be running afterwards — check the menu-bar note icon is present a few seconds later.
2. Open `~/Library/Logs/DiagnosticReports` → **no new SilverNotes crash report** with a timestamp from this launch. (Three reports from Nov 25, 16:55 are the old build's; anything newer is a failure of this check.)
3. Quit and launch again → the panel starts hidden this time (only the first launch auto-shows), the sliver is visible at the docked edge, mid-height, and clicking it slides the panel in.

**Panel basics**
4. Press ⌃⌥⌘Space → panel hides; press it again → panel shows. Repeat a few times; it should toggle cleanly every time.
5. Menu-bar note icon: left-click toggles the panel; right-click opens the menu (New Note, Hot Side toggle, dock side, Settings, About, Quit) and each item works.
6. Double-click the app in Applications while it is already running → the panel opens (relaunching a hidden accessory app is never a no-op).
7. Push the pointer into the docked screen edge and hold ~200 ms → panel slides in (Hot Side). Click somewhere in another app → panel slides away and focus returns to that app.

**Notes survive**
8. Create a note, type a line with a `- [ ]` task in it, tick the task, quit and relaunch → the note is still there with the task ticked, and the Trash still holds anything deleted earlier (30-day retention).

## Shipped log

- **Launch-crash fix** (build after v0.1.0, Nov 25, 2026) — root cause confirmed from the on-device crash reports: AppKit's cold-launch open path (`applicationOpenUntitledFile` → `_doOpenUntitled`) reached `PanelController.show()` before `setUp()` had run, and `show()` trapped on the nil panel/sliver (`EXC_BREAKPOINT`, main thread). Fix: an `ensureSetUp()` guard at the top of every public panel entry point (`show`, `hide`, `toggle`, `sideDidChange`, `createNoteShortcut`), `setUp()` made idempotent, and the untitled-file delegate hook removed with the reasoning recorded in a comment at the site. *Status: shipped, awaiting Femi's confirmation — checklist items 1–6. Not marked fixed until then.*
- **v0.1.0** (Nov 25, 2026) — the MVP, CI-built and published as a GitHub release the same day it was written. Edge-docked panel (~34% width, full height) with sliver, Hot Side, drag-in auto-reveal, Carbon hotkey ⌃⌥⌘Space (no Accessibility prompt), click-outside hide with an allow-list, pin-open, Esc layering, focus hand-back, hide-on-lock; flat folder home with counts and colour dots; card editor with the hidden-Markdown subset (headings, bold/italic/strikethrough, `==underline==`, `::highlight::` with word-boundary protection, code, links, quotes, lists, clickable task checkboxes with progress), floating formatting toolbar, three modes that never mutate the source; embedded-copy file attachments with thumbnails; Trash with 30-day retention; versioned JSON store with rotating backups and corruption quarantine; main menu + menu-bar menu; light/dark via design tokens. Ad-hoc signed, macOS 13+, Universal, zero dependencies. Deferred by decision (see the improvement list): sync, drag-resize/Wide, paste conversion, drag-reorder, per-display memory, licensing, SQLite, VoiceOver audit, syntax highlighting, pinch-to-fold. First on-device round the same day found the launch crash logged above.
