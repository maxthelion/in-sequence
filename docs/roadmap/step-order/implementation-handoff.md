---
feature: step-order
created: 2026-06-06
status: ready-for-build-loop-promotion
stage: implementation-handoff
sources:
  - README.md
  - docs/roadmap/step-order/open-questions.md
  - docs/roadmap/step-order/architecture.md
  - docs/roadmap/step-order/spec.md
  - docs/roadmap/step-order/plan.md
  - docs/roadmap/step-order/user-stories.md
  - docs/roadmap/step-order/existing-state.md
  - docs/roadmap/step-order/ux-review.md
  - docs/roadmap/step-order/prototypes/step-order-wireframe.html
---

# Step Order Implementation Handoff

## Purpose

This handoff packages the accepted Step Order v1 PM artifacts into
builder-ready scope. It should be used to open a future build loop, but it does
not itself promote a build loop, create a branch or worktree, route builders or
reviewers, merge, rebase, push, or change product code.

Step Order v1 is a phrase-scoped playback-order performance override. A
producer creates or edits a named 16-step map, assigns one map to the current
phrase, and enables the phrase's Step Order state. During playback, the output
phrase step remains the clock position while note/source playback reads a
source step through the active map. The feature supports the README goal of
bounded performable variation: change the rule, hear a surprising but
controlled variation, and return to authored material without destructive
edits.

## Build-Loop Boundary

A future build loop should implement the full Step Order v1 workflow end to
end:

- top-level project storage for named Step Order maps with stable IDs, names,
  and exactly 16 source-step values;
- phrase-level optional assignment storing one map ID plus saved enabled state;
- fixed 16-step validation with values constrained to `0...15`;
- legacy project decode to an empty map pool, no phrase assignments, and
  sequential playback;
- save/load round-trip for maps, assignments, and saved enabled state;
- map picker/list workflow for create, rename, edit, assign, usage count,
  delete-when-unused, and deletion-blocked feedback for assigned maps;
- active-map control and two-row output-step/source-step editor with
  auto-advance, wrap/end feedback, identity defaults, reset to identity, and
  pass-through/no-remap labeling;
- fixed visible `Phrase` scope, with no editable per-track, project, layer, or
  phrase/track scope controls in v1;
- runtime-only Off, On, Pending On, Pending Off, unavailable, unassigned, and
  invalid states;
- snapshot compilation of valid enabled phrase assignments into immutable
  engine-safe playback data before the tick path;
- non-destructive source-step remapping after the output `stepInPhrase` is
  known and before source/pattern note data is read;
- phrase-layer timing anchored to the output step for mute, fill, macro lanes,
  and phrase automation;
- focused automated tests plus built-surface visual or manual evidence for the
  implemented workflow.

The build should remain additive to the current project, phrase, snapshot,
playback, and Step Order UI surfaces. Do not broaden v1 into editable
per-track Step Order controls, project-wide Step Order, layer-level
automation, variable-length maps, hidden modulo behavior, stacked maps,
transformations that add notes, Note Repeat sharing, or mutation of clips,
generators, pattern slots, phrase cells, phrase layers, scenes, selected
phrase state, or transport position.

## Branch And Worktree Expectations

If this PM lane is promoted later, implementation should happen in a dedicated
build-loop branch and worktree, not as dirty product-code changes on `main`.
Unless the project decider chooses a conflict-free equivalent, use:

- build loop id: `build/step-order`;
- branch: `auto/roadmap-16-step-order`;
- worktree: `.worktrees/roadmap-16-step-order`;
- build-loop evidence root:
  `.meta/multipass/loops/build/step-order/`.

This PM lane does not create the build-loop manifest, branch, worktree, inbox
request, merge, rebase, push, or request lifecycle transition.

## Source Of Truth

| Artifact | Builder Use |
|---|---|
| `spec.md` | Primary behavior contract, acceptance criteria, edge cases, and verification requirements. |
| `plan.md` | Implementation and verification sequence for the build loop. |
| `architecture.md` | Accepted model, compilation, playback boundary, pending-state, UI, and test decisions. |
| `open-questions.md` | Resolved architecture and product-default questions; no current product-owner lock. |
| `existing-state.md` | Current integration seam map and known code gaps to reconfirm before editing. |
| `ux-review.md` | Accepted interpretation of the wireframe and prototype gaps closed by architecture/spec. |
| `prototypes/step-order-wireframe.html` | Product workflow reference for picker/editor/scope/toggle intent, not production styling source. |

