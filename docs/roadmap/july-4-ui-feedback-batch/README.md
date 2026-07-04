# July 4 UI Feedback Batch

Status: proposed goal batch
Created: 2026-07-04
Baseline: `main` at `6d74187a` plus local follow-up `40cf7a03`
Scope: July 4 morning bug reports from `docs/bugs/20260704-075604-*` through
`docs/bugs/20260704-091143-*`.

## Goal

Finish the still-open July 4 morning UI feedback batch, then mark resolved bug
reports in `docs/bugs/` with concrete status lines and refresh visual evidence.

This is mostly UI/interaction polish. It should not touch audio-engine timing,
routing invariants, realtime paths, or AU scheduling.

## Already Checked

Before creating this batch, repo history was checked for duplicate in-flight
work:

- `git worktree list --porcelain` showed active worktrees for `main`,
  `audio-routing-cleanup`, `fix/record-arm-crash-v2`,
  `feat/generator-pitch-cleanup`, `fix/slicer-polish`, and
  `fix/audio-idle-cleanup`.
- `git reflog --all --date=iso --since='2026-07-04 07:00'` showed only the
  July 4 UI-fix lanes `fix/audio-idle-cleanup`, `feat/generator-pitch-cleanup`,
  and `fix/slicer-polish`; all were merged into `main`.
- No reflog entries were found for the still-open scenes, phrase layers,
  library, randomize, FX empty state, or mixer/routing items.
- Registered worktrees did not contain hidden uncommitted source changes for
  this batch. Dirty state was visual evidence / `.meta/work-specs`, one
  `pbxproj` in `ux-batch`, and unrelated root work.
- Older scene/phrase/mixer branches exist, but predate this feedback and are
  either contained in `main` or stale/diverged. Do not assume they implement
  this batch.

## Done Or Mostly Done

These should be verified once, then marked resolved with exact commit evidence
if still true:

- `20260704-090248-i-m-a-bit-confused-about-this-view-it-sa`: chord generator
  now appears on a poly track rather than a mono track.
- `20260704-090801-track-steps-are-too-busy-they-should-use`: slicer velocity
  cells use number-above-border plus a single inset bar.
- `20260704-091036-layers-buttons-should-be-narrower`: slicer layer buttons are
  narrower after natural-width quick-switch work.
- `20260704-091143-orange-text-with-no-input-device-can-go`: audio idle warning
  copy was removed and the surface is tied to the green accent.
- `20260704-153522-the-top-section-of-slicer-normal-track-k`: resolved by
  `40cf7a03` (`fix(track): standardize single-track detail header`).

## Work Items

### Create Track / Library

- `20260704-075604-let-s-put-the-aus-at-the-top-then-sample`
  - Put AU instruments first in the sound chooser.
  - Put sampler next.
  - Move Blank to the bottom as the explicit rejection / leave-empty option.
  - Remove explanatory text.
  - Keep Rescan on the AU Instruments row.

- `20260704-080817-each-item-has-2-plus-signs-which-makes-i`
  - Library rows should not show two ambiguous plus affordances.
  - Keep one clear action per row, or visually disambiguate separate meanings.

### Scenes / Phrase Scenes

- `20260704-075957-take-out-grey-text-on-scenes-i-think-we`
  - Remove grey explanatory text from Scenes.
  - Number scenes.
  - Use consistent A/B slot colours.
  - Make phrase numbers larger.
  - Consider a top-level affordance to enter the phrase perform view.

- `20260704-080437-i-don-t-know-why-that-inputs-thing-is-at`
  - Remove unnecessary Inputs / Choose copy from phrase scene perform.
  - Coordinate A/B slot colours.

- `20260704-080735-too-busy-too-many-interface-containers-e`
  - Replace the busy scene-slot surface with a simple 4x4 scene matrix.
  - Each slot should show a large scene number.
  - Show active state clearly.
  - Empty slots should be dashed-border cells.

