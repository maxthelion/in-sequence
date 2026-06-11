---
feature: phrase-features
status: accepted PM implementation plan; not builder-ready until implementation handoff exists
stage: implementation-plan
updated: 2026-06-04
sources:
  - README.md
  - docs/roadmap/phrase-features/architecture.md
  - docs/roadmap/phrase-features/spec.md
  - docs/roadmap/phrase-features/ux-review.md
---

# Phrase Features Plan

## Status

Accepted PM slice plan for the Phrase Features v1 surface. This plan converts
the accepted spec into a buildable implementation sequence, but it does not
authorize build-loop promotion by itself. The lane still needs an accepted
`implementation-handoff.md` and fresh readiness observation.

## Build Goal

Implement phrase-level arrangement and performance controls in the phrase
matrix:

- phrase bar count, repeat count, and permanent loop controls from the phrase
  button;
- engine-owned repeat and loop advancement policy;
- phrase perform staging with explicit Save Back and Revert;
- matrix page arrows in header corner cells with adjacent-page occupancy hints;
- fixed-width, grid-aligned layer selection with no horizontal layout shift.

The build should preserve the README intent that phrases are arrangement units
and that performance changes can be auditioned, discarded, or committed without
silently overwriting useful musical state.

## Plan Decision: Dirty Overlay Basis Switch

V1 should block switching the perform basis phrase while the phrase perform
overlay is dirty. The user must choose Save Back or Revert before the basis
phrase can be replaced.

This is the narrower of the two spec-approved behaviors. It keeps v1 to one
visible runtime overlay, avoids hidden pending edits per phrase, and makes the
save/discard choice explicit at the moment it matters. A later release can add
per-basis pending overlays if the built surface shows that blocking is too
interruptive.

## Implementation Sequence

### 0. Confirm Current Seams

Before editing product behavior, verify the current code still matches the
architecture assumptions.

Read at least:

- `Sources/Models/PhraseModel.swift` or the current phrase model definition;
- `Sources/Engine/EngineController.swift`;
- `Sources/Engine/PhrasePlayhead.swift`;
- `Sources/AppState/SequencerDocumentSession.swift` or the current document
  session mutation layer;
- `Sources/UI/PhraseWorkspaceView.swift`;
- `Sources/UI/TracksMatrixView.swift`;
- `Sources/UI/LiveWorkspaceView.swift`;
- existing master-bus performance overlay code.

Confirm:

1. `PhraseModel` still owns `lengthBars` and `stepsPerBar`.
2. `EngineController.prepareTick(...)` still resolves the active phrase used
   for scheduling.
3. Live phrase navigation state still includes current, queued, basis, and
   phrase-cycle start state.
4. Track-matrix perform edits still write canonical phrase cells directly.
5. Matrix page arrows and layer selection still live outside the accepted
   corner-cell and fixed-width layout.

If code has moved, preserve the accepted boundaries: document phrase policy on
the model, live advancement in the engine/session boundary, staged perform
edits in runtime state, and layout ownership in the matrix grid.

### 1. Add Phrase Model Policy Fields

Add persisted phrase policy fields equivalent to:

```swift
var repeatCount: Int
var loopEnabled: Bool
```

Required behavior:

1. Older documents decode with `repeatCount == 1` and `loopEnabled == false`.
2. New phrases default to `lengthBars == 8`, `repeatCount == 1`, and
   `loopEnabled == false`.
3. Mutations clamp `lengthBars` to `1...64` and `repeatCount` to `0...64`.
4. Invalid persisted values clamp on decode or normalization.
5. `repeatCount == 0` means unlimited repeat.
6. `loopEnabled == true` overrides repeat count while preserving the stored
   repeat value for when the toggle is turned off.

Acceptance signals:

- Codable round trips preserve the new fields.
- Older fixture/project data loads with current behavior: each phrase plays
  once by default and permanent loop is off.
- Bar-count decrease changes the active boundary without destructively deleting
  out-of-window authored cell data where storage allows it.

### 2. Add Session Mutation APIs For Phrase Policy

Thread phrase policy edits through the existing document/session mutation
surface instead of binding SwiftUI directly to local state.

Add command-style APIs equivalent to:

```swift
setPhraseLengthBars(_ bars: Int, phraseID: UUID)
setPhraseRepeatCount(_ count: Int, phraseID: UUID)
setPhraseLoopEnabled(_ enabled: Bool, phraseID: UUID)
```

Required behavior:

1. Commands mutate canonical phrase model state and participate in the app's
   normal document dirty/undo behavior for structural phrase edits.
2. Structural controls are immediate edits in v1 and are not part of the
   perform overlay.
