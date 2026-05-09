---
created: 2026-05-03
stories_covered: [1, 2, 3, 4]
architecture_approved: true
architecture_review: architecture-review.md
prototype_approval: prototype-approval.md
---

# Mixer Main Out — Spec

Sources: `user-stories.md`, `existing-state.md`, `ux-review.md`, `prototype-approval.md`,
`decisions.md`, `architecture.md`, `architecture-review.md`, and the accepted 2026-05-09
product-owner correction.

---

## 1. Scope and Non-Goals

This spec covers all four approved user stories for Mixer Main Out:

- Story 1: dedicated master-out section in the mixer
- Story 2: insert effects on the master out
- Story 3: dBFS metering with clip indication
- Story 4: scene A / B crossfader in the master out section

### Explicitly out of scope

- Per-scene master output gain. V1 is one global master output fader only.
- Editing Scene A or Scene B insert chains from Master Out. Scene insert editing remains
  available in the existing scene workflows, but this mixer section owns only the post-blend
  master-bus insert chain.
- Auto-clearing clip indication. The latch clears only on explicit user action.
- Reset / Save Blend / Save to Scene controls in the mixer master column.
- New effect types, new AudioUnit hosting rules, or mixer-busses redesign.
- A second visual prototype pass unless later feedback invalidates the approved lane.

---

## 2. Product Direction

The approved direction is Variant A from `prototype-approval.md`: a fixed right-side
master column inside the mixer workspace.

The key product decisions are locked:

- The master fader is one global final-output control applied after the A/B blend.
- The insert panel edits the post-blend `MasterBusState.masterInserts` chain.
- The clip indicator latches until the user presses `CLR`.

This feature is a conservative DAW-style extension of the current master-bus path, not a
rewrite of mixer routing.

---

## 3. What Changes

### 3.1 Persisted document model

Add `masterOutputGain: Double` to `MasterBusState`.

- Default value for new documents: `1.0`
- Semantic meaning: `1.0 == 0 dB` (unity)
- Valid range: `0...2`
- Backward compatibility: older documents that do not encode the field decode to `1.0`

`MasterBusScene.outputGain` remains unused for this feature and must not be repurposed as
the master fader.

### 3.2 Audio graph

The global master gain is applied on `finalOutputMixer.outputVolume`.

This keeps the implementation narrow and keeps the metering tap and audible gain on the
same node. The feature must not introduce a second competing master-gain path elsewhere in
the graph.

### 3.3 Runtime metering state

Add a transient `MasterMeterPublisher`-style runtime owner for:

- left and right peak level
- left and right peak-hold marker position
- clip-latched state

These values are session-only and must not be written into the document model.

### 3.4 Mixer UI

The mixer gains a dedicated master-out column on the right edge. It contains, top to
bottom:

1. Scene A/B crossfader section
2. Post-blend master insert chain section
3. Combined global master fader and output meter section
4. Clip indicator and manual clear status

The existing Scene Perform crossfader widget is extracted into a reusable shared view so
both call sites render the same live state.

---

## 4. Behaviour

### 4.1 Story 1 — Dedicated master-out section

At workspace widths `>= 540 pt`, the mixer renders a fixed-width right column for Master
Out.

- Width: `190 pt`
- Visual treatment: distinct header and section separators matching Variant A
- Section order: crossfader, inserts, fader, meter

The master fader is global and post-blend. Moving it changes only final output level; it
does not alter individual track levels, bus levels, or scene crossfade coefficients.

The fader scale is:

- maximum: `+6 dB`
- unity marker: `0 dB`
- lower labels: `-6`, `-12`, `-18`, `-24`, `-36`, `-∞`
- default position for new documents: `0 dB`

`0 dB` must sit approximately `75–80%` up the fader throw, matching the approved prototype
and standard DAW convention.

### 4.2 Narrow-width behaviour

At workspace widths `< 540 pt`, the full 190 pt column collapses to a `44 pt` compact
strip pinned to the mixer edge.

The compact strip shows:

- a master-out label or icon
- clip-latched state when active
- a narrow live meter
- an expand affordance

Tapping or clicking the strip opens a temporary right-edge overlay containing the full
master-out controls. The compact strip does not show the insert chain or full fader
directly.

This is new behaviour. It should be specified explicitly rather than treated as inherited
from an existing mixer collapse pattern.

### 4.3 Story 2 — Insert effects on the master out

Master Out edits one post-blend master-bus insert chain stored on
`MasterBusState.masterInserts`.

Signal order is:

- Scene A/B branches
- Scene A/B crossfade blend
- `MasterBusState.masterInserts`
- final output gain and metering

The section label should present final-output ownership explicitly, for example:

`Final chain`

Supporting copy may identify placement as:

`After Scene A/B mix`

The section supports the same insert operations as other insert chains:

- add insert
- bypass / enable insert
- reorder insert
- remove insert

The section must not display or mutate `MasterBusScene.inserts`, must not switch chain
contents as the crossfader moves, and must not expose Scene A/B insert-edit affordances.
Scene A/B inserts remain editable from the existing scene-oriented surfaces.

When the master chain has fewer than two inserts, render dashed empty rows labeled:

