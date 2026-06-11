---
feature: phrase-features
created: 2026-06-04
status: accepted PM architecture; not builder-ready
sources:
  - README.md
  - docs/roadmap/phrase-features/notes.md
  - docs/roadmap/phrase-features/user-stories.md
  - docs/roadmap/phrase-features/existing-state.md
  - docs/roadmap/phrase-features/artifacts.md
  - docs/roadmap/phrase-features/ux-review.md
  - docs/roadmap/phrase-features/prototypes/phrase-button-controls.html
  - docs/roadmap/phrase-features/prototypes/matrix-navigation-and-layers.html
---

# Phrase Features Architecture

## Scope

Phrase Features turns phrase rows from static arrangement labels into the place
where a performer or composer controls phrase duration, phrase repetition, and
phrase-local loop behavior. It also moves matrix navigation and layer selection
into a stable grid-aligned structure.

This architecture covers:

- phrase bar-count editing from the phrase button;
- phrase repeat count and permanent loop semantics;
- phrase perform-mode staging, save-back, and discard semantics;
- track-page navigation arrows in the matrix corner cells with occupancy hints;
- fixed-width, grid-aligned layer selection.

This is still PM architecture. The lane is not builder-ready until spec, plan,
and implementation handoff exist.

## Current Implementation Facts Revalidated

`existing-state.md` was inspected on 2026-04-29. Current code has moved since
then in one important way: phrase navigation is now centralized enough to extend.

Current facts as of 2026-06-04:

- `PhraseModel` stores `lengthBars` and `stepsPerBar`, clamps both to at least
  1, and computes `stepCount` from them. It does not store repeat count or loop
  state.
- `PhrasePlayhead.playbackPhraseIndex(...)` still computes display phrase
  identity from phrase lengths and a transport tick. It has no repeat-count or
  loop-toggle semantics.
- `EngineController` now owns live phrase-navigation state:
  `currentPhraseID`, `queuedPhraseID`, `basisPhraseID`, and
  `phraseCycleStartTick`.
- `EngineController.prepareTick(...)` resolves an active phrase through
  `playbackPhraseForPrepare(...)`, then reads that phrase's layer snapshot for
  the phrase-local step.
- `TransportMode` still has global `.song` and `.free` cases, but current code
  only sets and reads the mode from the transport bar. The engine tick path does
  not consult `transportMode`.
- `PhraseWorkspaceView` still renders the phrase cell as a selectable row
  header with phrase name and read-only bar count; insert/duplicate/remove are
  separate row actions.
- `TracksMatrixView` and `LiveWorkspaceView` already resolve their editing
  phrase from `engineController.basisPhraseID` when valid, then fall back to the
  selected phrase.
- Track-matrix perform edits still call `session.setPhraseCell(...)` directly.
  There is no phrase perform staging layer.
- Master-bus scene perform mode has a usable staging pattern in
  `MasterBusPerformanceOverlayState`: runtime overrides are separate from
  canonical scene state and can be cleared after save/revert.
- Phrase matrix page arrows still live in the layer bar, not the matrix header
  corner cells. The current disabled state is a passive occupancy hint.
- The phrase matrix layer selector still sizes to content and is not fixed to
  the grid columns.

## Product Basis

The accepted product basis is:

- `phrase-button-controls.html` for phrase row expansion, bar count, repeat
  count, loop toggle, and the effective playback summary;
- `matrix-navigation-and-layers.html` for matrix-corner page navigation,
  occupancy badges, and a fixed-width grid-aligned layer selector.

Story 4 was intentionally deferred in UX review because save-back needs an
architecture decision. This document supplies that decision.

## Phrase Model Ownership

Phrase duration and phrase repeat policy are document state. They belong on
`PhraseModel`, not in view state and not only in `EngineController`.

The model should gain fields equivalent to:

```swift
var repeatCount: Int
var loopEnabled: Bool
```

`repeatCount` is the number of times the phrase plays before automatic song
advancement. It should be clamped to `0...` where `0` means unlimited repeat.
`loopEnabled` is an explicit phrase-level permanent-loop flag.

Effective repeat behavior is:

```text
if loopEnabled: repeat forever
else if repeatCount == 0: repeat forever
else: play repeatCount cycles, then advance
```

This keeps the user-story requirement that zero/unlimited repeat is valid while
also honoring the separate loop-toggle story. The UI should reduce ambiguity by
showing the effective playback sentence and disabling or visually deemphasizing
the repeat stepper while `loopEnabled` is on, but it should preserve the stored
repeat count for when the loop toggle is turned off.

Default values should preserve current project behavior as closely as possible:

- `lengthBars`: current default remains 8;
- `repeatCount`: default 1;
- `loopEnabled`: default false.

Older documents that lack the new fields decode to those defaults.

## Bar Count Semantics

Changing `lengthBars` updates the phrase playback boundary immediately and
persists with the phrase.

Decreasing bar count must be non-destructive for existing phrase cell data. The
active playback/editing window becomes the first `lengthBars * stepsPerBar`
steps, but stored step/bar arrays beyond the shorter boundary should be
preserved where the existing data structures allow it. If the user later
increases the bar count, previously authored data can reappear.

Builders should only normalize arrays when a cell mode or value must be
rewritten for type safety. The architecture must not require destructive
truncation as a side effect of changing phrase length.

This decision follows the README's bias toward bounded happy accidents and
discardable/commit-able performance changes: shrinking a phrase should audition
a shorter boundary without silently deleting musical work.

## Playback And Advancement Ownership

Repeat count and loop toggle belong in central playback policy, not in duplicated
view-side phrase-index math.

`EngineController` is the right owner for live phrase advancement because it
already owns the phrase currently used by `prepareTick(...)`, the queued phrase,
the UI basis phrase, and the cycle-start tick. The feature should extend that
state with repeat-cycle progress for the current phrase, or an equivalent
transport-session object owned by the engine/session boundary and read by the
engine tick path.

Required live state is equivalent to:

```swift
struct PhraseNavigationState {
    var currentPhraseID: UUID?
    var queuedPhraseID: UUID?
    var basisPhraseID: UUID?
    var phraseCycleStartTick: UInt64
    var currentPhraseCompletedCycles: Int
}
```

At each phrase cycle boundary, the engine evaluates the active phrase policy
against the cycle that just completed:

- if a valid queued phrase exists, queued promotion wins at the boundary;
- otherwise if `loopEnabled` is true, remain on the current phrase;
- otherwise if `repeatCount == 0`, remain on the current phrase;
- otherwise if `currentPhraseCompletedCycles + 1 < repeatCount`, increment
  cycle progress and remain on the current phrase;
- otherwise advance to the next phrase in document order, or stop/hold according
  to the later spec's end-of-arrangement rule.

With this rule, `repeatCount: 1` plays the phrase once and advances at the first
completed cycle boundary.

Spec must define the exact end-of-arrangement behavior. Architecture does not
need product-owner input for that because the current product already has
wrapping/looping behavior and the key decision here is where the policy lives.

`PhrasePlayhead.playbackPhraseIndex(...)` may remain a display helper, but it
must not become the source of truth for repeat/loop advancement. The old global
`TransportMode.free`/`.song` control should become a compatibility view of the
new phrase-local policy or be demoted by the spec. The tick path must read the
phrase policy itself.

## Phrase Button Interaction

The phrase row-header cell remains the primary phrase button, but gains an
expanded control state following the accepted prototype:

- collapsed row shows phrase name, bar count, repeat/loop summary, selected
  state, playing state, and loop badge when active;
- tapping the phrase button selects the phrase and opens/closes its controls;
- controls are inline in the matrix row area, not a detached modal;
- bar count and repeat count are compact steppers or equivalent small numeric
  controls;
- loop toggle is a binary control with a persistent visual state;
- long phrase names truncate with tooltip/accessibility text rather than
  shrinking to unreadable sizes.

The phrase button controls mutate phrase model fields through
`SequencerDocumentSession` APIs, not directly through SwiftUI local state.

## Phrase Perform Staging And Save-Back

Story 4 requires phrase perform edits to start from the current phrase, support
discard, and save back only by explicit action. Current track perform mode does
not meet that requirement because it writes directly to phrase cells.

Introduce a phrase perform overlay owned by the live document session or engine
session layer. Its shape should be equivalent to:

```swift
struct PhrasePerformanceOverlayState: Equatable {
    var basisPhraseID: UUID?
    var editedCellsByAddress: [PhraseCellAddress: PhraseCell]
}
```

The overlay is runtime/session state, not serialized project state. Entering
phrase perform mode seeds the overlay from the engine basis phrase. During
perform mode:

- reads resolve overlay cell values first, then the canonical phrase;
- perform taps write into the overlay;
- discard clears the overlay without mutating the project;
- save-back applies overlay cells into the basis phrase through existing session
  mutation APIs, then clears the overlay;
- changing or deleting the basis phrase invalidates or clears incompatible
  overlay entries;
- leaving perform mode with unsaved edits must make the discard/save choice
  explicit enough that edits are not silently lost or silently committed.

