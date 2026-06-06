---
feature: note-repeat
created: 2026-06-06
status: ready-for-build-loop-promotion
stage: implementation-handoff
sources:
  - README.md
  - docs/roadmap/note-repeat/architecture.md
  - docs/roadmap/note-repeat/spec.md
  - docs/roadmap/note-repeat/plan.md
  - docs/roadmap/note-repeat/open-questions.md
  - docs/roadmap/note-repeat/existing-state.md
  - docs/roadmap/note-repeat/user-stories.md
  - docs/roadmap/note-repeat/ux-review.md
  - docs/roadmap/note-repeat/prototypes/perform-page-toggle.html
  - docs/roadmap/note-repeat/prototypes/layer-interval-and-substep.html
---

# Note Repeat Implementation Handoff

## Purpose

This handoff packages the accepted Note Repeat v1 PM artifacts into
builder-ready scope. It should be used to open a future build loop, but it does
not itself promote a build loop, route implementation, create a worktree, or
schedule reviewers.

Note Repeat v1 is a track-local live performance override: the performer holds
Repeat from the tracks perform surface, the engine captures the current
quantized step's resolved clip-backed output, retriggers that captured material
at the track's stored interval, and rejoins normal transport-aligned playback
when the performer releases Repeat.

The feature supports the README performance-modification intent: fast,
performable variation that can be heard while the sequence runs, bounded by the
performer's preferences, and discarded without silently changing authored
phrase, clip, scene, or project state.

## Build-Loop Boundary

A future build loop should implement the full Note Repeat v1 workflow end to
end:

- Momentary press/hold Repeat control on the tracks perform surface for
  supported tracks.
- Command-shaped UI ingress equivalent to `engageNoteRepeat(trackID:)` and
  `releaseNoteRepeat(trackID:)`.
- Engine-owned active repeat runtime state keyed by track id, outside document
  state, persistence, undo, and redo.
- Current-step capture from resolved/prepared clip-backed output after normal
  phrase, fill, probability, and clip evaluation.
- Empty-step capture as silence, with no retriggers scheduled and normal
  release cleanup still available.
- Per-track repeat interval storage for exactly `1/16`, `1/32`, and `1/64`,
  defaulting missing or invalid stored values to `1/16`.
- Interval snapshot at engagement; stored interval edits apply only to the next
  engagement, not the active repeat.
- Engine-owned intra-step repeat scheduling anchored to the existing 1/16 step
  callback.
- No global `TickClock` resolution change in v1.
- Release, rapid re-engage, transport stop, source change, track deletion,
  project close, and playback session rebuild cleanup through one idempotent
  contract.
- Generator-backed or otherwise unsupported tracks disabled, unavailable, or
  suppressed in v1, with command ingress handled as a safe no-op.
- Built-surface evidence for supported inactive, active, released, interval
  feedback, and unsupported states.

The build should remain additive to the existing track, phrase, playback,
MIDI/audio output, and perform-surface paths. Do not broaden this into a global
sequencer timing rewrite, generator capture, phrase authoring, capture-to-clip,
or a redesign of track performance controls beyond the v1 Repeat workflow.

## Branch And Worktree Expectation

If this PM lane is promoted later, implementation should happen in a dedicated
build-loop branch and worktree, not as dirty product-code changes on `main`.
Use `build/note-repeat` and a dedicated worktree such as
`../in-sequence-note-repeat` unless the coordinator assigns a conflict-free
equivalent in `docs/multi-pass-coordinator/loops/build/note-repeat.yaml`.

The PM artifact source remains `docs/roadmap/note-repeat/`. Builders should
record build-loop evidence in the promoted build loop's runtime root, not in
the PM loop unless a later actor request explicitly asks for PM artifact
updates.

## Authoritative Context

| Artifact | Builder Use |
|---|---|
| `spec.md` | Primary behavior contract, acceptance criteria, edge cases, and verification requirements. |
| `plan.md` | Implementation and verification sequence for the build loop. |
| `architecture.md` | Accepted timing, runtime ownership, capture, persistence, cleanup, unsupported-source, and v1 default decisions. |
| `open-questions.md` | Resolved architecture and product-default questions; no current product-owner lock. |
| `existing-state.md` | Current integration seam map and known gaps to reconfirm before editing. |
| `ux-review.md` | Accepted prototype interpretation and UX gaps resolved by the architecture/spec. |
| `prototypes/perform-page-toggle.html` | Primary perform-surface reference for idle, engaged, released, and captured-step feedback. |
| `prototypes/layer-interval-and-substep.html` | Interval setting and sub-step explanation reference. |

