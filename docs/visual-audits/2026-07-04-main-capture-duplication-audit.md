# Main capture duplication audit - 2026-07-04

Audit target:

- Local set: `.meta/multipass/visual-review/main/`
- Manifest: `.meta/multipass/visual-review/manifests/9062180d966cc94893315d9dd49d1facba5a2579.json`
- Row count: 89 PNGs

## Summary

The current `main` capture set is not trustworthy as a complete UI evidence set.
The first-six stale-paint issue was fixed, but the broader audit found several
rows that are duplicated, visually near-duplicated, or were captured after failed
status waits.

Main problems:

- 3 exact pixel-duplicate row groups.
- 1 pixel-identical row pair with different PNG metadata.
- 4 forced recovery captures that should be treated as invalid until their
  command/status path is repaired.
- Several near-duplicates that may be legitimate subtle-state captures, but
  should be reviewed because their visual difference is very small.

## Exact Pixel Duplicates

These pairs/groups have identical rendered pixels:

| Rows | Status |
| --- | --- |
| `19-track-detail-sound`, `19a-track-detail-sound-empty` | Broken or redundant. Commands differ (`trackFillSource=generator` vs `trackSoundSource=empty`), but the resulting sound tab is identical. |
| `22g-track-generator-chord-instrument`, `22h-track-generator-chord-consumer` | Broken or redundant. Commands differ (`trackGeneratorKind=progressionChordGenerator` vs `trackGeneratorFollowing=chord`), but status and pixels are identical. |
| `32-step-order-unassigned`, `33-step-order-assigned-on` | Broken. Commands differ (`stepOrderFixture=unassigned` vs `assignedOn`), but both land in the same phrase/layers setup state; `phrasePerformLayer=stepOrder` does not visibly engage. |

## Pixel-Identical / Metadata-Different

These are visually identical after decoding even though the file hashes differ:

| Rows | Status |
| --- | --- |
| `23fa-slice-layer-quick-switch`, `23g-step-edit-rotaries` | Broken. `23g` leaves `slicerLayerSwitcher=open` in status and captures the same visible state as `23fa`, instead of the step-edit rotary state. |

## Forced Recovery Captures

These rows were captured with `QA_SURFACE_CAPTURE_ON_STATUS_TIMEOUT=1` after the
normal status wait failed. They are present in the gallery/R2 manifest, but
should be treated as invalid evidence until fixed:

| Row | Failed status evidence |
| --- | --- |
| `10a-phrase-density-zero` | Expected `phraseMatrixSelectedLayerID=density`; status stayed `pattern`. |
| `10b-phrase-density-ghosts` | Expected `phraseMatrixSelectedLayerID=density`; status stayed `pattern`. |
| `29-drum-kit-matrix` | Expected `drumKitMatrixRenderedGroupPatternSlot=mixed`; status stayed `1`. |
| `30-drum-kit-matrix-32` | Expected `drumKitMatrixRenderedDisplayStepCount=32`; status stayed `16`. |

The gallery symptom from Max's screenshot (`10a` and `10b` looking the same) is
explained by this: both rows failed to reach density mode and were force-captured
on the pattern/default view.

## Near-Duplicates To Review

These are not exact duplicates, but visual differences are very small:

| Rows | Difference |
| --- | --- |
| `08-phrase-layers-pattern`, `10-phrase-layers-automation-tool` | Likely legitimate: only the tool selection changes. |
| `19-track-detail-sound`, `20-track-fill-preview-active` | Suspicious: only a small header/control region differs. |
| `20b-track-randomize-settings`, `20c-track-randomize-rolled` | Likely legitimate: randomize lane values change in the lower panel. |
| `25-audio-live`, `27a-audio-source-tab` | Likely redundant/subtle: audio source tab state differs minimally. |
| `35-drum-kit-matrix-velocity-layer`, `36-drum-kit-matrix-chance-layer` | Likely legitimate: layer controls differ, but the matrix body is similar. |

## Recommended Fix Work

1. Fix command/status support for phrase density rows:
   - Make `phraseMatrixLayerID=density` actually select density in the app.
   - Remove the need for `QA_SURFACE_CAPTURE_ON_STATUS_TIMEOUT` for `10a/10b`.

2. Fix drum matrix command/status mismatch:
   - Decide whether row `29` should wait for `mixed` or status should report
     `mixed`.
   - Make `drumKitMatrixDisplayStepCount=32` visibly render/report 32 for row
     `30`.

3. Fix or retire duplicate track-detail rows:
   - `19a` needs an actually empty sound-state visual, or the row should be
     retired as duplicate of `19`.
   - `22h` needs a visible chord-consumer/following state, or the row should be
     retired as duplicate of `22g`.

4. Fix step-order rows:
   - `phrasePerformLayer=stepOrder` should enter the intended perform layer, or
     rows `32/33` should be rewritten to the current command vocabulary.

5. Fix slicer step-edit row isolation:
   - Row `23g` should explicitly close the slicer layer switcher and wait for a
     selected-step/rotary status before capture.

6. Re-run the full capture set only after the invalid rows pass strict status
   waits. Do not publish another R2 manifest from forced timeout captures unless
   the manifest or audit clearly marks those rows as provisional.