The MVP save-back scope is phrase cell content. Bar count, repeat count, and
loop toggle are structural phrase controls and should remain immediate phrase
model edits unless the later spec explicitly chooses to stage them too.

The scene perform overlay is the closest existing pattern, but phrase staging
must be phrase-cell aware and must support track/layer addresses rather than
scene macro IDs.

## Matrix Navigation And Layer Layout

The phrase matrix should use a stable outer grid with three structural regions:

- left corner/navigation column aligned with the phrase header column;
- track columns for visible track pages;
- right corner/navigation column aligned with the row actions/right edge.

The page navigation arrows move from the layer bar into the matrix header row's
left and right corner cells. Arrows should remain visible in both directions.
When no adjacent page exists, the arrow is disabled/visibly inactive rather than
hidden. When an adjacent page exists, the arrow is active and carries a positive
occupancy hint such as an adjacent-track count badge.

This resolves the prototype's grey-vs-hidden question from the user-story
acceptance signal: page arrows should always be visible at the matrix corners
and communicate availability.

The layer selector should be horizontally centered over the track grid, not
anchored to the old layer bar's left edge. It should have a fixed width across
all layer names, with text truncation/ellipsis inside the fixed frame. The
accepted prototype uses 220 px as proof of concept; spec may tune the exact
width against production typography, but the invariant is fixed outer width and
no horizontal layout shift.

On narrow layouts, the phrase matrix already scrolls horizontally. The selector
should align to the scrollable grid structure and may remain fixed-width inside
that structure rather than forcing an app-wide minimum window decision.

The 32 px prototype gutters/body spacers are alignment columns for v1. They
should not grow new row-level controls in this feature unless the spec can do so
without crowding the matrix or changing the accepted navigation model.

## Resolved Questions

No blocking product-owner questions remain for architecture.

| Question | Resolution |
| --- | --- |
| Loop toggle vs repeat-count-zero redundancy | Keep both. `loopEnabled` overrides; `repeatCount == 0` also means unlimited when loop is off. UI communicates the effective behavior and preserves repeat value while loop is on. |
| No-adjacent-page arrow treatment | Keep corner arrows visible and disabled/inactive when no adjacent page exists. Active arrows show an occupancy hint. |
| Grid gutter ownership | Header gutters own page navigation. Body gutters are alignment-only in v1. |
| Bar-count decrease with existing data | Non-destructive boundary change. Preserve out-of-range authored data where possible. |
| Story 4 staging boundary | Stage phrase cell edits in a runtime/session overlay; save-back commits explicitly; discard clears. Structural phrase controls remain immediate in MVP. |
| Fixed-width selector minimum | Fixed outer width with truncation; horizontal matrix scrolling handles narrow layouts. Spec may tune exact pixel width. |

## Builder-Facing Verification Implications

The later spec and plan should include focused tests or deterministic evidence
for:

- `PhraseModel` codable defaults for `repeatCount` and `loopEnabled`;
- phrase bar-count edits update `stepCount` and playback boundary without
  destructive truncation of existing step data;
- repeat-count policy advances after the requested number of phrase cycles;
- `repeatCount == 0` loops indefinitely;
- `loopEnabled` overrides repeat count and persists;
- queued phrase promotion and repeat policy interact deterministically at phrase
  boundaries;
- transport mode UI no longer implies a global source of truth that the engine
  ignores;
- perform-mode phrase edits write to overlay state before save-back;
- discard leaves canonical phrase cells unchanged;
- save-back applies overlay cells to the basis phrase and clears the overlay;
- matrix page arrows live in corner cells, stay visible, disable at boundaries,
  and show positive occupancy when navigation is available;
- layer selector outer width is stable across all phrase layers and long labels
  truncate without moving adjacent controls.

## Left For Spec

- Exact phrase-button expanded layout and keyboard/focus behavior.
- Numeric limits for bar count and repeat count.
- Exact end-of-arrangement behavior after the final phrase finishes its repeat
  count with no queued phrase.
- Exact visual copy for effective playback summary and unsaved perform edits.
- Whether leaving perform mode prompts, reverts, or keeps the overlay pending.
- Exact save-back and discard control placement.
- Exact occupancy badge copy/count for track pages.
- Production width token for the fixed-width layer selector.
- Accessibility labels and tooltips for phrase controls and page arrows.

## Readiness

This architecture closes the architecture and open-question-handling gap for
Phrase Features. No `open-questions.md` is needed at this layer because the
known questions are resolved above.

The lane remains not builder-ready until `spec.md`, `plan.md`, and
`implementation-handoff.md` are authored and freshly observed.