## Exact First Implementation Slice

The first slice should reconfirm current seams and make engine behavior
testable before UI polish:

- Verify `TracksMatrixView` / `TrackMatrixCard` still own the tracks perform
  page and that current perform card actions still mutate selected phrase-layer
  cells rather than live runtime state.
- Verify Fill remains phrase-authored through the `"fill-flag"` layer and is
  not a live runtime precedent to copy for Repeat.
- Verify `EngineController.prepareTick`, `resolvedStepNotes`,
  `Executor.tick`, and `dispatchTick` remain the normal prepared-note and
  output path.
- Verify `TickClock` still fires once per 1/16 step.
- Verify `RollingCaptureBuffer` remains history/capture-to-clip precedent only
  unless proven current-step exact and release-safe.
- Verify `MidiOut.flushPendingNoteOffs(now:)` and equivalent engine flush paths
  are still available for cleanup.
- Create the smallest engine-focused test harness that can submit engage and
  release commands, advance ticks deterministically, and observe active runtime
  state or scheduled repeat output without relying on SwiftUI.

Exit this slice with a short build evidence note listing any integration seams
that moved since `existing-state.md`. If the current code shape makes
deterministic engine tests impractical, record that as a build-loop blocker
before broad UI work.

## Implementation Sequence

Follow the accepted `plan.md` sequence:

1. Reconfirm current seams and establish the focused engine test harness.
2. Add the `NoteRepeatInterval`-equivalent model and per-track persistence.
3. Introduce engine-owned active repeat runtime state and command ingress.
4. Implement current-step capture from resolved/prepared clip-backed output.
5. Add intra-step repeat scheduling without changing global `TickClock`
   resolution or normal step indexing.
6. Centralize release, rapid re-engage, and lifecycle cleanup.
7. Wire unsupported-source semantics in the engine and UI.
8. Build the perform-surface Repeat control and interval setting UI.
9. Run safety and non-regression review against the full spec.

Do not start with prototype polish. The feature is builder-ready only because
the runtime, timing, capture, and cleanup contracts are now explicit; those are
also the highest-risk parts of the build.

## Required Tests

The build loop should leave focused test evidence for:

- Interval persistence: all three v1 values encode/decode, old documents with
  no interval default to `1/16`, invalid values recover to `1/16`, stored
  interval edits dirty the document normally, and engage/release alone do not.
- Command ingress and runtime state: engage, release, duplicate release,
  invalid track, unsupported source no-op, no document mutation, no undo/redo
  mutation, and independent active state per track.
- Current-step capture: populated clip steps, fill/main lane selection,
  probability captured once, velocity/gate/note length preservation,
  empty-step silence, and no stale rolling-history, adjacent-step, or future
  capture source.
- Scheduler behavior: `1/16`, `1/32`, and `1/64` trigger counts inside one
  1/16 step, sub-step events anchored to the current step tick, no main
  step-counter advancement for intra-step retriggers, and normal non-repeat
  track timing unchanged.
- Cleanup and safety: release inside a step, release at a step boundary, rapid
  release/re-engage, transport stop, source change, track deletion, project
  close, playback session rebuild, no stuck MIDI notes, and no retained
  audio/sample/AU repeat events after release.
- Unsupported states: generator-backed tracks disabled/unavailable/suppressed,
  unsupported engage safe no-op, active repeat cleanup when a track becomes
  unsupported, and missing/invalid interval recovery before UI/engine use.
- UI/view-model behavior: supported inactive, active, released, unsupported,
  interval feedback, track-local association, and independence from the
  selected phrase layer.

The final build pass should also run the normal project test command used by
the build loop. If the full suite is too slow or blocked, record the blocker
and provide the focused engine, persistence, scheduler, cleanup, unsupported,
and built-surface evidence that did run.

## Required Review Evidence

A reviewer should be able to verify all of these from the build-loop evidence:

- Engage and release do not mutate phrase cells, selected layer values, clips,
  scenes, track source data, persisted project data, undo, or redo.
- Active repeat state is runtime-only, engine-owned, and cleared by every
  release or lifecycle invalidation path.
