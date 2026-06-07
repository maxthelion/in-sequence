---
feature: autoslice-algorithm
created: 2026-06-07
status: spec-ready-for-plan
sources:
  - docs/roadmap/autoslice-algorithm/open-questions.md
  - docs/roadmap/autoslice-algorithm/architecture.md
  - docs/roadmap/autoslice-algorithm/user-stories.md
  - docs/roadmap/autoslice-algorithm/existing-state.md
  - docs/roadmap/autoslice-algorithm/ux-review.md
  - docs/roadmap/autoslice-algorithm/prototypes/bpm-hypothesis.html
  - docs/roadmap/autoslice-algorithm/prototypes/loop-boundary-heuristic.html
next_artifact: docs/roadmap/autoslice-algorithm/plan.md
---

# Autoslice Algorithm Spec

## Product Shape

Autoslice Algorithm v1 is a pure Swift analysis contract for turning sample
duration and detected transient frames into ranked loop boundary candidates.
It is not a production slicer UI, playback feature, document persistence
change, or automatic edit to a `SliceSet`.

The accepted v1 behavior combines the BPM-duration signal from
`prototypes/bpm-hypothesis.html` with the loop-boundary search and grid
alignment approach from `prototypes/loop-boundary-heuristic.html`.

## First Implementation Target

The first build target is a production Swift algorithm in the existing app
module, covered by deterministic unit tests. It should not create a standalone
prototype target before the pure Swift contract exists.

Add:

- `Sources/Audio/AutosliceAnalysis.swift`
- `Tests/SequencerAITests/Audio/AutosliceAnalysisTests.swift`
- `Tests/Fixtures/Autoslice/*.json`

Do not modify in the first algorithm build:

- `Sources/UI/Slicer/SliceTrackWorkspaceView.swift`
- `Sources/UI/Slicer/SlicerWaveformView.swift`
- `Sources/Document/SliceSet.swift`
- `Sources/Document/SliceMarker.swift`
- `Sources/Document/SliceMode.swift`
- engine playback, audition, or project document persistence paths.

`SliceAnalyzer` may stay responsible for existing `gridSlices` and
`transientSlices`. The v1 autoslice algorithm consumes transient frames that a
caller supplies; it does not open audio files or run onset detection itself.

## Swift Contract

`Sources/Audio/AutosliceAnalysis.swift` must define these internal Swift names
in the `SequencerAI` module:

```swift
enum AutosliceAnalyzer {
    static func analyze(
        input: AutosliceAnalysisInput,
        configuration: AutosliceConfiguration = .default
    ) -> AutosliceResult
}

struct AutosliceAnalysisInput: Equatable, Sendable {
    var durationSeconds: Double
    var sampleRate: Double
    var frameCount: Int64
    var transients: [AutosliceTransient]
}

struct AutosliceTransient: Equatable, Sendable {
    var frame: Int64
    var role: AutosliceTransientRole
}

enum AutosliceTransientRole: String, Codable, Sendable {
    case kick
    case snare
    case hat
    case unknown
}

struct AutosliceConfiguration: Equatable, Sendable {
    static let `default`: AutosliceConfiguration

    var bpmRange: ClosedRange<Double>
    var bpmStep: Double
    var barCounts: [Int]
    var snapToleranceSeconds: Double
    var maxStartSearchSeconds: Double
    var shortfallToleranceSeconds: Double
    var startSearchStepSeconds: Double
    var candidateDedupSeconds: Double
    var maxCandidatesPerHypothesis: Int
    var maxMergedCandidates: Int
    var roleWeightingEnabled: Bool
}

struct AutosliceBPMHypothesis: Equatable, Sendable {
    var bpm: Double
    var bars: Int
    var expectedDurationSeconds: Double
    var durationErrorSeconds: Double
    var durationFitScore: Double
    var integerBPMPrior: Double
}

struct AutosliceCandidateID: Hashable, Sendable, CustomStringConvertible {
    var bpmTimesTen: Int
    var bars: Int
    var startFrame: Int64
    var endFrame: Int64
}

struct AutosliceCandidate: Equatable, Identifiable, Sendable {
    var id: AutosliceCandidateID
    var hypothesis: AutosliceBPMHypothesis
    var startFrame: Int64
    var endFrame: Int64
    var startSeconds: Double
    var endSeconds: Double
    var alignmentScore: Double
    var durationFitScore: Double
    var coverageScore: Double
    var meanGridDistanceSeconds: Double
    var onGridTransientCount: Int
    var relevantTransientCount: Int
    var compositeScore: Double
    var details: [AutosliceTransientAlignment]
}

struct AutosliceTransientAlignment: Equatable, Sendable {
    var transient: AutosliceTransient
    var adjustedSeconds: Double
    var nearestGridStep: Int
    var distanceSeconds: Double
    var isOnGrid: Bool
    var isInCandidateRange: Bool
}

struct AutosliceResult: Equatable, Sendable {
    var hypotheses: [AutosliceBPMHypothesis]
    var candidates: [AutosliceCandidate]
    var warnings: [AutosliceWarning]
}

struct AutosliceWarning: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case noTransients
        case noViableHypotheses
        case noCandidates
        case maxStartSearchClamped
        case lowConfidenceTopCandidate
        case roleWeightingWithoutKnownRoles
        case invalidConfigurationRecovered
        case sampleTooShort
    }

    var kind: Kind
    var message: String
    var valueSeconds: Double?
}
```

