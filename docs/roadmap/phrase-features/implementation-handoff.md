---
feature: phrase-features
status: PM implementation handoff; awaiting fresh readiness observation
stage: implementation-handoff
updated: 2026-06-04
sources:
  - README.md
  - docs/roadmap/phrase-features/architecture.md
  - docs/roadmap/phrase-features/spec.md
  - docs/roadmap/phrase-features/plan.md
  - docs/roadmap/phrase-features/ux-review.md
  - docs/roadmap/phrase-features/prototypes/phrase-button-controls.html
  - docs/roadmap/phrase-features/prototypes/matrix-navigation-and-layers.html
---

# Phrase Features Implementation Handoff

## Builder Boundary

Implement the v1 Phrase Features surface described by the accepted
architecture, spec, and plan. The build is limited to:

- phrase bar count, repeat count, and permanent-loop controls from the phrase
  button;
- engine-owned repeat and loop advancement policy;
- phrase perform staging with explicit Save Back and Revert;
- matrix page arrows in the header corner cells with adjacent-page occupancy
  hints;
- fixed-width, grid-aligned layer selection.

Do not broaden the build into a separate phrase arrangement editor, global
transport redesign, row-level matrix gutter controls, serialized perform
overlays, destructive phrase-step trimming, or per-basis dirty overlay storage.

## Source Of Truth

Use these artifacts in order:

1. `architecture.md` for ownership decisions and resolved product questions.
2. `spec.md` for observable behavior, acceptance criteria, limits, edge cases,
   and v1 exclusions.
3. `plan.md` for implementation sequence and the selected dirty-overlay
   basis-switch behavior.
4. `ux-review.md` and the accepted prototypes for the intended interaction and
   layout direction.

The accepted PM decisions are:

- `repeatCount` and `loopEnabled` are persisted phrase model state.
- `repeatCount == 0` means unlimited repeat.
- `loopEnabled == true` overrides repeat count while preserving the stored
  repeat value.
- Older documents decode with `repeatCount == 1` and
  `loopEnabled == false`.
- V1 clamps `lengthBars` to `1...64` and `repeatCount` to `0...64`.
- Shrinking bar count changes the active boundary without silently deleting
  out-of-window authored data where storage allows preservation.
- The engine/session boundary, not view-side display math, owns repeat/loop
  advancement.
- Queued phrase promotion wins at phrase boundaries.
- Final finite phrase advancement wraps to the first phrase.
- Phrase perform edits are runtime/session overlay edits until Save Back.
- Revert clears staged phrase-cell edits only; structural phrase controls remain
  immediate edits.
- Dirty perform-overlay basis switches are blocked until Save Back or Revert.
- Matrix page arrows remain visible in both directions; unavailable arrows are
  disabled, not hidden.
- Active page arrows show the adjacent page's track count.
- The layer selector has a fixed outer width; 220 px is the v1 target unless
  production typography needs a nearby token.

No product-owner lock is active for v1.

## Required Build Sequence

Follow the accepted plan sequence unless fresh code inspection proves a lower
risk ordering inside the same boundary:

1. Confirm current seams in the phrase model, engine controller, playhead,
   document session, phrase workspace, matrix views, live workspace, and
   existing performance overlay pattern.
2. Add persisted phrase policy fields and decode/mutation clamping.
3. Add narrow document/session mutation APIs for phrase length, repeat count,
   and loop toggle.
4. Make engine phrase advancement policy-aware, including repeat-cycle progress
   and queued promotion precedence.
5. Build inline phrase button controls with collapsed summaries and one open
   panel at a time.
6. Add phrase perform overlay state, Save Back, Revert, dirty indicators, dirty
   basis-switch blocking, and basis-deletion handling.
7. Move matrix page arrows into header corner cells with enabled, disabled, and
   occupancy states.
8. Stabilize the layer selector width and grid alignment.
9. Finish with focused tests plus actual built-surface evidence.

If code has moved since PM inspection, preserve the same ownership boundaries:
document phrase policy on the model, live advancement in the engine/session
boundary, staged perform edits in runtime state, and layout ownership in the
matrix grid.

