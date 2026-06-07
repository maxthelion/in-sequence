---
feature: autoslice-algorithm
created: 2026-06-07
status: accepted
sources:
  - docs/roadmap/autoslice-algorithm/spec.md
  - docs/roadmap/autoslice-algorithm/architecture.md
  - docs/roadmap/autoslice-algorithm/open-questions.md
  - docs/roadmap/autoslice-algorithm/user-stories.md
  - docs/roadmap/autoslice-algorithm/existing-state.md
  - docs/roadmap/autoslice-algorithm/ux-review.md
next_artifact: docs/roadmap/autoslice-algorithm/implementation-handoff.md
---

# Autoslice Algorithm Plan

This accepted plan sequences the pure Swift Autoslice Algorithm contract from
`spec.md`. It is intentionally limited to the isolated analysis surface and
deterministic tests:

- `Sources/Audio/AutosliceAnalysis.swift`
- `Tests/SequencerAITests/Audio/AutosliceAnalysisTests.swift`
- `Tests/Fixtures/Autoslice/*.json`

The first build must not add production slicer UI, waveform overlays,
audition/playback, engine commands, document writes, persistence semantics,
`SliceSet`/`SliceMarker`/`SliceMode` mutations, build-loop promotion, merge,
rebase, push, or request lifecycle changes.

## Accepted Boundary

Implement the analyzer as a deterministic, side-effect-free Swift algorithm in
the `SequencerAI` module. The algorithm consumes sample duration, sample rate,
frame count, and caller-supplied transient frames. It returns duration-windowed
BPM/bar hypotheses, ranked loop-boundary candidates, score components,
alignment details, stable candidate IDs, and diagnostic warnings.

Do not open audio files, detect transients, play audio, draw UI, mutate the
project document, or persist candidate history. `SliceAnalyzer` can remain the
future provider of transient frames, but it is not part of the first algorithm
build unless a builder needs only adjacent test context.

## Implementation Sequence

### 1. Contract And Defaults

Create `Sources/Audio/AutosliceAnalysis.swift` with the internal names and
shapes accepted in `spec.md`:

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

Acceptance for this slice:

- the default configuration exactly matches the spec defaults;
- `maxStartSearchSeconds` is effectively clamped to `1.000` with a
  `.maxStartSearchClamped` warning when needed;
- invalid numeric configuration values recover to safe defaults with
  `.invalidConfigurationRecovered`;
- no random `UUID()` or non-deterministic identity is introduced.

### 2. Fixture Harness

Add JSON fixtures under `Tests/Fixtures/Autoslice/` using the fixture schema
from `spec.md`. Add a small test-side loader in
`Tests/SequencerAITests/Audio/AutosliceAnalysisTests.swift` that converts
fixture transient seconds to frames by rounding `seconds * sampleRate`.

Minimum fixture files:

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

Acceptance for this slice:

- fixtures contain synthetic analysis input only, not waveform samples or
  prototype UI state;
- tests can load fixtures deterministically from the test bundle or repo path;
- at least one fixture asserts a concrete `AutosliceCandidateID`.

### 3. BPM Hypothesis Generation

Implement duration-windowed hypothesis generation for configured bar counts
and BPM grid values.

Acceptance for this slice:

- supported defaults are 1, 2, 4, and 8 bars across 60...200 BPM at 0.5 BPM
  resolution;
- viability uses the accepted trim-aware window:
  `durationError >= -shortfallToleranceSeconds` and
  `durationError <= maxStartSearchSeconds`;
- `durationFitScore` follows the accepted positive/negative duration-error
  formulas;
- `integerBPMPrior` stays bounded and cannot override poor transient
  alignment;
- `.noViableHypotheses` and `.sampleTooShort` warnings are covered.

### 4. Boundary Search And Grid Scoring

Implement the private pure seams implied by the accepted architecture:

- BPM hypothesizer
- grid scorer
- boundary searcher
- candidate ranker

These may be private helpers in `AutosliceAnalysis.swift`; do not expose a
second analyzer, manager, view model, or integration facade.

Acceptance for this slice:

- start offsets sweep from `0` through
  `min(maxStartSearchSeconds, max(0, durationSeconds - loopDurationSeconds))`
  in `startSearchStepSeconds` increments;
