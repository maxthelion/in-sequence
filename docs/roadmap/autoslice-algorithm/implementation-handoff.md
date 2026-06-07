---
feature: autoslice-algorithm
created: 2026-06-07
status: accepted
sources:
  - docs/roadmap/autoslice-algorithm/open-questions.md
  - docs/roadmap/autoslice-algorithm/architecture.md
  - docs/roadmap/autoslice-algorithm/spec.md
  - docs/roadmap/autoslice-algorithm/plan.md
---

# Autoslice Algorithm Implementation Handoff

This is the accepted builder handoff for Autoslice Algorithm v1. It packages
the accepted PM artifacts into one implementation brief for a future
project-level decider or build loop. It does not promote the build loop, edit
product code, merge, rebase, push, or move runtime request files.

## Objective

Implement a deterministic, side-effect-free Swift autoslice analysis contract
that converts sample duration, sample rate, frame count, and caller-supplied
transient frames into ranked loop-boundary candidates.

The v1 build is intentionally isolated:

- algorithm file: `Sources/Audio/AutosliceAnalysis.swift`;
- tests: `Tests/SequencerAITests/Audio/AutosliceAnalysisTests.swift`;
- fixtures: `Tests/Fixtures/Autoslice/*.json`.

The analyzer returns BPM/bar hypotheses, candidate ranges, score components,
alignment details, stable candidate IDs, and diagnostic warnings. It does not
open audio files, detect transients, play audio, draw UI, mutate slicer models,
write the project document, or persist candidate history.

## Required Builder Inputs

Read these artifacts before implementation:

- `docs/roadmap/autoslice-algorithm/spec.md`
- `docs/roadmap/autoslice-algorithm/plan.md`
- `docs/roadmap/autoslice-algorithm/architecture.md`
- `docs/roadmap/autoslice-algorithm/open-questions.md`

Use `spec.md` as the source of truth for exact Swift names, defaults, scoring
formulas, warning behavior, fixture schema, and test acceptance. Use `plan.md`
for the implementation order and review gates.

## In Scope

Create `Sources/Audio/AutosliceAnalysis.swift` in the `SequencerAI` module
with the accepted internal contract:

- `AutosliceAnalyzer.analyze(input:configuration:)`
- `AutosliceAnalysisInput`
- `AutosliceTransient`
- `AutosliceTransientRole`
- `AutosliceConfiguration.default`
- `AutosliceBPMHypothesis`
- `AutosliceCandidateID`
- `AutosliceCandidate`
- `AutosliceTransientAlignment`
- `AutosliceResult`
- `AutosliceWarning`

Implementation may add private helpers in the same file for:

- BPM hypothesis generation;
- grid scoring;
- boundary search;
- candidate ranking and de-duplication;
- configuration normalization and warning aggregation.

Do not introduce a second analyzer, manager, view model, service, app
integration facade, or document mutation path for v1.

## Accepted Defaults

`AutosliceConfiguration.default` must match the spec exactly:

- `bpmRange`: `60...200`
- `bpmStep`: `0.5`
- `barCounts`: `[1, 2, 4, 8]`
- `snapToleranceSeconds`: `0.030`
- `maxStartSearchSeconds`: `0.500`
- `shortfallToleranceSeconds`: `0.050`
- `startSearchStepSeconds`: `0.005`
- `candidateDedupSeconds`: `0.020`
- `maxCandidatesPerHypothesis`: `3`
- `maxMergedCandidates`: `12`
- `roleWeightingEnabled`: `false`

If a caller supplies `maxStartSearchSeconds > 1.000`, clamp the effective
value to `1.000` and return `.maxStartSearchClamped`. Invalid numeric
configuration values should recover to safe defaults with
`.invalidConfigurationRecovered`.

## Algorithm Requirements

Generate duration-windowed hypotheses for every configured bar count and BPM
grid value:

```text
expectedDuration = bars * 4 * (60 / bpm)
durationError = durationSeconds - expectedDuration
```

A hypothesis is viable when:

```text
durationError >= -shortfallToleranceSeconds
durationError <= maxStartSearchSeconds
```

For each viable hypothesis, sweep start offsets from `0` through:

```text
min(maxStartSearchSeconds, max(0, durationSeconds - loopDurationSeconds))
```

using `startSearchStepSeconds`. Set `endSeconds` to
`startSeconds + loopDurationSeconds` and reject candidates that exceed the
sample duration by more than `shortfallToleranceSeconds`.

Score transient alignment against a 16th-note grid:

```text
gridStepSeconds = 60 / bpm / 4
transientSeconds = Double(frame) / sampleRate
adjustedSeconds = transientSeconds - startSeconds
nearestGridStep = round(adjustedSeconds / gridStepSeconds)
distanceSeconds = abs(adjustedSeconds - nearestGridStep * gridStepSeconds)
isOnGrid = distanceSeconds <= snapToleranceSeconds
```

A transient is relevant inside the loop range with snap tolerance at both
edges. `alignmentScore`, `coverageScore`, `meanGridDistanceSeconds`, on-grid
counts, relevant counts, and per-transient details must be exposed on returned
candidates.

Composite score:

```text
compositeScore =
    0.65 * alignmentScore +
    0.25 * durationFitScore +
    0.10 * coverageScore
```

Sort merged candidates by the accepted order from `spec.md`: composite score,
alignment score, duration fit, coverage, mean grid distance, start, BPM, then
bars. Keep at most `maxCandidatesPerHypothesis` per hypothesis and at most
`maxMergedCandidates` overall.

## Candidate Identity

Candidate identity must be deterministic and content-derived. Do not use
random `UUID()` values.

`AutosliceCandidateID` is derived from:

- `bpmTimesTen = round(bpm * 10)`
- `bars = hypothesis.bars`
- `startFrame = round(startSeconds * sampleRate)`
- `endFrame = round(endSeconds * sampleRate)`

Tests must assert concrete candidate identity for at least one fixture and
repeated analysis must return identical IDs, warnings, and sorted candidates.

## Role Weighting Boundary

Role weighting is optional diagnostic scoring only. It must not classify roles
from PCM, transient position, or spectral features.

- default: `roleWeightingEnabled == false`;
- disabled weighting: every relevant transient uses weight `1.0`;
- enabled weighting: kick and snare use `2.0`, hat and unknown use `1.0`;
- enabled weighting with all unknown roles returns
  `.roleWeightingWithoutKnownRoles`.

Spectral kick/snare/hat classification remains deferred.

## Fixtures And Tests

Add deterministic JSON fixtures under `Tests/Fixtures/Autoslice/` using the
schema in `spec.md`. Minimum fixture files:

- `clean-two-bar-120.json`
- `clean-one-bar-140.json`
- `two-bar-120-tail-bleed-80ms.json`
- `two-bar-120-tail-bleed-200ms.json`
- `two-bar-120-head-bleed.json`
- `ambiguous-double-time.json`
- `sparse-four-bar-90.json`
- `unknown-roles.json`
- `role-weighting-ranking.json`
- `too-short.json`

Add focused unit tests in
`Tests/SequencerAITests/Audio/AutosliceAnalysisTests.swift` covering the
accepted `spec.md` test set: clean loops, tail bleed, head bleed, ambiguous
double-time candidates, sparse/unknown-role behavior, role weighting, too-short
warnings or low confidence, invalid configuration recovery, and deterministic
repeat analysis.

The intended verification command is:

```sh
xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -only-testing:SequencerAITests/AutosliceAnalysisTests
```

If the local scheme or test target differs, build evidence must record the
exact replacement command and why it was used.

## Explicit Non-Goals

Do not include these in the first build:

- production slicer UI or waveform overlays;
- candidate audition or playback;
- engine seek or trigger commands;
- project document writes or `.seqai` schema changes;
- `SliceSet.bpmHint`, `SliceSet.bars`, `SliceMarker`, or `SliceMode`
  semantics;
- transient detection changes;
- spectral or positional role classification;
- app-facing algorithm tuning controls;
- build-loop promotion, merge, rebase, push, or request lifecycle edits.

## Review Gates

Future review should verify:

- exact contract fidelity against `spec.md`;
- defaults, clamping, formulas, warning behavior, and sort order;
- deterministic ordering and stable candidate identity;
- fixture coverage for clean, bleed, head-start, ambiguous, role, and
  too-short cases;
- no production UI, engine, document, persistence, transient detection, or
  slicer model changes;
- no parallel abstraction that duplicates the accepted analyzer contract.

Visual or Peekaboo evidence is not required for this first algorithm build
because the accepted v1 produces no user-facing surface.

## Readiness

Autoslice Algorithm now has accepted open-question reconciliation,
architecture, spec, plan, and implementation handoff artifacts. This makes the
PM artifact package ready for a project-level decider to consider promotion.
This artifact does not itself create or promote a build loop.

No product-owner attention is needed for v1 unless the scope changes to require
spectral role classification or literal in-app audition before the isolated
Swift analysis contract is implemented.
