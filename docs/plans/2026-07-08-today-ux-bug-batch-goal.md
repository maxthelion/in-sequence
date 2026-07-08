# 2026-07-08 Today UX Bug Batch Goal

## Objective

Resolve the 2026-07-08 bug batch as one holistic pass, not as isolated pixel
tweaks. The target is a flatter, quieter, more consistent working UI across
drum kit, phrase capture, track source, slicer, audio input, macros, and
randomize surfaces, plus a reliable QA capture path that can prove the fixes.

## Preflight

- Preserve unrelated dirty state. At plan creation, the tree contains separate
  document/engine work around `ChordPalette` and `ChordTrackSettings.swift` that
  blocks a full `xcodebuild`. Do not mix that work into this goal unless the
  goal owner explicitly includes it.
- Start from a buildable checkout or first resolve/stash the unrelated build
  break so acceptance can include a real build.
- Keep the capture flow branch/commit-aware:

  ```sh
  PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
    scripts/visual-scenarios/qa-surface-coverage.sh

  bug-reporter absorb-captures "$TMPDIR/in-sequence-captures/qa-$USER" \
    --project in-sequence \
    --source qa-surface-coverage
  ```

## Holistic Patterns

1. Remove title-adjacent ornament and grey explanatory copy.
   Shared modal/panel headers should not show the short accent rule after the
   title. Working surfaces should prefer compact labels, controls, or tooltips
   over grey prose under headings and inside cards.

2. Standardize empty wells and add targets.
   Empty states such as Add FX, source slot, macros, and similar "put something
   here" areas should share one dark, bordered/dashed well grammar with uniform
   internal spacing. Avoid one-off grey boxes.

3. Make track-detail tabs share the same body template.
   Mono/poly/chord/slicer/audio/drum-kit tabs should use a consistent top
   density, content padding, title scale, and empty-state layout. The smaller
   audio title size is the preferred scale.

4. Treat waveform displays as a shared component.
   Slicer and audio waveforms should use small bars, non-blocky rendering,
   visible step/bar guides where musical context matters, and a playhead where
   playback/capture position exists.

5. Keep state in controls, not badges of prose.
   Remove noisy badges such as "OVERWRITES", orange slice-count copy, and
   disabled-looking selected slice boxes. Show state through outline, selected
   thumb, icon-only remove controls, and direct previews.

6. Randomize should be an editing surface, not an audition/bake detour.
   Randomize settings should open, roll immediately into the clip using current
   settings, allow reroll after settings edits, and offer close/cancel or undo
   semantics. The normal step sequencer should remain visible with pitches
   layer context instead of a separate audition section.

7. Visual QA must be a reliable acceptance source.
   A UI polish batch cannot be accepted if `qa-surface-coverage.sh` can abort
   while collecting the evidence. Treat the `playerTime.sampleTimeValid`
   AVFAudio crash as a blocking evidence issue unless it is proven unrelated and
   quarantined with a narrower capture workaround.

## Work Items

1. Shared chrome cleanup
   - Remove the short accent rule from `StudioModal` and `StudioPanel`.
   - Sweep for bespoke copies of text + short accent rule.
   - Remove or compress grey subtitle/prose in affected template, phrase
     capture, source picker, and cell surfaces.
   - Candidate files:
     - `Sources/UI/Theme/StudioModal.swift`
     - `Sources/UI/Theme/StudioPanel.swift`
     - `Sources/UI/PhraseWorkspaceView.swift`
     - `Sources/UI/DrumGroup/DrumKitTemplateChooserSheet.swift`
     - `Sources/UI/TrackSource/TrackSourceSourceWell.swift`
     - `Sources/UI/TrackSource/TrackSourceContainedSourcePicker.swift`