The settled v1 choices are:

- Step Order assignment is phrase-only: one assigned named map per phrase,
  applied to all playable tracks in that phrase when enabled.
- Maps live in a top-level named project pool.
- Maps are exactly 16 entries, and each value is in `0...15`.
- The assigned map and saved enabled state persist as phrase settings.
- Live pending toggle state is runtime-only and is not persisted, exported,
  undoable, or redoable.
- Playback remapping is non-destructive and applies in the compiled
  playback/source-resolution path.
- Invalid, missing, deleted, unsupported, or non-16-step states compile to
  sequential playback with visible unavailable or unassigned UI state.
- Per-track, project-wide, layer-level, variable-length, and stacked behavior
  are deferred.

## First Bounded Builder Slice

Start with seam reconfirmation and model/engine testability before broad UI
work.

The first builder request should:

- verify `EngineController.prepareTick` still computes phrase-local
  `stepInPhrase` from `upcomingStep`;
- verify `PlaybackSnapshot.resolvedStep` or its current equivalent remains the
  source-step resolution path before per-track source/pattern reads;
- verify phrase layer reads still use the original output step;
- verify `SequencerSnapshotCompiler.compilePhraseBuffer` still owns phrase
  playback buffer construction and invalidation;
- verify `PhrasePlaybackBuffer` or `TrackPhrasePlaybackBuffer` remains the
  right immutable compiled-data home;
- verify project save/load and phrase Codable ownership still match the
  document-root paths identified in `existing-state.md`;
- add the smallest deterministic fixture that can observe sequential source
  reads and the accepted remap
  `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]` without depending on SwiftUI.

Exit this slice with compact build evidence listing any integration seams that
moved since `existing-state.md`. If deterministic model/compiler/playback tests
are impractical in the current code shape, record that as a build-loop blocker
before polishing the picker/editor UI.

## Required Build Sequence

Follow `plan.md` unless fresh code inspection proves a lower-risk order inside
the same accepted boundaries:

1. Reconfirm current seams and add focused test fixtures.
2. Add top-level project map pool and phrase assignment persistence.
3. Enforce validation and unsupported-state recovery.
4. Compile Step Order into immutable engine-safe phrase buffers.
5. Apply non-destructive playback source-step remapping.
6. Add runtime pending toggle state and command-style ingress.
7. Build the picker, editor, assignment, active-map, fixed-scope, and toggle
   surface.
8. Capture actual built-surface visual or manual evidence.

Review model, validation, snapshot compilation, and playback behavior before
depending on them from SwiftUI. Review pending-state ownership before treating
the toggle surface as complete.

## Acceptance Criteria

The build is not complete until the observable criteria from `spec.md` pass:

- map pool and phrase assignment persist and round-trip through save/load;
- existing projects decode with no Step Order state and unchanged sequential
  playback;
- invalid, wrong-length, out-of-range, missing-map, deleted-map, disabled,
  unassigned, unsupported, and non-16-step phrase states do not crash and do
  not enter an active compiled map;
- assigned-map deletion is blocked in v1 with visible usage/reason feedback;
- enabled valid assignments compile to immutable active maps, while inactive
  states compile to sequential playback;
- the tick path does not traverse live document state, query SwiftUI state,
  look up map IDs, or validate dynamic arrays;
- playback resolves source steps through
  `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]` exactly for the first 16 output steps;
- disabling Step Order restores sequential playback at the accepted timing;
- phrase-layer timing remains output-step based;
- clips, generated sources, pattern slots, phrase cells, phrase layers, scenes,
  selected phrase state, transport, unrelated phrases, and unrelated tracks are
  not mutated or behaviorally changed by Step Order playback;
- running-playback toggles show Pending On or Pending Off and apply at the next
  phrase boundary;
- stopped toggles apply immediately without boundary-pending state;
- picker/editor/assignment/toggle UI covers create, rename, edit, assign,
  active-map switching, identity labeling, reset, fixed `Phrase` scope,
  unavailable state, unassigned state, invalid state, deletion-blocked state,
  keyboard focus, and accessibility text.

## Verification Gates

Provide focused automated coverage where the current test architecture allows:

