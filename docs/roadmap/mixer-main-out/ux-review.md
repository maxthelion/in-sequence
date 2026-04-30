---
verdict: accepted
selected_prototype: mixer-main-out-variant-a.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/mixer-main-out-variant-a.html
  - prototypes/mixer-main-out-variant-b.html
feedback_applied: []
---

# Mixer Main Out UX Review — 2026-04-30

## Context

Two layout variants were produced for the Mixer Main Out feature (roadmap item 4).
Variant A places the master out as a fixed right-side column inside the mixer layout.
Variant B places it as a fixed horizontal band across the top of the mixer with track
strips scrolling below. Both variants cover all four user stories: dedicated master out
section, insert effects chain, dBFS metering with clip latch, and scene A/B crossfader
widget.

---

## Checklist Results

| Criterion | A | B |
|---|---|---|
| Single-file, no build steps | Pass | Pass |
| Monochrome base, semantic color only | Pass | Pass |
| Stub regions clearly marked | Pass | Pass |
| Real interactions on primary path | Pass | Pass |
| Fixture data is adversarial / varied | Pass | Pass |
| Same fixture data across compared variants | Pass | Pass |
| Interaction budget stated and verified | Pass | Pass |
| Variants are strategically different, not cosmetic | Pass | Pass |
| Reviewer cannot mistake for production | Pass | Pass |
| Master out visually distinct from track channels | Pass | Pass |
| All four user stories reachable in prototype | Pass | Pass |
| Vertical fader with usable throw | Pass | Fail |
| Vertical meter bars (conventional DAW orientation) | Pass | Fail |
| Clip notice path in ≤2 interactions | Pass | Pass |
| Insert bypass and reorder operable | Pass | Pass |
| Crossfader state reflects scene badges | Pass | Pass |

Both variants pass the core structure criteria. Variant A is clearly stronger on fader
precision and metering legibility. Variant B fails on two criteria the prototype author
explicitly flagged: horizontal fader throw and horizontal meter readability.

---

## Per-Variant Assessment

### Variant A — Right-Side Master Column

The master out column occupies the rightmost fixed 190 px of the mixer layout with the
track strips scrolling to its left. The master column is separated by a 2 px border and
a dark header bar ("MASTER OUT"), which is immediately legible as a separate section.

**What works:**

- Layout is consistent with Logic Pro, Ableton Live, and Pro Tools conventions. A user
  migrating from any major DAW will recognize the pattern without reading a label.
- The vertical fader (22 px wide, 160 px tall) has adequate throw for master bus work.
  The dB readout below the handle gives a numeric confirmation during drag. The scale
  ticks at +6, 0, −6, −12, −18, −24, −36, −∞ are correctly placed and labeled. The
  handle has a line scribe that confirms the Unity (0 dB) reference position visually.
- The meter section uses a dual vertical bar (L + R) with green / amber / red color
  zones and a peak-hold tick. The clip latch ("CLIP") is red and prominent; the "CLR"
  button appears alongside the indicator only when a clip has occurred. The 2-interaction
  clip path (see CLIP indicator → click CLR) is verified.
- The insert chain renders three slots with working bypass toggle (filled circle =
  enabled, hollow circle = bypassed), up/down reorder arrows with correct disabled state
  at first and last slots, and a remove button with hover-state visual warning (red tint).
  Two empty slots with dashed borders signal available capacity without cluttering the
  active chain.
- The section label "Inserts (Scene: Intro Loop)" makes the scene-scoped nature of the
  insert chain explicit. This is the correct statement of the current model and avoids a
  false impression that the inserts are global.
- The crossfader widget correctly shows A and B scene name badges; the active badge
  darkens when the crossfader is within 30 % of either end. Five state fixtures
  (idle, mid-signal, near-clip, clipped, xf-b) are all reachable via buttons and each
  transitions the meter and crossfader consistently.
- The fader and meter are in adjacent but vertically separated zones within the column.
  The signal-chain reading order (top to bottom: crossfader → inserts → fader → meter)
  maps directly to the audio graph topology: scene blend → master chain → gain → output
  level.
- Model gaps and extraction requirements are explicitly annotated below the prototype,
  making the prerequisites visible to an architecture reviewer without hiding them in
  prose.

**What fails or is limited:**

- The master column is 190 px wide at a fixed workspace width of 960 px. At narrower
  viewport widths (e.g., split-screen on iPad), the column could crowd the track strip
  area. This is a layout risk to flag in architecture rather than a prototype defect, but
  it should be noted.