## Target Seams To Inspect

Builders should inspect the current equivalents of:

- `Sources/Models/PhraseModel.swift`;
- `Sources/Engine/EngineController.swift`;
- `Sources/Engine/PhrasePlayhead.swift`;
- `Sources/AppState/SequencerDocumentSession.swift`;
- `Sources/UI/PhraseWorkspaceView.swift`;
- `Sources/UI/TracksMatrixView.swift`;
- `Sources/UI/LiveWorkspaceView.swift`;
- the master-bus performance overlay state and save/revert flow.

These paths are starting points from PM evidence, not a guarantee that code has
not moved. Do not duplicate policy into views if the files have changed.

## Non-Negotiable UX Invariants

- Phrase controls stay in the matrix context and do not become a detached
  settings screen.
- The collapsed phrase button communicates phrase name, bar count, repeat/loop
  summary, selected state, playing state, and loop state where active.
- Long phrase names and layer labels truncate inside stable frames with
  tooltip/accessibility text; they do not shrink to unreadable sizes or expand
  the layout.
- The effective playback summary makes loop/repeat precedence understandable.
- Dirty Save Back/Revert state remains visible when leaving perform mode.
- A blocked dirty basis switch must read as a deliberate pending-edit guard, not
  as a broken click.
- Page arrows live in matrix header corner cells and stay visible at boundaries.
- Disabled page arrows do not show misleading positive occupancy counts.
- Switching layers does not move page arrows, track headers, phrase buttons, or
  surrounding layer controls horizontally.
- Body gutter columns remain alignment-only in v1.

## Verification Required From Build Loop

Provide focused automated coverage where the current test architecture allows:

- `PhraseModel` encoding/decoding, defaults, and clamping.
- Bar-count boundary changes and non-destructive shrink behavior.
- Repeat advancement for finite counts, repeat zero, permanent loop, queued
  promotion, final-phrase wrap, and one-phrase documents.
- Playing/basis phrase display agreement with engine/session truth.
- Overlay staging, Revert, Save Back, dirty leave-perform behavior, dirty
  basis-switch blocking, basis deletion, and non-persistence across reopen.
- Matrix arrows in corner cells with first/middle/final page states and
  occupancy counts.
- Fixed layer selector width and truncation under long labels.
- Accessibility labels/tooltips for truncated labels, loop state, repeat count,
  bar count, page arrows, occupancy badges, Save Back, and Revert.

Also capture actual built-surface evidence, preferably with the project-local
visual scenario flow, showing:

- opened phrase controls with bar, repeat, loop, and effective summary;
- dirty phrase perform overlay with Save Back and Revert visible;
- two-page matrix arrows in enabled and disabled states with occupancy hints;
- layer changes across Pattern, Transpose, Variance %, FX Send, and Mute with
  no selector-width shift.

If the full test suite or visual capture is blocked in the build worktree,
record the blocker and include the focused checks that did run.

## Out Of Scope

- Product-code work outside this feature boundary.
- Build-loop promotion by this PM handoff.
- A separate phrase arrangement editor.
- Serialized or undoable runtime perform overlays.
- Per-basis dirty overlay storage.
- Staging bar count, repeat count, or loop toggle in the perform overlay.
- Destructive phrase-step trimming when bar count is reduced.
- Hidden matrix-page arrows.
- Row-level controls in matrix body gutters.
- A global transport-mode redesign beyond making phrase-local policy
  authoritative for advancement.
- Advanced automation or ramp editing for phrase layers.

## Residual Risk

The main implementation risk is engine/view disagreement: repeat/loop policy,
playing phrase display, and perform overlay reads must resolve from one
engine/session truth. The other high-risk area is the dirty perform overlay:
builders need explicit UI and tests for Save Back, Revert, basis deletion, and
blocked basis switching so staged performance edits are never silently saved or
lost.

The PM artifact chain is now complete enough for a fresh PM readiness
observation. Promotion should wait for that observation to confirm coherence,
freshness, and absence of duplicate in-flight work or owner locks.