`— empty slot —`

Those rows are affordances only; they do not imply hidden extra routing state.

### 4.4 Story 3 — Metering and clip indication

The master meter is a dual vertical L/R peak meter measured from the same post-blend,
post-insert, post-master-fader signal the user hears.

Meter requirements:

- source node: `finalOutputMixer`
- tap lifecycle is coupled to engine rebuilds
- displayed scale includes `0`, `-6`, `-12`, `-18`, `-24`, `-36`, and `-∞`
- color zones: green, amber, red
- peak-hold marker on each channel
- clip latch triggers when either channel exceeds `0 dBFS`

The meter must update smoothly during playback. Implementation may choose the exact publish
cadence, but the visible update rate must not feel stalled or flickery and should not drop
below roughly 30 Hz while audio is active.

Clip behaviour:

- `CLIP` remains latched until the user presses `CLR`
- `CLR` is only shown when the latch is active
- there is no auto-clear timer in v1

Peak-hold marker behaviour:

- fast attack from the audio callback
- short visual hold before release
- release tuning is implementation-level, but should feel DAW-like rather than animated

### 4.5 Story 4 — Scene A/B crossfader in the master-out section

The master column embeds the same live crossfader state used by Scene Perform.

- Scene labels show the current A-slot and B-slot scene names
- dragging the crossfader writes through the existing live overlay path
- the widget must not own a second local copy of crossfader state

The master-column crossfader and the Scene Perform crossfader are two views onto the same
underlying live value. Changing one updates the other immediately.

The master column does not add Reset, Save Blend, or Save to Scene actions.

---

## 5. Data and Ownership

### 5.1 Persisted

`Project.masterBus` remains the single persisted owner of authored master-bus state.

New persisted field:

| Field | Owner | Meaning |
|---|---|---|
| `masterOutputGain` | `MasterBusState` | Global final-output gain, post-blend |

Existing persisted fields reused by this feature:

| Field | Owner | Used for |
|---|---|---|
| `masterInserts` | `MasterBusState` | Post-blend master-bus insert chain |
| `abSelection.crossfader` | `MasterBusABSelection` | Authored baseline crossfader position |

### 5.2 Transient

The following remain runtime-only:

| Value | Owner |
|---|---|
| live crossfader override | `masterBusPerformanceOverlay` |
| meter peak values | `MasterMeterPublisher` |
| peak-hold markers | `MasterMeterPublisher` |
| clip-latched state | `MasterMeterPublisher` |
| compact-strip expanded/collapsed UI state | view-local presentation state |

No meter value or clip state is persisted.

---

## 6. Implementation Constraints

### 6.1 Audio-thread and graph rules

- Meter tap callbacks run off the main thread.
- Observable/UI publication from tap data must dispatch to the main thread.
- Audio-graph mutations continue to go through the existing `performOnMain` discipline.
- Any rebuild of the post-blend master insert chain must remove and reinstall the meter tap so
  metering does not silently stop after insert edits.

### 6.2 Backward compatibility

Adding `masterOutputGain` is a document-model change.

The implementation must include round-trip coverage proving:

- old documents decode with `masterOutputGain == 1.0`
- new documents persist the field
- existing master-bus data continues to round-trip unchanged

### 6.3 Shared component extraction

The current Scene Perform crossfader must be extracted into a reusable component or shared
helper. The build must not leave two diverging crossfader UIs with different state paths or
behaviour.

---

## 7. Acceptance Criteria

### Story 1

- Opening Mixer shows a visually distinct Master Out section at normal widths.
- Moving the master fader changes final output loudness without changing individual channel
  faders.
- New documents open with the master fader at `0 dB`.
- The narrow-width compact-strip fallback activates below `540 pt`.

### Story 2

- The insert section shows the post-blend `MasterBusState.masterInserts` chain and labels it
  as final-output processing.
- Add, bypass, reorder, and remove mutate `MasterBusState.masterInserts`.
- An empty chain shows two dashed `— empty slot —` rows.
- The feature does not edit Scene A/B insert chains from Master Out.

### Story 3

- Playback shows live L/R meter movement in the master column.
- Exceeding `0 dBFS` on either channel latches `CLIP`.
- `CLIP` remains latched until the user presses `CLR`.
- Metering continues to work after insert-chain edits that rebuild the graph.

### Story 4

- The mixer master-column crossfader and Scene Perform crossfader stay in sync.
- Dragging either control updates the same live audio blend.
- Scene A/B labels in the master column reflect the current slot assignments.
- No Reset / Save Blend / Save to Scene actions appear in the master column.

---

## 8. Non-Goals and Dependencies

- This spec does not resolve mixer-busses item 5 into a general bus-routing redesign.
- If mixer-busses later changes how ordinary buses or scene inserts are organized, that later
  feature must preserve or explicitly migrate this post-blend Master Out chain.
- This spec does not introduce new effect types, new metering preferences, or alternate
  clip-reset policies.

---

## 9. Open Questions

None. The remaining architecture choices were resolved here:

- global master fader uses `masterOutputGain`
- unity is `1.0` / `0 dB`
- empty master insert state uses dashed rows
- narrow-width behaviour uses the compact strip below `540 pt`