- The fader handle starts at 66 % from the bottom, which places it at approximately
  −12 dB in the prototype scale. The "0.0 dB" readout below the handle does not update
  in the prototype (the fader is not draggable in the HTML). This is acceptable for a
  Balsamiq-style prototype — the state fixtures cover the states that matter — but the
  spec must clarify whether "0 dB" is the default fader position and where Unity is on
  the scale.
- The insert reorder arrows (▲/▼) are 14 × 11 px each. This is small for precise touch
  interaction. Arrow-button reorder is consistent with what already exists in
  `ScenesWorkspaceView`, but the spec should consider whether drag reorder is in scope.
- There is no "no inserts" empty state shown for the active scene. If a scene has no
  inserts yet, the section should render the two empty-slot dashes with a hint label or
  an "Add your first insert" affordance. This is a missing state to address in the spec.
- The prototype shows the insert chain labeled "Inserts (Scene: Intro Loop)" but does
  not show what happens when the crossfader is mid-blend (i.e., two scenes active). The
  spec must clarify: does the master out panel show the inserts of the A scene, the B
  scene, or both? The existing model is per-scene, so the crossfader state may need to
  influence which scene's inserts are displayed.

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Dedicated master-out section in the mixer | Covered: column is visually distinct, clearly labeled |
| 2. Insert effects on the master out channel | Covered: add, bypass, reorder, remove all shown; add-picker is stubbed |
| 3. dBFS metering with clip indication | Covered: calibrated meter with L/R bars, clip latch, CLR action |
| 4. Scene A/B crossfader in the master out section | Covered: crossfader widget with scene names and active badge |

---

### Variant B — Top Master Band

The master out spans the full width of the mixer workspace as a horizontal band above
the track strips. The band is subdivided into four horizontal sub-panels: crossfader
(190 px), insert chain (flex, fills remaining width), fader (120 px), meter (140 px).

**What works:**

- The band is immediately visible on load — it is the first thing a user sees when
  opening the mixer workspace, which aids discoverability for new users.
- The horizontal insert chain reads left-to-right as a signal flow diagram, which is
  an intuitive ordering. The sub-panel layout with crossfader → inserts → fader → meter
  matches the audio topology.
- The clip latch mechanism, insert bypass toggle, and crossfader badge behavior are
  identical to Variant A and work correctly.
- The prototype author annotates the layout concerns explicitly and self-critically. The
  two known weaknesses are visible before the reviewer reaches them independently.

**What fails or is limited:**

- The horizontal fader (a 22 px tall, full-width-minus-static-panels bar) has far shorter
  throw than Variant A's vertical fader for the same 120 px sub-panel allocation. Master
  bus fader precision is important — a 1 dB adjustment on a busy mix requires fine drag
  distance. Horizontal throw at this width is insufficient for production use. The
  prototype author flags this in both the HTML comment and the annotation block.
- Horizontal meter bars are harder to read at a glance than vertical bars. The L and R
  bars are only 14 px tall. The color zones (green / amber / red) are distinguishable in
  the prototype, but at real screen DPI and in peripheral vision the horizontal format is
  a significant regression from conventional metering. Users trained on any DAW will
  reach for a vertical meter.
- The top band compresses the vertical space available for track strips. The track area
  receives whatever remains below the master band. On a 560 px workspace, the band is
  approximately 120 px tall, leaving ~400 px for track strips. With a tall master band
  the track area could become cramped, particularly on iPad.