### Phrase Layers / Global Apply

- `20260704-080905-each-cell-should-have-a-border-it-s-not`
  - Pattern layer cells all need consistent borders.

- `20260704-081015-each-cell-should-have-a-border-i-think-d`
  - Mute layer cells all need consistent borders.
  - Remove or reconsider inherited dashed treatment if it is not useful.

- `20260704-081150-the-track-cells-matrix-should-disappear`
  - When the layer selector is open, it should replace the track matrix
    in-place.
  - Selector cells should occupy the same location as the cells they replace.

- `20260704-081215-cells-should-be-the-same-height`
  - Global Apply cells should have consistent height.

- `20260704-081347-all-and-clear-should-be-reduced-height-t`
  - Reduce All / Clear button height.
  - Remove washed-out stacked grey backgrounds.

### Track Detail Residuals

- `20260704-084704-can-we-take-out-the-little-pills-within`
  - Verify after `40cf7a03`.
  - Normal, slicer, and audio input should share the compressed kit-like top
    header.
  - Remove remaining duplicated top-section pills/text if any remain.

- `20260704-084929-randomize-is-a-feature-of-clips-the-butt`
  - Randomize should be a clip-header feature.
  - It should replace the step sequencer view instead of opening a modal.

- `20260704-085114-the-blue-dot-on-the-4-pattern-button-is`
  - Remove confusing pattern/config dots.
  - Put the config affordance in the track header rather than a separate line.

- `20260704-085200-this-should-just-have-a-big-plus-button`
  - Empty FX state should use a large plus add-card, likely dashed-border.

- `20260704-085439-this-is-very-grey-the-instrument-and-des`
  - Make the Mixer tab less grey.
  - Remove unnecessary Instrument / Destination line.
  - Keep Output useful.
  - Replace Scene dropdown with three clear buttons.
  - Reconsider whether Sends belong here or only on Mixer.

- `20260704-085618-the-layer-buttons-should-be-less-long-to`
  - Finish layer button placement/narrowness.
  - Treat per-step macro automation as follow-up unless explicitly scoped into
    this batch.

### Generator Residuals

- `20260704-085910-mono-generator-text-is-unreadable-i-m-no`
  - Improve low-contrast generator text.
  - Remove unclear "Following None" treatment or make it meaningful.
  - Remove unnecessary top steps and "Generator controls Euclidean" copy.

- `20260704-090019-pitch-modifier-and-pitch-expander-headin`
  - Remove unnecessary pitch modifier / expander headings.
  - Verify or add the mini-piano pitch-pool treatment.

- `20260704-090330-this-is-also-confusing-the-pitch-modifie`
  - Remove confusing pitch modifier lane treatment from chord-consumer view.

### Slicer Residuals

- `20260704-090514-layer-button-should-go-on-same-line-as-l`
  - Verify after `40cf7a03`.
  - Layer, lane, and length should use consistent placement across normal and
    slicer tracks.

- `20260704-090836-this-bottom-section-is-very-grey-with-us`
  - Further simplify slicer Source tab.
  - Reduce grey framed bottom section and useless text.

- `20260704-091011-very-grey-and-washed-out-the-rounded-cor`
  - Further simplify slicer Slice tab.
  - Clean up rounded-corner nesting relative to parent.
  - Remove duplicate text.

## Acceptance

- All listed bug reports have either `Status: RESOLVED <commit>` or a deliberate
  `Status: WONTFIX <reason>` line.
- Fresh QA visual captures cover the changed surfaces.
- `scripts/bug-status.sh --open` no longer lists the resolved July 4 morning
  reports.
- Debug app build passes.

## Suggested Verification

- Run a Debug build:
  `xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- If visual automation is pre-authorized, run
  `scripts/visual-scenarios/qa-surface-coverage.sh`.
- If visual automation is not authorized, record that evidence is blocked by
  `capture-permission-or-focus` and rely on source/build evidence until an
  interactive capture pass is available.
