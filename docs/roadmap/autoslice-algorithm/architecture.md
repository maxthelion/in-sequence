---
feature: autoslice-algorithm
created: 2026-06-07
status: accepted-builder-facing
sources:
  - docs/roadmap/autoslice-algorithm/open-questions.md
  - docs/roadmap/autoslice-algorithm/notes.md
  - docs/roadmap/autoslice-algorithm/user-stories.md
  - docs/roadmap/autoslice-algorithm/existing-state.md
  - docs/roadmap/autoslice-algorithm/ux-review.md
  - docs/roadmap/autoslice-algorithm/prototypes/bpm-hypothesis.html
  - docs/roadmap/autoslice-algorithm/prototypes/loop-boundary-heuristic.html
---

# Autoslice Algorithm Accepted Architecture

This is accepted PM architecture for the next Autoslice Algorithm spec pass.
It defines the Swift-facing heuristic contract for ranked loop-boundary
candidates. It does not wire the algorithm into the production app; spec,
plan, implementation handoff, and build-loop promotion remain downstream.

## V1 Shape

Autoslice Algorithm v1 is a pure analysis pipeline:

1. Accept sample duration, sample rate, frame count, and detected transient
   frames.
2. Generate duration-windowed BPM/bar hypotheses for 1, 2, 4, and 8 bar loops.
3. For each viable hypothesis, sweep loop-start offsets across a bounded
   search range.
4. Score each start/end candidate by transient alignment against a 16-step
   grid.
5. Merge candidates across hypotheses into one ranked list with separate score
   components and a composite score.

The pipeline is deterministic and side-effect-free after its inputs are
provided. It does not read files, detect transients, play audio, write the
project document, or mutate slice sets.

## Product Basis

The accepted UX basis is `prototypes/loop-boundary-heuristic.html` as the
primary direction, with `prototypes/bpm-hypothesis.html` as upstream duration
logic.

Accepted carry-forward behavior:

- derive plausible BPM/bar candidates from sample duration;
- treat duration as a candidate window, not a final answer, so slightly
  overlong loops can still surface their true BPM;
- score transient alignment against a 16th-note grid;
- search start offsets over the full accepted range instead of one step;
- return multiple de-duplicated candidates;
- carry optional roles and role weights, but do not require spectral role
  classification;
- keep the prototype/app integration boundary explicit.

## Swift-Facing Contract

Exact names can change during spec, but the production contract should preserve
these data shapes and semantics.

```swift
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
    var bpmRange: ClosedRange<Double>       // default 60...200
    var bpmStep: Double                     // default 0.5
    var barCounts: [Int]                    // default [1, 2, 4, 8]
    var snapToleranceSeconds: Double        // default 0.030
    var maxStartSearchSeconds: Double       // default 0.500, hard max 1.000
    var shortfallToleranceSeconds: Double   // default 0.050
    var startSearchStepSeconds: Double      // default 0.005
    var candidateDedupSeconds: Double       // default 0.020
    var maxCandidatesPerHypothesis: Int     // default 3
    var maxMergedCandidates: Int            // default 12
    var roleWeightingEnabled: Bool          // default false until roles exist
}

struct AutosliceBPMHypothesis: Equatable, Sendable {
    var bpm: Double
    var bars: Int
    var expectedDurationSeconds: Double
    var durationErrorSeconds: Double
    var durationFitScore: Double
    var integerBPMPrior: Double
}

struct AutosliceCandidate: Equatable, Sendable, Identifiable {
    var id: UUID
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
```

`UUID` is acceptable for candidate identity only if generated deterministically
within a result or replaced by a stable rank/path identifier. Tests should not
depend on random IDs.

## BPM Hypothesis Generation

V1 must be trim-aware.

For each bar count and BPM value on the configured grid:

```text
expectedDuration = bars * 4 * (60 / bpm)
durationError = sampleDuration - expectedDuration
```

Interpretation:

