---
status: proposal
stage: design-decision
priority: high
blocked_by: []
---

# Tab unification + UX-canon creep repair

Synthesis of the 2026-07-02 four-census pass (code census, visual census,
canon-history hunt, creep audit). Addresses three user reports as ONE design
pass: (1) tab inconsistency across track types + missing containing element;
(2) greyness creeping back after the bold-flat pass; (3) silly text labels.

## Diagnosis

**The design system already contains the answer; three surfaces ignored it.**

- The canonical tab grammar exists: `StudioSlotTabButton`
  (Sources/UI/Theme/StudioSegmentedControls.swift:27 — eyebrow caps, 2px
  accent underline, 1.5px ghost-stroke, optional SOLID status badge). Used by
  the melodic track and kit-level tabs.
- The containing element exists: `TrackSourceSelectedWellBody`
  (Sources/UI/TrackSource/TrackSourceSelectedWellBody.swift — square top
  corners docking under the tab strip, section-radius bottom, accent
  ghost-stroke). Used ONLY by the melodic track.
- Three bespoke rebuilds diverged: the audio-input panel hand-builds its tab
  row (TrackWorkspaceView.swift:601-633, adding subtitle explainers), the
  slicer built its own solid-fill pill bar (SliceTrackEditingControls.swift:783)
  and a third pattern for its layer row (:57), and neither audio-input nor
  drum-kit content has any container.
- Secondary-selector placement is chaotic: inside content (audio-input MODE),
  above the tabs (slicer layer rows), below the tabs (drum kit layer row),
  embedded as badges (melodic).
- Selection color has no system: green vs purple vs orange, outline vs solid
  fill, all-caps vs title case.

**Grey creep is a component-default problem, not hardcoding.** Zero raw hex
in views — but the shared chrome defaults to grey when no accent is passed:
`StudioControls.swift:56` (`accent ?? StudioTheme.border`),
`StudioCards.swift:53,73`, `StudioSegmentedControls.swift:35,44,71,160,242`.
Every inactive state in the app therefore renders as the same grey outline —
the "wall of grey capsules". Top offenders by count:
SliceTrackEditingControls (13), TrackWorkspaceView (11), TracksMatrixView (9).
A few `.secondary`/`.gray` system-color escapes bypass tokens entirely.

**Label creep violates codified canon.** docs/ux-canon.md Rule 1 (headers not
restated in cells), Rule 3 (no explainer prose on surfaces — "any full
sentence on a working surface is a finding"), Rule 12 (color identifies,
never floods). The creep audit inventoried ~45 filler strings with file:line
(tab subtitles "live or playback"/"insert chain"/"M1-M8"/"bus + sends",
Write-Target captions, "Press play to record live history." ×4, modal
subheadings, etc. — full list in the audit, reproduced in the appendix of the
implementation ticket when cut).

**Root cause of recurrence: no enforcement.** The audio Hard Rules got lint
scripts; the UX canon got nothing. This is the third grey-text purge.

## Proposed unified grammar (one rule set for every track type)

1. **Primary section tabs** — `StudioSlotTabButton` everywhere: melodic ✓,
   kit ✓, audio-input (migrate off the bespoke rebuild), slicer (migrate off
   solid-fill pills). All-caps eyebrow labels. NO subtitle explainers; the
   only adornment is an optional SOLID status badge carrying real state
   ("No instrument", "Insert") per canon Rule 12.
2. **One containing element** — promote `TrackSourceSelectedWellBody` to a
   theme primitive (`StudioTabWell`): tab strip + well are one visual unit
   (square-top well docks under the strip, accent ghost-stroke ties them).
   ALL five surfaces get it: melodic ✓, audio-input, slicer, kit-level,
   kit-expanded-row.
3. **Secondary selectors live INSIDE the well** as `StudioSegmentedControl`
   solid-thumb chips (audio-input MODE already does this correctly). Slicer
   layer row and drum-kit layer row move inside their wells. This also
   codifies the existing intentional hierarchy: primary = underline tab,
   subordinate = solid-thumb segment — which answers "drum kit has more of a
   toggle-ish thing": kit-level keeps tabs; the toggle grammar is reserved
   for subordinate selectors everywhere.
4. **Accent discipline** — one accent per surface (track-type identity
   color), applied consistently to underline + well stroke + status badges.
   No per-tab color roulette.
5. **Label purge** — delete the inventoried explainer strings; real state
   becomes badges; anything genuinely instructional moves to `.help`
   tooltips (canon Rule 3).
6. **Grey defaults flipped** — shared components require an explicit accent
   for stateful chrome (no silent `?? StudioTheme.border`); `.secondary`/
   `.gray` escapes swept to tokens; the top-10 offender files audited
   against Rule 12.
7. **Enforcement** — new `scripts/diagnostics/ux-canon-lint.sh`: bans
   `accent.opacity(`-style translucent accent fills, bans system greys in
   Sources/UI outside Theme/, flags sentence-like Text literals (ends in
   period, >4 words) outside sheets' single subtitle slot, flags new
   `subtitle:` explainer params on tab components. Wired next to the audio
   lints so creep pass #4 never ships.

## Open choice for the owner (prototyped as variants)

- **Variant A** — canonical underline-tab grammar unified (per spec AC1)
  with the well; boldest-conforming, least churn.
- **Variant B** — segmented/toggle-primary: primary sections as solid-thumb
  segments (the "toggle-ish" feel everywhere), well unchanged. Diverges from
  the accepted track-view-ia spec; shown for comparison since the owner is
  "not set on tabs".
- Both variants rendered with the label purge + accent discipline applied to
  the audio-input, slicer, and kit surfaces.

## Sequencing / coordination

- Implementation waits for the ux-batch workflow branch to land (it touches
  TrackSourceEditorView/creation flows); this branch then rebases.
- `feature/routing-source-mixer-split` splits the routing tab — the well
  migration must not collide; coordinate at rebase.
- The rotary-template item in ux-batch shares the "one primitive, migrate
  all" shape; land order decided at rebase time.
