# 2026-07-10 Today UX Bug Batch Goal

## Objective

Resolve all twelve bug reports filed on 2026-07-10, plus the outstanding phrase
pattern mini-grid size and clickability requirement, as five coherent UX
rounds. The result should make selection and value controls direct and easy to
hit, remove unnecessary nesting and empty space, and reuse the app's shared
border, scrollbar, step-selection, and preview grammar instead of adding more
surface-specific variants.

## Preflight

- Implement in a dedicated build-loop worktree. The primary checkout has
  unrelated dirty `.meta`, project, UI, roadmap, and bug-intake state; do not
  stage, revert, or absorb that state into this goal.
- The twelve `docs/bugs/20260710-*` directories are untracked intake artifacts in
  the primary checkout. Preserve them there because bug-reporter's file intake
  is branch-agnostic and points at that checkout.
- Reconcile commit `869c5cc6` (`codex/step-length-layer`) before editing the
  shared step-grid files. It is not on `main` at plan creation and overlaps
  `ClipContentPreview`, `StepGridCoordinator`, and related tests.
- Start the worktree from the latest real `main`, not merely the primary
  checkout's current `2f520683` if `main` has advanced elsewhere.
- Commit after each round so review and rollback stay bounded.
- Follow the standard capture/publish split:

  ```sh
  PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
    scripts/visual-scenarios/qa-surface-coverage.sh

  bug-reporter absorb-captures "$TMPDIR/in-sequence-captures/qa-$USER" \
    --project in-sequence \
    --source qa-surface-coverage
  ```

## Holistic Patterns

1. **The visible control owns its whole cell.** A pattern slot, track tile,
   step, menu row, or icon button must respond over the complete rendered
   shape, including padding. Do not leave glyph-only or narrow-label hit areas.

2. **Selection is direct and unambiguous.** Selected track cards use a solid
   track-accent state with dark foreground content, not a small checkmark plus
   a competing outline. Step selection uses secondary click consistently and
   exposes the same copy, paste, and clear actions across sequencer families.

3. **Identity chrome is shared.** Track and mixer channel outlines derive from
   the same full-strength track/group accent role and standard border width.
   Avoid separately desaturating mixer channels.

4. **Contained editors should fill their owning well.** A child editor that
   already has clear internal structure should not receive an additional grey
   card, border, and large inset from its parent. Sampler, randomize, and modal
   content should use one meaningful boundary.

5. **Scroll chrome is conditional.** Use the existing custom scrollbar for
   real overflow and no scrollbar when all rows fit. Replacing a native `List`
   must preserve insert reordering and keyboard/accessibility behavior.

6. **Preview cells are visual, not narrated.** History thumbnails and pattern
   mini-grids should communicate through their content, index/selection state,
   and accessibility labels rather than repeated visible text.

## Round 1: Direct Manipulation And Hit Areas

### 1. Phrase pattern mini-grid

- Make each of the 16 controls in `PatternIndexCellPreview` fill its complete
  4x4 grid allocation, with the `Button` frame and `contentShape` applied after
  expansion rather than only around the inner rounded rectangle.
- Reduce unused outer padding so the matrix occupies more of the phrase layer
  cell while retaining clear gutters between slots.
- Preserve exact-slot behavior: clicking P7 selects P7; clicking an already
  selected slot is idempotent and does not cycle the whole card.
- Keep card-background cycling disabled for pattern layers and keep the whole
  mini-grid available in both setup and perform overlays.
- Candidate files:
  - `Sources/UI/PhraseCells/PatternIndexCellPreview.swift`
  - `Sources/UI/PhraseWorkspaceView.swift`
  - `Sources/UI/TrackPerformSelectionState.swift`
  - `Tests/SequencerAITests/UI/TrackPerformSelectionStateTests.swift`

### 2. Shared step selection and actions

- Promote `SliceStepBatchActionBar` to a shared step-grid action component.
- Put Clear, Copy, and Paste in the aligned step-editor header. Keep them
  visible but disabled until at least one step is selected; Paste additionally
  requires clipboard content.
- Secondary-clicking anywhere in a step cell selects/toggles that step without
  changing its trigger or value. Primary click keeps its existing edit action.
- Apply the same interaction contract to melodic, chord, slicer, and drum-kit
  step grids instead of fixing only the captured mono view.
