# July 5 UI Feedback Batch

Status: implementation pass complete; visual proof pending
Created: 2026-07-05
Baseline: `main` at `9c1744ba`
Scope: bug reports created on 2026-07-05 under `docs/bugs/20260705-*`.

## Goal

Resolve the July 5 UI feedback batch as one coherent visual and interaction
polish pass. The work should make selection, creation modals, scene slots, mixer
strips, drum-kit tabs, and visual evidence captures follow the same product
grammar instead of fixing each screenshot in isolation.

This goal is UI/state polish only. It should not change audio engine timing,
render-thread behaviour, routing invariants, AU scheduling, or realtime paths.

## Current Execution State

Implemented on branch `codex/july-5-ui-feedback-batch`:

- Track navigator cells have stable colour borders, context menus, selection
  actions, right-click selection, copy/paste, and independent pasted clip
  material.
- Phrase-layer cells have context actions for selection/copy/paste/automation,
  right-click selection, plus direct additive selection through command-click
  and non-boolean shift-click.
- Creation modals, scene cards, phrase scene slots, FX wells, kit macro/mixer
  placeholder chrome, and capture layout have been cleaned up per the July 5
  reports.
- Empty drum-kit creation is real: zero-member groups persist, appear in the
  navigator, and expose `Add Part`; kit-page pattern templates remain available
  through `Apply Template...`.

Verified:

- `xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
  passed after the implementation pass.
- `scripts/diagnostics/ux-canon-lint.sh` passed with zero violations.
- Scoped `git diff --check` over the changed implementation files passed.
- `scripts/visual-scenarios/qa-surface-coverage.sh` now uses an acknowledged
  `visualCommandID` handshake before trusting status waits, and the app binds
  the command runner to the owning `NSWindow` before screenshots are taken. The
  original branch capture set completed under the legacy visual-review/R2-sync
  path. New capture runs should record to
  `$TMPDIR/in-sequence-captures/qa-$USER` and publish with `bug-reporter
  absorb-captures`.
- Duplicate-state audit found zero exact duplicate PNG groups after the command
  acknowledgment fix. The first six captures are visually distinct.

Still pending before closing bug reports:

- Mark the July 5 bug reports `Status: RESOLVED <commit>` only after the capture
  evidence proves the relevant views.
- See `adversarial-review.md` for remaining interaction-risk notes and capture
  audit observations.

## Preflight Already Checked

- `git worktree list --porcelain` showed active worktrees for `main`,
  `feature/mixer-strip-followup`, `feature/track-phrase-perform-mini-cells`,
  and older unrelated feature/fix worktrees.
- `git reflog --all --date=iso --since='2026-07-05 00:00'` showed
  `feature/mixer-strip-followup` and `feature/track-phrase-perform-mini-cells`
  were merged into `main` earlier today.
- Treat this plan as remaining work after those merges. Do not assume older
  worktrees contain hidden implementations for these July 5 reports without
  checking their diffs first.
- The July 5 bug report directories are currently untracked intake files. Keep
  status edits scoped to the reports this goal resolves.

## Source Reports

- `20260705-102035-all-tracks-should-have-a-border-that-is`
- `20260705-102540-when-a-track-is-selected-allow-copy-and`
- `20260705-102958-right-click-a-cell-here-to-show-more-men`
- `20260705-103104-the-text-should-be-bigger-maybe-centrall`
- `20260705-150256-let-s-leave-out-the-routing-part-it-shou`
- `20260705-150325-get-rid-of-grey-subtext-and-line-after-h`
- `20260705-193532-let-s-make-the-aus-one-colour-border-the`
- `20260705-193605-the-send-channels-should-be-the-same-hei`
- `20260705-193840-the-big-number-in-each-cell-should-be-ce`
- `20260705-193958-we-don-t-need-scene-name-at-the-top-perh`
- `20260705-194029-get-rid-of-the-2-8-text-above-macros`
- `20260705-194506-we-don-t-need-this-with-the-new-slot-vie`
- `20260705-194642-the-whole-of-the-top-of-each-slot-should`
- `20260705-194854-this-would-be-a-more-useful-capture-if-i`
- `20260705-195208-the-empty-fx-well-should-be-black-not-gr`
- `20260705-195311-get-rid-of-kit-wide-macro-sweeps-text-ma`
- `20260705-195340-this-is-now-inconsistent-with-other-trac`
- `20260705-195724-this-is-quite-messy-get-rid-of-the-captu`
- `20260705-195817-this-needs-to-be-less-grey-and-low-contr`

## Holistic Patterns

### Selection And Cell Actions

Track grid cells and phrase-layer cells should share one interaction grammar:
visible colour borders, right-click selection/context menus, additive selection,
and direct copy/paste actions where a selected value or track can reasonably be
copied.

Target reports:

- `20260705-102035-*`
- `20260705-102540-*`
- `20260705-102958-*`

Likely files:

- `Sources/UI/TracksMatrixView.swift`
- `Sources/UI/PhraseWorkspaceView.swift`
- Supporting selection/action helpers if duplication appears during the change.

Work:

- Give every track cell a stable border matching its track colour.
- Remove or replace unexplained purple/grey top-right cell affordances.
- Make right-click on a track cell select it and open the relevant menu.
- Make shift-left-click add to an existing track selection.
- Add selected-track copy/paste actions next to Delete.
- Add a Perform menu section with `By Track` and `By Value` choices.
- In phrase-layer setup cells, add right-click menu actions for Copy Value and
  Paste Value.
- Support multi-selection in phrase-layer setup mode using the same feel as the
  tracks view.
- Show Automation only when a single phrase-layer cell is selected; it should
  open the existing automation modal if that state already exists.
- Remove the phrase-layer value pill if it is not carrying actionable state.
- If some phrase-layer actions must be unavailable while Perform is on, gate
  them explicitly and keep setup-mode behaviour complete.

Acceptance:

- Right-click selection works for both track cells and phrase-layer cells.
- Multi-select behaviour is deterministic and visible.
- Copy/paste actions are present only when they have a valid source/target.
- Fresh captures for `02-tracks-navigator.png`,
  `02a-tracks-selection-actions.png`, and
  `02b-tracks-layer-perform-nav.png` show distinct states.

### Creation Modal Chrome

Creation flows should stop using explanatory grey text, title rules, and
ambiguous disabled bottom actions. Cards should read as direct choices.

Target reports:

- `20260705-103104-*`
- `20260705-150256-*`
- `20260705-150325-*`
- `20260705-193532-*`

Likely files:

- `Sources/UI/Track/CreateTrackFlow.swift`
- `Sources/UI/Theme/StudioCards.swift`
- `Sources/UI/DrumGroup/AddDrumGroupContent.swift`
- `Sources/UI/Track/AddSliceTrackContent.swift`

Work:

- Make the first create-track modal cards use larger, centered text.
- Remove the decorative heading rule after `Track` in create-track steps.
- In the sound step, make AU choices use one border colour, Sampler choices a
  second border colour, and Leave Blank a third.
- Keep AU Instruments first, Sampler second, Leave Blank last.
- Remove grey subtext and the heading rule from the slice loop picker.
- In the drum-group creation modal, remove the Routing section and default to a
  new dedicated bus.
- Remove the Sounds and Patterns section title/rule chrome.
- Move clip-template/pattern setup out of the creation modal and onto the kit
  page, or remove it from creation until the kit-page control exists.
- Allow creating an empty kit; provide an Add Part action on the kit page rather
  than disabling the modal's primary action without explanation.

Acceptance:

- Creation modals present direct choices without low-contrast explanatory copy.
- Empty-kit creation is possible and the next place to add parts is visible.
- Fresh captures for `02c-create-track-modal.png`,
  `02d-add-drum-group-modal.png`,
  `02e-add-slice-track-loop-picker.png`, and
  `02f-create-track-sound-step.png` reflect the cleaned grammar.

### Scene And Phrase Slot Grammar

Scenes and phrase-scene slots should use one slot grammar: big centered numbers,
simple A/B slot markers, border colour for selected slot membership, and no
duplicated titles or counts.

Target reports:

- `20260705-193840-*`
- `20260705-193958-*`
- `20260705-194029-*`
- `20260705-194506-*`
- `20260705-194642-*`

Likely files:

- `Sources/UI/Mixer/ScenesWorkspaceView.swift`
- `Sources/UI/PhraseWorkspaceView.swift`

Work:

- Center the big scene number in each browse cell.
- Remove duplicated number/name treatments from scene cards.
- Replace `A:1` / `B:2` pills with simple `A` / `B` pills.
- Use border colour to show whether the selected scene belongs to slot A, slot
  B, both, or neither.
- In scene edit, remove the editable scene name header unless a direct rename
  affordance is deliberately retained elsewhere.
- Replace the scene edit header with just the scene number and remove the blue
  underline.
- Remove the `2 / 8` macro count above scene macros.
- Retire the old phrase scene select sheet if the new slot view has replaced
  it; remove its capture row or change the row to prove it is gone.
- In phrase scene perform, make the top of each slot a large `A:1` / `B:2`
  style label with no separate `Slot A` title or scene-name duplication.

Acceptance:

- Scene browse, scene edit, and phrase scene perform all use the same slot
  language.
- There is no dead phrase scene select modal reachable from the normal flow.
- Fresh captures for `05-scenes-browse.png`,
  `05a-scenes-edit-empty.png`, `05b-scenes-edit-content.png`,
  `06-phrase-scenes-perform.png`, and `06b-phrase-scenes-perform-slots.png`
  prove the state. `06a-phrase-scene-select.png` is retired because the old
  selector sheet no longer exists.

### Mixer And Drum-Kit Parity

Send returns, drum-kit mixer routing, FX empty wells, macro controls, and kit
matrix parts should match the visual treatment used by normal track detail
views.

Target reports:

- `20260705-193605-*`
- `20260705-195208-*`
- `20260705-195311-*`
- `20260705-195340-*`
- `20260705-195817-*`

Likely files:

- `Sources/UI/Mixer/MixerWorkspaceView.swift`
- `Sources/UI/MixerView.swift`
- `Sources/UI/Theme/StudioMixerStrip.swift`
- `Sources/UI/FX/InsertChainComponents.swift`
- `Sources/UI/Track/TrackFXChainView.swift`
- `Sources/UI/DrumGroup/KitBusFXChainView.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+KitTabs.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixRowView.swift`

Work:

- Make send return channels the same height and visual weight as other mixer
  channels.
- Make empty FX wells black/dark rather than grey across track types and the kit
  bus. Do this at the FX empty-state component level if one exists.
- Remove `Kit-wide macro sweeps` placeholder text.
- Make kit macro rotaries use the same component and background treatment as
  the other macro views.
- Replace unwired kit mixer placeholders with the same scene routing grammar
  used by other tracks, or remove them until wired.
- Remove grey row/subpanel backgrounds from drum kit part cells, especially on
  the velocity layer.

Acceptance:

- Mixer send returns align with the main strips.
- FX empty states are dark and consistent across mono/poly/slicer/audio/kit.
- Drum-kit macro and mixer tabs no longer look like placeholder panels.
- Drum kit velocity layer has no washed-out grey cell backgrounds.
- Fresh captures for `04-mixer.png`, `29a-drum-kit-fx-tab.png`,
  `29b-drum-kit-macros-tab.png`, `29c-drum-kit-mixer-tab.png`, and
  `35-drum-kit-matrix-velocity-layer.png` show the corrected states.

### Capture Save And Evidence Rows

The capture UI and screenshot script should prove the intended state instead of
recording repeated or misleading surfaces.

Target reports:

- `20260705-194854-*`
- `20260705-195724-*`

Likely files:

- `Sources/UI/TrackSource/TrackSourceEditorView.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView+Capture.swift`
- `Sources/UI/DrumGroup/DrumKitMatrixView.swift`
- `Sources/UI/VisualScenarioCommandRunner.swift`
- `scripts/visual-scenarios/qa-surface-coverage.sh`

Work:

- Change the track fill preview visual scenario so
  `20-track-fill-preview-active.png` shows the step sequencer with fill preview
  active.
- Remove the Capture History title/rule from the kit capture save surface.
- Compress per-part capture previews to triggered steps rather than pitch-like
  lanes.
- Put one clear border around the capture save bottom area.
- Move Save Capture into the menu/control strip above the UI, not below it.
- When capture save slot selection is active, show pattern numbers at the top;
  a subtle pulse is acceptable until a selection is made.
- After capture script changes, audit output for accidental duplicate states.

Acceptance:

- `20-track-fill-preview-active.png` no longer duplicates a generic track detail
  or modal state.
- `29f-drum-kit-capture-save-slot.png` shows the simplified capture save flow.
- The first six captures and later track-detail captures are no longer
  accidentally identical except where the filenames intentionally represent the
  same state.

## Execution Order

1. Create a focused branch or worktree from `main` for this goal.
2. Re-run `scripts/bug-status.sh --open` and confirm the 19 July 5 reports are
   still open.
3. Implement selection/cell actions first, because later captures depend on
   selected states being visible.
4. Implement creation modal cleanup.
5. Implement scene and phrase slot grammar.
6. Implement mixer/drum-kit parity.
7. Implement capture-save and visual scenario fixes.
8. Run the verification commands below.
9. Append `Status: RESOLVED <commit>` to each July 5 bug report that is fixed.
10. Commit the implementation and status updates logically.

## Verification

Required:

```sh
xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
scripts/bug-status.sh --open
```

Run if UI source files changed and the script exists:

```sh
scripts/diagnostics/ux-canon-lint.sh
```

Run in an interactive single-agent session:

```sh
PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
  scripts/visual-scenarios/qa-surface-coverage.sh

bug-reporter absorb-captures "$TMPDIR/in-sequence-captures/qa-$USER" \
  --project in-sequence \
  --source qa-surface-coverage
```

`SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1` is accepted by older runbooks but is no
longer required. Coordinators that dispatch parallel agents should instead set
`SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION=1` to stop workers from taking over the
desktop. The capture script records PNGs and notes only; `bug-reporter
absorb-captures` owns the R2 upload and gallery filing.

Then audit the captures for duplicate or stale states:

```sh
find "$TMPDIR/in-sequence-captures/qa-$USER" -maxdepth 1 -type f -name '*.png' | sort
```

## Definition Of Done

- Every July 5 source report listed above has either
  `Status: RESOLVED <commit>` or a deliberate owner-approved
  `Status: WONTFIX <reason>` line.
- The debug build passes.
- Fresh visual captures cover every affected screenshot row.
- Capture output has been checked for duplicated states, especially the first
  six captures and the track-detail rows around `18` through `20c`.
- If visual automation is blocked by permission/focus, record that explicitly
  as evidence rather than marking screenshot-dependent items resolved.
- The final commit message names the July 5 UI feedback batch and references
  the resolved report set.