3. Playback-safe snapshots see the changed policy on the next scheduling-safe
   update or phrase boundary, following the existing engine mutation model.
4. Phrase deletion and invalid phrase ids reconcile without crashes.

Acceptance signals:

- UI can call one narrow session command per control.
- Tests can validate clamping and dirty-state behavior without rendering the
  phrase button.

### 3. Make Engine Advancement Phrase-Policy Aware

Extend central live phrase navigation with repeat-cycle progress equivalent to:

```swift
var currentPhraseCompletedCycles: Int
```

Required boundary policy:

1. At each completed phrase cycle, a valid queued phrase wins and promotes at
   the boundary.
2. Promotion resets phrase-cycle progress and sets current/basis phrase to the
   queued phrase.
3. Without a queued phrase, `loopEnabled == true` stays on the current phrase.
4. Without a queued phrase or loop toggle, `repeatCount == 0` stays on the
   current phrase.
5. Finite repeat counts stay on the current phrase until the requested number
   of cycles has completed.
6. When a finite phrase completes its repeat count, advance to the next phrase
   in document order.
7. When the final finite phrase completes, wrap to the first phrase and
   continue.
8. In a one-phrase document, finite advancement resolves back to that phrase
   and resets cycle progress.

Acceptance signals:

- `repeatCount == 1` advances after one full cycle.
- `repeatCount == 4` advances after four full cycles.
- `repeatCount == 0` does not automatically advance.
- `loopEnabled == true` does not automatically advance even when repeat count
  is finite.
- Queueing another phrase while looping still takes effect at the next phrase
  boundary.
- Views that display playing/basis phrase agree with engine/session state, not
  with duplicate view-side phrase-index math.

### 4. Build Phrase Button Controls

Extend the phrase row-header button into the accepted inline control surface.

Required behavior:

1. Collapsed state shows phrase name, bar count, repeat/loop summary, selected
   state, playing state, and loop badge when active.
2. Tapping the phrase button selects the phrase and opens/closes inline
   controls.
3. Only one phrase control panel is open at once in v1.
4. Controls expose bar count, repeat count, and permanent loop.
5. The effective playback summary explains the real behavior in plain terms,
   including `repeatCount == 0` and loop override.
6. When loop is on, the repeat control may be disabled or deemphasized, but the
   stored repeat value remains intact.
7. Long phrase names truncate with tooltip/accessibility text instead of
   shrinking to unreadable sizes.

Acceptance signals:

- A user can adjust bar count and repeat count without leaving the matrix.
- Permanent loop state is visible without opening the controls.
- Structural phrase edits persist immediately and update playback policy.
- The opened control panel does not overlap row actions, track headers, or
  matrix cells at supported widths.

### 5. Add Phrase Perform Overlay, Save Back, And Revert

Introduce runtime/session-only phrase perform staging equivalent to:

```swift
struct PhrasePerformanceOverlayState: Equatable {
    var basisPhraseID: UUID?
    var editedCellsByAddress: [PhraseCellAddress: PhraseCell]
    var isDirty: Bool
}
```

Required behavior:

1. Entering phrase perform mode seeds overlay reads from the current basis
   phrase.
2. Perform-mode phrase-cell edits write overlay values first, not canonical
   phrase cells.
3. Reads during perform mode resolve overlay values before canonical phrase
   cells.
4. Dirty state is visible through compact Save Back and Revert controls or
   equivalent state indicators.
5. Save Back applies overlay cells into the basis phrase through session
   mutation APIs and clears the overlay.
6. Revert clears staged edits and leaves canonical phrase cells unchanged.
7. Leaving perform mode with dirty edits keeps the overlay pending and keeps
   Save Back/Revert visible.
8. Attempting to switch basis phrase while dirty is blocked until Save Back or
   Revert.
9. Deleting the basis phrase clears incompatible overlay entries and disables
   Save Back into a missing phrase.
10. Closing/reopening the document does not restore unsaved overlay state.

Acceptance signals:

- Perform taps can change audible/visible perform state before canonical phrase
  cells change.
- Revert restores canonical phrase cell state exactly for edited cells.
- Save Back persists staged cells into the basis phrase and clears dirty state.
- Blocking a dirty basis switch is visible and test-covered.
- Structural phrase controls are not reverted by Revert.

### 6. Move Matrix Page Arrows Into Header Corners

Rework matrix grid structure so the header row owns left and right corner-cell
navigation.

Required behavior:

1. Left and right arrows stay visible in all page states.
2. Boundary arrows are disabled/inactive, not hidden.
3. Active arrows show the adjacent page's track count as a compact positive
   occupancy badge.