- Move the remove-source cross to the trailing edge of the header.
- Remove the visible `Lane`, `Length`, and `Layer` captions from this compact
  row and align the bottoms of every selector/action on one baseline. Preserve
  those names in help and accessibility labels.
- Candidate files:
  - `Sources/UI/StepGridView.swift`
  - `Sources/UI/Theme/StudioRightClickSelection.swift`
  - `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`
  - `Sources/UI/Slicer/SliceTrackEditingControls.swift`
  - `Sources/UI/Slicer/SliceTrackWorkspaceView.swift`
  - `Sources/UI/Chord/ChordTrackWorkspaceView.swift`
  - `Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift`
  - `Sources/StepGrid/StepGridCoordinator.swift`

### Round 1 acceptance

- Focused tests prove exact pattern-slot selection, repeat-click idempotence,
  secondary-click selection without mutation, and action enablement rules.
- An interaction-level hit test clicks the center and padded edge of at least
  two pattern mini-cells and proves the requested slot is selected. A helper
  that bypasses SwiftUI hit testing is not sufficient evidence.
- Captures show the larger pattern controls and the selected-step action row:
  `08-phrase-layers-pattern`, `18-track-detail-steps-clip`,
  `23g-step-edit-rotaries`, plus representative chord/drum/slicer rows.
- Commit this round independently.

## Round 2: Tracks Navigator Selection And Filtering

### 3. Track card selection grammar

- In selection mode, remove the checkbox/tick from track and kit cards.
- Put the track or kit name at the top of the card.
- Remove the type logo badge and visible `MONO`/type footer from normal track
  cards. Preserve type information in accessibility and help.
- Fill selected cards with their solid track/group accent and use the standard
  dark foreground treatment. Do not use a translucent accent wash.
- Apply the same selected grammar to normal tracks, collapsed kits, and
  expanded drum-part cards.

### 4. One Perform action

- Replace the separate By Track and By Value buttons with one `Perform`
  command that enters Phrase > Layers scoped to the selected tracks and starts
  in By Track mode.
- Keep By Value reachable from the phrase layer surface; do not delete its
  underlying mode or document behavior.

### 5. Track type filter

- Add a compact menu/filter control with: All, Mono, Poly, Chord, Slicer,
  Audio, Drum Kits, and Drum Parts.
- Classify grouped members as Drum Parts before applying their raw melodic
  track type so Mono/Poly filters do not unexpectedly include kit parts.
- Drum Kits shows one kit card per group. Drum Parts shows member cards without
  mutating the group's linked/collapsed document state.
- Filtering is presentation-only: it must not reorder tracks, mutate the
  project, clear selection, or silently include hidden tracks in a new
  selection.
- Candidate files:
  - `Sources/UI/TracksMatrixView.swift`
  - `Sources/UI/VisualScenarioCommandRunner.swift`
  - `Tests/SequencerAITests/UI/WorkspaceModeTests.swift`
  - `Tests/SequencerAITests/UI/TracksPageInvalidationTests.swift`

### Round 2 acceptance

- Unit tests cover every filter category, grouped-vs-ungrouped precedence,
  stable ordering, non-mutating filter changes, and Perform routing to scoped
  By Track mode.
- A hit-area check proves track card selection works at the card edge, not only
  on its title.
- Extend visual commands/captures to show All, Drum Kits, and Drum Parts filter
  results. `02a-tracks-selection-actions` must show the simplified action bar
  and solid selected card.
- Commit this round independently.

## Round 3: Creation, Mixer, And Scene Chrome

### 6. Add Drum Group composition

- Make the modal content-sized or use its available height; remove the large
  dead lower region in the blank state.
- Replace the tiny bespoke Add Part and Create Group controls with established
  app button/row grammar. Remove redundant plus glyphs from text-labelled
  commands.
- Render populated part rows with the same quiet option-row style and aligned
  controls used elsewhere in creation flows, not a separate card style.
- Keep kit selection, part rename/sound choice/removal, and Create Group
  behavior intact.
- Candidate files:
  - `Sources/UI/DrumGroup/AddDrumGroupContent.swift`
  - `Sources/UI/Track/CreateTrackFlow.swift`
  - `Sources/UI/Theme/StudioModal.swift`

### 7. Mixer border identity

