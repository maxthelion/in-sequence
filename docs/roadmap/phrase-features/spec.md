---
feature: phrase-features
created: 2026-06-04
status: PM spec; not builder-ready until plan and implementation handoff exist
sources:
  - README.md
  - docs/roadmap/phrase-features/notes.md
  - docs/roadmap/phrase-features/user-stories.md
  - docs/roadmap/phrase-features/existing-state.md
  - docs/roadmap/phrase-features/artifacts.md
  - docs/roadmap/phrase-features/ux-review.md
  - docs/roadmap/phrase-features/architecture.md
---

# Phrase Features Spec

## Product Contract

Phrase Features makes phrases a directly editable arrangement/performance unit
from the phrase matrix. A user can set phrase length, repeat policy, and
phrase-local loop behavior from the phrase button; perform against the current
phrase without immediately overwriting it; save staged perform edits back when
they choose; and navigate the matrix with stable grid-aligned controls.

This spec covers the v1 product surface for:

- phrase bar count;
- phrase repeat count;
- phrase permanent loop toggle;
- phrase perform-mode save-back and revert;
- matrix page arrows with occupancy hints;
- fixed-width layer selection.

This is a builder-facing product contract. It is not an implementation plan.

## Definitions

- **Phrase button**: the phrase row-header control currently labeled with names
  such as "Phrase A".
- **Phrase cycle**: one full playback of a phrase from step 0 through
  `lengthBars * stepsPerBar - 1`.
- **Repeat count**: the number of phrase cycles to play before automatic song
  advancement. `0` means unlimited.
- **Permanent loop**: a phrase-local toggle that forces unlimited looping while
  enabled, regardless of repeat count.
- **Basis phrase**: the phrase that perform mode is currently using as the
  canonical source for staged edits.
- **Overlay**: runtime/session-only staged phrase-cell edits that can be saved
  back or reverted.

## Phrase Button Controls

### Observable Behavior

- The collapsed phrase button continues to show phrase name and bar count.
- The collapsed phrase button also shows enough repeat/loop state to explain
  the effective playback behavior:
  - finite repeat count: for example, "1x", "4x";
  - unlimited repeat count: "loop";
  - permanent loop enabled: visually distinct loop badge.
- Selecting a phrase button selects that phrase.
- Opening phrase controls happens inline in the matrix area, not in a separate
  settings screen or detached modal.
- Only one phrase control panel needs to be open at once in v1. Opening another
  phrase's controls closes the previously open panel.
- Long phrase names truncate with a tooltip/accessibility label containing the
  full name. Production UI must not shrink phrase names to unreadable sizes.

### Bar Count

- `lengthBars` is editable from the phrase button controls.
- V1 valid range: `1...64` bars.
- Existing documents keep their current `lengthBars`; new default phrases still
  default to 8 bars.
- Changing bar count updates the phrase playback/edit boundary immediately.
- Shrinking bar count is non-destructive where existing storage allows it:
  authored cell data beyond the new boundary becomes out of the active window
  but is not silently deleted just because the phrase got shorter.
- Increasing bar count can expose previously authored out-of-window cell data
  again when that data still exists.

### Repeat Count

- `repeatCount` is editable from the phrase button controls.
- V1 valid range: `0...64`.
- `0` means unlimited repeat.
- Default for older documents and new phrases is `1`.
- A finite repeat count of `1` means play the phrase once, then advance at the
  next phrase boundary.
- The UI must communicate the effective playback behavior in plain terms near
  the controls, because repeat count `0` and permanent loop both produce an
  unlimited result.

### Permanent Loop Toggle

- `loopEnabled` is a persisted phrase-level boolean editable from the phrase
  button controls.
- Default for older documents and new phrases is `false`.
- When `loopEnabled` is true, the phrase repeats forever until the user disables
  the toggle, queues another phrase, or otherwise changes playback state through
  an existing transport action.
- When `loopEnabled` is true, the repeat-count control may be visually
  deemphasized or disabled, but its stored value must be preserved for when the
  toggle is turned off.
- Effective playback precedence is:
  - queued phrase promotion at a phrase boundary wins;
  - otherwise `loopEnabled == true` repeats forever;
  - otherwise `repeatCount == 0` repeats forever;
  - otherwise finite repeat count controls automatic advancement.

## Playback Advancement

### Observable Behavior

- Song advancement uses central phrase-navigation policy, not duplicated
  view-only phrase-index calculations.