- The horizontal fader note in the prototype ("Note: horizontal fader gives shorter throw
  than vertical (see Variant A)") is an admission by the prototype itself that this
  variant is weaker for the primary Story 1 interaction goal.
- The insert empty slot rendering ("—" only, no width label) is less clear than Variant
  A's "— empty slot —" label. Minor, but relevant to the empty-state concern.

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Dedicated master-out section in the mixer | Covered: band is distinct, but fader precision is degraded |
| 2. Insert effects on the master out channel | Covered: same functionality as Variant A |
| 3. dBFS metering with clip indication | Partial: metering is functional but horizontal orientation is a usability regression |
| 4. Scene A/B crossfader in the master out section | Covered: same as Variant A |

---

## Head-to-Head: Variant A vs Variant B

| Dimension | A | B |
|---|---|---|
| Master section discoverability for new users | Requires scanning right edge | Immediately top-of-screen |
| Fader precision (throw length) | Good (vertical, 160 px) | Weak (horizontal, ~80–100 px effective) |
| Meter legibility (conventional DAW convention) | Good (vertical bars) | Weak (horizontal bars) |
| Signal-chain reading order | Top-to-bottom in column | Left-to-right in band |
| Vertical space for track strips | Full height | Compressed by ~120 px |
| Consistency with DAW conventions | High | Low |
| Insert chain overflow at 6+ effects | Vertical scroll in column | Horizontal scroll in band (more natural) |
| Width at narrow viewports | Column crowds track area | Band does not change with viewport width |

The discoverability advantage of Variant B (master section always visible, full width)
does not compensate for its fader and metering regressions. A performer doing gain staging
or clip recovery on the master bus needs high-precision controls. Variant A preserves
both, at the cost of requiring the user to scroll to the right edge. That cost is low:
the master column is fixed and visible whenever the mixer workspace is open.

Horizontal insert chain reading (Variant B) is marginally better for signal-flow
comprehension, but the existing architecture already uses a top-to-bottom insert list in
`ScenesWorkspaceView`, so Variant A's vertical insert list is consistent with the project
convention.

---

## Recommendation

**Select Variant A (right-side master column) as the direction for architecture and spec.**

Reasons:

1. Vertical fader with adequate throw is essential for master bus gain staging. Variant B
   cannot support this without a substantially wider right-panel allocation, at which
   point it becomes Variant A rotated.
2. Vertical metering is the standard across all major DAWs. Users will look for a
   vertical meter. Variant B's horizontal bars are a readability regression.
3. The right-column layout is consistent with DAW convention and directly matches the
   reference screenshot in `artifacts.md` (the hardware mixer shows a right-side "MASTER
   MIX" panel with vertical output meters).
4. The signal-chain reading order (crossfader → inserts → fader → meter, top to bottom)
   matches the audio graph topology: scene blend → master chain → output gain → output
   level. This is correct and learnable.
5. The track strip area retains its full vertical height, avoiding layout pressure on
   iPad or split-screen.

**Elements to carry forward from Variant A into the spec:**

- Right-side fixed column separated by a 2 px border and dark header row.
- Top-to-bottom zone order: crossfader → inserts → fader → meter.
- Section label "Inserts (Scene: \<active scene name\>)" to make scope explicit.
- Insert slot: bypass toggle (filled/hollow), name, up/down arrows, remove button.
- Clip latch: red "CLIP" indicator, appears alongside "CLR" button only when latched.
- dBFS meter: L + R vertical bars, green/amber/red zones, peak-hold tick.
- Crossfader: A/B badges darken at 30 % proximity, scene names truncate with ellipsis.

**Open questions to resolve before or during architecture:**

1. **Active scene inserts during mid-blend.** When the crossfader is between A and B,
   which scene's insert chain does the master out panel display? Options: always the A
   scene, always the scene with higher crossfader weight, or show both with a separator.
   This must be a product decision before spec because it affects which model field the
   view binds to.
2. **Master fader scope (per-scene vs global).** `MasterBusScene.outputGain` exists but
   is clobbered to 1.0 by `normalized()` (MasterBus.swift:301). The architecture pass
   must decide whether the master fader should be a new global `MasterBusState.masterOutputGain`
   field (applied after the A/B crossfade) or a per-scene field that is no longer
   normalized away. Existing-state section 8, question 1 captures this.
3. **Default fader position.** The prototype shows the fader handle at ~66 % (visually
   near −12 dB) but the readout says "0.0 dB." The spec must define where Unity (0 dB)
   sits on the fader scale and what the default fader position is at document creation.
4. **Empty insert state.** The spec must define the label or affordance shown when a
   scene's insert chain is empty. The prototype shows two dashed-border empty-slot rows;
   the spec should confirm this or choose a different empty-state pattern.
5. **Narrow viewport behavior.** At iPad split-screen widths (~540–700 pt), the 190 px
   master column plus the minimum-width track strips may not fit. The spec should define
   a minimum workspace width or a collapse behavior for the master column.
6. **Clip indicator reset mechanics.** User story 3 says the latch clears "until manually
   cleared." Existing-state section 8, question 4 asks whether automatic reset after a
   hold period is also required. This must be resolved before spec.

---

## Next Action

Advance to `write-architecture`. Variant A is the selected direction. The six open
questions above are inputs for the architecture stage; questions 1, 2, and 6 may also
require user clarification before the spec is final.
