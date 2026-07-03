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
After the first render pass the owner flagged the strip/well GAP (selected
tab floating above the well edge, reading as two artifacts); the three files
now cover the three connection forms he asked to compare:
- `08-unified-tab-well-A.html` — **Variant A, seamless folder tabs** (owner
  form 1): `StudioSlotTabButton` grammar (all-caps eyebrow, optional solid
  status badge — mono's five tabs carry real-state badges:
  Clip/Empty/Insert/Empty/Master), with the selected tab's outline flowing
  seamlessly into the well border: the well's top border runs left of the
  tab, up and around its sides/top, back down, and continues right. No line
  under the active tab; its interior is continuous with the well. Unselected
  tabs stay pills above the border line.
- `08-unified-tab-well-B.html` — **Variant B, segmented-primary**: primary
  sections as a full-width `StudioSegmentedControl` solid-thumb pill (the
  "toggle-ish" grammar) rendered as a header row INSIDE the well, so no
  strip/container gap exists at all; mono's status badges become small
  inline chips inside each segment. Diverges from the accepted spec — shown
  because the owner is "not set on tabs".
- `08-unified-tab-well-C.html` — **Variant C, pill + full-accent border**
  (owner form 2): the original pill-tab look (2px accent underline, gap to
  the well retained) but the well border carries the surface accent at full
  strength so pill + container read as one system. Accent as outline only —
  canon Rule 12 bans accent fills, not outlines.
- `08-unified-tab-well-D.html` — **Variant D, solid pills over a
  fully-rounded accent well** (owner hybrid of B + C): Variant B's
  solid-thumb segmented pills (selected = fully solid accent with dark
  glyph, unselected = outline) float OUTSIDE the container with the small
  gap as in C, and the well is a complete full-strength-accent-outlined
  container with all four corners rounded (12px, no square tops).
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
  (swap `-A` for `-B` / `-C` / `-D` for the other files). All files also expose
  `setPrototypeState("audio:fx")` / `"mono:sound"` / `"slicer:slice"` etc. to
  jump a given surface to an off-path stub pane, and cross-link to each other
  for direct A/B comparison in a browser.

