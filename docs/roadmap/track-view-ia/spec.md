---
feature: track-view-ia
created: 2026-06-19
status: accepted builder-facing behavior spec
sources:
  - README.md
  - docs/roadmap/track-view-ia/reasoning.md
  - docs/roadmap/track-view-ia/feedback/
  - docs/roadmap/track-view-ia/prototypes/
---

# Track View IA Spec

## Product Contract

The track view is reorganised into three altitudes — **track matrix** (all
tracks + drum groups), **kit matrix** (one drum group, all parts), and the
**single-track/part detail** — with a consistent tabbed grammar. Drum kits are
first-class: their own bus, their own tabs, explicit pattern linking, and a
shared history. The work must preserve the app's matrix-based groovebox
character and reuse existing controls/layouts where they already express the
right concept (notably the `routing-source-mixer-split` source/mixer split and
the phrase perform grammar).

This is an IA + interaction change. It introduces exactly one genuinely new model
concept — **per-track insert FX** — and otherwise re-cuts and reuses existing
surfaces.

## Functional Delta Checklist

### Single-track detail — re-cut tabs
- The detail editor's tabs are, in order: **Steps/Clip · Sound · FX · Macros · Mixer**.
- **Steps/Clip** = the existing clip/step source grid (today's "Source" grid).
- **Sound** = the instrument only (AU instrument / MIDI out / sampler), reusing
  the `routing-source-mixer-split` SOUND SOURCE well + `.soundSource` vocabulary.
- **Mixer** = output bus + Send A/B (the MIXER & FX well).
- The instrument tab is named **Sound**, never "Source" (a "Source" tab already
  means the clip/note source).
- A **Patterns** row is always visible above the detail tabs (consistent with the
  kit page); it is not inside a tab.

### Per-track FX
- **FX is a per-track insert chain** — a new model concept; inserts previously
  existed only on buses / master / scenes.
- Each insert row: a **drag handle to reorder** (no up/down arrows), the FX name +
  subtitle, and a **bypass toggle + remove ✕ on one line**.
- Add control is a **"+ FX"** button (not an "Insert" dropdown).
- No "Enabled" label; no large "Empty"/"Empty Scene" filler text — compact empty
  state only.
- The same cleanup applies to the Scenes inserts panel and the kit-bus FX chain.

### Filter plugin
- Radial controls where possible; **no wet/dry** control.
- More filter types (at least Low Pass, High Pass, Band Pass, Notch, Peak, plus
  others e.g. Comb/Formant).
- A **filter-curve visualization** reflecting type + cutoff + resonance.
- A drum part's filter stays **inside the mini sampler** (part of Sound), not the
  FX chain, this pass.

### Macros
- Macros are a first-class tab (track and kit): macro lanes + slot assignments
  (M1–M8) together.
- Per-type **editable default templates seeded with initial values**: a fresh
  drum part lands with M1 sample direction, M2 sample length, M3 filter cutoff
  pre-mapped; all editable/removable.

### Kit matrix — layout
- Step grid is **fixed at 16 columns** with a **bar pager** (1–16 / 17–32 …);
  the 16/32 width toggle is removed.
- Step editing reuses the **same primitives as the normal track view**.
- Each part **name is to the LEFT** of its row (not on top) so more rows fit.

### Kit page — patterns, tabs, capture, perform
- The **Patterns row is always visible, above the kit tab bar** (a persistent
  assignment surface).
- Kit tab bar: **Matrix · FX · Macros · Mixer**.
- **Kit FX** = insert chain on the kit's own bus (across all parts).
- **Kit Macros** = M1–M8 sweeping a parameter across all parts at once, or the
  bus FX.
- **Kit Mixer** = the kit bus output (→ Master), Send A/B, and per-part levels.
- **Capture** and **Perform** are header buttons (not tabs), side by side.
- **Capture opens the history surface**, which **replaces the tab view**; the
  Patterns row stays visible so a captured clip set can be assigned to a slot.

### Kit bus
- A new drum group routes to **its own dedicated bus by default** (named after
  the kit), not Master. Master remains a selectable non-default option.
- Surfaced as the default in the Add Drum Group routing step.

### Kit pattern linking
- Linking is an **explicit toggle** in the Patterns row (not the implicit
  "MIXED" badge).
- Linking locks **pattern slot selection only**: all parts switch slots together.
  **Mute, fill, and macros stay per-part** even when linked.
- A **linked kit collapses to one cell** in the track/perform matrix and **Song
  mode**; unlinked expands to per-part cells. (linked↔collapsed,
  unlinked↔expanded.) Scenes is deferred.
- Editing a part's **step content** within the shared slot is always allowed and
  does not break linking.
- **Structural divergence** (a part given a different length, or moved to a
  different slot) resolves by **break**: that part auto-unlinks, the kit shows
  MIXED, with one-click re-link. No modal block; no pattern fork.

### Expand a kit row
- A part row **expands as an accordion**: the detail panel opens **to the right
  of the part name** (in the row's step area); the row grows vertically and other
  parts stay compact. The user stays in the kit matrix.
- The panel **reuses the single-track detail surfaces** inline: Steps/Clip ·
  Sound · FX · Macros · Mixer, plus an "Open full editor" affordance.
- **Steps/Clip is a tab** with a **Clip ↔ Generator** switch; the generator can
  carry a modifier.

### History
- History leaves the per-track tabs and is reached via **Capture** at both the
  track and kit altitudes.
- Kit history shows **all parts' live buffers together** and saves the lot as
  **one coordinated clip set** (assignable to a Pattern slot), not part by part.
- A shared **scrubber/timeline** moves the selection window back through the
  rolling buffer **in lockstep across all parts**, with a **live** anchor to jump
  to now. (Model: capture `22-track-history-tab`, which today has no way to scrub
  back through the buffer.)

### Scoped Track Perform
- A **Perform** button on a track or kit opens the **phrase perform UI scoped
  down** to that single track / whole kit — reusing the phrase perform grammar
  (layers, value cells, Mom/Latch, latch timing, Capture/Discard, basis phrase).
  No bespoke surface.

## Data And Engine Checklist
- Per-track insert FX is a new persisted model concept (chain of inserts per
  track), ordered, each with bypass.
- A drum group's default destination is a newly created bus; kit-bus inserts
  apply to the summed kit.
- Kit "linked" is an explicit per-group state controlling pattern-slot ganging
  only; mute/fill/macros remain per-member.
- Structural divergence of a member (length/slot) auto-clears that member's link
  participation and surfaces MIXED; re-link restores ganging.
- Macro default templates are seeded per track type at creation and are fully
  editable thereafter (not fixed mappings).
- Kit history reads all members' live buffers against one shared selection window
  and writes a coordinated clip set in one action.
- Scoped perform reuses the existing phrase perform overlay model at single-track
  / single-kit scope; no new overlay model.

## Anti-Hybrid Checklist
Reviewers should fail the build if any of these are true:
- The instrument tab is labelled "Source" (collides with the clip/note source).
- The kit step grid still offers a 16/32 width toggle instead of 16 + bar pager.
- Part names are still rendered on top of rows rather than to the left.
- History is still a persistent tab instead of a Capture-button surface.
- The Patterns row is hidden inside a tab instead of always visible above the tabs.
- FX uses up/down arrows or an "Insert" dropdown, or shows "Enabled"/"Empty Scene".
- The filter still shows a wet/dry control.
- Linking is only the implicit "MIXED" badge with no explicit toggle.
- Linking gangs mute/fill/macros (it must gang pattern slot only).
- A structural-divergence edit opens a modal block or forks a pattern instead of
  breaking the link.
- Expanding a kit row pushes a full-screen editor or opens below the row instead
  of an accordion to the right.
- Scoped perform builds a second, bespoke perform UI instead of reusing the
  phrase perform grammar.

## Acceptance Criteria
1. Single-track detail shows tabs in order Steps/Clip · Sound · FX · Macros · Mixer.
2. The instrument tab is named "Sound"; the clip/note source remains "Steps/Clip".
3. A Patterns row is visible above the tabs on both the track detail and the kit page.
4. FX is a per-track insert chain: rows reorder by drag handle, with bypass + ✕ on one line, added via "+ FX".
5. No "Enabled"/"Empty Scene" filler text appears in FX/inserts.
6. The filter plugin uses radial controls, offers ≥5 filter types, shows a curve visualization, and has no wet/dry.
7. A drum part's filter is inside the mini sampler (Sound), not the FX chain.
8. Macros is a tab; a fresh drum part has M1 direction / M2 length / M3 cutoff pre-mapped and editable.
9. The kit step grid is 16 columns with a working bar pager; the 16/32 toggle is gone.
10. Drum part names render to the left of each row.
11. A new drum group defaults its destination to a dedicated bus (not Master).
12. The kit Patterns row stays visible across all kit tabs and during Capture.
13. The kit tab bar is Matrix · FX · Macros · Mixer; Capture + Perform are header buttons.
14. Capture opens history, replaces the tab view, and the Patterns row stays for assigning.
15. Kit history shows all parts together and saves one coordinated clip set to a chosen slot.
16. Kit history has a scrubber that moves the selection window back through the buffer across all parts in lockstep, with a live anchor.
17. Pattern linking has an explicit toggle and gangs slot selection only; mute/fill/macros stay per-part.
18. A linked kit collapses to one cell in the track/perform matrix and Song mode; unlinked expands to per-part cells.
19. Editing a part's step content while linked is allowed and does not break the link.
20. Structural divergence (different length/slot) auto-unlinks that part (MIXED) with one-click re-link; no modal block, no fork.
21. Expanding a kit row opens an accordion to the right of the name; other rows stay compact; Steps/Clip offers a Clip↔Generator switch.
22. A Perform button on a track/kit opens the phrase perform UI scoped to that track/kit (reused, not bespoke).
23. Kit FX / Macros / Mixer tabs operate at kit-bus scope, distinct from per-part FX/macros.
24. Visual review evidence shows the built surfaces compared with the prototype intent (01–06).

## Verification Scenarios
Use the smallest automated checks plus QA-capture visual evidence. New/updated
QA surface-coverage rows should be added so each surface is captured
deterministically (mirroring the existing `qa-surface-coverage.sh` table).

- Open a melodic track: detail tabs read Steps/Clip · Sound · FX · Macros · Mixer; Patterns row above.
- FX tab: add two inserts, reorder by handle, bypass one, remove one — no arrows, no "Insert" dropdown, no filler text.
- Filter: switch among ≥5 types; curve updates; no wet/dry control present.
- New drum group: routing step defaults to a dedicated bus.
- Drum kit: open kit page — Patterns above tabs (Matrix · FX · Macros · Mixer), Capture + Perform in header; names left; 16 steps + bar pager pages to 17–32.
- Link toggle on: switch the group pattern, all parts follow; mutes set per-part are unaffected.
- Move one part to a different slot: it auto-unlinks, kit shows MIXED, re-link restores.
- Expand a part row: accordion opens to the right, other rows compact; switch Steps/Clip between Clip and Generator.
- Capture (kit): history replaces tabs, all parts shown; scrub back through the buffer; save as clip set → assign to a Pattern slot.
- Perform (kit): the phrase perform UI opens scoped to the kit.
- Kit FX tab: an insert added here processes the whole kit (bus), distinct from a per-part FX added via row expand.
</content>
