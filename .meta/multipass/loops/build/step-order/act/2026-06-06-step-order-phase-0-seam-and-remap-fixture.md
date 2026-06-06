---
created: 2026-06-06T15:12:00Z
loop: build/step-order
phase: act
actor: builder
request: 2026-06-06T14-03-00-000Z-Step-Order-Phase-0-seam-and-remap-fixture
worktree: /Users/maxwilliams/dev/in-sequence/.worktrees/roadmap-16-step-order
branch: auto/roadmap-16-step-order
---

# Step Order Phase 0 Seam And Remap Fixture

## PM Doc Visibility

The accepted PM docs named by the request were not present in the feature
worktree at slice start. The following non-product roadmap docs were copied
from `/Users/maxwilliams/dev/in-sequence/docs/roadmap/step-order/` into this
branch so the build loop can see the accepted handoff:

- `docs/roadmap/step-order/implementation-handoff.md`
- `docs/roadmap/step-order/spec.md`
- `docs/roadmap/step-order/architecture.md`
- `docs/roadmap/step-order/plan.md`
- `docs/roadmap/step-order/open-questions.md`

## Seam Findings

- `EngineController.prepareTick` still derives phrase-local playback position
  from `upcomingStep`, but the direct modulo identified in `existing-state.md`
  has moved into `playbackPhraseForPrepare(upcomingStep:snapshot:)` and
  `phraseLocalStep(upcomingStep:cycleStartTick:stepCount:)`. `prepareTick`
  consumes the returned `stepInPhrase`.
- `PlaybackSnapshot.resolvedStep(phraseID:trackID:stepInPhrase:)` remains the
  source/pattern resolution path before per-track source reads. This slice
  extended it to expose `sourceStepIndex` and to use the compiled source step
  for pattern-slot and clip macro-override reads.
- Phrase-layer reads still use the original output step. `prepareTick` calls
  `layerSnapshot(phraseID:stepInPhrase:)` with the output `stepInPhrase`; this
  slice keeps `mute`, `fillEnabled`, and phrase macro values anchored to that
  output step even when source reads remap.
- `SequencerSnapshotCompiler.compilePhraseBuffer` still owns immutable phrase
  playback buffer construction. Incremental compilation still rebuilds phrase
  buffers through the existing `layersChanged`, `trackIDs`, and `phraseIDs`
  paths.
- `PhrasePlaybackBuffer` remains the correct phrase-level immutable home for
  v1 Step Order compiled data. This slice added `stepOrderMap: [UInt8]?` there;
  `TrackPhrasePlaybackBuffer` remains unchanged.
- Project save/load still routes through the document-root Codable path in
  `Project+Codable.swift`; phrase Codable ownership remains on `PhraseModel`.
  No durable Step Order project pool or phrase assignment was added in this
  phase-0 slice.

## Fixture Added

Added a deterministic non-SwiftUI engine fixture in
`Tests/SequencerAITests/Engine/PlaybackSnapshotBuffersOnlyTests.swift`.

Coverage:

- no compiled Step Order map resolves source steps sequentially as `0...15`;
- an injected immutable compiled map resolves the accepted remap
  `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]`;
- phrase-layer fill remains output-step based by asserting output step 11 keeps
  fill active while reading source step 0.

## Files Changed

- `Sources/Engine/PhrasePlaybackBuffer.swift`
- `Sources/Engine/PlaybackSnapshot.swift`
- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Engine/PlaybackSnapshotBuffersOnlyTests.swift`
- synced PM docs listed above
- this evidence artifact

## Checks Run

- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/PlaybackSnapshotBuffersOnlyTests`
  - passed: 8 tests, 0 failures
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/SequencerSnapshotCompilerSemanticsTests`
  - passed: 8 tests, 0 failures

## Remaining Risk

- `SequencerSnapshotCompiler` currently emits `stepOrderMap: nil` because the
  top-level map pool, phrase assignment, validation, persistence, and
  invalidation triggers are intentionally left for later Step Order slices.
- Full-suite coverage was not run in this bounded slice; focused engine and
  compiler checks passed.
- No product-owner attention is needed for this slice.
