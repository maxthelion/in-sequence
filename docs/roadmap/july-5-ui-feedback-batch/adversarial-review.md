# Adversarial Review Notes

Status: implementation pass complete; visual proof pending
Reviewed: 2026-07-05
Base: working diff on `codex/july-5-ui-feedback-batch`

This is an adversarial review of the current implementation pass against
`docs/roadmap/july-5-ui-feedback-batch/README.md`. It assumes the build passing
is insufficient and calls out places where the diff can still satisfy the
compiler while missing the product request.

## Fixed Since First Review

- Empty drum-group creation now has a real document path. `Project.addDrumGroup`
  accepts a zero-member plan, the tracks navigator keeps zero-member groups in
  `groupedSections`, and empty kit cells expose `Add Part`.

- Empty-kit `Add Part` is a real mutation. `SequencerDocumentSession.addDefaultDrumPart`
  calls `Project.addDrumPart(groupID:)`, which creates a sample-backed default
  drum part, its clip, its pattern bank, phrase/macro sync, and kit bus routing.

- Track paste now duplicates authored clip material. `Project.duplicateTracks`
  clones any referenced `ClipPoolEntry` values in the copied pattern bank and
  rewrites source refs to the new clip IDs, avoiding accidental shared clip edits.

- Phrase-layer setup has direct additive selection. Command-click always adds to
  phrase-layer track selection; shift-click adds for non-boolean layers while
  preserving the existing boolean shift-click cascade gesture.

- Right-click selection is now automatic for the named matrix cells.
  `StudioRightClickSelection` is a non-consuming AppKit event probe used by
  track cards, kit cards, and phrase-layer cells, so the cell selection is
  updated before SwiftUI opens the context menu.

- The pattern-template control is on the kit page, not the creation modal.
  `DrumKitMatrixView` exposes `Apply Template…`, presents
  `DrumKitTemplateChooserSheet`, previews against the current group/slot, and
  applies through `SequencerDocumentSession.applyPatternTemplate`.

- Unwired kit mixer scene placeholders are gone. The kit mixer row shows the
  real bus output state only; dedicated kit scene-routing controls can be added
  later when they are wired.

- `captureTriggeredStepStrip(snapshot:memberID:)` now uses its supplied
  snapshot rather than taking a second fresh capture snapshot.

## Critical

- No remaining compile-known critical blocker after the 2026-07-05 22:06 build.
  The remaining items below are interaction fidelity or visual-proof gaps, not
  known silent no-op/data-sharing failures.

## Important

- Phrase-layer multi-selection is improved but not identical to tracks.
  Command-click is the reliable additive gesture. Shift-click is selection for
  non-boolean layers only because boolean layers already use shift-click for the
  established forward cascade behavior. This is probably the right compromise,
  but it should be checked by hand.

- Send-return strip height still needs visual proof.
  The code already used `StudioMixerStrip`, and this pass did not materially
  change send-return geometry. The report cannot be marked resolved until a new
  `04-mixer.png` capture proves sends match channel strip height.

- Capture and scene changes now have a fresh screenshot set.
  `scripts/visual-scenarios/qa-surface-coverage.sh` completed with 68 PNGs in
  `.meta/multipass/visual-review/july-5-ui-feedback-batch/` after the
  command/status protocol gained a `visualCommandID` acknowledgment and the
  capture harness was bound to the `NSWindow` that owns the command channel. A
  duplicate audit found zero exact duplicate PNG groups; the first six captures
  are no longer stale repeats. The same set was uploaded to R2 as manifest
  `july-5-ui-feedback-batch-latest`.

## Minor

- Some retired UI remains callable internally.
  `phraseSceneSlotPickerSheet` is no longer opened by the visual command path,
  but the sheet code and state still exist. That is acceptable as a transition,
  but it should be deleted if no remaining normal flow uses it.

- The scene editor no longer exposes the scene name. That matches the report's
  direction, but if rename is still required somewhere, it needs a deliberate
  alternate affordance instead of vanishing accidentally.

## Verification So Far

- `xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
  passed on 2026-07-05 before the critical fixes and again after them at
  approximately 22:06 local time.
- `scripts/diagnostics/ux-canon-lint.sh` passed with zero violations.
- Scoped `git diff --check` over the changed implementation files passed.
- Visual capture now runs by default in a single-agent interactive session. The
  old allow variable is still accepted by compatibility runbooks, but
  coordinators should set `SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION=1` when
  dispatching parallel workers.
- `scripts/visual-scenarios/qa-surface-coverage.sh` completed with 68 screenshots
  after retiring the stale `06a-phrase-scene-select` row, adding command
  acknowledgments, binding capture to the owning window, and syncing the finished
  set to R2.

## Status Update Gate

The code-level silent no-op and shared-clip blockers are fixed, and the fresh
capture set now proves the screenshot-driven rows. Append `Status: RESOLVED
<commit>` to the July 5 intake reports after the final verification pass and
commit hash are available.