2. Drum kit matrix and template flow
   - Make drum-kit matrix margins/title scale match other track-detail views.
   - Move Apply Template to the persistent top pattern/routing area, not inside
     the matrix layer row.
   - Rework template chooser rows:
     - remove grey summary subtext where it duplicates visible content;
     - remove "OVERWRITES" badges from normal chooser rows;
     - use a primary action matching app button grammar;
     - render a compact pattern preview in each template pill using the clip
       history preview mechanism or a shared equivalent.
   - Candidate files:
     - `Sources/UI/DrumGroup/DrumKitMatrixView.swift`
     - `Sources/UI/DrumGroup/DrumKitMatrixView+Header.swift`
     - `Sources/UI/DrumGroup/DrumKitTemplateChooserSheet.swift`
     - `Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift`

3. Shared empty-state well grammar
   - Introduce or formalize a single component for empty add wells if
     `StudioAddCard` is not enough.
   - Apply it to drum-kit Add FX, macros empty body, and track source add-source
     picker.
   - Make Add Source bottom section two halves:
     - left: empty well with New Clip only;
     - right: blank generator choices;
     - remove Select Clip/Generator From Pool, Cancel, Add Source title, and
       explanatory subtext from the root state.
   - Candidate files:
     - `Sources/UI/Theme/StudioCards.swift`
     - `Sources/UI/DrumGroup/KitBusFXChainView.swift`
     - `Sources/UI/Track/TrackWorkspaceView.swift`
     - `Sources/UI/TrackSource/TrackSourceContainedSourcePicker.swift`
     - `Sources/UI/TrackSource/TrackSourceSourceWell.swift`

4. Slicer source and slice surfaces
   - Remove orange slice-count copy.
   - Replace Remove Sample text/button with a simple cross/icon affordance.
   - Change selected slice highlighting from grey fill to a non-grey selected
     treatment, preferably accent outline/indicator.
   - Make waveform bars smaller, around 3 px where space allows.
   - Candidate files:
     - `Sources/UI/Slicer/SlicerSourceWidget.swift`
     - `Sources/UI/Slicer/SlicerWaveformView.swift`
     - `Sources/UI/Slicer/SliceTrackWorkspaceView.swift`
     - `Sources/UI/WaveformView.swift`

5. Audio capture waveform
   - Remove "Rolling capture" title text from playback/capture waveform body.
   - Add step and bar markers to the waveform.
   - Add a playhead when capture/playback progress is known.
   - Keep the same waveform grammar as slicer.
   - Candidate files:
     - `Sources/UI/Track/TrackWorkspaceView.swift`
     - `Sources/UI/WaveformView.swift`

6. Macros tab consistency
   - Replace the plain "No Macros" text with the shared empty well/body template.
   - Align spacing with the track-detail tab grammar used by source/FX/mixer.
   - Candidate files:
     - `Sources/UI/Track/TrackWorkspaceView.swift`
     - `Sources/UI/TrackDestination/AUMacroSlotKnob.swift`

7. Randomize flow
   - Replace the separate audition section with the normal step sequencer in
     pitches context.
   - Pressing Randomize should open settings and roll immediately using current
     settings, applying to the track.
   - Reroll should apply updated settings.
   - Remove Bake from this context.
   - Provide close/cancel or undo semantics.
   - Make root/scale controls readable.
   - Candidate files:
     - `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`
     - randomize model/helper files found from `rg "Randomize"`

8. QA capture AVFAudio crash
   - Reproduce or invalidate the 2026-07-08 `qa-surface-coverage.sh` abort on a
     stamped build.
   - Investigate sample/drum-kit playback scheduling paths that can issue
     `AVAudioPlayerNode` schedule/play commands while node time is invalid.
   - Preserve audio hard rules: schedule ahead from the audio clock, avoid
     render-thread locks/allocation, and do not repair by stopping/restarting
     topology during playback.
   - If the crash is fixed, prove with a full uninterrupted QA capture. If the
     crash is not part of this UI goal, document a narrow quarantine and still
     provide complete visual evidence for the UI rows.
   - Candidate files:
     - `Sources/Audio/SamplePlaybackEngine.swift`
     - `Sources/Audio/MainAudioGraph.swift`
     - `Sources/Engine/EngineController.swift`
     - `Sources/UI/VisualScenarioCommandRunner.swift`
     - `.meta/multipass/state/runtime-problems.md`