- `endSeconds` is `startSeconds + loopDurationSeconds`;
- candidates beyond the shortfall tolerance are rejected;
- transient alignment uses the 16th-note grid formula from `spec.md`;
- relevance includes snap tolerance at both loop edges;
- `alignmentScore`, `coverageScore`, `meanGridDistanceSeconds`, on-grid
  counts, relevant counts, and per-transient details are exposed;
- `.noTransients` and `.noCandidates` warnings are covered.

### 5. Role Weighting

Implement optional role weighting exactly as diagnostic scoring, not spectral
classification.

Acceptance for this slice:

- role weighting defaults to disabled;
- when disabled, all relevant transients use weight `1.0`;
- when enabled, kick and snare weight `2.0`, hat and unknown weight `1.0`;
- when enabled and every transient is unknown, return
  `.roleWeightingWithoutKnownRoles`;
- no positional or spectral role classifier is added.

### 6. Ranking, De-Duplication, And Warnings

Implement candidate de-duplication, per-hypothesis truncation, merged ranking,
and warning aggregation.

Acceptance for this slice:

- de-duplicate candidates within `candidateDedupSeconds`, keeping the
  better-ranked candidate;
- each hypothesis keeps at most `maxCandidatesPerHypothesis`;
- the merged result keeps at most `maxMergedCandidates`;
- sort order exactly follows the spec:
  composite score, alignment score, duration fit, coverage, mean grid
  distance, start, BPM, bars;
- `AutosliceCandidateID` is derived from rounded BPM-times-ten, bars,
  start frame, and end frame;
- `.lowConfidenceTopCandidate` is returned when the top candidate exists and
  `compositeScore < 0.50`;
- repeated analysis of the same input returns identical hypotheses,
  candidates, IDs, warnings, and ordering.

## Test Plan

Add focused unit tests in
`Tests/SequencerAITests/Audio/AutosliceAnalysisTests.swift` covering the
spec acceptance set:

- clean fixtures return the expected BPM within `1.0` BPM and expected bar
  count;
- clean fixtures start at `0` and end at the known loop duration within one
  `startSearchStepSeconds` increment;
- tail-bleed fixtures include a high-ranked true-duration candidate with bleed
  outside the chosen range;
- head-bleed fixture returns a top candidate with non-zero `startSeconds`;
- ambiguous fixture returns at least two distinct candidates within `0.10`
  composite score;
- unknown-role fixture works with `roleWeightingEnabled == false`;
- role-weighting fixture changes ranking only when roles are supplied and
  weighting is enabled;
- too-short fixture returns a warning or low-confidence candidate, not a
  falsely confident exact loop;
- invalid/out-of-range configuration values recover with warning behavior;
- repeated analysis is deterministic.

The focused verification command for the future build is:

```sh
xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -only-testing:SequencerAITests/AutosliceAnalysisTests
```

If the local scheme or test target differs, build evidence must record the
exact replacement command and why it was used.

## Review Gates

The future implementation handoff should ask reviewers to verify:

- contract fidelity against `spec.md`;
- deterministic ordering and candidate identity;
- score formulas and warning behavior;
- fixture coverage for clean, bleed, head-start, ambiguous, role, and
  too-short cases;
- no production UI, engine, document, persistence, or slicer model changes in
  the first build;
- no second analyzer/manager abstraction that duplicates the accepted contract.

Visual or Peekaboo evidence is not required for this first algorithm build
because it intentionally produces no user-facing surface.

## Non-Goals

Do not include these in the first build:

- production slicer UI or waveform overlays;
- candidate audition or playback;
- engine seek/trigger commands;
- document persistence or `.seqai` schema changes;
- `SliceSet.bpmHint`, `SliceSet.bars`, `SliceMarker`, or `SliceMode`
  semantics;
- spectral kick/snare/hat classification;
- positional role auto-classification;
- manual algorithm tuning controls in the app;
- transient detection changes;
- build-loop promotion, merge, rebase, push, or request lifecycle edits.

## Remaining PM Gap

This plan is accepted and ready to feed
`docs/roadmap/autoslice-algorithm/implementation-handoff.md`.

Autoslice Algorithm is still not builder-ready until the implementation
handoff exists and a project-level decider explicitly consumes the readiness.
No product-owner decision is needed for this plan.