Implementation may add private helpers in the same file. Do not expose a
second public analyzer, manager, view model, or document mutation path for this
v1 contract.

## Accepted Defaults

`AutosliceConfiguration.default` must use:

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

If a caller supplies `maxStartSearchSeconds > 1.000`, the analyzer must clamp
the effective value to `1.000` and include a `.maxStartSearchClamped` warning.
The default remains `0.500`.

## Algorithm Contract

The analyzer must be deterministic and side-effect-free. Given the same input
and configuration, it returns the same hypotheses, candidates, candidate IDs,
warnings, and ordering.

### BPM Hypotheses

For every configured bar count and BPM grid value:

```text
expectedDuration = bars * 4 * (60 / bpm)
durationError = durationSeconds - expectedDuration
```

A hypothesis is viable when:

```text
durationError >= -shortfallToleranceSeconds
durationError <= maxStartSearchSeconds
```

Duration fit score:

```text
if durationError >= 0:
    durationFitScore = 1 - min(durationError / maxStartSearchSeconds, 1)
else:
    durationFitScore = 1 - min(abs(durationError) / shortfallToleranceSeconds, 1)
```

`integerBPMPrior` is allowed only as a bounded tie-breaker. It must not allow a
poorly aligned integer BPM to outrank a strongly aligned non-integer BPM.

### Boundary Search

For each viable hypothesis:

1. Compute `loopDurationSeconds`.
2. Compute `maxStart = min(maxStartSearchSeconds, max(0, durationSeconds - loopDurationSeconds))`.
3. Sweep `startSeconds` from `0` through `maxStart` in
   `startSearchStepSeconds` increments.
4. Set `endSeconds = startSeconds + loopDurationSeconds`.
5. Reject a candidate if `endSeconds` exceeds `durationSeconds` by more than
   `shortfallToleranceSeconds`.

Tail bleed is represented by `startSeconds == 0` and `endSeconds` before the
sample end. Head bleed is represented by a non-zero `startSeconds`. V1 does
not stretch, pad, or repair short audio.

### Grid Alignment

Grid step duration:

```text
gridStepSeconds = 60 / bpm / 4
```

For each transient:

```text
transientSeconds = Double(frame) / sampleRate
adjustedSeconds = transientSeconds - startSeconds
nearestGridStep = round(adjustedSeconds / gridStepSeconds)
distanceSeconds = abs(adjustedSeconds - nearestGridStep * gridStepSeconds)
isOnGrid = distanceSeconds <= snapToleranceSeconds
```

A transient is relevant when:

```text
adjustedSeconds >= -snapToleranceSeconds
adjustedSeconds <= loopDurationSeconds + snapToleranceSeconds
```

Default role weights are:

| Role | Weight |
| --- | ---: |
| `kick` | 2.0 |
| `snare` | 2.0 |
| `hat` | 1.0 |
| `unknown` | 1.0 |

When `roleWeightingEnabled` is `false`, all relevant transients have weight
`1.0`. When role weighting is enabled and every transient role is `unknown`,
the result must include `.roleWeightingWithoutKnownRoles`.

Alignment score:

```text
alignmentScore = weightedOnGridTransientTotal / weightedRelevantTransientTotal
```

Coverage score:

```text
coverageScore = relevantTransientCount / max(totalTransientCount, 1)
```

Composite score:

```text
compositeScore =
    0.65 * alignmentScore +
    0.25 * durationFitScore +
    0.10 * coverageScore
```

## Candidate Identity And Ranking

Candidate identity must not use random `UUID()` values.

`AutosliceCandidateID` is derived from analysis content:

```text
bpmTimesTen = round(bpm * 10)
bars = hypothesis.bars
startFrame = round(startSeconds * sampleRate)
endFrame = round(endSeconds * sampleRate)
```

Candidate IDs must be stable across repeated runs with the same input and
configuration. Tests should assert candidate IDs directly for at least one
fixture.