- SwiftUI sends commands through the existing thread-safe command queue or
  state-lock pattern; playback callbacks do not read SwiftUI view state.
- Capture is current-step exact at the engine command application point and
  replays captured material rather than re-running probability.
- Empty-step capture behaves as silence rather than failed engage or nearby
  step snapping.
- Multi-track active repeat state is independent where multiple supported
  controls can be active.
- Sub-step scheduling does not change global `TickClock` resolution, normal
  step indexing, phrase advancement, fill/main lane evaluation, probability
  resolution, or output timing for non-repeat tracks.
- Cleanup cancels pending sub-step events and flushes MIDI note-offs plus
  equivalent audio/sample/AU obligations.
- Generator-backed tracks are explicitly unavailable in v1 and command ingress
  remains safe for unsupported sources.

## UX And Visual Evidence Expectations

Review the actual built surface, not only the prototypes. Required visual or
manual evidence:

- Tracks perform surface with a Repeat control visually associated with its
  track.
- Supported inactive state.
- Momentary active press/hold state with the repeating track and interval
  snapshot visible.
- Released state showing return to inactive without jumping transport back to
  the captured step.
- Unsupported generator-backed or otherwise unsupported state, disabled,
  unavailable, or suppressed with a clear inactive presentation.
- Interval setting UI for `1/16`, `1/32`, and `1/64` in the accepted track
  layer settings area.
- Evidence that changing the stored interval while Repeat is active does not
  change the current runtime interval snapshot.
- Evidence that Repeat controls remain independent of the currently selected
  phrase layer and do not create visible phrase-cell edits or dirty-state
  changes from engage/release alone.

Use `prototypes/perform-page-toggle.html` for the primary perform-surface
mental model and `prototypes/layer-interval-and-substep.html` for interval
setting and sub-step communication. Treat prototype styling and DOM structure
as reference evidence, not production implementation requirements.

## V1 Exclusions

Do not implement or infer these in v1:

- latch, tap-toggle, or hybrid tap/hold Repeat behavior;
- generator-backed repeat capture;
- phrase-step, bar-level, scene-level, or automated repeat interval changes;
- mid-engagement interval changes;
- interval setup directly in perform mode;
- global `TickClock` resolution changes;
- detached SwiftUI or UI-owned repeat timers;
- phrase-cell authoring from the Repeat control;
- capture-to-clip, undoable Repeat state, redoable Repeat state, or persisted
  active repeat restoration;
- broad redesign of the tracks perform page beyond the controls needed for
  Note Repeat v1.

## Promotion-Readiness Criteria

This PM lane is ready for project build-loop promotion when this handoff, the
accepted architecture, accepted spec, and accepted plan are all available to
the decider. That condition is now met.

A future promotion should still be sparse: create one bounded build loop for
Note Repeat v1, point it at this handoff and the accepted PM artifacts, assign
the dedicated branch/worktree, and require the evidence listed above before
review or integration.

## Residual Risks

- Sub-step scheduling is the largest implementation risk. Review must verify
  that no hidden global sequencer timing rewrite or `TickClock` resolution
  change landed.
- Current-step capture must happen at the engine command application point. A
  stale rolling-history implementation would violate the product contract.
- Thread discipline matters because playback callbacks must consume an
  engine-safe snapshot, not SwiftUI state.
- Cleanup must be centralized and idempotent. Ad hoc release paths are likely
  to leave stuck notes, doubled notes, or retained scheduled events.
- Empty-step capture should be silent but still cleanup-safe; treating it as a
  failed engage can make UI and release semantics ambiguous.
- Interval persistence is document state, but active repeat state is not.
  Mixing them can create dirty-state, undo, restore, or migration bugs.
- Generator-backed tracks must remain explicitly unavailable in v1. Silent
  partial support would reopen unresolved capture semantics.
- Existing Fill behavior is phrase-authored. Builders should not copy Fill's
  phrase-cell mutation path for Repeat.

## Product-Owner Attention

No product-owner decision is needed for build-loop promotion. The accepted
architecture, spec, plan, open-question defaults, UX review, and prototypes
close the v1 product choices needed for implementation:

- Repeat is momentary press/hold.
- Clip-backed tracks are the supported v1 source scope.
- Empty-step capture is silence.
- Interval changes apply on next engagement.
- Interval setup may remain outside perform mode.
- Runtime active state is engine-owned and not persisted.
- Global `TickClock` resolution remains unchanged in v1.
