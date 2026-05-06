---
id: write-p0-performance-overlay-build-plan
mode: build-planning
status: ready-for-agent
created: 2026-05-06T20:20:00+01:00
objective: Write the P0 production build plan for transient track-performance overlays
max_parallel: 1
requires_context_pack: true
source_reviews: docs/roadmap/agentic-loop/reviews/prepare-production-cherry-pick-candidates/
source_candidates: docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md
---

# Write P0 Performance Overlay Build Plan

## Objective

Create an agent-actionable production build plan for the transient
track-performance overlay before any code is ported from probe branches.

This is planning work only. Do not merge, push, cherry-pick, or modify Swift
production code in this pass.

## Required Inputs

- `README.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/roadmap/agentic-loop/reviews/prepare-production-cherry-pick-candidates/ux-ia.md`
- `docs/roadmap/agentic-loop/reviews/prepare-production-cherry-pick-candidates/architecture.md`
- `docs/roadmap/agentic-loop/reviews/prepare-production-cherry-pick-candidates/testing.md`
- `wiki/pages/live-view.md`
- `wiki/pages/playback-data-path.md`
- `wiki/pages/document-model.md`
- current production code around `LiveSequencerStoreState`,
  `PlaybackSnapshot`, `EngineController`, phrase cells, and track performance
  UI surfaces
- probe artifact `3a1d15d:Sources/Engine/TrackPerformanceOverrideLayer.swift`
  and its tests, read-only

## Expected Outputs

- `docs/plans/YYYY-MM-DD-track-performance-overlay.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/attention-ledger.md`
- this pass file, marked complete only after the build plan exists

## Plan Requirements

The build plan must specify:

- runtime/session owner for `trackPerformanceOverlay`;
- command API for multi-track fill, repeat intent, step-order intent, clear,
  Keep, and Discard;
- tick-path read point and precedence relative to `PlaybackSnapshot.resolvedStep`;
- Keep write destinations for authored phrase cells and any scene state in
  scope;
- Discard restore owner for authored phrase, scene, mixer, and overlay state;
- UI surface expectations for visible transient consequence, Keep target, and
  Discard target;
- tests proving audition does not mutate `Project`, Keep writes intentionally,
  Discard restores authored playback, and note-repeat sub-step behavior is
  either implemented or explicitly deferred.

## Stop Conditions

- Current production ownership cannot be identified from code/wiki.
- The plan would need a user product judgment before naming Keep/Discard
  semantics.
