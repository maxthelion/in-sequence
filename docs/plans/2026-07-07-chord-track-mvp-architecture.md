# Goal: Dedicated Chord Track MVP

Status: proposed
Created: 2026-07-07
Parent plan: `docs/plans/2026-07-07-fresh-bug-batch-capture-kit-history-chord-track.md`
Source bug: `docs/bugs/20260707-211517-let-s-make-a-new-version-of-the-poly-tra/`
Bug Reporter row: `bug_20260707201517_Let-s-make-a-new-version-of-the-poly-track-w`

## Objective

Implement a real `Chord Track` workflow rather than renaming the existing
poly/chord generator surface. A chord track is a first-class track grammar:
users choose reusable chord palette slots, place palette references on steps,
edit per-step chord parameters as layers, and hear/bake the resulting chords
without losing the recipe.

This is intentionally split out of the fresh bug batch because it crosses
document schema, playback, source/bake semantics, track creation, editor UI,
visual command fixtures, and regression coverage.

## Non-Negotiables

- Do not ship a cosmetic label change from `Poly` to `Chord`.
- Do not duplicate full chord definitions into every step.
- Do not hide the palette inside the generator panel; the palette sits above the
  tabbed editor and remains visible while editing steps.
- Do not break existing `polyMelodic` tracks, clips, generators, or documents.
- Baking must produce a playable clip while preserving the chord-track recipe
  when the source model supports retained generator/source state.
- The UI must follow `docs/ux-canon.md`: no native black dropdowns, no clipped
  labels, no explanatory prose on the working surface.

## Proposed Architecture

1. Add a user-visible track type:
   - introduce `TrackType.chord`;
   - label it `Chord`;
   - choose a distinct accent in the existing track palette grammar;
   - include it in create-track flow and visual command helpers.

2. Add chord recipe storage:
   - add a codable `ChordPalette`/`ChordPaletteSlot` model with stable slot IDs
     or indexes, root, quality/type, scale/extension fields, and display name;
   - store the palette on `StepSequenceTrack` or a track-owned settings model so
     it survives clip swaps and baking;
   - provide migration defaults for old documents.

3. Add chord step-reference content:
   - either add a dedicated `ClipContent.chordSteps(...)` case or a track-owned
     per-pattern recipe that stores:
     - step enabled state;
     - chord palette slot reference;
     - inversion at minimum;
     - optional octave/voicing/length only if the model supports it cleanly;
   - normalize parallel arrays the way `sliceTriggers` does, but keep chord
     semantics separate from slice semantics.

4. Playback resolution:
   - resolve a chord step by looking up its palette slot at playback/precompute
     time;
   - convert the resolved chord + inversion into `NoteEvent`s using the same
     note scheduling path as melodic clips;
   - changing a palette slot updates all referencing steps on the next snapshot
     without mutating those steps;
   - inversion transforms voiced notes without mutating the palette.

5. Bake/source retention:
   - baking chord-track output materializes a normal playable note-grid clip;
   - source/recipe metadata remains attached to the pattern/source where the
     current generator/source-retention architecture allows it;
   - a user can return to live chord-track editing after bake.

6. UI:
   - route `TrackType.chord` to a dedicated `ChordTrackWorkspaceView` or a
     chord-specialized branch of the track editor;
   - show a compact chord palette above `StudioSectionPills`;
   - add a `Chords` tab for add/remove/select/edit;
   - show `Steps/Clip` as chord-slot references, similar to slicer step cells;
   - expose layers for chord slot and inversion at minimum;
   - keep Sound/FX/Macros/Mixer tabs consistent with other musical tracks.

7. Visual command coverage:
   - add fixture commands for a populated chord track;
   - add commands/status for selected chord tab, selected layer, selected step,
     palette count, and active chord references;
   - add `qa-surface-coverage.sh` rows for:
     - chord track Steps/Clip;
     - chord track Chords tab;
     - chord track inversion layer.

## Acceptance Criteria

- A user can add a `Chord Track` from the create-track flow.
- A new chord track opens to a usable surface with a visible chord palette above
  the tabs.
- The `Chords` tab supports add/remove/select/edit for palette slots.
- The `Steps/Clip` grid places palette references, not duplicated chord
  definitions.
- The layer UI includes chord selection and inversion.
- Behavior tests prove:
  - assigning palette item `N` to a step plays notes from palette item `N`;
  - changing palette item `N` updates every referencing step;
  - per-step inversion changes voiced notes without mutating the palette;
  - baking creates a playable note-grid clip and leaves the recipe recoverable.
- Existing poly melodic, generator, and slice tests still pass.
- Fresh screenshots exist for the three chord-track rows listed above.
- `scripts/diagnostics/ux-canon-lint.sh` passes.
- `scripts/diagnostics/realtime-path-lint.sh` and
  `scripts/diagnostics/runtime-ownership-lint.sh` pass.
- Only after all criteria pass:
  - append `Status: RESOLVED <commit>` to
    `docs/bugs/20260707-211517-let-s-make-a-new-version-of-the-poly-tra/note.md`;
  - update
    `bug_20260707201517_Let-s-make-a-new-version-of-the-poly-track-w` to
    `fixed`.

## Suggested Execution Slices

1. Model and playback first:
   - add chord track schema and normalization;
   - add chord-step resolution tests;
   - add bake/source-retention tests.

2. Track creation and editor shell:
   - create-track flow;
   - palette above tabs;
   - Chords tab with direct editing;
   - basic Steps/Clip reference grid.

3. Layer polish and visual evidence:
   - inversion layer;
   - command-channel fixture/status;
   - `qa-surface-coverage.sh` rows;
   - screenshots and bug closure.