**Owner picked Variant D; kit/part proof approved — grammar LOCKED
(function-based rule, owner-approved 2026-07-02):**
- `09-kit-and-part-D.html` — Variant D grammar on the kit view, two stacked
  sections: collapsed matrix and expanded part. ALL section switchers use
  the D-pill grammar: the kit-level MATRIX/FX/MACROS/MIXER pills (solid
  kit-orange thumb) floating outside the well, AND the part-level
  Steps/Clip·Sound·FX·Macros·Mixer switcher inside the expanded sub-card —
  left-aligned flush to the sub-card edge, same shape/size grammar as the
  kit pills. ONLY value/layer selectors (Steps/Velocity/Chance, Normal/Fill,
  BAR range) use the inset-track solid-thumb style — solid thumbs inside a
  darker inset capsule. The well is a complete full-strength kit-accent
  outline (12px all corners) containing the layer selector rows AND the
  part rows; Apply Template stays a standalone solid action button; the
  expanded Kick row is a NEUTRAL-outlined sub-card (border grey, never a
  second accent outline fighting the kit's).
  - Part pill accent choice: kit orange, not a per-part colour — one chrome
    accent per surface; the render confirms the cyan/green content accents
    (green kick waveform, cyan Cutoff ring + filter curve + solid LP chip)
    sit on inset panels one step darker and read as content state, with no
    section-switcher ambiguity now that pill shape separates switchers from
    the inset-track value selectors.
  - States: `kit-matrix`, `part-expanded` (scrollIntoView per section);
    `setPrototypeState("kit:fx")` / `"part:macros"` etc. jump to stub panes.
    Render with the same command shape as the 08 files, output
    `rendered/09-kit-and-part-D/`.

### Generators (chord dual-role + mono split-vs-unified)
- `14-generators.html` — D-grammar applied to the generator surfaces, for the
  2026-07-02 intents (chord-generator revisit 150004, mono-generator options
  150005). Three parts on one page:
  - **(a) Chord generator, dual role.** (a-1) as a playable instrument on its
    own track — full progression editor (Length chips, Chords trigger cards,
    Load Preset panel with the real seeds Minor Descending / Pop Major / Jazz
    Turnaround / Empty, selected-chord controls Position/Type/Inversion/
    Voicing/Notes/Length as inset-track rows, Layer row, 16-step page whose
    cells show roman + active-layer value). Amber = chord identity accent.
    (a-2) the SAME source from a consumer's side: a mono track's Pitch stage
    where the current opaque `Picker("Harmonic Sidechain", …)` menu becomes a
    visible **Chord Source** inset-track row (None / Chord Context / Chords 3 /
    Chords 7); picking a chord track lights the chip amber (the source's
    identity colour) and shows a small solid "FOLLOWING Chords 3 · iv" badge.
  - **(b) Mono generator, split form** — the current
    `.mono(trigger:pitch:shape:)` pipeline as two D-pill stage tabs
    (Trigger · Pitch). Trigger offers Euclidean (Pulses/Steps/Offset knobs,
    per StepAlgoEditor) AND a proposed Weighted mode (per-step probability
    bars reusing the GridEditor treatment). Pitch = algorithm row
    (Manual/Scale/Chord/Prob/Markov/Clip/MIDI In per PitchAlgoKind) with
    Markov controls (Root, Style Vocal/Balanced/Jazz, Scale, Leap, Color) +
    the Chord Source row.
  - **(c) Mono generator, unified alternative** — identical params on ONE
    well with no stage tab: Trigger and Pitch as eyebrow-labelled regions
    separated by a hairline, plus a read-only "Combined result" strip
    (trigger dots + resolved note names) that only the unified form can show.
    (b) and (c) are functionally equivalent so split-vs-unified reads as a
    structural comparison only — the owner's open question from intent 150005.
  - States: `chord-instrument`, `chord-sidechain`, `mono-split-euclidean`,
    `mono-split-weighted`, `mono-split-pitch`, `mono-unified-euclidean`,
    `mono-unified-weighted` (all via `setPrototypeState(...)`). Render with
    the standard command, output `rendered/14-generators/`; copies at
    `.meta/multipass/visual-review/feature-track-view-tab-unification/proto-14-*.png`.
  - Deliberate stubs: Sound/FX/Macros/Mixer panes, and the sidechain
    surface's own Trigger pane (shown fully in (b) instead). Weighted trigger
    does not exist in `StepAlgo` yet — proposal only.

Copies of all rendered PNGs (08-A/B/C/D + 09 + 14) also live at
`.meta/multipass/visual-review/feature-track-view-tab-unification/` as
`proto-08D-audio-input.png` / `proto-09-kit-matrix.png` etc., so the owner's
bug-reporter app picks them up; `prototypes/rendered/` stays canonical.

### Pattern-row state model: playing / displayed / perform-tracking / fill
- `10-pattern-row-fill-states.html` — **superseded by `15-pattern-row-v2.html`
  for the playing/displayed/tracking model** (owner review 2026-07-03: keep
  the playing-indicator idea but "the progress bar doesn't work"; "10 is a
  bit complicated" re Tracking/Pinned). The fill-lane scenarios (`c-engaged`,
  `c-preview`) remain current. Original entry: the pattern-slot row STATE MODEL on a
  D-grammar mono-track surface, resolving intents
  `20260702-150001-fill-mode-should-actually-work.md` (fill mode is currently
  inert) and `20260702-150002-pattern-row-state-model-tension.md` (playing vs.
  displayed vs. perform-tracking tension: "arguably there is also a perform
  mode for tracks that changes the current pattern within the playing phrase
  and tracks it as it changes"). Grounded on the current pattern-row
  implementation (`Sources/UI/TrackSource/TrackPatternSlotPalette.swift`) and
  `.meta/multipass/visual-review/engine-precompute-lookahead/18-track-detail-steps-clip.png`
  / `20-track-fill-preview-active.png`. Six stacked scenarios, each an
  independently-interactive mono-track surface (click any pattern slot,
  Perform, the Tracking/Pinned segmented control, Lane, or Fill Preview to
  explore combinations beyond the six named states):
  - `a-baseline` — playing ≠ displayed: slot 1 plays, slot 4 is open for
    editing.
  - `a-combined` — playing == displayed: slot 4 is both.
  - `b-tracking` — Perform ON, Tracking: displayed auto-follows playing as it
    changes (clicking a slot both launches it live and opens it for editing).
  - `b-pinned` — Perform ON, Pinned: playback keeps running on one slot while
    the user pins a different slot open for editing without disturbing it; a
    `⟲` resync icon (visible only when playing ≠ displayed while pinned)
    snaps back to Tracking.
  - `c-engaged` — Lane = Fill: the pattern row's markers and the step grid
    switch to the clip's fill items.
  - `c-preview` — Fill Preview ON while Lane stays Normal: fill-only steps
    overlay as a dashed amber ring on top of the committed (solid) normal
    steps, without switching the Lane selection.
  - Visual grammar (all readable without text, canon Rule 3): **playing** =
    small play-tick + a bottom progress bar + soft glow, independent of
    selection; **displayed** = accent outline ring (no fill, canon Rule 12);
    **tracking** = pulsing ring + solid `»` badge; **pinned** = solid `◆`
    badge (neutral colour, not accent) + the `⟲` resync affordance;
    **occupied/empty** = solid vs. hollow dot (unchanged from the shipped
    component). Fill state recolors only the *content* accent (marker dots,
    ticks, badges, step-grid on-color) to amber; the well/tab-strip/surface
    chrome stays the track's identity accent (cyan) throughout — this follows
    the LOCKED "one chrome accent per surface" rule (fill is content, not
    surface identity) and mirrors the existing violet bypass-state override
    already in `TrackPatternSlotPalette.swift`.
  - States via `setPrototypeState(name)`: `a-baseline`, `a-combined`,
    `b-tracking`, `b-pinned`, `c-engaged`, `c-preview`. Render:
    ```sh
    node scripts/render-html-prototype-screenshots.mjs \
      docs/roadmap/track-view-ia/prototypes/10-pattern-row-fill-states.html \
      docs/roadmap/track-view-ia/prototypes/rendered/10-pattern-row-fill-states \
      'a-baseline=setPrototypeState("a-baseline")' \
      'a-combined=setPrototypeState("a-combined")' \
      'b-tracking=setPrototypeState("b-tracking")' \
      'b-pinned=setPrototypeState("b-pinned")' \
      'c-engaged=setPrototypeState("c-engaged")' \
      'c-preview=setPrototypeState("c-preview")'
    ```
  - Copies also live at
    `.meta/multipass/visual-review/feature-track-view-tab-unification/` as
    `proto-10-a-baseline.png` / `proto-10-a-combined.png` /
    `proto-10-b-tracking.png` / `proto-10-b-pinned.png` /
    `proto-10-c-engaged.png` / `proto-10-c-preview.png` /
    `proto-10-legend.png`.
  - Off-path stubs: Sound/FX/Macros/Mixer tab panes; Layer = Velocity/Chance
    and the Length row are decorative (unwired) in this pass.
  - Reviewer-only legend (dashed border, marked "not app chrome") at the
    bottom explains each visual cue.
  - Coordination note: `13-track-perform.html`'s in-session pattern-row
    treatment ("collapsed played+displayed into one TRACKED slot: solid
    accent fill + second offset outline ring") predates this prototype and
    uses a different tracking visual (solid fill vs. this file's pulsing
    outline ring + `»` badge) — flagged there for reconciliation against this
    file; not yet reconciled here.

### Pattern-row state model v2 (owner iteration on 10 vs 13)
- `15-pattern-row-v2.html` — the owner's decisions after reviewing 10 and 13,
  on the D-grammar mono-track surface:
  - **Playing = pulsing bullet**: the slot's existing small dot pulses in the
    surface accent (persistent glow so static captures read it too) —
    replaces 10's play-tick + progress bar entirely.
  - **Displayed = outline ring** (unchanged); ring + pulsing dot stack
    cleanly when playing == displayed.
  - **No Tracking/Pinned sub-mode.** Default click = view/edit (displayed
    moves, playing untouched). **Right-click = launch override**: quantized
    to the next bar, single-value (holds until changed/cleared), never
    mutates the phrase. Pending-until-bar uses the app's armed-not-committed
    idiom: dashed amber outline + blinking hollow amber dot.
  - **Dirty/ghost phrase — the keystone**: when overrides make playback
    diverge from the defined phrase, the transport's phrase-chip row grows a
    ghost pill `A′` (dashed amber outline, breathing glow) inserted beside
    the basis `A`, which dims to a muted outline with a dotted amber
    underline. Clicking the ghost opens the fork: **Save as new phrase**
    (solid green) · **Apply to A** (amber outline) · **Discard** (neutral
    outline). 13's dashed basis-anchor folds into the pattern row: while an
    override plays, the slot the phrase originally defined keeps a dashed
    neutral border + tiny `basis` badge (the Reset target).
  - States via `setPrototypeState(name)`: `a-split` (playing ≠ displayed),
    `b-pending` (right-click launch armed at 1:3:4), `c-ghost` (override
    active, ghost A′ + basis markers), `d-fork` (ghost fork open). Sections
    are independently interactive: right-click any slot to arm a launch,
    click A′ to toggle the fork. Render:
    ```sh
    node scripts/render-html-prototype-screenshots.mjs \
      docs/roadmap/track-view-ia/prototypes/15-pattern-row-v2.html \
      docs/roadmap/track-view-ia/prototypes/rendered/15-pattern-row-v2 \
      'a-split=setPrototypeState("a-split")' \
      'b-pending=setPrototypeState("b-pending")' \
      'c-ghost=setPrototypeState("c-ghost")' \
      'd-fork=setPrototypeState("d-fork")'
    ```
  - Copies at `.meta/multipass/visual-review/feature-track-view-tab-unification/`
    as `proto-15-a-split.png` / `proto-15-b-pending.png` /
    `proto-15-c-ghost.png` / `proto-15-d-fork.png`.
  - Scale judgment from the renders: the ghost pill DOES read at
    transport-bar scale — dashed amber against the solid violet defined
    phrases is unambiguous, and inserting A′ directly after A keeps the
    lineage legible; but the dimmed-A dotted underline is near the legibility
    floor at chip size, so if the built app's chips are smaller than the
    mock's (34px min-width), prefer dropping the underline and letting the
    dimmed fill + adjacent ghost carry the "basis" relationship. The fork
    popover anchors under the ghost without colliding with the pattern row.
  - Off-path stubs: Sound/FX/Macros/Mixer panes are static; phrase chips
    B–D are decorative.

### Layer system: Pitch layer + quick-switch
- `11-step-layer-system.html` — the unified step-layer system, addressing
  three linked intent items: a dedicated PITCH layer (mono generators
  currently decide pitch opaquely), octave as an editing dimension on that
  layer, and a quick-switch layer selector (owner: "possibly based on the
  8x8 matrix pattern we've used elsewhere" — the phrase-view Layers grid,
  `.meta/multipass/visual-review/engine-precompute-lookahead/02b-tracks-layer-perform-nav.png`).
  Rendered at the same production fidelity as 08/09 (D-well grammar: D-pill
  section switcher outside the well, inset-track value selectors inside).
  - **Mono layer set**: Steps · Velocity · Chance · Pitch · Gate.
  - **Slicer layer set**: Slice Index · Velocity · Direction · Note Repeat ·
    Gate · Chance — proves the same mechanism absorbs both track types.
  - **Pitch cell**: scale degree is the dominant glyph (center, large);
    octave is a separate 3-dot band (Low/Mid/High) along the bottom edge,
    with a small corner badge for octaves beyond that immediate band. Dots
    are click targets — octave is shiftable directly on the cell.
  - **Quick-switch**: value-selector mechanism (inset-track family, never
    the section-switcher pill grammar). Closed = a solid accent value-chip
    showing only the current layer. Open = a compact square matrix of layer
    cells (3 cols, sized to the layer count — mono pads one reserved dashed
    stub cell to keep a stable 3x2 shape as future layers land), each
    carrying its own state only (label + a "has content" dot), replacing
    the old cluttered linear layer row.
  - **One grid grammar**: binary (Steps) = solid fill, no glyph; continuous
    magnitude (Velocity/Chance/Gate) = bar rising in an outlined cell;
    discrete value (Pitch degree, Slice Index, Direction, Note Repeat) =
    solid fill + centered glyph — same component family on both track
    types.
  - States: `setPrototypeState("mono:steps")`, `"mono:pitch"`,
    `"mono:switch-open"`, `"slicer:index"`, `"slicer:direction"`,
    `"slicer:switch-open"`. Render:
    ```sh
    node scripts/render-html-prototype-screenshots.mjs \
      docs/roadmap/track-view-ia/prototypes/11-step-layer-system.html \
      docs/roadmap/track-view-ia/prototypes/rendered/11-step-layer-system \
      'mono-steps=setPrototypeState("mono:steps")' \
      'mono-pitch=setPrototypeState("mono:pitch")' \
      'mono-switch-open=setPrototypeState("mono:switch-open")' \
      'slicer-index=setPrototypeState("slicer:index")' \
      'slicer-direction=setPrototypeState("slicer:direction")' \
      'slicer-switch-open=setPrototypeState("slicer:switch-open")'
    ```
  - Copies also live at
    `.meta/multipass/visual-review/feature-track-view-tab-unification/` as
    `proto-11-mono-steps.png`, `proto-11-mono-pitch.png`,
    `proto-11-mono-switch-open.png`, `proto-11-slicer-index.png`,
    `proto-11-slicer-direction.png`, `proto-11-slicer-switch-open.png`.
  - Reviewer annotations (pitch-cell + quick-switch design notes) are a
    marked, dashed-border legend at the bottom of the file — no explainer
    prose lives on the surfaces themselves.
  - Grounded on
    `docs/intents/inbox/20260702-150006-mono-pitch-opacity-pitch-layer.md`,
    `20260702-150007-octave-treatment.md`,
    `20260702-150008-layer-controls-revisit.md`.

### Clip randomize
- `12-clip-randomize.html` — visualizes
  `20260702-150003-clip-randomize-baked.md`: a dice-style Randomize action
  above the pattern selector on the mono-track surface that BAKES step +
  pitch data into the current clip by rules, destructively overwriting it
  (with undo), with rule settings persisted per clip for later re-rolls.
  Built on the locked Variant D tab-well grammar (`08-unified-tab-well-D.html`
  mono surface); only Steps/Clip is on the path under test, Sound/FX/Macros/
  Mixer stay stubs.
  - States: `closed` (dice action button in its own row above the pattern
    row; slot 4 active, never randomized; slot 7 shown with a persisted-dot
    as a per-clip secondary example), `settings` (the rules sheet open,
    reusing the shared StudioModal grammar per `02c-create-track-modal.png`
    — no popover primitive exists in the repo — already mid-audition after
    one simulated Re-Roll: green "Playing" pill, playhead ring, Undo
    enabled), `rolled` (sheet closed; the plain on/off grid is replaced by a
    pitch-labelled grid; persisted-dot now lit on both the dice button and
    pattern slot 4). Render:
    ```sh
    node scripts/render-html-prototype-screenshots.mjs \
      docs/roadmap/track-view-ia/prototypes/12-clip-randomize.html \
      docs/roadmap/track-view-ia/prototypes/rendered/12-clip-randomize \
      'closed=setPrototypeState("closed")' \
      'settings=setPrototypeState("settings")' \
      'rolled=setPrototypeState("rolled")'
    ```
  - Rule controls: Density/Velocity Variance/Gate Variance/Octave
    Center/Span as rotary knobs (canon Rule 6 — no slider thumbs); Scale and
    Root as inset-track solid-thumb chips (D-grammar value-selector rule);
    Octave Range additionally shows a highlighted band over an octave strip
    (center ± span) as the visual tie-in, not a caption.
  - Copies of the three renders also live at
    `.meta/multipass/visual-review/feature-track-view-tab-unification/` as
    `proto-12-closed.png` / `proto-12-settings.png` / `proto-12-rolled.png`.
  - Reviewer-annotation legend at the bottom of the file (dashed border,
    marked "not part of the UI") explains each placement/grammar choice.

### Track Perform: transactional perform session
- `13-track-perform.html` — the transactional Track Perform session
  (`20260702-150009-track-perform-mode.md`, clarified: tweaks ARE recorded as
  events, same model as the scene-crossfader capture, in addition to the
  commit/reset ending) on a mono track in phrase context. Same D-well
  production fidelity as 08/09/11. States:
  - `idle` (a — ENTER): header Perform button, no session chrome.
  - `session` (b — IN SESSION): the session signal is canon-legal
    outline/badge only — the outer surface border flips neutral-grey→track
    accent and a solid "SESSION" badge appears, no container tint anywhere.
    A dedicated red rec-strip ("Recording tweaks as events") states capture
    is live. Macros pane carries the redrawn rotaries (shared 7-o'clock→
    5-o'clock top arc template, one knob shown "live"/hot) plus a Randomize
    action (stubbed, ties to the 12-prototype's dice). Pattern row: resolves
    the `20260702-150002-pattern-row-state-model-tension.md` tension inside a
    session by collapsing played+displayed into one TRACKED slot (solid
    accent fill + second offset outline ring = "live and following"), while
    the pre-session pattern keeps a dashed neutral BASIS-anchor outline for
    Reset. Coordinator: reconcile this tracking visual against the
    10-prototype's once it exists.
  - `exit-fork` (c — EXIT): the Perform control is replaced by an explicit,
    equal-weight two-option fork bar — Reset (outline, returns to the basis
    pattern) vs Save (solid accent, labelled with and highlighting the next
    free destination slot in the pattern row) — never a menu.
  - Off-path stubs: Steps/Clip, Sound, FX, Mixer tabs (Macros is the tab
    under test). Render:
    ```sh
    node scripts/render-html-prototype-screenshots.mjs \
      docs/roadmap/track-view-ia/prototypes/13-track-perform.html \
      docs/roadmap/track-view-ia/prototypes/rendered/13-track-perform \
      'a-enter=setPrototypeState("idle")' \
      'b-in-session=setPrototypeState("session")' \
      'c-exit-fork=setPrototypeState("exit-fork")'
    ```
  - Copies also live at
    `.meta/multipass/visual-review/feature-track-view-tab-unification/` as
    `proto-13-a-enter.png`, `proto-13-b-in-session.png`,
    `proto-13-c-exit-fork.png`.
  - Reviewer annotations (session-signal / tracking / recording / fork design
    notes) are a marked legend at the bottom of the file — no explainer prose
    on the surfaces themselves.

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