- At a phrase cycle boundary, the current phrase's repeat/loop policy determines
  whether playback stays on the phrase or advances.
- If a valid phrase is queued before the boundary, the queued phrase becomes the
  current/basis phrase at the boundary and repeat-cycle progress resets.
- If no phrase is queued and the current phrase has completed its finite repeat
  count, playback advances to the next phrase in document order.
- When the final phrase completes its finite repeat count, v1 wraps to the first
  phrase and continues. This preserves the current looping arrangement feel.
- In a one-phrase document, finite advancement resolves back to the same phrase
  and repeat-cycle progress resets at each completed cycle.
- Deleting the current phrase during playback uses the app's existing selected
  phrase fallback, then resets repeat-cycle progress for the resolved phrase.

### Acceptance Criteria

- A phrase with `repeatCount == 1` and `loopEnabled == false` advances after one
  full phrase cycle.
- A phrase with `repeatCount == 4` and `loopEnabled == false` advances after
  four full cycles, not before.
- A phrase with `repeatCount == 0` does not automatically advance.
- A phrase with `loopEnabled == true` does not automatically advance even when
  `repeatCount` is finite.
- Turning `loopEnabled` off restores the finite or unlimited behavior expressed
  by the stored `repeatCount`.
- Queueing a different phrase remains possible while a phrase is looping and
  takes effect at the next phrase boundary.
- Views that display the playing phrase agree with the engine/session source of
  truth.

## Phrase Perform Save-Back

### Observable Behavior

- Entering phrase perform mode seeds a runtime overlay from the active basis
  phrase.
- Perform-mode phrase-cell edits write to the overlay first, not directly to the
  canonical phrase model.
- Dirty overlay state is visible through compact controls or state indicators.
- Save Back applies staged overlay edits to the basis phrase through normal
  document/session mutation APIs, then clears the overlay.
- Revert discards staged overlay edits and leaves the canonical phrase
  unchanged.
- Leaving perform mode with unsaved staged edits does not silently save or
  silently discard. V1 keeps the overlay pending and continues to expose Save
  Back/Revert until the user chooses one or the basis phrase becomes invalid.
- Changing bar count, repeat count, or permanent loop from the phrase controls
  remains an immediate structural phrase edit in v1; those controls are not part
  of the perform overlay.

### Basis Phrase Changes

- If the user switches to a different basis phrase while an overlay is dirty,
  v1 must make the pending state explicit before replacing it.
- Acceptable v1 behavior is either:
  - block the basis switch until Save Back or Revert; or
  - keep one pending overlay per basis phrase.
- The implementation plan must choose one of those two behaviors and test it.
- If the basis phrase is deleted, incompatible overlay entries are discarded
  and the UI must not offer Save Back into a missing phrase.

### Acceptance Criteria

- A perform tap changes audible/visible perform state without changing the
  canonical phrase cell before Save Back.
- Revert restores the canonical phrase state exactly for edited cells.
- Save Back persists edited cells into the basis phrase and clears the dirty
  overlay indicator.
- Switching out of perform mode with dirty edits leaves a visible save/revert
  choice.
- Structural phrase controls still persist immediately and are not lost when
  Revert clears perform edits.

## Matrix Page Arrows

### Observable Behavior

- Track-page navigation arrows move into the top-left and top-right corner cells
  of the phrase matrix header row.
- The arrows stay visible in both directions.
- When no adjacent track page exists, the arrow is disabled/inactive.
- When an adjacent track page exists, the arrow is active and shows a positive
  occupancy hint.
- The v1 occupancy hint is the number of tracks on the adjacent page displayed
  as a compact badge on or next to the arrow.
- Activating the left arrow moves to the previous track page.
- Activating the right arrow moves to the next track page.
- The current track page remains clamped to valid pages when tracks are added or
  removed.

### Acceptance Criteria

- On the first page, the left arrow is visible but disabled.
- On a middle page, both arrows are active when both adjacent pages contain
  tracks.
- On the final page, the right arrow is visible but disabled.
- Active arrows show the adjacent-page track count.
- Disabled arrows do not show a misleading positive occupancy count.
- Arrow placement is part of the matrix grid, not the old layer bar.

## Fixed-Width Layer Selection

### Observable Behavior

- The layer selector is centered over the track grid and aligned with the matrix
  structure.
- The layer selector has a fixed outer width across all layer names and layer
  subtitles.
