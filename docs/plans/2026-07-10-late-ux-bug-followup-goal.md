# 2026-07-10 Late UX Bug Follow-up Goal

## Objective

Resolve the thirteen July 10 reports that were either filed after the
`69c37028` capture or omitted from the earlier five-round batch. Treat them as
shared interaction and component problems: visible controls must remain
legible, track scope must be a reusable persisted object, nested scrolling must
have one owner, and drum/audio/chord detail pages must reuse the same grammar as
mono tracks.

Work continues in `codex/20260710-ux-batch`. Preserve the primary checkout's
unrelated dirty state and file-backed bug intake.

## Round 1: Visible Controls And Stable Type

- Give the Tracks type filter an explicit funnel icon and visible selected
  value using the shared menu-picker chrome.
- Make selected and unselected navigator card names use the same fixed text
  style; long names wrap or truncate without shrinking.
- Apply explicit studio foreground/tint roles to drum-group text fields and
  menus so populated rows remain legible in a dark modal.
- Use the full track accent for the step-editor boundary and match the
  selection ring radius to the step cell.

Acceptance:

- Hosted hit tests activate the type filter and selected track card at their
  visible edges.
- Captures `02a-tracks-selection-actions`,
  `02ab-tracks-filter-drum-parts`, `02da-add-drum-group-populated`, and
  `23g-step-edit-rotaries` show legible controls and consistent type.

## Round 2: Persisted Performance Track Groups

- Add a document-owned bank of sixteen optional performance track-group slots.
  Each group has stable identity, name, colour, and ordered track IDs.
- Normalize missing/stale track IDs on decode and when tracks are removed.
  Existing documents decode with an empty bank.
- Replace the disabled `Create performance group` placeholder with
  `Create Track Group`. The modal shows the selected tracks and a 4x4 slot
  matrix; choosing a slot creates or replaces that group.
- Replace Phrase's `All N Tracks` plus ad-hoc per-track selector with a track
  group picker: `All Tracks` followed by occupied group slots. Both By Track
  and By Value use the chosen group's members. No separate selection sheet,
  ticks, All, or Clear controls remain in Phrase.

Acceptance:

- Codable/migration, overwrite, stale-member cleanup, track-removal, and
  ordered-scope tests pass.
- `02a-tracks-selection-actions` shows the real create command; add
  `02ae-create-track-group` for the 4x4 modal.
- `13-phrase-global-apply` shows the group picker and no manual track
  selector. Add one capture with a saved group selected.

## Round 3: Phrase Selection And Scene Gestures

- Keep the Layers/Scenes tabs visible while choosing a layer.
- Remove the selected tick from layer option cells. Clicking any option
  selects it and closes the chooser; repeated clicks are idempotent.
- Secondary-clicking any populated scene cell selects that scene for its slot
  and hard-switches the phrase crossfader to 0% for A or 100% for B. Primary
  click continues to choose the slot scene without forcing the crossfader.

Acceptance:

- Tests prove layer chooser close/idempotence and A/B secondary-click hard
  switching without changing the opposite slot.
- `11-phrase-layer-selector-open` keeps the tabs and has no tick.
- Add `06ba-phrase-scenes-hard-switch` with the requested scene selected and
  the crossfader at the corresponding endpoint.

## Round 4: One Scroll Owner

- Correct shared attached-scroll discovery so it binds to the nearest
  geometrically matching List scroll view, never the outer workspace scroller.
- Hide the native List scroller and show one studio thumb only for insert-list
  overflow. The outer scene editor must not gain a second attached thumb.
- Preserve List reorder, focus, keyboard, and accessibility behavior.

Acceptance:

- Geometry-selection tests cover nested candidate scroll views.
- Existing reorder tests remain green.
- `05b-scenes-edit-content` has no thumb; `05ba-scenes-edit-overflow` has
  exactly one studio thumb and no white native scrollbar.

## Round 5: Track Detail Parity

- Chord config: make the shared piano keyboard consume the available width and
  place Scale controls to its right.
- Audio input: merge Record and Write Target into one recording well. Use a
  standard `Record` command. While recording, replace setup controls with a
  progress waveform plus a `Recording` overlay and Cancel command.
- Drum matrix: replace the Steps/Velocity/Length/Chance segmented row with the
  same layer menu used by mono tracks and show available layers as a quiet line
  beneath it. Replace `1-16` / `17-32` with bar numbers.
- Drum macros: use `MacroSlotKnob` for assigned and empty slots.
- Drum mixer: reuse the mono track mixer layout for output, scene, Send A, and
  Send B, with the kit bus as the output destination.

Acceptance:

- Layout/presentation tests cover chord split widths, audio recording states,
  drum layer/bar labels, macro descriptors, and mixer model parity.
- Captures `23l-track-chord-config`, `27a-audio-source-tab`,
  `29-drum-kit-matrix`, `29b-drum-kit-macros-tab`, and
  `29c-drum-kit-mixer-tab` visibly prove parity. Add an audio-recording
  capture.

## Verification And Closure

Run:

```sh
git diff --check
scripts/diagnostics/ux-canon-lint.sh
scripts/diagnostics/realtime-path-lint.sh
scripts/diagnostics/runtime-ownership-lint.sh
xcodebuild -quiet -project SequencerAI.xcodeproj -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/seqai-20260710-late-ux build
```

Run focused UI/document tests after each round and the full serial
`SequencerAITests` suite at the end. Record the full 92+ row QA run with the
single-window harness, absorb it through bug-reporter, inspect every named row,
then mark all thirteen database and file-backed reports resolved with the final
commit and absorbed run ID.
