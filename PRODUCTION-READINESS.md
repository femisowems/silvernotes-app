# SilverNotes — production readiness plan

Opened Fri Nov 27, 2026 at Femi's word: get SilverNotes to a
production-level working version with little to no bugs, on a
develop-branch workflow. The honest headline: the app is
feature-complete for a 1.0 and CI-gated by 19 automated tests, but
it has never had a complete on-device verification round — that
round, and what it surfaces, is most of what "production" takes.

## Branch workflow (from Nov 27, 2026)

- `main` is release-only: it always matches the latest published
  release.
- `develop` is the integration branch. New work lands through
  short-lived feature branches + PRs into `develop`.
- Releases are cut `develop` → `main` through the existing
  pipeline: CI test suite green, inner-zip verified (app at root,
  bundle version, sha256 recorded), GitHub release marked Latest.
- The self-updater reads GitHub releases, so `main`/releases stay
  the single distribution channel.

## The list, in order

### A. Verification — the core of "little to no bugs"
1. [ ] **Milestone capture round** on the current build (Femi,
   ~4 min, CAPTURE-SCRIPT.md): closes ROADMAP checks 36–38,
   exercises the never-verified v0.2–v0.5 features (checks 16–35),
   and supplies the frames for the visual grading (item 2).
2. [ ] **Visual grading** against VISUAL-AUDIT-RUBRIC.md (109
   rows, Variation A) from the capture; produce the residual
   fix list, including the 8 capture-verify items left open by
   v0.6.0 (panel blur/shadow rendering, caption dot, dark-mode
   folder-row shadow, empty-state measure/button width, card
   dual shadow, checklist rhythm, gear-menu backdrop, toolbar
   background, sliver shadow).
3. [ ] **Fix release** for everything items 1–2 surface, each fix
   covered by a new automated test wherever the failure is logic
   (the population-suite pattern), so the suite grows teeth with
   every bug found.
4. [ ] **Fresh-user pass**: true first launch on a clean account —
   seeding, welcome state, Gatekeeper first-open, empty states,
   self-update from the previous release. (A second user account
   on Femi's Mac covers most of this; a rented cloud Mac is the
   full clean-room version.)
5. [ ] **The unenumerated "few bugs"** Femi noted on the first
   working build (Nov 25) — collected during the capture round
   and item 3, not before.

### B. Distribution
6. [ ] **Developer ID signing + notarization** (ROADMAP item 15)
   — DECISION OWED (Femi): needs the paid Apple Developer
   enrolment. The same enrolment covers ClipKeep's identical
   item; one decision unlocks both. Until then every new user
   hits Gatekeeper's "Open Anyway" on first launch.
7. [ ] **Trademark clearance + domain** (ROADMAP item 13) —
   proper clearance search before any branding spend; the
   Nov 24–25 check was explicitly not conclusive. Only
   silvernote.io looked available among domains checked.
8. [ ] **v1.0.0 production release**: the fix release (item 3)
   promoted — version bump, release notes, README + ROADMAP
   status refresh, App Roadmaps entry.

### C. Production polish (pre-1.0 if time, else 1.1)
9. [ ] VoiceOver audit (ROADMAP item 10).
10. [ ] Keyboard-navigation completion (item 7) and large-note
    performance (item 22).
11. [ ] Settings drawn toggle switches — open micro-decision
    from the v0.6.0 pass (native controls kept; the mockup
    draws switches). Femi's call.

### Explicitly NOT required for production 1.0
- CloudKit sync (V1.1 by decision — local-first is the product),
  iOS companion (V2), Markdown tables (V2), nested folders (V2),
  SQLite migration (the versioned JSON store is sound at this
  scale), tags (open question, item 20).