Within each hypothesis, candidates are de-duplicated by start offset within
`candidateDedupSeconds`, keeping the better-ranked candidate. Each hypothesis
keeps at most `maxCandidatesPerHypothesis`.

Merged candidates sort by:

1. `compositeScore` descending
2. `alignmentScore` descending
3. `durationFitScore` descending
4. `coverageScore` descending
5. `meanGridDistanceSeconds` ascending
6. `startSeconds` ascending
7. `bpm` ascending
8. `bars` ascending

The result keeps at most `maxMergedCandidates`.

## Warning Behavior

Warnings are diagnostics, not thrown errors. The analyzer should return the
best available result even when warning conditions are present.

Required warning behavior:

- `.noTransients`: input has no transient frames; hypotheses may still be
  returned, but candidates have `alignmentScore == 0`.
- `.noViableHypotheses`: no configured BPM/bar pair fits the duration window.
- `.noCandidates`: viable hypotheses exist but all boundary candidates are
  rejected or removed.
- `.maxStartSearchClamped`: caller requested a search range above `1.000`
  seconds.
- `.lowConfidenceTopCandidate`: the top candidate exists but has
  `compositeScore < 0.50`.
- `.roleWeightingWithoutKnownRoles`: role weighting is enabled but all
  transient roles are `unknown`.
- `.invalidConfigurationRecovered`: invalid numeric configuration values were
  normalized to safe defaults.
- `.sampleTooShort`: at least one otherwise plausible hypothesis was rejected
  only because the sample was shorter than the accepted shortfall tolerance.

Tests should assert warning kinds, not localized message text.

## Fixture Format

Fixtures live under `Tests/Fixtures/Autoslice/` as JSON. Each fixture describes
synthetic analysis input; no WAV decoding is required for the v1 algorithm
tests.

Fixture schema:

```json
{
  "name": "two-bar-120-tail-bleed-180ms",
  "sampleRate": 44100,
  "durationSeconds": 4.18,
  "transients": [
    { "seconds": 0.0, "role": "kick" },
    { "seconds": 0.5, "role": "snare" }
  ],
  "expected": {
    "topBpm": 120.0,
    "topBars": 2,
    "topStartSeconds": 0.0,
    "topEndSeconds": 4.0,
    "minCompositeScore": 0.80,
    "warnings": []
  }
}
```

The test loader converts each transient `seconds` value to `frame` by rounding
`seconds * sampleRate`. The fixture format may include extra transients and
expected candidate counts, but it must not include waveform samples or
prototype-only UI state.

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

## Test Acceptance

`Tests/SequencerAITests/Audio/AutosliceAnalysisTests.swift` must cover:

- clean fixtures return the expected BPM within `1.0` BPM and expected bar
  count;
- clean fixtures start at `0` and end at the known loop duration within one
  `startSearchStepSeconds` increment;
- tail-bleed fixtures include a high-ranked candidate with the true loop
  duration and the bleed outside the candidate range;
- head-bleed fixture returns a top candidate with non-zero `startSeconds`;
- ambiguous fixture returns at least two distinct candidates within `0.10`
  composite score of each other;
- unknown-role fixture works with `roleWeightingEnabled == false`;
- role-weighting fixture changes candidate ranking when roles are supplied and
  `roleWeightingEnabled == true`;
- too-short fixture returns a warning or low-confidence candidate, not a
  falsely confident exact loop;
- repeated analysis of the same fixture returns identical candidate IDs,
  warnings, and sorted candidate order;
- invalid or out-of-range configuration values are recovered with warning
  behavior rather than crashes.

The future build loop should run at least:

```sh
xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -only-testing:SequencerAITests/AutosliceAnalysisTests
```

If the scheme names differ in the build environment, the build evidence must
record the exact replacement command.

## Future UI And Audition Boundary

V1 returns auditionable data only: `startFrame`, `endFrame`, `startSeconds`,
`endSeconds`, score components, and transient alignment details. It does not:

- play candidate audio;
- seek or trigger the engine;
- draw waveform overlays;
- update a selected candidate in the slicer UI;
- write `SliceSet`, `SliceMarker`, `SliceMode`, `bpmHint`, or `bars`;
- persist ranked candidate history in `.seqai`;
- expose algorithm tuning controls in production UI.

A future integration can use candidate ranges for waveform previews or
audition commands, but that work needs its own plan and acceptance evidence.

## Readiness

This spec is accepted and ready to feed `docs/roadmap/autoslice-algorithm/plan.md`.
It does not make Autoslice Algorithm builder-ready by itself; accepted
`plan.md` and `implementation-handoff.md` are still required before promotion.

No product-owner decision is needed for this spec. The accepted architecture
supports v1 without adding spectral role classification or in-app audition.
