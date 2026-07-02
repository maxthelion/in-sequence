# Track View IA — Prototypes

These wireframes test information architecture and interaction grouping for the
track view (drum kits are the hard case). They do not specify production styling,
exact copy, or engine storage details. House style matches the phrase-section
prototypes (light grayscale + accent, `setPrototypeState`).

## Files & states

### Altitudes
- `03-track-matrix.html` — TOP level: all tracks + drum groups.
  States: `edit`, `perform`, `kit-collapsed`, `kit-expanded`.
- `02-kit-matrix.html` — MID level: one drum group, all parts. Patterns are
  always visible above the tab bar (kit tabs: Matrix · FX · Macros · Mixer).
  Header has Capture + Perform buttons: Capture opens History (replacing the tab
  view while patterns stay for assigning); Perform opens scoped kit perform.
  Matrix tab holds names-left rows, 16-step grid + bar pager, layers, and
  expand-a-row as an accordion (detail to the right of the name; Steps/Clip is a
  tab with a Clip↔Generator switch). FX = kit-bus insert chain; Macros = kit
  macros across all parts; Mixer = kit bus output/sends + per-part levels. Plus a
  collapsed-kit-cell view (the track matrix). States: `linked`, `unlinked`,
  `velocity`, `expanded`, `fx`, `macros`, `mixer`, `history` (capture),
  `collapsed`.
- `01-track-detail-tabs.html` — DETAIL level: the re-cut single-track/part editor.
  Tabs: Steps/Clip · Sound · FX · Macros · Mixer. History lifted out; Perform is a
  scoped entry point. States: `steps`, `sound`, `fx`, `macros`, `mixer` + a
  Main-Track ↔ Drum-Part variant toggle.

### Flows / deep dives
- `04-track-perform-scoped.html` — scoped Track Perform (phrase-style overlay
  scoped to one track / whole kit). States: `track`, `kit`, `capture-open`.
- `05-sound-fx-filter.html` — Sound (mini sampler + in-sampler filter), per-track
  FX chain, redesigned filter plugin. States: `sound`, `fx-chain`, `filter-plugin`.
- `06-add-drum-group.html` — kit creation wizard. States: `sounds`, `patterns`,
  `routing` (own-bus-by-default).

### Tab unification + canon-creep repair
Visualizes `../tab-unification-and-canon-creep.md` — the fix for tab
inconsistency across track types (no shared containing element), greyness
creeping back in, and filler label text. Unlike the wireframes above, these
two are rendered at production fidelity (near-black ground `#0d0d10`, drawn
1.5px `#62626c` outlines, solid saturated accents, dark glyphs on solid
fills — the tokens in `Sources/UI/Theme/StudioTheme.swift` /
`StudioSegmentedControls.swift` / `TrackSourceSelectedWellBody.swift`) so the
tab-grammar comparison reads exactly as it will in the app, matching the
current-state screenshots they're diffed against. Each file stacks the same
three surfaces — audio-input (green), mono track (cyan), slicer (violet) —
sharing one `StudioTabWell` (square top corners docking under the tab strip,
12px bottom radius, accent ghost-stroke, one neutral fill step above ground)
with secondary selectors (MODE, LANE/LAYER/LENGTH, the slicer layer row)
living inside the well. Off-path tabs (FX/Macros/Mixer, Sound, Slice) are
dashed stubs per the stub-treatment convention.
- `08-unified-tab-well-A.html` — **Variant A**: primary sections as
  `StudioSlotTabButton` underline tabs (all-caps eyebrow, 2px accent
  underline, ghost-stroke outline, optional solid status badge — mono's five
  tabs carry real-state badges: Clip/Empty/Insert/Empty/Master). Boldest
  conformance to the accepted spec, least churn.
- `08-unified-tab-well-B.html` — **Variant B**: identical surfaces and well,
  but primary sections render as a full-width `StudioSegmentedControl`
  solid-thumb pill (the "toggle-ish" grammar) instead of underline tabs;
  mono's status badges become small inline chips inside each segment.
  Diverges from the accepted spec — shown because the owner is "not set on
  tabs".
- States: `audio-input`, `mono-track`, `slicer-track` (each scrolls the
  matching surface into view — the page stacks all three, taller than one
  screenshot). Render:
  ```sh
  node scripts/render-html-prototype-screenshots.mjs \
    docs/roadmap/track-view-ia/prototypes/08-unified-tab-well-A.html \
    docs/roadmap/track-view-ia/prototypes/rendered/08-unified-tab-well-A \
    'audio-input=document.getElementById("surface-audio").scrollIntoView()' \
    'mono-track=document.getElementById("surface-mono").scrollIntoView()' \
    'slicer-track=document.getElementById("surface-slicer").scrollIntoView()'
  ```
  (swap `-A` for `-B` for the second file). Both files also expose
  `setPrototypeState("audio:fx")` / `"mono:sound"` / `"slicer:slice"` etc. to
  jump a given surface to an off-path stub pane, and cross-link to each other
  for direct A/B comparison in a browser.

## Decisions baked in
- Re-cut detail tabs: Steps/Clip · Sound · FX · Macros · Mixer.
- Tracks get a real per-track FX chain (new model concept).
- Drum-part filter stays inside the mini sampler (part of Sound) this pass.
- Drum kits route to their own bus by default (→ kit-wide FX via bus inserts).
- Kit step grid fixed at 16 + bar pager; part names to the left.
- Pattern linking is explicit; linked kits can collapse to one cell.
- History lifts to track/kit altitude; kit history = all parts, save as one clip set.
- Macros are a first-class tab with per-type defaults.

## Decisions

All open questions are resolved — see `reasoning.md` and the atomic items in
`../feedback/`. The prototype callouts now read "Decided (#N)" rather than "Open
question". Summary: steps-as-tab + persistent patterns (#1); Capture→history at
both altitudes (#2); link = pattern-slot only (#3); collapsed cell in
track/perform + Song, Scenes deferred (#4); structural divergence → break (#4b);
scoped perform reuses the phrase UI (#5); filter in sampler (#6); macro defaults
as editable templates (#7).

## Grounding captures

Fresh build captures (current `main`) in `.meta/multipass/visual-review/`:
`03-tracks-perform`, `02-tracks-edit`, `18-track-source-clip`,
`21-track-modifier-tab`, `22b-track-routing-tab`, `28-drum-part`,
`29-drum-kit-matrix`, `30-drum-kit-matrix-32`, `11-phrase-perform-overlay`,
`14-tracks-perform-layer-selector`, `05a/05b-scenes-edit-*`, `31-drum-kit-routing`.
</content>
