# Resolution: tracks perform cells too busy — whole cell should be the toggle

Date: 2026-06-10

## What changed

**Note-repeat (and fill) perform cards are now a single whole-cell toggle.**
`TrackPerformRuntimeLayerControl` lost everything that wasn't the toggle:

- the per-cell interval picker (1/16 / 1/32 / 1/64 chips) is gone — the rate
  comes from the layer header selection ("NOTE REPEAT – 1/8"), which is now
  written to the track on engagement so the engine captures it;
- the SEL / BASE / MOM-LATCH badges are gone (they duplicated the header);
- the card body is the entire trigger surface (momentary hold or latch
  click, following the global MOM/LATCH control — note repeat previously
  ignored LATCH and was hardwired momentary).

**On = values written, off = values reset.** While engaged, the cell shows
the captured step and rate ("STEP 5 · 1/8") straight from the engine
runtime snapshot (`engagedAtTickIndex` / `capturedStep` / `interval`);
releasing clears the runtime and the cell returns to READY.

**"Note repeat 1/8" is now real.** `NoteRepeatInterval` gained `1/4` and
`1/8` (the engine fires on every 4th/2nd step via a stride counted from the
engagement tick). The layer's variant list now mirrors the engine-backed
intervals exactly — the phantom Trip/Roll/Hold variants (never implemented)
are gone from the selector.

**Phrase page instance** (the "probably other instances" hunch): the
perform-layer placeholder cells repeated the full layer title plus a
"Selection only" sentence in every cell; they now show only the layer icon
and the cell's own phrase/track identity. The remaining phrase-matrix cell
pills ("SINGLE" + "Pattern slot" in every cell) are tracked as QA review
item P1.10 in `docs/bugs/2026-06-10-qa-surface-review.md`.

## Files

- `Sources/Document/StepSequenceTrack.swift` — NoteRepeatInterval 1/4, 1/8 + stride
- `Sources/Engine/EngineController.swift` — stride scheduling in scheduleActiveNoteRepeats
- `Sources/UI/TrackPerformSelectionState.swift` — variants mirror NoteRepeatInterval
- `Sources/UI/TracksMatrixView.swift` — whole-cell toggle, captured-step readout,
  latch support, header-variant → engagement interval
- `Sources/UI/PhraseWorkspaceView.swift` — placeholder cell de-noised

## Tests

- `test_noteRepeatSlowIntervalsFireOnStrideStepsOnly` (1/8 fires ticks 1,3,5;
  1/4 fires 1,5 after engagement)
- variant-label and allCases assertions updated to the new interval set