- Change the shared `StudioMixerStrip` outline to use the same track/group
  accent strength and standard border width as track-detail identity borders.
- Verify track channels, buses, send returns, and master remain visually
  coherent; selected/solo emphasis may add weight but must not introduce a
  second desaturated base grammar.
- Candidate files:
  - `Sources/UI/Theme/StudioMixerStrip.swift`
  - `Sources/UI/MixerView.swift`
  - `Sources/UI/Mixer/MixerWorkspaceView.swift`
  - `Sources/UI/Mixer/MixerBusStrip.swift`

### 8. Scene FX overflow

- Replace the native-scrollbar `List` in the scene insert column with the
  shared custom vertical scroll chrome or a shared equivalent.
- Hide the scrollbar completely for the two-insert captured state.
- Show the custom thumb only when insert rows exceed the viewport.
- Preserve drag-to-reorder, selection, enable/remove actions, keyboard focus,
  and accessibility ordering.
- Candidate files:
  - `Sources/UI/Mixer/ScenesWorkspaceView.swift`
  - `Sources/UI/Theme/StudioControls.swift`

### Round 3 acceptance

- Tests cover drum plan edits, scene insert reorder after the container change,
  and custom scrollbar overflow/no-overflow calculations.
- `02d-add-drum-group-modal` shows the compact blank state. Add a populated
  drum-group capture row so part-row styling is visible.
- `04-mixer` shows full-strength channel borders.
- `05b-scenes-edit-content` shows no scrollbar with two inserts; add an
  overflow fixture/capture proving the custom scrollbar with enough inserts.
- Commit this round independently.

## Round 4: Track Detail Density And Preview Cleanup

### 9. Sampler fills its well

- Remove the redundant outer inset around `SamplerDestinationWidget` in the
  Sound tab so the sampler uses the full tab-well width.
- Remove one of the nested grey border/background layers while retaining the
  sampler's meaningful internal waveform/filter separation.
- Apply the same embedding rule wherever the shared sampler widget is hosted,
  including drum-part expanded Sound, unless that host has a documented reason
  for a different inset.
- Candidate files:
  - `Sources/UI/SamplerDestinationWidget.swift`
  - `Sources/UI/TrackDestinationEditor.swift`
  - `Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift`
  - track Sound-tab host files found from `rg "SamplerDestinationWidget"`

### 10. Randomize panel alignment

- Put an icon-only Close control in the panel's top-right corner.
- Remove Cancel and the bottom text Close command.
- Place Re-Roll on the same top row as the controls/actions rather than in a
  detached footer.
- Present Root and Scale first, with their labels below the controls on the
  same baseline as rotary labels.
- Closing keeps the already-applied randomization, matching the current
  immediate/reroll model; this is not a rollback action.
- Candidate files:
  - `Sources/UI/TrackSource/TrackSourceEditorView.swift`
  - `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`

### 11. Text-free clip history cells

- Remove visible index, `1 bar`, `empty`, and `live` text from history cells.
- Let the piano-roll thumbnail, empty/disabled treatment, selection border,
  and range border carry the visual state.
- Retain descriptive accessibility labels for region index, availability, and
  selected length.
- Candidate files:
  - `Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift`
  - `Tests/SequencerAITests/UI/TrackSourceSourceDisplayStateTests.swift`

### Round 4 acceptance

- Focused tests preserve sampler parameter editing, randomize close/reroll
  semantics, and history-cell accessibility descriptions.
- `19-track-sampler-sound-populated`, `20b-track-randomize-settings`, and
  `22aa-track-clip-history` visibly prove each change.
- Commit this round independently.

## Round 5: Pitch Entry And Chord Generator Semantics

### 12. Piano-keyboard pitch layer

- Promote the existing chord-root/pitch-pool keyboard grammar into a shared,
  interactive piano keyboard instead of introducing a third bespoke keyboard.
- When Pitch is the active layer, place one octave of keys below the step row
  with an octave selector alongside it.
- Use secondary-click step selection from Round 1 as the edit target. Pressing
  a key writes that MIDI note to every selected triggered step in the active
  Normal/Fill lane; it does not silently turn rests into triggers.
- Render active pitch cells as DAW note names such as `C4` using `DAWNoteName`.
  Rest/inactive cells stay blank rather than showing octave dots or a pitch
  that will not play.