4. Disabled arrows do not show misleading positive occupancy.
5. Activating arrows changes the current track page through existing page
   navigation state.
6. Removing tracks clamps the current page to the last valid page.
7. Body gutter columns remain alignment-only in v1.

Acceptance signals:

- First page: left arrow visible disabled, right arrow active when another page
  has tracks.
- Middle page: both arrows active when both adjacent pages contain tracks.
- Final page: right arrow visible disabled.
- Arrow placement is part of the matrix grid, not the old layer bar.

### 7. Stabilize Layer Selector Layout

Center the layer selector over the track grid and give it a fixed outer width.

Required behavior:

1. V1 target width is 220 px unless production typography requires a nearby
   token.
2. The fixed-width invariant is required even if the exact token changes.
3. Long layer names, subtitles, phrase names, and track names truncate inside
   their allocated frames with tooltip/accessibility labels.
4. Switching layers does not move matrix page arrows, track headers, phrase
   buttons, or surrounding layer controls horizontally.
5. On narrow windows, the selector participates in the existing horizontally
   scrollable matrix structure instead of forcing an app-wide minimum width.

Acceptance signals:

- Switching among Pattern, Transpose, Variance %, FX Send, and Mute produces no
  selector-width change.
- Long labels remain identifiable and do not overlap adjacent controls.
- Grid alignment holds before and after page navigation and layer changes.

### 8. Capture Built-Surface And Regression Evidence

Builders should finish with deterministic tests plus actual built-surface
evidence.

Verification should cover:

1. `PhraseModel` encoding/decoding, defaults, and clamping.
2. Bar-count boundary changes and non-destructive shrink behavior.
3. Repeat advancement for finite counts, repeat zero, permanent loop, queued
   promotion, final-phrase wrap, and one-phrase documents.
4. Playing/basis phrase display agreement with engine/session truth.
5. Overlay staging, Revert, Save Back, dirty leave-perform behavior, dirty
   basis-switch blocking, basis deletion, and non-persistence.
6. Matrix arrows in corner cells with enabled/disabled and occupancy states.
7. Fixed layer selector width and truncation behavior under long labels.
8. Accessibility labels/tooltips for truncated phrase names, truncated layer
   labels, loop state, repeat count, bar count, page arrows, occupancy badges,
   Save Back, and Revert.

Preferred evidence order:

1. Focused model/session tests.
2. Focused engine advancement tests.
3. Focused overlay staging tests.
4. UI/view-model tests for phrase controls, matrix arrows, and layer selector
   state.
5. Full project test command normally used by the build loop.
6. Peekaboo or equivalent visual evidence from the actual app showing phrase
   controls, dirty Save Back/Revert, two-page matrix arrows, and no layer
   selector shift with long labels.

If the full suite or visual capture is blocked in the build worktree, builders
should record the blocker and provide the focused checks that did run.

## Handoff Risks

- Engine advancement must become the phrase-policy source of truth. Leaving
  repeat/loop logic in display helpers would create view/engine disagreement.
- Repeat progress must reset on queued promotion, immediate phrase resolution,
  deletion fallback, final wrap, and one-phrase self-advancement.
- Bar-count shrink must not silently delete authored data unless an existing
  data structure requires normalization for type safety.
- Phrase perform overlay must not reuse canonical phrase-cell mutation paths
  before Save Back.
- Blocking dirty basis switches needs clear UI treatment so it does not feel
  like a broken click.
- Structural phrase controls remain immediate edits; Revert only discards
  staged phrase-cell edits.
- Matrix layout should not introduce row-level gutter controls in this feature.
- The 220 px selector target can be tuned, but a content-sized selector would
  miss the accepted UX.
- Accessibility/tooltips are part of acceptance because this feature relies on
  truncation for long user-authored labels.

## Out Of Scope For This Build

- `implementation-handoff.md` authoring.
- Build-loop promotion.
- A separate phrase arrangement editor.
- Serialized or undoable perform overlay state.
- Per-basis dirty overlay storage.
- Staging bar count, repeat count, or loop toggle in the perform overlay.
- Destructive phrase-step trimming when bar count is reduced.
- Hidden matrix-page arrows.
- New row-level controls in matrix body gutters.
- A global transport-mode redesign beyond making phrase-local policy
  authoritative for phrase advancement.
- Advanced automation or ramp editing for phrase layers.

## Promotion Dependency

This plan closes the PM implementation-sequence gap. The lane remains not
builder-ready until `implementation-handoff.md` exists and a fresh PM readiness
observation confirms that the artifact chain is complete, coherent, and free of
owner locks.