- model, Codable, dirty-state, legacy-decode, and runtime-non-persistence
  tests;
- validation and recovery tests for wrong-length, out-of-range, missing-map,
  deleted-map, disabled, unassigned, unsupported, and non-16-step states;
- snapshot compiler and invalidation tests for assignment changes,
  enabled-state changes, assigned-map value changes, deletion, and invalidation;
- playback tests for active remap, sequential restoration, unaffected phrases,
  unaffected tracks, and phrase-layer timing remaining output-step based;
- non-mutation regression tests for clips, generators, pattern slots, phrase
  cells, phrase layers, scenes, selected phrase state, transport, and unrelated
  state;
- engine/session tests for Off, On, Pending On, Pending Off, boundary
  application, stopped toggles, invalidation cleanup, and phrase-boundary race
  ordering;
- UI or view-model tests for picker create/rename/edit/assign/delete-blocked,
  active-map switching, identity/pass-through, reset, fixed phrase scope,
  unavailable/unassigned/invalid states, pending toggle rendering, focus, and
  accessibility.

Run the full Swift/package/app test command normally used by the build loop
after focused coverage. If the full suite is too slow or blocked, record the
blocker and provide the focused tests plus built-surface evidence that did run.

## Required Evidence

The future build loop should leave compact evidence under
`.meta/multipass/loops/build/step-order/` for:

- seam audit findings from the first slice;
- model and persistence tests;
- validation and invalid-data recovery tests;
- compiler and invalidation tests;
- playback remap, sequential restoration, and non-mutation tests;
- pending-toggle runtime and phrase-boundary tests;
- UI/view-model tests for picker/editor/assignment/toggle states;
- full-suite result or explicit blocker;
- visual or manual evidence from the actual built app surface.

Built-surface evidence should cover:

- creating, naming, editing, resetting, and deleting an unused map;
- assigning a map to the current phrase from the picker;
- switching the active phrase assignment from the editor control;
- assigned-map usage blocking deletion with visible reason;
- fixed `Phrase` scope with no editable per-track v1 controls;
- identity/pass-through labeling;
- output/source grid editing, auto-advance, and end-of-map wrap signal;
- running-playback Pending On or Pending Off clearing at the phrase boundary;
- stopped toggle applying immediately without pending state;
- non-16-step or invalid assignment showing unavailable state;
- audible remap and return to sequential playback without changing authored
  clip or phrase data.

Use the accepted wireframe as PM intent. Review the actual built app surface
for implementation evidence.

## Handoff Risks

- `existing-state.md` identified phrase+track feasibility, but accepted
  architecture and spec supersede that direction. V1 must stay phrase-only.
- The main correctness risk is applying the remap too early and accidentally
  remapping phrase-layer timing. V1 remaps source-step playback only.
- The tick path must read immutable compiled data only. SwiftUI state, live
  document traversal, map-ID lookup, and dynamic validation do not belong on
  the playback callback.
- Pending toggle state is runtime-only. It must not dirty, persist, undo,
  redo, export, or restore.
- Non-16-step phrases need explicit unavailable/blocking behavior. Hidden
  modulo behavior violates the accepted fixed-16 contract.
- Assigned-map deletion is blocked in v1. Do not invent reassignment,
  cascade-delete, or orphan cleanup UX beyond safe invalid-data recovery.
- UI completion requires assignment and active-map switching paths, not just a
  standalone map editor.

## V1 Exclusions

Do not implement or infer these in v1:

- editable per-track Step Order controls, opt-in, or opt-out;
- project-wide Step Order toggles or automatic application across all phrases;
- layer-level Step Order automation;
- variable-length maps or modulo behavior for arbitrary phrase lengths;
- stacked maps or transformations that add notes;
- shared data structures or controls with Note Repeat;
- mutation of clips, generated sources, pattern slots, phrase cells,
  phrase-layer automation, scenes, selected phrase state, or transport from
  Step Order playback.

## Product-Owner Attention

No product-owner decision is needed for build-loop promotion. The accepted open
questions, architecture, spec, and plan lock the conservative v1 defaults:
phrase-only assignment, top-level named map pool, fixed 16-step maps,
runtime-only pending state, non-destructive playback remapping, and deferred
per-track, project-wide, layer-level, variable-length, and stacked behavior.