- Keep the keyboard disabled when there is no selected triggered step, preserve
  multi-selection batch editing, and clamp octave/note choices to MIDI 0...127.
- Reuse this presentation for every melodic note-grid pitch layer that edits
  `ClipStepNote`, not for chord-reference or slicer index layers.
- Candidate files:
  - `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`
  - `Sources/UI/Chord/ChordTrackWorkspaceView.swift`
  - `Sources/UI/TrackSource/Generator/PitchAlgoEditor.swift`
  - `Sources/StepGrid/StepGridCoordinator.swift`
  - `Sources/StepGrid/ClipNoteGridStepEditing.swift`
  - `Sources/Musical/DAWNoteName.swift`

### 13. Chord-only random chord generator

- Replace the user-facing progression generator with a chord-track generator
  whose two stages mirror melodic generators: Trigger chooses the firing steps;
  Chords chooses the pool and chord variation behavior.
- Make the new generator creatable/assignable only on `.chord` tracks. Remove
  it from Poly creation, compatible-generator lists, and kind switching.
- Source chord choices from stable chord-palette slot IDs. The Chords stage
  lets the user include/exclude palette chords and configure bounded inversion
  randomization; an empty choice set produces no notes.
- On every fired trigger, choose one enabled chord deterministically from the
  existing seeded evaluation context, apply the allowed inversion variation,
  and emit the resulting notes through the normal generated-note pipeline.
  Do not perform UI-state lookup, allocation, or unseeded randomness on the
  realtime path.
- Prefer a new serialized `chordGenerator` kind/params shape. Retain
  `progressionChordGenerator` as decode/playback-compatible legacy data but
  hide it from new creation. Existing poly-track projects must load and retain
  their generator assignment; normalization must not silently drop or replace
  it. Document the legacy boundary and provide an explicit conversion helper
  if conversion can preserve the chord set and trigger positions.
- Replace the current manual per-step progression editor with the shared
  Trigger/Chords stage UI and chord-palette controls. Update visual fixtures so
  the canonical chord-generator capture uses a chord track, not `Poly 9`.
- Candidate files:
  - `Sources/Document/TrackSourceCatalog.swift`
  - `Sources/Document/GeneratorParams.swift`
  - `Sources/Document/ProgressionChordGeneratorParams.swift`
  - `Sources/Document/GeneratedSourcePipeline.swift`
  - generated-source evaluator/snapshot compiler files found from
    `rg "progressionChords" Sources`
  - `Sources/UI/TrackSource/Generator/GeneratorParamsEditorView.swift`
  - `Sources/UI/TrackSource/Generator/ProgressionChordGeneratorEditorView.swift`
  - `Sources/UI/VisualScenarioCommandRunner.swift`

### Round 5 acceptance

- Pitch-layer tests prove note-name rendering only for triggered steps, octave
  selection, MIDI boundary clamping, Normal/Fill isolation, and multi-selected
  keyboard writes without creating triggers.
- Generator catalog tests prove the new kind is offered to Chord only and not
  Mono/Poly/Slicer/Audio; legacy progression documents still round-trip and
  play without source loss.
- Deterministic evaluator tests prove identical seed/input produces identical
  chord and inversion choices, different enabled pools constrain output, rests
  emit nothing, and every emitted pitch belongs to the resolved chord.
- `22c-track-pitch-layer` shows readable note names plus the keyboard/octave
  selector. Replace/update `22g-track-generator-chord-instrument` so it shows
  the Trigger/Chords generator on a chord track.
- Commit this round independently.

## Bug Coverage Matrix

