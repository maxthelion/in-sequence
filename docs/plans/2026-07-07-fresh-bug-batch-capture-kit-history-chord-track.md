# Goal: Fresh Bug Batch - Capture Stability, Kit History, and Chord Track

Status: proposed
Created: 2026-07-07
Checkout: `/Users/maxwilliams/dev/in-sequence`

## Objective

Resolve the fresh bug batch from the latest QA/review pass without repeating the
previous failure mode where the plan was marked complete on partial evidence.

This goal covers three different sizes of work:

- a high-priority audio-graph crash found during full visual capture;
- a focused drum-kit capture-history UI correction;
- a larger product feature direction for a dedicated chord track.

The goal is complete only when each item has direct evidence: code/tests for
behavioral and crash fixes, fresh screenshots for UI surfaces, and explicit bug
status updates.

## Source Bug Reports

- `docs/bugs/20260707-211900-qa-capture-track-sound-source-avengine-detach-crash/`
- `docs/bugs/20260707-210132-this-is-better-but-each-history-cell-sho/`
- `docs/bugs/20260707-211517-let-s-make-a-new-version-of-the-poly-tra/`

Related but not directly closed by this plan unless the same fix proves it:

- `docs/bugs/20260629-121929-au-removal-while-playing-crash/`

## Lessons From The Previous Miss

This section is binding.

- Do not treat a row-by-row capture recovery as proof that the full capture
  suite is stable. The crash was found by the monolithic sequence; the
  monolithic sequence must pass.
- Do not mark a UI bug fixed because a control exists in code. Acceptance is
  based on the actual captured screen matching the product intent.
- Do not turn the chord-track request into a cosmetic rename of the current poly
  generator/chord surface. The request is for a track grammar closer to slicer:
  a reusable chord palette above the tabs and step cells that place chords from
  that palette.
- Do not collapse broad product work into a hidden implementation shortcut. If
  the chord track MVP is too large for one builder pass, split it deliberately
  and leave unfinished bugs open.
- Every completed bug gets `Status: RESOLVED <commit>` in its file-backed note
  or report, and database-backed Bug Reporter rows are updated to `fixed` where
  applicable.

## Task 1: Fix The QA Capture AVAudioEngine Detach Crash

### Problem

The full `qa-surface-coverage` run crashed after the track sound-source rows.
The faulting stack is:

```text
SamplePlaybackEngine.removeTrack(trackID:)
MainAudioGraph.disconnectOutput(_:)
MainAudioGraph.removeTrackSendNodes(for:)
AVAudioEngine.detachNode
```

This is not the July 7 phrase-scene tick-path crash. It is a main-thread graph
lifetime problem during sample-track/send-node teardown.

### Requirements

- Keep the audio hard rules intact:
  - no `engine.stop()/start()` topology workaround during playback;
  - no render-thread allocation/locking/file IO;
  - no hard disconnect of sounding paths before ramp-to-silence;
  - graph ownership stays on the control/main graph path, never the tick path.
- Identify the ownership boundary for track send nodes:
  - decide whether `disconnectOutput(_:)` should own send-node teardown for all
    callers, or whether sample-track teardown needs an explicit send-node
    teardown phase;
  - make send-node teardown idempotent and safe across repeated source changes;
  - prevent double detach/dangling fanout ownership when a track changes source
    shape rapidly.
- Add targeted diagnostics or tests around the transition that failed:
  - sample-backed track -> empty/no source;
  - populated sound source -> empty sound source;
  - repeated transition through `19-track-sampler-sound-populated` and
    `19a-track-sound-empty` command states.

### Acceptance

- `scripts/visual-scenarios/qa-surface-coverage.sh` completes as one
  monolithic run with all active rows captured and no crash reports.
- The completed run is absorbed through Bug Reporter and linked in the final
  evidence.
- A focused automated test or harness regression fails on the old unsafe
  teardown shape and passes after the fix.
- `scripts/diagnostics/realtime-path-lint.sh` passes.
- `scripts/diagnostics/runtime-ownership-lint.sh` passes.
- `scripts/visual-scenarios/routing-stress.sh` is run successfully, or the
  blocker is documented with enough detail for a follow-up.
- `docs/bugs/20260707-211900-qa-capture-track-sound-source-avengine-detach-crash/report.md`
  is marked `Status: RESOLVED <commit>`.

## Task 2: Correct Drum-Kit Capture History Cells

### Problem

The current kit capture/history strip is better than before but still misses
the desired grammar:

- each history cell should show the drum parts separated;
- cells should not contain text labels such as ordinal numbers or `1 bar`;
- there should be 16 bars of captures to navigate, not only the currently
  visible small set.

