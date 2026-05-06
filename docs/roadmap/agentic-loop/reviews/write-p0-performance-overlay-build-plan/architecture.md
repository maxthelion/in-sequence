---
status: reviewed
verdict: pass
reviewed: 2026-05-06T20:27:00+01:00
source_pass: docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md
reviewed_output: docs/plans/2026-05-06-track-performance-overlay.md
scheduled_follow_up: docs/plans/2026-05-06-track-performance-overlay.md
---

# Architecture Review

## Verdict

Pass after tightening the repeat and indexed-layer ownership in the build plan.
The corrected plan names implementable production owners and does not require
user product judgment before Swift work starts.

The next build should execute the plan in order: pure value/tests first,
engine/session ownership second, playback resolution third, UI last.

## Evidence Checked

- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/plans/2026-05-06-track-performance-overlay.md`
- `wiki/pages/live-view.md`
- `wiki/pages/playback-data-path.md`
- `wiki/pages/document-model.md`
- `Sources/Engine/LiveSequencerStore.swift`
- `Sources/Engine/PlaybackSnapshot.swift`
- `Sources/Engine/SequencerSnapshotCompiler.swift`
- `Sources/Engine/EngineController.swift`
- `Sources/App/SequencerDocumentSession.swift`
- `Sources/App/SequencerDocumentSession+Mutations.swift`
- `Sources/Document/PhraseModel.swift`
- `Sources/Document/MasterBus.swift`
- `Sources/UI/LiveWorkspaceView.swift`
- `Sources/UI/TracksMatrixView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`
- `3a1d15d:Sources/Engine/TrackPerformanceOverrideLayer.swift`
- `3a1d15d:Tests/SequencerAITests/Engine/TrackPerformanceOverrideLayerTests.swift`

## What Passed

- `EngineController` is the right runtime owner. The tick path already reads
  `currentPlaybackSnapshot` under the state lock and prepares notes from
  `EngineController.resolvedStepNotes(...)`.
- `SequencerDocumentSession` is the right command and transaction owner. It
  already coordinates store mutation, snapshot publication, scoped runtime
  updates, document flush, and master-bus save paths.
- The overlay is read above `PlaybackSnapshot.resolvedStep(...)` and is not
  stored inside `PlaybackSnapshot`, preserving the authored snapshot boundary.
- Keep destinations are implementable against existing phrase-cell mutation and
  master-bus mutation APIs.
- Discard can be implemented as a runtime restore coordinator: clear track and
  master-bus overlays, clear prepared output, and leave `Project`,
  `LiveSequencerStore`, phrase cells, scene state, mixer state, and routing
  untouched.

## Caught And Fixed

- Repeat capture needed an engine-owned pending state. The plan now distinguishes
  `.pendingStepLock` from `.stepLocked(capturedStepIndex:)`, so SwiftUI/session
  code does not infer the captured step from transport state.
- Repeat Keep needed an authored source-step destination. The plan now requires
  both `repeat-intent` and `repeat-source-step` layers.
- The new repeat/order layers cannot reuse `PhraseLayerValueType.patternIndex`,
  because that normalization is tied to `TrackPatternBank.slotCount`. The plan
  now requires a range-aware indexed value type or equivalent specialized layer
  targets.

## Guardrails For Implementation

- Do not add overlay state to `Project`, `LiveSequencerStoreState`, or
  `PlaybackSnapshot`.
- Do not call `apply(documentModel:)` or install a new snapshot when auditioning
  an overlay.
- Do not fork clip and generator playback paths. Add a small effective-step
  resolver that keeps mute, pattern slot, macro values, routing, and generator
  state on the authored path.
- Keep must be all-or-clear: failed repeat capture or unresolved phrase/layer
  destinations leave the overlay active.
- The current engine still prepares playback from `PlaybackSnapshot.selectedPhraseID`.
  Song-mode labels should use the shared Live/Tracks editing phrase resolver
  until engine song phrase playback catches up.