- `durationError == 0`: exact duration fit.
- `durationError > 0`: sample has extra audio that may be trimmed from the
  head or excluded from the tail.
- `durationError < 0`: sample is shorter than the hypothesis duration.

A hypothesis is viable when:

```text
durationError >= -shortfallToleranceSeconds
durationError <= maxStartSearchSeconds
```

This differs from the simplest sandbox 1 implementation, which analytically
inverts duration to one exact BPM per bar count. The accepted production
contract still uses duration as the upstream signal, but it keeps nearby BPMs
whose expected loop duration fits inside the accepted extra-audio window. This
is required for slightly-too-long samples where exact inversion would choose a
slower BPM than the musical loop.

The default duration score is:

```text
if durationError >= 0:
    durationFitScore = 1 - min(durationError / maxStartSearchSeconds, 1)
else:
    durationFitScore = 1 - min(abs(durationError) / shortfallToleranceSeconds, 1)
```

`integerBPMPrior` is a small bounded prior favoring whole-number BPM values. It
must never override poor transient alignment.

## Boundary Search

For each viable BPM/bar hypothesis:

1. Compute `loopDurationSeconds`.
2. Compute the maximum auditionable start:
   `min(maxStartSearchSeconds, max(0, durationSeconds - loopDurationSeconds))`.
3. Sweep start offsets from `0` through that maximum at
   `startSearchStepSeconds`.
4. Set `endSeconds = startSeconds + loopDurationSeconds`.
5. Reject any candidate whose end exceeds the input duration by more than the
   shortfall tolerance.

The search is intentionally start-offset based. Tail bleed is handled by a
candidate with `startSeconds == 0` and an end before the sample's final frame.
Head bleed is handled by a non-zero start. V1 does not time-stretch, pad, or
repair genuinely short samples.

## Grid Alignment Scoring

Grid step duration:

```text
gridStepSeconds = 60 / bpm / 4
```

For each transient, compute:

```text
adjustedSeconds = transientSeconds - startSeconds
nearestGridStep = round(adjustedSeconds / gridStepSeconds)
distanceSeconds = abs(adjustedSeconds - nearestGridStep * gridStepSeconds)
isOnGrid = distanceSeconds <= snapToleranceSeconds
```

A transient is relevant when its adjusted time is inside the candidate loop
region, allowing the snap tolerance at both edges:

```text
adjustedSeconds >= -snapToleranceSeconds
adjustedSeconds <= loopDurationSeconds + snapToleranceSeconds
```

Default role weights:

| Role | Weight |
| --- | ---: |
| `kick` | 2.0 |
| `snare` | 2.0 |
| `hat` | 1.0 |
| `unknown` | 1.0 |

When role weighting is disabled, every relevant transient has weight `1.0`.
When no relevant transient exists, `alignmentScore` is `0` and the result
should include a warning.

Alignment score:

```text
alignmentScore = weightedOnGridTransientTotal / weightedRelevantTransientTotal
```

Mean grid distance is the unweighted mean `distanceSeconds` for relevant
transients. It is a tie-break and diagnostic, not the primary score.

Coverage score:

```text
coverageScore = relevantTransientCount / max(totalTransientCount, 1)
```

Coverage prevents a candidate that ignores most of the sample's detected
material from winning solely because a few included hits align cleanly. A
single tail-bleed hit outside the loop should lower coverage slightly, not
invalidate an otherwise strong candidate.

## Candidate Ranking

Each hypothesis keeps its top `maxCandidatesPerHypothesis` after de-duplicating
start offsets within `candidateDedupSeconds`.

Composite score:

```text
compositeScore =
    0.65 * alignmentScore +
    0.25 * durationFitScore +
    0.10 * coverageScore
```

Composite score is only for ranking. The result must expose the component
scores so future UI and tests can explain why a candidate won.

Merged candidates sort by:

