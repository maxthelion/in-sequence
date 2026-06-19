# Track View IA — V1 Reasoning

This pass rethinks the information architecture of the track view, with drum kits
as the hard case that stresses every decision. It mirrors the phrase-section
workflow: ground in real captures, write the IA tension down, then iterate in
HTML prototypes before any production styling.

## Captures grounding this pass

- `.meta/multipass/runtime/loops/project/observe/qa-surface-coverage/03-tracks-perform.png`
  — track matrix (8 cards, perform action bar: Track Layer, Basis Phrase, Edit
  Set, Mom/Latch, Perform).
- `.meta/multipass/runtime/loops/project/observe/qa-surface-coverage/29-drum-kit-matrix.png`
  — kit matrix (808 Bones, 8 parts · 16 steps, Group Pattern row = MIXED,
  Steps/Velocity/Chance layers, part name on top of each row, Pattern Mismatch).
- `.meta/multipass/runtime/loops/project/observe/qa-surface-coverage/30-drum-kit-matrix-32.png`
  — same kit at 32 steps (the layout this pass wants to remove).
- `docs/bugs/.../05a-scenes-edit-empty.png`, `05b-scenes-edit-content.png`
  — Scenes "Inserts" / FX chain panel + scene macros (drives the FX cleanup).

## Current state

The single-track detail is already tabbed: **Source** (sound well + clip/step
grid + macro lanes), **Modifier** (a single FX generator), **History** (clip
capture buffer), **Routing** (AU card + preset + output bus + Send A/B + AU macro
slots M1–M8). Drum parts are ordinary grouped `StepSequenceTrack`s overlaid with
`TrackGroup` metadata; the kit matrix is the multi-part editing surface.

So this is not "add tabs from scratch" — it is re-cutting existing tabs along
cleaner seams and lifting two responsibilities (History, Perform) to a higher
altitude.

## Three altitudes

1. **Track matrix** — all tracks and drum groups together.
2. **Kit matrix** — one drum group, all parts.
3. **Single track / single part detail** — the tabbed editor.

The recurring design pressure across all three is one question: **is a drum kit
one thing or eight things?** It shows up in the Group Pattern row (linked vs
MIXED), the perform matrix (one kit cell vs eight part cards), and history (one
clip set vs per-part clips). Because it surfaces in three places at once, it
should be a single explicit link state those surfaces all read from.

## Proposed direction

### Re-cut the detail tabs

The four current tabs become five, cut along cleaner functional seams:

- **Steps / Clip** — core pattern editing (today's Source grid).
- **Sound** — the instrument only: AU instrument / MIDI output / sampler, plus
  preset. (Pulled from Source's source well + Routing's AU card.) For drum parts
  the sound is a **sampler + filter combination**, which raises the seam question
  below: is that filter part of Sound, or a standalone entry in FX?
- **FX** — a real insert chain, not a single modifier. Drag handle to reorder
  (not arrows), inline bypass + remove (✕) on one line, "+ FX" add button (not a
  dropdown labelled Insert), no "Enabled"/"Empty" filler text. The filter plugin
  inside this chain gets radial controls, more filter types, no wet/dry, and a
  filter-curve visualization.
- **Macros** — macros as a first-class surface: macro lanes + AU macro slots
  (M1–M8) together. Macros can ship **type-specific defaults**: a drum part could
  initialize with sample direction, sample length, and filter cutoff already
  mapped to M1–M3, so a fresh part is performable without manual assignment.
- **Mixer** — just the mix routing: output bus + Send A/B. (Split off from Sound.)

Open: is **Steps/Clip** its own tab, or always-visible with Sound/FX/Macros/Mixer
as tabs beneath it (the way the kit matrix keeps its grid on top)?

### Lift History up a level

Clip history leaves the per-track tabs. For a kit, history should show **all
parts together** and let the user **save the lot as one set of clips** (a single
capture produces a coordinated clip set across the kit, not eight separate
captures). This makes History an altitude-aware surface (track-level vs
kit-level), not a buried tab.

**Missing mechanism — moving through history.** The current History tab
(capture `22-track-history-tab`) is a *rolling live buffer* with a Selection
Length (½ / 1 / 2 / 4 bars) and a "Recent Output" strip of 16 slots, but it has
**no way to move through the recorded history** — you can only grab the live
window or a recent-output slot, not scrub/page back to an earlier moment. The
kit history needs a **shared scrubber/timeline** that moves the selection window
back through the rolling buffer, in lockstep across all parts, with a "live"
anchor to jump back to now — before Save as clip set captures the chosen window
across the whole kit.

Open: does History live at the track-matrix level (global capture surface), the
kit level, or both?

### Track Perform as an entry point

A **Perform** button on a track or kit page launches the new phrase-style perform
views, but **scoped to the single selected track/kit** rather than the whole
project. Reuses the phrase perform layer/scene grammar at single-track scope.

### Kit-specific fixes

- Part names move to the **left** of each row (not on top) so more part rows fit.
- The kit step grid is **capped at 16 steps** with a **bar-select pager** to page
  through bars, reusing the same step primitives as the normal track view. The
  32-wide layout is removed. The pager already exists: the single-part editor
  shows a `1-16 / 17-32` bar pager at the bottom of its clip grid, so this is
  bringing an existing primitive up to the matrix, not inventing one.

### Kit bus by default

A new drum group should route to **its own bus by default**, not straight to
Master. Because inserts live on buses (see the FX fork), a dedicated kit bus is
what makes "FX across the whole kit" possible — kit-level FX is just inserts on
the kit's bus. This also gives the kit a single mixer strip and a natural place
for the collapsed-kit cell to point at.

### Kit-level tabs

The kit is a first-class entity (its own bus, its own parts), so the kit altitude
gets its own tab bar paralleling the track tabs one level up.

**Patterns are always visible, above the tabs.** The group pattern row (slots +
the link control) is a persistent assignment surface, not buried inside a tab. It
stays on screen across every kit tab — and crucially during Capture — so a
captured clip set can always be assigned to a slot.

The tabs:

- **Matrix** — the parts × steps grid (the default; holds layers, bar pager,
  expand-a-row).
- **FX** — the insert chain on the kit's own bus, i.e. FX across the whole kit.
  Distinct from per-part FX (reached by expanding a part row).
- **Macros** — kit macros: M1–M8 that drive a parameter across all parts at once
  (e.g. filter cutoff on every part) or the bus FX. Relates to macro defaults (#7).
- **Mixer** — the kit bus: output (→ Master), Send A/B, and per-part levels.

**Capture and Perform are header buttons, not tabs.** They sit together in the
kit header above the patterns. **Capture** opens the history surface, which
*replaces the tab view* (the patterns stay visible above it for assigning the
captured clip set). **Perform** opens the scoped perform surface for the whole
kit. History is therefore reached as a capture action, not a persistent tab.

The track-level tabs (Sound/FX/Macros/Mixer) apply per part when a row is
expanded or dived into — so FX and macros exist at two scopes: kit-bus and
per-part.

### Expand a kit row into part controls

From the kit matrix, a part row should **expand** to expose the normal
track-detail options for that part — Steps/Clip, Sound, FX, Macros, Mixer. It
behaves as an **accordion**: the detail panel opens **to the right of the part
name** (in the row's step area) and the row grows vertically while the other
parts shrink/stay compact — you never leave the kit matrix. The panel reuses the
single-track detail surfaces (so no second editor is invented), with
**Steps/Clip as a tab** like the track view that lets the part switch between a
**clip** and a **generator (+ modifier)**.

The complication is the **pattern/clip contradiction**: when the kit pattern is
linked, but the expanded part's clip/pattern differs from the linked group
pattern (the current "MIXED" / "Pattern Mismatch" condition), editing the part's
Steps/Clip contradicts the link. Options to resolve: editing a part's steps
**breaks the link** for that part (it becomes per-part), or it **forks** a new
pattern, or it is **blocked** with a warning while linked. Note that the other
part controls (Sound, FX, Macros, Mixer) do **not** contradict the link — only
the Steps/Clip layer does — so expand-to-edit is safe for everything except
pattern content.

### Pattern linking for kits

Patterns should be **linked by default** so all parts switch together as one unit.
But linking fights the layer and perform views, which may want per-part
independence. So linking/unlinking becomes an **explicit state** (not something
discovered via a "MIXED" badge). When linked, the kit can **collapse to a single
cell** in the perform/macro matrix — one cell drives pattern (and related values)
for the whole kit as a unit instead of eight separate part cells.

## Existing in-flight work to build on (not against)

Two gated worktrees already overlap this redesign:

- `feature/routing-source-mixer-split` already performs the **content** split:
  the Routing tab body is re-laid into a **"SOUND SOURCE" well** (the instrument:
  AU / MIDI port / sampler / slicer / group inheritance) and a **"MIXER & FX"
  well** (output bus + Send A/B). It reuses the existing routing model — no new
  mixer semantics — and ships a `.soundSource` vs `.destination` vocabulary plus
  a `TrackRoutingWellsPresentation`. The wireframes should reuse
  `TrackDestinationEditor(vocabulary: .soundSource)` for the Sound surface and the
  output/sends block for the Mixer surface. Our incremental work is only
  **promoting the two wells to two tabs**, not inventing the split. Not yet gated.
- `auto/p0-track-performance-overlay` + `codex/live-perform-fill-overlay` already
  build a track performance overlay and fill latch — the substrate for the scoped
  Track Perform entry point.

Two consequences for naming and scope:

- **Naming collision.** A top-level **"Source" tab already exists** and means the
  *clip / generator note source* (the pattern), which is different from the
  instrument. This pass resolves it by renaming the clip tab to **Steps/Clip** and
  using **Sound** for the instrument. Do not call the instrument tab "Source".
- **Per-track FX (DECIDED): tracks get their own FX.** Inserts did not exist
  per track before (they lived on buses / master / scenes — the FX cleanup bugs
  are on the *Scenes* "Inserts" panel). This pass introduces **per-track inserts
  as a real model concept**: the FX tab is a genuine per-track insert chain. Kits
  additionally route to their own bus by default (see Kit bus by default), so a
  kit has both per-part FX and shared bus FX available.
- **Drum-part filter (DECIDED): stays in the mini sampler for now.** A drum
  part's sound is a sampler + filter voice, and for this pass the filter remains
  *inside* the sampler (part of **Sound**) rather than being separated into the
  FX chain. The filter cleanup bug (radial controls, curve viz) applies to that
  in-sampler filter. Fully separating it into FX is deferred.

## Decisions

- **#1 Steps placement** — the step grid is a **tab** (Matrix on the kit,
  Steps/Clip on the track). The always-visible element above the tabs is the
  **Patterns row**, not the grid.
- **#2 History altitude** — the **Capture button → history surface** pattern is
  used at **both** altitudes: kit (all parts, save as one clip set) and
  single-track (the 1-part case). Capture replaces the tab view; patterns stay
  visible for assigning.
- **#3 Kit link scope** — linking locks **pattern (slot selection) only**. Mute,
  fill, and macros stay **per-part** even when linked, because those are the
  performance gestures you don't want ganged. The control is an explicit toggle
  in the persistent Patterns row.
- **#4 Collapsed kit cell** — appears in the **track/perform matrix (edit +
  perform) and Song mode**, with an Expand button; linked↔collapsed,
  unlinked↔expanded. **Scenes is deferred** (different model).
- **#5 Scoped Perform** — **reuse the phrase perform UI, scoped down** to one
  track/kit. No bespoke surface (proto 04 shows it).
- **#6 Drum part filter** — stays in the mini sampler (part of Sound) this pass;
  separating it into FX is deferred.
- **#7 Macro defaults** — **editable templates seeded with initial values**. A
  fresh drum part lands with sample direction / length / filter cutoff pre-mapped
  (kit macro: cutoff-across-parts + bus drive), all fully editable/removable.
- **#4b Linked-part edit** — editing a part's **step content** within the shared
  slot never contradicts linking (all parts still switch slots together), so it
  is always allowed. The only conflict is **structural divergence** — a part
  given a different **length** or moved to a different **slot** (the "MIXED"
  state) — and that resolves by **break**: the divergent part auto-unlinks, the
  kit flags MIXED, with one-click re-link. No modal block, no pattern forking.
  Non-pattern controls (Sound, FX, Macros, Mixer) never contradict the link.

All open questions are now resolved.
</content>