### Requirements

- The capture/history strip presents 16 navigable bar cells.
- Each cell is a miniature drum-part matrix:
  - visible per-part rows are separated;
  - step activity is visible per part;
  - the cell body contains no text;
  - selected/current state is indicated by border/fill, not by text inside the
    cell.
- Length controls remain readable and horizontal.
- `Choose slot` remains part of the same capture workflow.
- The selected capture preview below the strip updates when a history cell is
  selected.
- The design remains close to the track capture/history grammar where that
  grammar is still valid.

### Acceptance

- Fresh screenshot for `29f-drum-kit-capture-save-slot` shows 16 navigable
  capture cells.
- The screenshot shows separated drum-part rows inside each history cell.
- No history cell contains text such as a number or bar length.
- The lower full preview still has readable part labels and no clipped row.
- Any command-channel status needed to prove the selected history bar is exposed
  by `VisualScenarioCommandRunner`.
- The bug report
  `docs/bugs/20260707-210132-this-is-better-but-each-history-cell-sho/note.md`
  is marked `Status: RESOLVED <commit>`.
- The database bug
  `bug_20260707200132_This-is-better.-but-each-history-cell-should` is updated
  to `fixed`.

## Task 3: Specify And Implement A Chord Track MVP

### Problem

The current poly/chord generator surface does not match the requested workflow.
The desired product shape is a dedicated `Chord Track` that borrows the slicer
track grammar:

- a palette/list of chosen chords sits above the tabbed interface;
- a `Chords` tab lets the user choose and edit the palette;
- the step sequencer places chords from the palette onto steps, like slices in
  the slicer sequencer;
- per-step chord parameters such as inversion should become layers instead of
  awkward inline controls.

### Requirements

- Introduce a user-visible `Chord Track` path without breaking existing poly
  melodic tracks.
- The chord palette sits above the tabbed editor and remains visible while
  editing steps.
- Add a `Chords` tab for palette editing:
  - add/remove/select chord slots;
  - edit root/quality/extensions or the existing equivalent model fields;
  - choose a compact preset/progression only if it does not replace direct
    editing.
- The `Steps/Clip` grid places chord-slot references, not full duplicated chord
  definitions, on steps.
- Step layers support chord-appropriate per-step parameters:
  - at minimum chord selection and inversion;
  - include length/voicing/octave only if the existing model can support them
    cleanly in this pass.
- Bake/playback semantics are explicit:
  - live chord-track playback uses the selected chord palette and per-step
    layers;
  - baking produces a playable clip while preserving the chord-track recipe if
    the source mode supports generator/source retention.
- The UI uses the same track editor grammar as other track types:
  - no native black dropdowns;
  - no clipped labels;
  - no text-heavy explanatory surface.

### Acceptance

- A user can add a `Chord Track` from the create-track flow.
- Fresh screenshot coverage includes:
  - chord track `Steps/Clip`;
  - chord track `Chords` tab;
  - at least one chord-layer view, preferably inversion.
- A behavior test proves that assigning chord palette item `N` to a step plays
  the notes from palette item `N`.
- A behavior test proves that changing a palette chord updates playback for
  steps referencing that palette slot.
- A behavior test proves that per-step inversion changes the voiced notes
  without mutating the palette chord.
- Existing poly melodic track tests still pass.
- The bug report
  `docs/bugs/20260707-211517-let-s-make-a-new-version-of-the-poly-tra/note.md`
  is marked `Status: RESOLVED <commit>` only when the dedicated chord-track MVP
  exists; otherwise leave it open and write a follow-up split plan.
- The database bug
  `bug_20260707201517_Let-s-make-a-new-version-of-the-poly-track-w` is updated
  to `fixed` only when the MVP acceptance above is met.

## Verification Checklist

Run these before reporting the goal complete:

- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS'`
- `scripts/diagnostics/realtime-path-lint.sh`
- `scripts/diagnostics/runtime-ownership-lint.sh`
- `scripts/diagnostics/ux-canon-lint.sh`
- `scripts/visual-scenarios/qa-surface-coverage.sh`
- `bug-reporter absorb-captures "$CAPTURE_DIR" --project in-sequence --source qa-surface-coverage`
- `bug-reporter list-bugs --project in-sequence --status open --json`
- `scripts/bug-status.sh --open`

Completion evidence must include:

- commit hash;
- test/lint results;
- gallery URL;
- explicit list of bug IDs marked resolved/fixed;
- explicit list of any related bugs intentionally left open.