1. `compositeScore` descending;
2. `alignmentScore` descending;
3. `durationFitScore` descending;
4. `coverageScore` descending;
5. `meanGridDistanceSeconds` ascending;
6. `startSeconds` ascending;
7. `bpm` ascending;
8. `bars` ascending.

The returned list is truncated to `maxMergedCandidates`. The top candidate is
the algorithm's best suggestion, not an automatic edit to the project.

## Fixture Expectations

The next spec/plan should define a small deterministic fixture set before
production integration.

Minimum fixtures:

- clean 2-bar loop at 120 BPM with transients on beats and 16ths;
- clean 1-bar loop at 140 BPM;
- 2-bar 120 BPM loop with 80 ms tail bleed;
- 2-bar 120 BPM loop with 180-200 ms tail bleed;
- loop with head bleed where the best start is non-zero;
- ambiguous double-time fixture where multiple candidates remain close;
- sparse 4-bar loop at 90 BPM;
- no-role fixture to prove `unknown` roles work without role weighting;
- optional-role fixture to prove kick/snare weighting changes ranking without
  requiring spectral classification;
- too-short fixture that produces a warning or low score rather than a false
  confident candidate.

Expected acceptance signals:

- clean fixtures return the known BPM within 1 BPM and start at 0;
- overlong fixtures include at least one high-ranked candidate with the true
  loop duration and the bleed outside the chosen range;
- ambiguous fixtures return multiple distinct candidates;
- no fixture requires writing `Sources/` to evaluate the heuristic contract.

## Test Seams

Implementation should keep the algorithm split into pure seams:

- `AutosliceBPMHypothesizer`: duration, BPM range, bar counts, and search
  window in; sorted hypotheses out.
- `AutosliceGridScorer`: one hypothesis, one start offset, transients, and
  config in; one scored candidate out.
- `AutosliceBoundarySearcher`: one hypothesis and input in; de-duplicated
  candidates out.
- `AutosliceCandidateRanker`: per-hypothesis candidates in; merged ranked list
  out.

These seams should be testable with synthetic frame/time arrays. File loading,
waveform rendering, transient detection, UI state, project persistence, and
engine playback must stay outside these unit tests.

## Existing-Code Boundary

Existing production code provides useful future inputs but is not part of this
PM artifact's build scope:

- `SliceAnalyzer.transientSlices(file:sensitivity:)` can provide transient
  frames in a later integration.
- `AudioSample.lengthSeconds`, `lengthFrames`, and `sampleRate` can provide
  duration and conversion inputs.
- `WaveformDownsampler` can support later visual evidence.
- `SliceSet.bpmHint` and `SliceSet.bars` exist but currently have no accepted
  production semantics for this feature.
- `SliceMarker` has no role field, and v1 does not require one.

No builder should change `Sources/` from this architecture alone. A later spec
must define exactly whether the algorithm lives in a new pure Swift type,
inside `SliceAnalyzer`, or in a prototype/test harness.

## Prototype Boundary

The HTML prototypes remain evidence, not production code.

Production architecture may reuse the demonstrated heuristics, fixtures, and
visual explanation, but it should not copy prototype UI controls into the app
or assume that canvas selection, audition buttons, role auto-classification, or
manual BPM entry are accepted app workflows.

## Left For Spec

- Exact Swift type names and file placement.
- Whether the first implementation is a test-only Swift package, command-line
  harness, or app-target pure type with no UI call site.
- Exact fixture file format if real audio samples are introduced.
- Exact warning cases and user-facing copy for low-confidence results.
- Whether `UUID` candidate identity is replaced by deterministic rank/path IDs.
- Whether role weighting defaults to disabled globally or only disables when
  all roles are unknown.
- How a future UI selects, previews, or applies a candidate.

## Readiness

This accepted architecture closes the architecture artifact gap only.
Autoslice Algorithm remains not builder-ready until accepted `spec.md`,
`plan.md`, and `implementation-handoff.md` exist.