- V1 target width is 220 px unless production typography requires a nearby
  token; changing the token is acceptable only if the fixed-width invariant is
  preserved.
- Long layer names, subtitles, and track names truncate inside their allocated
  frames rather than widening the selector or moving adjacent controls.
- Switching layers must not shift the matrix page arrows, track headers, phrase
  buttons, or surrounding layer controls horizontally.
- On narrow windows, the selector participates in the existing horizontally
  scrollable matrix structure rather than forcing an app-wide minimum window.

### Acceptance Criteria

- Switching between Pattern, Transpose, Variance %, FX Send, and Mute produces
  no horizontal selector-width change.
- The selected layer remains readable enough to identify, with full text
  available through tooltip/accessibility label when truncated.
- Page arrows and track-name cells remain aligned to the same grid before and
  after a layer switch.

## Edge Cases

- Older documents without `repeatCount` or `loopEnabled` decode with
  `repeatCount == 1` and `loopEnabled == false`.
- Invalid persisted values are clamped on decode or mutation:
  - `lengthBars < 1` becomes `1`;
  - `lengthBars > 64` becomes `64`;
  - `repeatCount < 0` becomes `0`;
  - `repeatCount > 64` becomes `64`.
- Reducing phrase length while playback is inside the removed range moves the
  next phrase-local step into the new valid range without crashing or producing
  out-of-bounds reads.
- Increasing phrase length while playback is running uses the new boundary on
  the next scheduling-safe tick or phrase cycle boundary, whichever matches the
  existing engine mutation model.
- Removing tracks while on a later track page clamps the visible page to the
  last available page.
- A track page containing fewer than the full visible page size still counts as
  occupied and shows its actual track count in the adjacent-page badge.
- A dirty perform overlay must not survive document close/reopen unless it has
  been saved back.
- Save Back into a missing deleted phrase is unavailable.
- Long user-authored phrase names and layer labels use truncation plus
  tooltip/accessibility text, not dynamic layout expansion.

## V1 Exclusions

- No destructive phrase-step trimming workflow when bar count is reduced.
- No phrase arrangement editor beyond the existing phrase matrix and row
  controls.
- No multiple simultaneous open phrase-control panels.
- No staging of bar count, repeat count, or loop toggle in the perform overlay.
- No serialized perform overlay or recovery of unsaved perform edits after
  document close.
- No row-level controls in the matrix body gutter columns.
- No hidden-arrow variant for unavailable page navigation.
- No new transport-mode redesign beyond making phrase-local policy authoritative
  for phrase advancement.
- No advanced automation/ramp editing for phrase layers.
- No implementation requirement to prototype Story 4 visually before the build
  plan, provided the save-back/revert behavior above is implemented and tested.

## Verification Requirements

Builders must provide deterministic verification for the following before the
feature can be accepted:

- `PhraseModel` encoding/decoding preserves `lengthBars`, `repeatCount`, and
  `loopEnabled`, including defaults for older documents.
- Bar-count mutation clamps to `1...64`, updates `stepCount`, and does not
  destructively delete out-of-window authored cell data as a side effect.
- Repeat-count mutation clamps to `0...64`.
- Phrase advancement honors finite repeats, `repeatCount == 0`, permanent loop,
  queued phrase promotion, final-phrase wrap, and one-phrase documents.
- The playing phrase/basis phrase shown in phrase-related views matches the
  central engine/session source of truth.
- Perform-mode edits are staged in overlay state before Save Back.
- Revert leaves canonical phrase cells unchanged.
- Save Back applies staged cells to the basis phrase and clears overlay state.
- Dirty overlay behavior is explicit when leaving perform mode or attempting to
  change basis phrase.
- Matrix page arrows render in the header corner cells, remain visible at page
  boundaries, disable correctly, and show adjacent-page track counts only when
  navigation is available.
- Layer selector outer width is stable across all phrase layers and long labels.
- Accessibility labels/tooltips exist for truncated phrase names, truncated
  layer labels, loop state, repeat count, bar count, page arrows, occupancy
  badges, Save Back, and Revert.
- Visual evidence or UI tests demonstrate no horizontal layout shift when
  switching layers and no overlap/truncation failure with long phrase names,
  long track names, and a two-page track fixture.

## Readiness

This spec closes the Phrase Features PM spec gap. The lane remains not
builder-ready until `plan.md` and `implementation-handoff.md` exist and a fresh
PM readiness observation confirms the artifact chain.
