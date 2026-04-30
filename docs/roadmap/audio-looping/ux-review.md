---
verdict: accepted
selected_prototype: prototypes/looping-page-primary.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/looping-page-primary.html
feedback_applied: []
---

# Audio Looping UX Review — 2026-04-30

## Context

Single prototype covers all five user stories (open page, arm, global record
trigger, playback toggle, clear loop). This is a first-pass review with no
prior feedback files. The `input-audio` ux-review (accepted, 2026-04-30) is
used as a cohesion reference: that feature owns the per-track audio model this
page consumes.

---

## Checklist Results

| Criterion | looping-page-primary |
|---|---|
| Single-file, no build steps | Pass |
| Monochrome base, semantic color only | Pass |
| Stub regions clearly marked | Pass |
| Real interactions on primary path | Pass |
| Fixture data is adversarial / varied | Pass (long unicode name, long descriptor, short name "FX", long compound name) |
| Interaction budget stated and verified | Pass |
| Reviewer cannot mistake for production | Pass |
| All required states reachable | Pass (6 presets + interactive) |
| Empty / error states present | Partial (empty state present; no "no loop-capable tracks" empty state) |
| Reversibility / cancel path present | Pass (disarm, clear-confirm cancel, stop recording) |
| Progressive disclosure respected | Pass |
| Primary goal confirmed within stated budget | Pass |
| Open questions surfaced in prototype | Pass (annotation panel, inline annotation tags) |

---

## Per-Prototype Assessment

### looping-page-primary.html

**Primary paths tested:**
1. Story 1 (open the page): sidebar "Looping" entry visible and selected; other
   sections are correctly stubbed.
2. Story 2 (arm a track): tap Arm button on any empty track → card turns red,
   label reads "Armed", arm button fills red. Tap again to disarm. Single
   interaction, reversible.
3. Story 3 (global record trigger): arm one or more tracks, tap "Record All
   Armed" → countdown fill animation → all armed tracks transition to
   "Recording" with pulsing red border → auto-stop transitions them to
   "Has Loop". Manual stop also works. The bar-boundary quantize concept is
   communicated by the countdown bar, with an annotation referencing
   `TickClock.tickIndex % stepsPerBar`.
4. Story 4 (playback toggle): tap Play on a track with a loop → state becomes
   "Playing", button label changes to "Mute", card border turns blue. Tap again
   to return to silent. Single interaction, correctly labelled.
5. Story 5 (clear a loop): tap Clear → inline confirm overlay → tap "Clear"
   confirms; "Cancel" dismisses without change. Two-interaction budget met.

**What works:**

- State machine is complete and coherent. All six states (empty, armed,
  recording, has-loop, playing, counting-in) are visually distinct. Border
  color, card background tint, state label, and button states all update
  consistently. A reviewer can verify every story goal without reading
  annotations.
- The card layout (name column | waveform region | controls column) is clean
  and scales to all four adversarial fixture tracks without overflow. Long names
  truncate with ellipsis; short names ("FX") fill the name column without
  visual problems. Unicode character in "Kick & Sub Layér" renders correctly.
- Global record bar is visually separated from per-track cards. The "Record All
  Armed" button uses a red outline while idle and fills red when recording,
  making it visually distinct from the per-track arm buttons (which are red
  filled when armed). The distinction is sufficient to prevent accidental
  activation.
- The countdown bar during counting-in gives the performer feedback that a
  bar boundary is approaching. This is the correct interaction for a
  quantized-record pattern and is coherent with the input-audio prototype's
  ARM → countdown concept.
- Play/Mute toggle correctly reuses the toggleTrackMute primitive concept.
  The annotation tag makes the implementation assumption explicit, which is the
  right thing to surface before architecture.
- Clear confirm overlay is minimal (single-line inline panel, not a modal
  dialog), which respects the performance-surface goal. It does not break the
  spatial relationship between the trigger and the confirmation.
- Waveform region is correctly stubbed with dashed borders. The static SVG
  bars for tracks that "have a loop" are clearly placeholder; the annotation
  explicitly marks them as stubs.
- The annotation panel at the bottom catalogues all code-level gaps (new
  WorkspaceSection case, missing arm state, disabled TransportBar button, no
  clearLoop() mutation, no loop-capable TrackType). This directly supports the
  architecture and spec stages.
- Cohesion with input-audio: the prototype correctly positions this page as a
  consumer of the Input Audio track model. No per-track audio settings or
  record-buffer controls appear here (those live in the input-audio track
  workspace). The looping page is a macro performance surface only, which
  matches the user-story scope boundary.

**What is limited or missing:**

- There is no empty-page state for the case where no tracks are loop-capable.
  The user stories say the page shows "only tracks capable of looping." If no
  tracks have an audio input assigned, the page should show a clear empty state
  (e.g., "No loop-capable tracks — assign an audio input in the Tracks view").
  This is a meaningful gap for a new-session or fresh-install scenario. Spec
  must cover it.