| Report | Requirement | Work item | Evidence |
| --- | --- | --- | --- |
| `20260710-064606-instead-of-the-tick-to-indicate-selected` | Solid selected track card; no tick, logo, or type text; name at top | 3 | `02a-tracks-selection-actions` |
| `20260710-064805-instead-of-the-by-track-and-by-value-but` | One Perform button defaulting to By Track | 4 | `02a`, scoped navigation test |
| `20260710-065116-add-a-type-filter-to-show-only-drum-trac` | Track-type filter including kits and drum parts | 5 | new filter rows |
| `20260710-065350-lots-of-wasted-space-here-the-text-and-d` | Compact drum-group modal and consistent populated rows/buttons | 6 | `02d` plus new populated row |
| `20260710-065449-the-borders-around-channels-seem-to-be-d` | Mixer channel borders match track identity style | 7 | `04-mixer` |
| `20260710-065559-the-fx-section-has-a-scrollbar-that-does` | Custom scrollbar only on actual scene-FX overflow | 8 | `05b` plus new overflow row |
| `20260710-070017-the-line-above-the-steps-should-be-align` | Aligned header, no captions, trailing cross, copy/paste/clear, right-click selection | 2 | `18`, `23g`, interaction tests |
| `20260710-070107-the-sampler-can-fill-the-element-rather` | Sampler fills tab well without redundant grey border | 9 | `19-track-sampler-sound-populated` |
| `20260710-070303-let-s-put-close-for-the-randomize-settin` | Top-right close, no Cancel, aligned Re-Roll and Root/Scale labels | 10 | `20b-track-randomize-settings` |
| `20260710-070332-take-out-the-text-in-the-history-cells` | Text-free history thumbnails | 11 | `22aa-track-clip-history` |
| `20260710-074137-where-pitch-is-the-layer-and-perhaps-oth` | Piano keyboard/octave selector and note names on triggered pitch steps | 12 | `22c-track-pitch-layer` |
| `20260710-074352-this-generator-should-be-rethought-as-so` | Chord-only random chord generator with Trigger/Chords split | 13 | updated `22g` plus evaluator tests |
| `20260708-160122-make-the-pattern-selector-widget-the-sam` | Pattern mini-grid fills more of the cell | 1 | `08-phrase-layers-pattern` |
| `20260616-110235-the-behaviour-of-pattern-layer-in-a-cell` | Every pattern mini-cell is directly clickable | 1 | hit test plus `08` |

## Verification Gates

Run after each round where relevant and again on the complete batch:

```sh
git diff --check
scripts/diagnostics/ux-canon-lint.sh
scripts/diagnostics/realtime-path-lint.sh
scripts/diagnostics/runtime-ownership-lint.sh

xcodebuild -quiet -project SequencerAI.xcodeproj -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/seqai-20260710-ux-batch build
```

Run focused tests for the touched surfaces, including:

- `TrackPerformSelectionStateTests`
- `TracksPageInvalidationTests`
- `WorkspaceModeTests`
- `StepGridCoordinatorTests` and step-grid parity tests
- drum-group plan/create tests
- scene insert/reorder and custom scrollbar tests
- `TrackSourceSourceDisplayStateTests`
- `ProjectTrackSourceCatalogTests` and `GeneratorKindTests`
- generated-source evaluator and source-normalization compatibility tests

Then run the full `SequencerAITests` suite before final acceptance.

## Visual Acceptance

1. Extend `VisualScenarioCommandRunner` and the `CAPTURES` table before the
   implementation is considered complete. New rows must cover track filters,
   a populated drum-group builder, scene-FX overflow, and selected step actions.
2. Record the full QA suite from the final committed worktree.
3. Absorb the capture directory through bug-reporter.
4. Inspect every row named in the coverage matrix at desktop capture size.
5. Perform direct interaction checks that screenshots cannot prove:
   - click pattern mini-cells at both center and padded edge;
   - right-click steps in melodic, chord, slicer, and drum grids;
   - select several triggered pitch steps and apply notes from both black and
     white piano keys at two octave settings;
   - drag-reorder scene inserts after the custom-scroll conversion;
   - activate controls by clicking their visible padding, not only glyphs.

## Status And Completion

- Append `Status: RESOLVED <commit>` to all twelve `20260710-*` reports only after
  their acceptance evidence passes.
- Treat the July 8 pattern-size report as reopened by this clarification; add
  the final commit/evidence to it rather than relying on its earlier resolved
  line.
- Resolve the still-open June 16 pattern-cell behavior report when the hit-area
  interaction test passes.
- Update all database-backed counterparts with:

  ```sh
  bug-reporter update-bug BUG_ID --status fixed
  ```

- Update the relevant stable wiki page if shared interaction or scrollbar
  contracts change.
- The goal is complete only when all five commits are reviewed, all gates pass,
  all fourteen report requirements are resolved, and the final absorbed run plus
  interaction checks demonstrate both appearance and behavior.