9. Status and bug bookkeeping
   - Append `Status: RESOLVED <commit>` to each fixed `docs/bugs/20260708-*`
     note.
   - Update database-backed bugs to `fixed` with `bug-reporter update-bug`.
   - Keep capture references in the notes unchanged; new captures are linked by
     `absorb-captures`.

## Bug Coverage Matrix

| Bug | Report | Capture row | Covered by |
| --- | --- | --- | --- |
| `20260708-090019-this-view-has-larger-margin-round-the-ed` | Drum-kit margins and title size inconsistent | `29-drum-kit-matrix` | Work items 2, 3 |
| `20260708-090354-take-out-grey-subtext-take-out-overwrite` | Template chooser grey subtext, overwrite badge, apply style, mini previews | `38-drum-kit-matrix-template-chooser` | Work items 1, 2 |
| `20260708-090518-put-apply-template-at-the-top-near-the-p` | Apply Template belongs near patterns/routing | `36-drum-kit-matrix-chance-layer` | Work item 2 |
| `20260708-090713-the-background-of-the-add-fx-box-is-not` | Add FX empty area should use consistent template | `29a-drum-kit-fx-tab` | Work item 3 |
| `20260708-090916-take-out-rolling-capture-text-add-step-a` | Audio capture waveform needs markers/playhead/no title | `27c-audio-playback` | Work items 4, 5 |
| `20260708-091112-the-selected-slice-first-one-is-a-grey-b` | Selected slice should not be grey box | `23fa-slice-layer-quick-switch` | Work item 4 |
| `20260708-091214-the-waveform-is-very-blocky-can-we-use-s` | Waveforms should use smaller bars | `23e-track-slicer-slice-tab` | Work items 4, 5 |
| `20260708-091311-take-out-orange-8-slices-text-make-remov` | Remove orange slice-count text and make remove simple cross | `23d-track-slicer-source-tab` | Work item 4 |
| `20260708-091710-let-s-tidy-this-up-let-s-make-the-bottom` | Add Source root should be two halves, no pool/cancel/title/subtext | `22a-track-add-source-empty` | Work items 1, 3 |
| `20260708-092025-macros-view-is-inconsistent-with-other-t` | Macros tab should share track UI element/empty state | `21-track-macros-tab` | Work items 3, 6 |
| `20260708-092155-take-out-line-after-title-and-grey-sub-t` | Phrase capture title rule and grey subtext | `13b-phrase-perform-capture` | Work item 1 |
| `20260708-093224-instead-of-the-audition-section-let-s-ju` | Randomize should be normal sequencer/settings flow | `20c-track-randomize-rolled` | Work item 7 |
| `20260708-093533-qa-capture-avfaudio-player-time-sampletimevalid` | QA capture aborts in AVFAudio while driving drum-kit rows | full `qa-surface-coverage` run, especially rows `29` through `38` | Work item 8 |

## Acceptance Evidence

Code checks:

```sh
git diff --check
scripts/diagnostics/ux-canon-lint.sh
xcodebuild -quiet -project SequencerAI.xcodeproj -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/seqai-today-ux-bug-batch-build build
```

Pattern sweeps:

```sh
rg -n "showsTitleRule|title rule|header rule" Sources/UI -g '*.swift'
rg -n -U 'Text\([^\n]+\)\n(?:\s*\.[^\n]+\n){0,8}\s*Rectangle\(\)\n\s*\.fill\([^\n]+\)\n\s*\.frame\(width: (24|28|32|36|40|44|48), height: (1|2|3)\)' Sources/UI -g '*.swift'
rg -n '"Rolling capture"|"OVERWRITES"|"8 slices"|"Select Generator From Pool"|"Select Clip From Pool"|"No Macros"' Sources/UI -g '*.swift'
```

Visual evidence:

- Regenerate and absorb QA captures with the standard two-command flow.
- Confirm the new absorbed run includes these rows and visually inspect them in
  the bug-reporter gallery:
  - `13b-phrase-perform-capture`
  - `20c-track-randomize-rolled`
  - `21-track-macros-tab`
  - `22a-track-add-source-empty`
  - `23d-track-slicer-source-tab`
  - `23e-track-slicer-slice-tab`
  - `23fa-slice-layer-quick-switch`
  - `27c-audio-playback`
  - `29-drum-kit-matrix`
  - `29a-drum-kit-fx-tab`
  - `36-drum-kit-matrix-chance-layer`
  - `38-drum-kit-matrix-template-chooser`
- Confirm the full run does not abort during drum-kit rows `29` through `38`,
  and that `absorb-captures` reports/publishes all expected rows.

Bug status evidence:

```sh
scripts/bug-status.sh --all | rg '20260708-'
bug-reporter list-bugs --project in-sequence --status open --json
```

The goal is complete only when all 13 file-backed reports above are marked
resolved, their database-backed counterparts are fixed, the checks pass, and the
absorbed capture run demonstrates the updated UI for every listed row.

## Execution Evidence

Status: COMPLETE in this commit.

Checks run:

```sh
git diff --check
scripts/diagnostics/ux-canon-lint.sh
xcodebuild -quiet -project SequencerAI.xcodeproj -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/seqai-today-ux-bug-batch-build build
```

Pattern sweeps passed with no matches for retired visible strings/patterns:

```sh
rg -n "showsTitleRule|title rule|header rule|\"Rolling capture\"|\"OVERWRITES\"|\"8 slices\"|\"Select Generator From Pool\"|\"Select Clip From Pool\"|\"No Macros\"|\"AUDITION\"|Text\(\"Bake\"\)" Sources/UI -g '*.swift'
```

Fresh visual evidence was captured from the explicit app bundle:

```sh
SEQUENCER_AI_VISUAL_APP_PATH="/tmp/seqai-today-ux-bug-batch-build/Build/Products/Debug/SequencerAI.app" \
PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
  scripts/visual-scenarios/qa-surface-coverage.sh
```

The first fresh full run produced 76/79 rows and did not reproduce the AVFAudio
abort. Rows `29c`, `29d`, and `29f` timed out on status acknowledgement, then
were rerun narrowly and backfilled as PNG evidence. The final absorbed set has
all 79 PNGs.

Absorbed gallery evidence:

- Run: `20260708-090903-in-sequence-qa-surface-coverage-main-923a889d`
- Gallery: <http://localhost:4747/gallery?run=20260708-090903-in-sequence-qa-surface-coverage-main-923a889d>
- Contact sheet: `/tmp/in-sequence-today-ux-bug-batch-contact-final.png`

Visual audit results:

- `13b-phrase-perform-capture`: modal title has no rule and no grey subtitle.
- `20c-track-randomize-rolled`: normal step grid remains visible; no audition
  strip or Bake action.
- `21-track-macros-tab`: shared empty well grammar replaces plain text.
- `22a-track-add-source-empty`: root add-source body is split into new clip and
  blank generator halves, with no pool/cancel/title/subtext.
- `23d-track-slicer-source-tab`: slice-count copy is gone; remove sample is an
  icon/cross affordance.
- `23e-track-slicer-slice-tab`: waveform uses smaller shared bars.
- `23fa-slice-layer-quick-switch`: selected slice no longer uses a grey filled
  box.
- `27c-audio-playback`: "Rolling capture" text is gone; waveform shows musical
  guides/playhead.
- `29-drum-kit-matrix`: drum-kit matrix uses the tighter track-detail spacing
  and smaller title scale.
- `29a-drum-kit-fx-tab`: Add FX uses the shared empty well grammar.
- `36-drum-kit-matrix-chance-layer`: Apply Template sits in the header near the
  pattern/routing controls.
- `38-drum-kit-matrix-template-chooser`: no title subtitle/rule, no overwrite
  badges, rows show compact pattern previews, and Apply uses app button grammar.