- Arming a track that already has a loop is not prototyped. In the current
  interaction model, the Arm button only works when a track is in the "empty"
  state. What happens if a performer wants to re-record over an existing loop?
  The prototype silently ignores arm taps on has-loop or playing tracks. The
  spec must decide: (a) disallow re-arm until the loop is cleared, (b) allow
  re-arm and overwrite when recording completes, or (c) require an explicit
  clear before re-arm. This decision has implications for the "re-record" live
  performance workflow.
- The global record bar has no "stop recording early" affordance that is
  visually prominent. The button changes to "Stop Recording" while active, but
  it is the same size and position as the idle trigger button. In a live
  performance, the performer may want a larger or more distinctly positioned
  stop control. Minor; acceptable for this prototype fidelity but worth noting
  for spec.
- There is no per-track loop length display. The input-audio prototype (Story 3)
  lets the user choose a bar length (1/2/4/8 bars) before arming. The
  looping-page prototype does not expose or inherit this value. A track in the
  "armed" state could have any loop length. If the looping page is purely a
  consumer of the Input Audio model (where bar length is set on the track's
  own workspace page), this is fine — but the spec must confirm that bar length
  is visible on the track card or communicated through the Input Audio track page
  before the performer visits this surface.
- The waveform stub does not differentiate between a track in "has-loop" vs.
  "playing" state visually in the waveform region (only the card border color
  and button state change). For a dark-stage performance scenario the card
  border is small. A spec-level decision: should the waveform region itself
  animate or highlight when a loop is actively playing?
- There is no visual indication when a recording completes that the result was
  captured successfully versus silently failed. The transition from recording →
  has-loop is automatic (simulated in prototype), but if the engine fails to
  capture audio, the performer would have no way to know. Spec should define
  an error state for failed capture.

---

## Cohesion with Input Audio

The input-audio review accepted prototype 02 (track workspace page), which
handles per-track arm, record, bar-length selection, and the input/loop mode
toggle. The audio-looping page reviewed here is a separate performance surface
that aggregates across multiple tracks.

The boundary is coherent:

- Input Audio owns: track creation, hardware input assignment, per-track bar
  length, per-track arm → record → loop lifecycle, input/loop mode toggle at
  the single-track level.
- Audio Looping owns: cross-track arm (Story 2), global simultaneous record
  trigger (Story 3), per-track loop play/mute from the performance view
  (Story 4), loop clear from the performance view (Story 5).

One tension worth noting: the input-audio prototype's ARM button is on the
single-track workspace page; the audio-looping page also has a per-track Arm
button. These are two different surfaces arming the same underlying state.
Architecture must define whether arm state is owned by the Input Audio track
model (and this page just reflects it) or whether the looping page sets its own
parallel arm state. The existing-state report recommends session-level transient
state, which is consistent with either reading, but the canonical source must be
one surface, not both.

---

## Open Questions for Architecture

1. **Empty page when no loop-capable tracks exist.** What does the looping page
   show when no tracks have an audio input assigned? Spec must include this
   empty state and define the navigation hint.

2. **Re-arm over existing loop.** Should the Arm button be available on a track
   that already has a loop? If yes, does recording overwrite the existing loop
   (same question as input-audio open Q8: overdub vs. destructive replace)?

3. **Arm state ownership.** Is the per-track arm state owned by the Input Audio
   track model (and reflected in both the track workspace and the looping page),
   or is it a separate looping-page-only concept? The architecture must pick one
   canonical location.

4. **Bar length visibility on looping page.** Does the loop length configured
   in the input-audio track workspace appear on the track card on this page, or
   is it invisible to the performer while on the looping surface?

5. **Loop-playback vs. mute primitive.** The prototype assumes the play/mute
   toggle maps to `toggleTrackMute`. Architecture must confirm this is correct
   and does not silence the track's step-sequencer MIDI output alongside the
   loop audio.

6. **Recording failure state.** What does the page show if a recording attempt
   fails (e.g., no input signal, engine error)? Currently not prototyped.

---

## Recommendation

**Accept the prototype and advance to `write-architecture`.**

The single prototype covers all five user stories end-to-end at appropriate
prototype fidelity. The primary interaction paths are implemented and
verifiable. State transitions are visually unambiguous. The stub treatment and
annotation strategy are correct.

The missing states (no-loop-capable-tracks empty state, re-arm over existing
loop) and the arm-state ownership question are architecture and spec concerns,
not prototype failures. They should be captured in `open-questions.md` and
resolved before spec is written.

**Key inputs for the architecture stage:**

- Arm state must have a single canonical owner (Input Audio track model vs.
  looping-page session state). This decision affects both features.
- The play/mute toggle's mapping to `toggleTrackMute` must be validated against
  the Input Audio track model's output routing before spec.
- The looping page's WorkspaceSection case, sidebar entry, and workspace view
  switch arm are straightforward to add (well-precedented pattern per
  existing-state), but they cannot render meaningful content until Input Audio
  delivers the loop-capable TrackType and per-track arm/record model.
- The looping page should be specced in dependency order: first confirm Input
  Audio's architecture is accepted, then write this feature's spec so it can
  reference the stable track model.
