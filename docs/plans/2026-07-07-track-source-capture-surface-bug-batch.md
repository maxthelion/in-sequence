# Goal: Track Source, Capture, Kit, and Sampler Surface Bug Batch

Status: proposed
Created: 2026-07-07
Checkout: `/Users/maxwilliams/dev/in-sequence`

## Objective

Resolve the July 7 UI/behavior bug batch as one coherent surface repair rather
than as isolated screenshot tweaks.

The bugs cluster around a single product problem: track source editing,
generator editing, clip capture/history, drum-part editing, kit capture, and
sampler sound editing do not currently share a reliable working grammar. Some
surfaces expose implementation language ("Source", modifier plumbing, "No sound
source"), some hide primary controls in the wrong place, some omit capture
coverage, and some behaviors are not pinned well enough to trust a visual-only
fix.

The target is a set of track-working surfaces that:

- expose primary work directly, not through extra modal hops;
- use one compact toolbar/header grammar for source, generator, clip, sound,
  capture, and close actions;
- use rotaries, dropdowns, segmented controls, and history strips consistently;
- remove dead or deferred affordances from the visible UI;
- publish deterministic screenshot coverage for every repaired state;
- include behavior tests for non-visual regressions such as save-to-pattern,
  right-click selection, and retained source/capture state.

## Source Bug Reports

This goal covers the file-backed bug reports created in the July 7 UI batch:

- `docs/bugs/20260707-095425-modal-for-an-fx-on-a-mixer-bus-doesn-t-f/`
- `docs/bugs/20260707-104637-include-the-pitch-generator-in-the-captu/`
- `docs/bugs/20260707-105143-similar-treatment-for-triggers-as-for-pi/`
- `docs/bugs/20260707-105626-on-clip-view-the-elements-above-the-step/`
- `docs/bugs/20260707-105805-add-the-add-source-view-to-the-captures/`
- `docs/bugs/20260707-105921-right-clicking-a-track-in-the-tracks-vie/`
- `docs/bugs/20260707-110157-on-the-kit-view-the-name-of-the-drum-par/`
- `docs/bugs/20260707-110401-include-the-generator-mode-for-drum-part/`
- `docs/bugs/20260707-110758-the-sound-page-for-a-sampler-is-missing/`
- `docs/bugs/20260707-111802-the-capture-page-for-a-kit-is-quite-bugg/`

The two July 7 tick-path crash reports are not part of this UI batch. If they
are still open, route them through the audio/runtime crash safety queue; do not
mix them into this visual/source workflow goal.

## Lessons From The Generator Goal Miss

This section is binding. Do not mark this goal complete unless every item below
has evidence.

The previous generator goal was reported complete too early because the plan
contained correct intentions but allowed weak proof:

- "Bake should match playback" did not explicitly ban the old `previewNotes`
  bake shortcut.
- "State key candidate" allowed an implementation to omit slot identity.
- Modifier behavior was not pinned for active modifiers.
- Tests used shortcuts such as pattern overrides, nil chord context, and
  bypassed-only modifier cases.

For this goal, every requirement needs at least one of:

- a behavior/unit test that fails on the old behavior;
- a deterministic command-channel visual state and screenshot;
- a code-path assertion or lint that forbids the old shape;
- a documented manual smoke step only when the behavior cannot be automated.

Do not accept "looks nicer" as proof. Do not accept a capture row unless the
row actually drives the intended state and waits on an honest status key. Do not
accept a UI cleanup if the old action is still reachable through the visible
surface unless the spec explicitly says it should remain.

## Product Canon Applied

Use `docs/ux-canon.md` as the taste baseline, especially:

- Rule 1: state named in a header is not repeated in cells.
- Rule 2: the whole cell is the control.
- Rule 3: no explainer prose on working surfaces.
- Rule 4: edit in place.
- Rule 5: one grid grammar.
- Rule 6: tokens, never raw chrome.
- Rule 7: text never deforms.
- Rule 8: nothing clips, everything scrolls.
- Rule 10: progressive disclosure, grouped flows.
- Rule 12: color identifies, it never floods.

This goal should not create a new visual language. Prefer existing shared
components such as `StudioSegmentedControl`, `StudioModeSegmentedPill`,
`TrackSourceActionButton`, standard icon buttons, shared rotaries, and
StudioTheme/StudioMetrics tokens.

## Non-Negotiable Semantics

### Source Editing

The user is editing the active pattern slot. Avoid exposing implementation
terms when the user's mental model is "clip", "generator", "sound", "capture",
"history", and "pattern slot".

- Do not show the word "Source" as a visible section label on the drum-part
  generator surface.
- Do not show modifier controls for drum parts in this batch.
- Do not hide add-source behind a second click when a slot is empty.
- Retained generator/clip semantics from
  `docs/plans/2026-07-07-generator-source-bake-architecture.md` must remain
  intact.

### Generator Editing

Trigger and pitch are peer stages of one generator editor. They should share a
compact top-line grammar, not two unrelated forms.

- Bake belongs in the generator editor top line with the close/cross action.
- Trigger/Pitch switching belongs in the shared stage selector.
- Generator names should be user-meaningful. Remove useless labels such as
  "Mono Generator 2" when they are only generated pool ordinals.
- Euclidean trigger controls should be immediately visible and evenly arranged.
- Pitch controls should use the correct control type: piano key strip for pitch
  class selection, rotaries for continuous/numeric controls, dropdown for scale.

### Capture And History

Capture is a first-class track/kit workflow, not an afterthought:

- Capture history should be visible as a mini history strip/bar where the user
  chooses the captured take.
- Selecting a history cell changes the displayed capture.
- Save-to-pattern should clearly arm/pulse the pattern bar.
- Selecting a pattern while save is armed writes to that slot and stops the
  pulsing.
- Pattern selection must not corrupt or unexpectedly mutate the captured output.

### Visual Evidence

Every repaired surface must have deterministic capture coverage through
`scripts/visual-scenarios/qa-surface-coverage.sh` or a focused scenario script.
If a required state cannot be driven through the command channel, add command
support in `Sources/UI/VisualScenarioCommandRunner.swift` and the owning view.

Do not manually copy screenshots into the gallery. Use:

```sh
PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
  scripts/visual-scenarios/qa-surface-coverage.sh

bug-reporter absorb-captures "$TMPDIR/in-sequence-captures/qa-$USER" \
  --project in-sequence \
  --source qa-surface-coverage
```

## Scope

In scope:

- mono/poly generator trigger editor layout;
- mono/poly generator pitch editor layout;
- drum-part generator mode layout;
- track clip editor top controls and capture history entry point;
- empty pattern slot add-source surface;
- Tracks page secondary-click behavior;
- kit/drum-part row header layout;
- sampler sound page populated and empty-source states;
- kit capture history/save-to-pattern flow;
- mixer/FX insert editor modal sizing;
- visual command/status/capture coverage for the above.

Out of scope unless directly required by the acceptance criteria:

- new generator algorithms;
- full modifier-generator UX;
- broad color-system migration beyond the touched surfaces;
- AU plug-in permission/runtime work;
- audio graph crash fixes;
- replacing the whole track/kit architecture.

## Likely Code Touchpoints

Primary UI:

- `Sources/UI/TrackSource/TrackSourceEditorView.swift`
- `Sources/UI/TrackSource/TrackSourceSourceTabContent.swift`
- `Sources/UI/TrackSource/TrackSourceSourceWell.swift`
- `Sources/UI/TrackSource/TrackSourceSlotWellTabBar.swift`
- `Sources/UI/TrackSource/TrackSourceActionButton.swift`
- `Sources/UI/TrackSource/Generator/GeneratorParamsEditorView.swift`
- `Sources/UI/TrackSource/Generator/StepAlgoEditor.swift`
- `Sources/UI/TrackSource/Generator/PitchAlgoEditor.swift`
- `Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift`
- `Sources/UI/StepGridView.swift`
- `Sources/UI/TracksMatrixView.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+Capture.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+Header.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixRowView.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+VisualCommand.swift`
- `Sources/UI/SamplerDestinationWidget.swift`
- `Sources/UI/FX/FXInsertEditorSheet.swift`

Session/document behavior:

- `Sources/App/SequencerDocumentSession+Mutations.swift`
- `Sources/App/SequencerDocumentSession+TrackSourceSlotModifiers.swift`
- `Sources/Document/Project+TrackSources.swift`

Capture harness:

- `Sources/UI/VisualScenarioCommandRunner.swift`
- `scripts/visual-scenarios/qa-surface-coverage.sh`
- focused scenarios under `scripts/visual-scenarios/` if broad QA coverage
  becomes too slow/noisy for behavioral capture states.

## Implementation Phases

### Phase 0: Baseline And Red Tests

Before touching UI implementation, write down baseline evidence.

- Read every source bug report listed above.
- Capture or inspect the current screenshot for every bug with an image.
- Add failing or characterization tests where behavior matters:
  - secondary click on a track card selects it and does not expose a context
    menu;
  - kit capture save-to-pattern arms, writes one selected slot, and disarms;
  - capture history selection changes the displayed capture index/content;
  - empty slot add-source is represented by a single inline surface.
- Add/adjust visual command statuses before adding capture rows when the current
  command channel cannot prove the state.

Acceptance:

- The implementation artifact cites this plan and the bug dirs.
- At least one test or visual status exists for each behavioral issue.
- Any missing automation is explicitly listed under "manual smoke required",
  not silently skipped.

### Phase 1: Shared Source/Generator Chrome

Create or consolidate the shared grammar for source/generator editors.

Requirements:

- A compact top line contains:
  - meaningful generator/source title;
  - stage selector when editing a generator;
  - Bake action when applicable;
  - close/cross action at the far right.
- Remove useless generated ordinal text from the visible generator header.
- The top line should not repeat "Mono Generator" as both title and subtitle.
- Top line controls fit at the minimum supported app width without clipping.
- The generator editor body starts with the important controls, not a decorative
  summary/header.

Acceptance:

- Mono generator trigger and pitch screenshots show one top-line grammar.
- The old large header row with "Gen / Mono Generator 2 / Mono Generator" is
  gone or reduced to meaningful, non-redundant content.
- Bake is not stranded in a second row.
- The close/cross is aligned to the top-right action cluster.
- No visible explainer prose is added.

### Phase 2: Pitch Generator Editor

Source bug:

- `docs/bugs/20260707-104637-include-the-pitch-generator-in-the-captu/`

Requirements:

- Add pitch generator state to the capture suite.
- Reorganize pitch editing around the controls the user actually changes.
- Piano key/pitch-class strip appears across the top of the pitch body as the
  first body element.
- Root note is a rotary.
- Spread is a rotary.
- Selection is either:
  - converted to a clearly named rotary if it is a numeric probability/choice
    control; or
  - renamed/reworked if "Selection" is not a real user concept.
- Scale is a dropdown/menu using a standard aesthetic component, not a full
  row of loose prose.
- Labels are compact and aligned; values are close to their controls.

Acceptance:

- `qa-surface-coverage.sh` has a pitch capture row that reaches the pitch stage
  and waits on `trackGeneratorStage=pitch` or a more specific rendered status.
- The capture shows:
  - the pitch-class keyboard as the first pitch body item;
  - root/spread/selection as matching rotaries;
  - scale as a compact dropdown/menu;
  - Bake and close in the top line.
- No "Generator 2" pool ordinal is visible.
- No unrelated trigger controls appear in the pitch capture body.
- `scripts/diagnostics/ux-canon-lint.sh` passes.

### Phase 3: Trigger Generator Editor

Source bug:

- `docs/bugs/20260707-105143-similar-treatment-for-triggers-as-for-pi/`

Requirements:

- Trigger view uses the same top-line grammar as pitch.
- The Trigger/Pitch selector is a shared stage switch, not an unrelated wide
  segmented body row.
- Manual trigger is not shown in this slice.
- Euclidean is the active default for mono generator trigger editing.
- Euclidean rotaries are all visible by default and the same size.
- Rotaries are arranged on a balanced four-column grid.
- Remove the ellipsis/menu in the top-right of the Euclidean control area.
- Bake is in the top line.

Acceptance:

- Trigger capture shows the Euclidean rotary grid without requiring a dropdown
  or ellipsis.
- The grid includes the required Euclidean controls from the current data model
  (pulses, steps, offset, velocity/gate if still part of the trigger/shape
  cluster).
- Manual trigger mode is not visible.
- Trigger and Pitch captures share the same top-line structure.
- Visual capture coverage includes the trigger state and waits on an honest
  rendered status.

### Phase 4: Drum-Part Generator Mode

Source bug:

- `docs/bugs/20260707-110401-include-the-generator-mode-for-drum-part/`

Requirements:

- Include drum-part generator mode in capture coverage.
- Remove the word "Source" from the visible drum-part source/generator surface.
- Remove modifier controls from drum-part generator mode for now.
- Add Euclidean mono controls mirroring the mono track generator editor grammar.
- A drum part can show clip mode and generator mode without looking like a
  half-built developer stub.

Acceptance:

- There is a deterministic capture row for drum-part generator mode.
- The capture shows a drum part in generator mode with Euclidean controls.
- It does not show "Source".
- It does not show "Modifier" or "Add modifier".
- The controls use the same rotary/grid grammar as mono trigger editing.
- Existing drum-kit matrix generator/read-only captures still pass.

### Phase 5: Clip Editor Header And Capture Entry

Source bugs:

- `docs/bugs/20260707-105626-on-clip-view-the-elements-above-the-step/`
- `docs/bugs/20260707-105805-add-the-add-source-view-to-the-captures/`

Requirements:

- On the clip editor, controls above the step sequencer align vertically.
- Labels sit to the left of their controls where that improves scan/read order.
- The close/cross moves to the right side of the header/action row.
- Add a capture button that opens a clip history view.
- The history view should take cues from kit capture/history and the older
  track history concept where appropriate.
- Remove the `Assign Macro` button and the right-side assign macro modal from
  this surface. Macro assignment belongs under the Macros tab.
- Add the add-source/empty-slot surface to capture coverage.
- Roll add-source into the empty view; do not require two clicks to reach the
  add-source choices.

Acceptance:

- Clip editor screenshot shows Lane, Length, Layer, Randomize, Capture/History,
  and close aligned on one coherent row or intentionally grouped rows.
- The last controls are not visually higher than Lane/Length.
- No `Assign Macro` affordance is visible in the clip editor.
- Clicking/toggling the capture/history button opens the history view.
- Empty slot capture shows the add-source choices inline.
- There is no separate intermediate empty state requiring another click before
  choosing Generator/Clip.
- Capture rows exist for:
  - clip editor normal state;
  - clip editor history open;
  - empty slot add-source state.

### Phase 6: Tracks Page Secondary Click

Source bug:

- `docs/bugs/20260707-105921-right-clicking-a-track-in-the-tracks-vie/`

Requirements:

- Secondary-clicking a track card selects the track.
- It must not open the current little context menu.
- The menu items `Select`, `Copy`, and `Mute` should not appear as a secondary
  click menu on track cards.
- If Copy/Mute still need to exist, expose them through intentional visible
  controls or another approved mode, not through this context menu.

Acceptance:

- A UI/unit test or view-model test proves secondary click routes to selection
  and does not present menu state.
- Manual smoke or visual automation confirms right-click on a track card changes
  selection with no context menu.
- The screenshot/capture of the Tracks page no longer shows an AppKit-style
  grey menu over a track card.

### Phase 7: Kit Row Header Stability

Source bug:

- `docs/bugs/20260707-110157-on-the-kit-view-the-name-of-the-drum-par/`

Requirements:

- In kit view, each drum-part row has the part name toward the top.
- The part name is larger and stable in position.
- Expanding a part does not cause the name to jump vertically.
- Remove grey subtext such as `1 bar - 16 steps`.
- The row still has an affordance to open/expand the part, but it should not
  compete with the name.

Acceptance:

- Normal and expanded kit-row captures show the part name at the same top
  position.
- The grey subtext is gone.
- The row remains readable at default and minimum supported widths.
- Any long part name truncates or scales according to UX canon; it does not
  wrap into the step grid.

### Phase 8: Sampler Sound Page

Source bug:

- `docs/bugs/20260707-110758-the-sound-page-for-a-sampler-is-missing/`

Requirements:

- Restore the waveform on the sampler sound page.
- Remove the bottom `Load AU instrument` button from sampler sound page.
- Remove the config button next to the play button that navigates to Macros.
- Empty sound source state shows two dashed-border boxes with plus affordances.
- The two empty boxes sit side by side.
- Remove visible "No sound source" text.
- Populated sampler sound page keeps the useful sample editing controls and
  filter controls, but with the restored waveform and cleaned chrome.

Acceptance:

- Populated sampler sound capture shows a visible waveform, not an empty panel.
- No `Load AU instrument` button is visible.
- No config/settings button next to the play button is visible.
- Empty sampler sound capture shows exactly two dashed add boxes side by side.
- Empty sampler sound capture does not show "No sound source".
- The waveform and empty boxes use Studio tokens and track accent, not raw
  system chrome.

### Phase 9: Kit Capture Page

Source bug:

- `docs/bugs/20260707-111802-the-capture-page-for-a-kit-is-quite-bugg/`

Requirements:

- Replace the current capture controls with one capture bar.
- The capture bar contains:
  - close cross at the top-right/navigation end;
  - mini capture-history strip;
  - capture length selector;
  - save button.
- Remove Audition.
- Remove Live.
- Remove arrow history navigation in favor of the mini history strip.
- Selecting cells in the history strip changes the displayed capture.
- Save capture arms/pulses the pattern bar.
- Clicking Save should pulse the pattern bar, not leave it stuck flashing.
- Selecting a pattern while save is armed writes the displayed capture to that
  clip slot and stops pulsing.
- Pressing pattern buttons must not do weird mutations to the capture output.

Acceptance:

- Kit capture capture row shows one capture bar with history, length, save, and
  close.
- Audition and Live are not visible.
- Arrow history navigation is not visible.
- A behavior test covers:
  - selecting capture history item changes displayed capture;
  - pressing save enters exactly one "choose pattern slot" pending state;
  - selecting pattern slot writes the selected capture to that slot;
  - pending save state clears after selection;
  - the captured output data is not modified by merely choosing a destination.
- Visual command support can drive:
  - capture open;
  - history fixture with at least three cells;
  - selected history cell;
  - save armed/pulsing state;
  - post-save selected slot state.
- `qa-surface-coverage.sh` includes before/after rows or a focused scenario
  publishes equivalent evidence.

### Phase 10: Mixer Bus FX Modal Sizing

Source bug:

- `docs/bugs/20260707-095425-modal-for-an-fx-on-a-mixer-bus-doesn-t-f/`

Requirements:

- FX insert editor modal on a mixer bus fits its content.
- Long AU names do not clip off the left edge or under the toggle.
- Toggle, remove button, and close/navigation affordances are inside the modal
  bounds at the minimum supported modal width.
- Modal content scrolls or reflows rather than clipping.

Acceptance:

- A capture/manual screenshot with a long AU name such as
  `Tokyo Dawn Labs TDR Kotelnikov` shows the full useful title or a polished
  truncation with no clipped leading characters.
- The bypass toggle is fully visible.
- The remove button is visible and not clipped.
- No content extends beyond the modal boundary.

## Capture Coverage Requirements

Update `scripts/visual-scenarios/qa-surface-coverage.sh` and command/status
support as needed. At minimum, the final evidence set must include:

- mono generator trigger editor;
- mono generator pitch editor;
- track clip editor normal controls;
- track clip history open;
- empty slot add-source view;
- tracks page with no secondary-click menu state;
- kit matrix normal rows;
- kit row expanded state;
- drum-part generator mode;
- populated sampler sound page;
- empty sampler sound page;
- kit capture open with history strip;
- kit capture save armed/pattern pulse;
- mixer bus FX modal with a long AU name.

Required capture discipline:

- Each capture row waits on a status that proves the intended state rendered.
- If a row requires new UI state, add that state to
  `VisualScenarioCommandRunner` and the owning view before adding the row.
- Use `QA_SURFACE_CAPTURE_FILTER` during development, then run the relevant
  rows or full QA surface coverage before claiming done.
- Publish screenshots through `bug-reporter absorb-captures`.

## Automated Verification Requirements

Run the narrowest useful tests during implementation, then these gates before
completion:

```sh
xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' \
  -only-testing:SequencerAITests

scripts/diagnostics/ux-canon-lint.sh
scripts/diagnostics/realtime-path-lint.sh
scripts/diagnostics/runtime-ownership-lint.sh
git diff --check
```

If the full `SequencerAITests` suite is too slow/flaky for the working loop,
the implementer may run focused tests first, but the final evidence must list
exactly which tests ran and why any broader test was not run.

Suggested new or updated tests:

- `TracksMatrixViewTests` or equivalent for secondary-click selection/no menu.
- `DrumKitCaptureSessionTests` for history selection and save-to-pattern state.
- `TrackSourceEditorSessionTests` for empty slot add-source path if behavior is
  model-driven.
- Existing sampler/track-source tests updated for empty/populated sound states
  if they exist.

## Manual Smoke Requirements

Manual smoke is required only for interactions the harness cannot drive after a
reasonable command-channel update.

Minimum manual smoke if not automated:

- Right-click a track card: selection changes, no context menu.
- Open the mixer bus FX modal with a long AU name: content fits.
- Open kit capture, choose a history cell, press Save, choose a pattern slot:
  capture writes to that slot and pulse stops.

Manual smoke notes must include exact date, app build/commit, and the observed
result. Do not replace automated tests with vague manual confidence.

## Definition Of Done

All of the following must be true:

- Every source bug report listed in this plan has a corresponding acceptance
  item checked by test, visual evidence, or manual smoke.
- The old unwanted affordances are removed, not merely hidden in the tested
  fixture:
  - track-card context menu;
  - visible drum-part "Source" label;
  - drum-part modifier controls;
  - generator editor ellipsis in the Euclidean block;
  - clip editor Assign Macro affordance;
  - sampler `Load AU instrument` button;
  - sampler config-to-macros button;
  - kit capture Audition/Live/arrow navigation.
- Every new or changed screenshot state is driven by the command channel.
- Captures are published via `bug-reporter absorb-captures`.
- `scripts/diagnostics/ux-canon-lint.sh` passes.
- Audio/runtime lints pass if any engine/session/runtime files were touched.
- The implementation final names every test and capture run.
- Each fixed file-backed bug note gets a `Status: RESOLVED <commit>` line after
  the fixing commit exists.

## Review Requirements

Before marking this goal complete, run a review sequence that explicitly tries
to find missed places:

1. Spec-compliance review:
   - Check each source bug against the final UI and tests.
   - Confirm no acceptance criterion was satisfied by a shortcut.
2. Code-quality review:
   - Check for duplicated layout grammar that should be shared.
   - Check token/canon compliance.
   - Check that deleted affordances are not still reachable by visible UI.
3. Adversarial review:
   - Assume several surfaces were missed.
   - Inspect screenshots and source for old labels/actions.
   - Try to disprove capture rows by checking whether they wait on meaningful
     statuses.

The goal is not complete until the adversarial review has no blocking findings
or the remaining findings are explicitly moved to new bug reports with product
owner agreement.

## Anti-Patterns That Must Not Pass Review

- Adding a screenshot row without adding command/status support for the state.
- Fixing mono generator pitch/trigger but leaving drum-part generator as a stub.
- Restoring sampler waveform while leaving the AU/config buttons.
- Moving Assign Macro instead of removing it from the clip editor surface.
- Replacing the track context menu with a different hidden menu.
- Letting kit capture save change the currently displayed capture output.
- Leaving pattern slots pulsing after a save target is chosen.
- Marking a bug resolved because one viewport looks good while minimum width
  still clips text.
- Marking the goal complete before updating bug notes with `Status: RESOLVED`.

## Open Questions

These should be answered by implementation evidence where possible, not by
asking the product owner unless the code truly cannot infer the answer:

- What exactly should the pitch "Selection" control be named if it is not a
  user-facing concept?
- Which two empty sampler source boxes are the intended choices? Likely sample
  and instrument/source import, but verify against current model capabilities.
- Should Copy/Mute from the removed track context menu move to a visible card
  affordance now, or remain unavailable until a broader track-actions pass?

If an answer changes product behavior materially, record the decision in the
implementation notes before coding past it.

