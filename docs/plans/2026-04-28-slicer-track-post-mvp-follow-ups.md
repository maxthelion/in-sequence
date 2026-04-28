# Slicer Track Post-MVP Follow-Ups

**Split from:** `docs/plans/2026-04-25-slicer-track-mvp.md`
**MVP commit:** `3f27351` (`feat(slicer): add sliced-loop playback destination`)
**Status:** Draft follow-up plan.

## Summary

The slicer MVP made `TrackType.slice` audible and established the core runtime shape:

- `SliceMarker`, `SliceSet`, `SlicerSettings`, and `Project.sliceSetPool`
- `Destination.slicer(sliceSetID:settings:)`
- grid and transient analysis
- `SamplePlaybackEngine.playSlice(...)` with frame-range scheduling and reverse-slice cache
- snapshot/store plumbing for slice sets
- tagged slice events from slice clips/generators
- a basic slicer destination card and waveform editor

This document captures the parts of the original plan that did not land in that MVP, plus the larger features that were explicitly deferred. It should be treated as the backlog for making slicer tracks feel complete rather than as a request to rewrite the foundation.

## Do Not Rebuild

The follow-up work should reuse the MVP's existing architecture:

- Keep `SliceSet` project-scoped and referenced by `Destination.slicer`.
- Keep per-slice values on `SliceMarker`.
- Keep playback on `SamplePlaybackEngine.playSlice(...)`.
- Keep runtime dispatch through `EngineSlicerDispatcher`.
- Keep slice source output as voice tags (`slice-N`, `slice-run-N`).

## MVP Gaps To Finish

### 1. Slice Track From Loop Workflow

The original MVP plan called for an "Add Slice Track from loop" entry point. The shipped MVP has `Add Slice`, an empty slicer destination, and a sample picker inside `SlicerSourceWidget`, but not the one-step loop workflow.

Build:

- A track-create flow that lets the user pick a loop/sample first, then creates a slice track already pointed at a new grid-sliced `SliceSet`.
- A clear empty-state path when no loop-category samples exist.
- Filtering or grouping in the picker so loops are easy to find, while still allowing other sample categories intentionally.
- Optional reuse: if a slice set already exists for the chosen sample, offer to reuse it or create a new one.

Acceptance:

- Add Slice From Loop creates a slice track, creates or selects a `SliceSet`, assigns `Destination.slicer`, and opens the track.
- The first authored slice trigger plays slice 0 / whole sample after the sample is selected.
- Legacy Add Slice still works as an empty destination path.

### 2. Full Slicer Editor Controls

The MVP editor is intentionally lightweight. It supports fixed 16-grid analysis, transient analysis with default sensitivity, basic boundary movement, and marker inspection. The original plan also called for richer controls that did not land.

Build:

- Grid division control, not fixed 16 only.
- Transient sensitivity slider.
- Manual mode entry from the source widget.
- BPM hint and bars fields on the waveform editor.
- Re-slice controls inside the waveform editor.
- Insert marker and delete marker operations.
- Click slice region to select, not only the list.
- Zero-crossing snap for dragged boundaries within a small frame window.
- Drag preview with commit on mouse-up; avoid committing on every drag tick.
- Inspector audition button for the selected slice.
- Stronger marker 0 affordance: visible, selectable, but not movable/deletable.

Acceptance:

- Grid divisions = 8 creates 9 markers including slice 0.
- Transient sensitivity changes marker count on an impulse fixture.
- Insert/delete preserves stable IDs for unaffected markers and normalizes ranges.
- Marker 0 cannot be moved or deleted.
- Boundary movement commits one `mutateSliceSet` action per completed drag.

### 3. True `runFromHere` Bar Semantics

The MVP added `SliceTriggerStepMode.runFromHere`, emits `slice-run-N`, and dispatches a long frame range from that slice to the whole-sample end. It does not yet implement the original "replace the per-step trigs that follow it until the bar boundary" behavior.

Before implementing, resolve the semantic tension in the original plan:

- Option A: `runFromHere` suppresses all later slice triggers on that track until the next bar boundary.
- Option B: `runFromHere` starts a long segment, but a later explicit slice trigger can steal/retrigger the voice.
- Option C: support both with a second per-step mode, for example `runLockedFromHere` and `runUntilRetrigger`.

Recommended V1 follow-up: implement Option A for predictability, then add an explicit retrigger mode later if needed.

Build:

- Runtime-only suppression state keyed by track ID, not stored in the document.
- Suppression clears at the next bar boundary, transport stop, phrase/source change, or destination change.
- Suppression runs after normal phrase/source evaluation but before slicer event enqueue.
- The long segment still uses the same `EngineSlicerDispatcher` resolution path.

Acceptance:

- Step 4 `runFromHere(sliceIndex: 2)` suppresses authored single trigs on steps 5-15.
- Step 0 of the next bar resumes normal trigger behavior.
- Stopping transport clears suppression.
- Non-slicer tracks are unaffected.
- Snapshot/store revisions do not change when suppression state changes.

### 4. UI And Helper Test Coverage

The MVP added strong document/audio/engine coverage, but the original UI/helper test matrix was broader than what landed.

Add tests for:

- Slicer source widget sample selection creates and assigns a slice set.
- Re-slice UI writes the expected marker count and mode.
- Voice mode and gain controls update only `SlicerSettings`.
- Waveform boundary drag normalizes once on completed drag.
- Insert/delete marker behavior.
- Marker 0 immovability.
- Empty sample-library state.

### 5. Documentation Cleanup And Release Tagging

The MVP added `wiki/pages/slicer-tracks.md` and updated project layout / destination docs. The original plan also called for more wiki coverage and a tag.

Build:

- Update `wiki/pages/document-model.md` with `sliceSetPool`.
- Add a short note in `wiki/pages/app-support-layout.md` explaining that slice-set documents are future/cross-project storage, while MVP slice sets live in the project.
- Decide whether to create `v0.0.NN-slicer-track-mvp` from commit `3f27351` or from a later polished follow-up.

## Larger Deferred Features

These were intentionally outside the MVP and should remain separate plans unless one becomes urgent.

### BPM And Loop Tempo Metadata

The MVP stores `bpmHint` and `bars`, but does not provide the full UX or auto-detection path.

Future plan:

- Filename regex, for example `(\d{2,3})\s*bpm`.
- User-editable BPM and bars in the waveform editor.
- Visual drift warning when project BPM and loop metadata disagree.
- Optional onset-envelope autocorrelation / dynamic-programming beat tracker after the filename/user path is useful.

### Pickup Machine And Bus-Tap Sampling

Octatrack-style live recording deserves a dedicated plan.

Future plan:

- `AudioInputHost` with device selection and microphone permission handling.
- Transport-synced record arm / start / stop.
- Circular recording buffers.
- Track-bus and master-bus tap paths.
- Convert a captured buffer into an `AudioSample` and `SliceSet`.

### Slice Auto-Labeling

Future plan:

- Spectral centroid / envelope classifier.
- Tags such as kick, snare, hat, perc, other.
- Manual override remains authoritative.

### Rich Slice Generator

The MVP can emit slice voice tags, but it does not implement the richer generator family from the brainstorm.

Future plan:

- Euclidean over slice tags.
- Markov over tag transitions.
- Random-from-pool and weighted slice choice.
- Compatibility with future `voice-route` and note-repeat performance overlays.

### Live Pad Ratchet / Note Repeat

The MVP supplies the slice-trigger primitive. Live repeat remains performance-overlay work.

Future plan:

- Hold pad to repeat the current slice step at a selected subdivision.
- Repeat should use runtime overlay state, not mutate clips or slice sets.
- Works for clips and generated slice streams.

### Per-Slice Filter And Envelope DSP

The MVP has per-track sample/filter macro compatibility, not per-slice DSP.

Future plan:

- Per-slice amp envelope.
- Per-slice filter/envelope overrides.
- Decide whether these are authored on `SliceMarker` or represented as per-voice runtime modulation.

### Pitch, Rate, And Time Stretch

The MVP stores `SlicerSettings.transpose` but does not resample or time-stretch.

Future plan:

- Playback rate / pitch transpose without stretch.
- Optional time-stretch for BPM-matched loops.
- Clear CPU and quality constraints before choosing an implementation.

### Composite Slice Sets

The MVP's `SliceSet` references one sample.

Future plan:

- Multi-file slice sets for drum-chop kits.
- Per-marker sample reference.
- Migration strategy from one-sample slice sets.

### Sample Locks And Per-Pattern Slice-Set Overrides

The pool-shaped data model enables this, but the engine and UI do not yet read per-step or per-pattern slice-set overrides.

Future plan:

- Parameter-lock shape for overriding `sliceSetID`.
- UI for locking a step to a different loop/slice set.
- Snapshot invalidation rules for locked slice-set references.

## Suggested Execution Order

1. Finish slicer UX controls and the Add Slice From Loop workflow.
2. Resolve and implement true `runFromHere` bar semantics.
3. Add UI/helper tests around the editor and widget.
4. Add BPM/loop metadata UX.
5. Choose one advanced feature: sample locks, pickup-machine recording, rich slice generator, or time-stretch.

## Verification

Run focused tests while iterating, then a full suite before merging:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  test
```

Manual smoke for the follow-up polish:

1. Import or select a loop.
2. Add Slice From Loop.
3. Verify the generated slice set and whole-sample slice 0.
4. Change grid divisions and transient sensitivity.
5. Insert, delete, and drag markers.
6. Use `runFromHere` and verify the chosen bar-suppression semantics.
7. Save, close, reopen, and verify slice metadata persists.
