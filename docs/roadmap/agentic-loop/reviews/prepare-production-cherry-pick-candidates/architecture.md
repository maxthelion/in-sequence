---
status: reviewed
verdict: pass
reviewed: 2026-05-06T20:20:00+01:00
source_pass: docs/roadmap/agentic-loop/passes/prepare-production-cherry-pick-candidates.md
reviewed_output: docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md
scheduled_follow_up: docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md
---

# Architecture Review

## Verdict

Pass with one required sequencing constraint: port only the pure value/test
seeds after a production ownership plan maps the overlay onto the existing
session, snapshot, engine, phrase, and UI command boundaries.

No correction pass is needed for the candidate list. The next pass should write
the P0 performance-overlay build plan.

## Evidence Checked

- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `wiki/pages/project-layout.md`
- `wiki/pages/document-model.md`
- `wiki/pages/playback-data-path.md`
- `wiki/pages/routing.md`
- `Sources/Document/Project+CapturedClips.swift`
- `Sources/Document/Project+TrackSources.swift`
- `Sources/Engine/PlaybackSnapshot.swift`
- `Sources/Audio/MainAudioGraph.swift`
- `3a1d15d:Sources/Engine/TrackPerformanceOverrideLayer.swift`
- `3a1d15d:Tests/SequencerAITests/Engine/TrackPerformanceOverrideLayerTests.swift`
- `a9bdbc4:Sources/Diagnostics/ObservabilityProbeModels.swift`
- `a9bdbc4:Tests/SequencerAITests/Diagnostics/ObservabilityProbeModelsTests.swift`
- `99834b3:Sources/UI/Inputs/AudioInputLoopingAutosliceProbeModel.swift`
- `6991918:Sources/UI/Mixer/MixerRoutingProbeModel.swift`

## What Passed

- `TrackPerformanceOverrideLayer` is a credible pure `Engine` value seed:
  it is `Equatable`/`Sendable`, owns no SwiftUI state, and has focused tests for
  fill fallback, multi-track updates, note-repeat precedence, step-order
  remapping, and clearing.
- The synthesis correctly refuses direct cherry-picks for audio buffers and
  mixer returns. Those probes live under `Sources/UI/...` and own local runtime
  or view state, while production needs `Project`, runtime audio buffer,
  routing, and `MainAudioGraph` ownership.
- The source-slot capture/history recommendation aligns with existing
  `Project.saveCapturedClip` and `SourceRef` behavior, which preserve generator
  and clip identity instead of replacing the source model.
- The playback plan warning is correct: the hot path reads
  `PlaybackSnapshot`, so runtime overrides need an explicit read point above or
  during `PlaybackSnapshot.resolvedStep(...)`, not arbitrary SwiftUI mutation.
- Observability can become developer tooling if renamed away from `Probe`,
  stripped of seeded samples, and placed behind a diagnostics path rather than
  a musician workspace.

## Caught

The candidate synthesis is intentionally not a build plan. The risky boundary
is the P0 performance integration: Keep/Discard needs named write and restore
owners before implementation. In particular, a production overlay must not
write phrase cells during audition, must not fork the tick path around
`PlaybackSnapshot`, and must not promise 1/32 or 1/64 note repeat until
sub-step scheduling ownership is designed.

The audio and mixer source artifacts should remain fully qualified in follow-up
briefs because their useful models live in UI probe files, not in current
production engine/audio graph boundaries.

## Scheduled

The next pass should write a focused build plan for a session/engine-owned
`trackPerformanceOverlay` with:

- runtime owner and lifecycle;
- command API for multi-track fill, repeat intent, step-order intent, clear,
  Keep, and Discard;
- tick-path read point and snapshot precedence;
- Keep destinations in phrase cells or scene state only after explicit action;
- Discard restoration from authored phrase/scene/mixer state;
- tests that prove audition does not mutate `Project`.
