# Overnight Probe Visual Baseline

Date: 2026-05-06

This is a static Peekaboo baseline for the six overnight broad-probe branches.
The first capture attempt is rejected: it captured Finder/open panels rather
than the app surfaces. Those screenshots remain in the lane directories as
evidence of a capture-process failure, not as UX evidence.

Validated evidence:

- Contact sheet: `validated-contact-sheet.png`
- Per-lane captures: `<lane>/validated-window.png`
- Capture status: `<lane>/validated-capture-status.txt`

Validation used:

- launch the probe app build;
- create a new document;
- ask Peekaboo for SequencerAI windows;
- capture the main document window by window id;
- reject captures whose main window is missing, blank, or titled `Open`.

Limitation at capture time: Peekaboo Screen Recording was available, but
Accessibility was not, so this pass captured visible evidence only; it did not
exercise controls or produce a reliable UI element map. Accessibility was later
confirmed granted on 2026-05-06, so future runs should use Peekaboo `see` and
interaction checks rather than treating this limitation as normal.

## Summary

The probes did produce useful holistic shape. The strongest harvest candidates
visually are `audio-input-looping-autoslice` and `track-editor-foundation`,
because they expose a real workflow rather than only diagnostic or placeholder
state. `mixer-routing-and-sends` has important product content, but its routing
model is partly below the fold. `phrase-scene-song-performance` is clear but
too sparse. `performance-overrides-pattern-manipulation` and
`external-control-and-automation` need another UX pass before they should guide
production UI.

The biggest shared issue is that most probes made a credible panel, not a
credible whole workspace. The morning harvest should look for interaction and
model ideas, then consolidate them into a more intentional interactive
wireframe before cherry-picking visual structure wholesale.

## Lane Notes

### Track Editor Foundation

Evidence: `track-editor-foundation/validated-window.png`

Useful shape:

- The history, slot source chain, and step edit panels belong together.
- The "modifier after source" and "transient selection" concepts are visible
  enough to judge.
- The selected-step highlights make the edit target legible.

Criticism:

- The first viewport is over-dense; destination and lower pattern context are
  pushed below the visible fold.
- The source/modifier stack reads like a static status card more than an edit
  surface.
- The chips at the bottom encode important semantics, but they are visually
  secondary and unexplained by the surrounding layout.

Harvest implication: keep the source-chain/history/step-edit relationship, but
redesign the first viewport around one primary edit task and one visible output
target.

### Phrase, Scene, Song Performance

Evidence: `phrase-scene-song-performance/validated-window.png`

Useful shape:

- A combined phrase/scene performance surface is plausible.
- The Scene A/B area communicates live crossfade intent quickly.
- The active phrase row is readable at a glance.

Criticism:

- The center of the workspace is mostly empty, so the surface feels like a
  sketch rather than a performance instrument.
- Phrase, scene, and song controls are adjacent, but the musical flow between
  them is not visible.
- The right rail is doing most of the interesting work, which makes the layout
  feel unbalanced.

Harvest implication: use this as evidence that the lane wants a performance
surface, but do not copy the layout until phrase rows, scene rows, and song
structure are shown together.

### Mixer Routing And Sends

Evidence: `mixer-routing-and-sends/validated-window.png`

Useful shape:

- Track strip plus routing model is the right conceptual pairing.
- Bus/send cards make the route graph tangible.
- Bus solo/sends/master questions are now visible product decisions.

Criticism:

- The top mixer card is mostly empty, while the routing model is partially
  below the fold.
- The main fader card is oversized relative to the information it carries.
- Bus cards are truncated by the viewport, so the key lane idea is hidden at
  the moment of first inspection.

Harvest implication: keep the routing-card concept, but make routing the first
viewport hero for this lane; the fader strip should support it rather than
consume the space.

### Audio Input, Looping, Autoslice

Evidence: `audio-input-looping-autoslice/validated-window.png`

Useful shape:

- This is the strongest visual probe. Input tracks, shared buffer, autoslice,
  and live loop deck form a coherent workflow.
- The waveform gives the lane an immediate source of truth.
- The buffer users panel helps explain why shared capture matters.

Criticism:

- Capture, loop, and autoslice are all visually prominent, so the primary next
  action is not quite obvious.
- The autoslice percentages are technical; they need a musician-facing layer.
- Input monitoring/armed/recording state should be more explicit.

Harvest implication: this lane is ready for deeper behavioral review. It is a
good candidate for the holistic interactive wireframe source of truth.

### Performance Overrides And Pattern Manipulation

Evidence: `performance-overrides-pattern-manipulation/validated-window.png`

Useful shape:

- Momentary/latch override modes and per-track live state are the right ideas.
- The pattern selector plus perform button begins to connect edit and perform
  workflows.

Criticism:

- The surface is too sparse and disabled-looking; it does not yet feel playable.
- Override controls do not show audible or pattern-level consequences.
- Track selection and override panels feel disconnected from the step/pattern
  model.

Harvest implication: keep the transient override model, but use another pass to
show actual performance feedback before merging UI structure.

### External Control And Automation

Evidence: `external-control-and-automation/validated-window.png`

Useful shape:

- Diagnostics, runtime signals, event selection, and issue drafting make a
  coherent agent/control observability surface.
- The log inbox and action buttons suggest a useful review workflow.

Criticism:

- The result reads like an operations dashboard, not yet like a musician's
  control-surface workflow.
- The issue draft is below the fold, even though it is the main conversion from
  observation to action.
- The actionable/suppress controls are small relative to their importance.

Harvest implication: cherry-pick the observability model, but separate
developer diagnostics from performer-facing external control.

## Process Improvement

Visual evidence should be treated as a claim with preconditions, not as a file
existing on disk. A capture pass is only useful if it can prove:

- the intended app is running from the intended branch or worktree;
- the target document or scenario has opened;
- the captured window is the app surface, not a picker, browser, or desktop;
- the screenshot includes the lane-specific UI expected by the probe;
- any missing permission is recorded as a blocker instead of silently degrading
  the review.

For future overnight probes, the worker should write `visual-capture-status:
valid|invalid|blocked` and should not put invalid captures under "UX findings".
Invalid captures should become process findings for the supervisor.
