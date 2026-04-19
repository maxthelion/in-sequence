# Generator Algos and Pool Shape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat `GeneratorKind` enum (`manualMono`/`drumPattern`/`sliceTrigger`) with the `StepAlgo × PitchAlgo` orthogonal composition from the spec, ship the static musical tables (`Scales`, `Chords`, `StyleProfiles`) the algos depend on, extend `GeneratorPoolEntry` to carry per-kind `GeneratorParams`, and provide pure evaluation functions. Verified end-to-end by XCTest — each algo variant's output on a fixed RNG seed matches expected values; `GeneratorPoolEntry.defaultPool` produces three valid entries (mono / drum / slice-stub); legacy-format documents decode into the new shape.

**Architecture:** Two Swift modules grow. `Sources/Musical/` is new, carrying `Scale`, `ChordDefinition`, `StyleProfile` value types plus their `{ScaleID, ChordID, StyleProfileID}` enums and static lookup tables — read-only, shipped with the binary, no library-scoped overlay. `Sources/Document/` gains `StepAlgo.swift`, `PitchAlgo.swift`, `NoteShape.swift`, `GeneratorParams.swift`, all as value types with `Codable`, `Equatable`, `Sendable` conformance. Eval lives in extensions: `StepAlgo.fires(at:totalSteps:rng:)` and `PitchAlgo.pick(context:rng:)` — pure functions, no state kept across calls. `GeneratorKind` expands from 3 cases to 5 to match the spec's generator-kind roster; `GeneratorPoolEntry` gains a `params: GeneratorParams` field. `defaultPool` is refreshed. **This plan does NOT wire the new algos into the running engine** — the existing `NoteGenerator` block keeps reading its own inlined params. Engine integration is a separate plan so this one stays reviewable.

**Tech Stack:** Swift 5.9+, Foundation, XCTest. No new package dependencies.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — §"Components inventory (block palette sketch)" → "Generator composition — StepAlgo × PitchAlgo", "Static code tables", "Generator kinds — the actual list".

**Environment note:** Xcode 16 at `/Applications/Xcode.app`. `xcode-select` points at CommandLineTools. All `xcodebuild` invocations in this plan prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.3-generator-algos` at TBD.

**Deliberately deferred (documented in header, not in this plan):**

- **TrackType rename** from 3-case (`instrument`/`drumRack`/`sliceLoop`) to 4-case (`monoMelodic`/`polyMelodic`/`drum`/`slice`). A separate plan will do this. Compatibility filtering in this plan uses the current 3-case enum; when TrackType splits, the mapping tightens without changing the algos.
- **Engine wiring.** The running `NoteGenerator` block keeps its inlined params. A follow-up plan ("Engine resolves pattern slot to generator instance") replaces the inline approach with pool lookup + algo eval.
- **UI for picking algos.** The pattern editor's algo picker comes with the engine-wiring plan or the pattern-editor UI plan, not here.
- **Voicing per-tag preset map** for drum tracks. Separate plan.

---

## File Structure

```
Sources/
  Musical/                                # NEW module, static reference data
    ScaleID.swift                         # enum
    Scale.swift                           # struct { intervals: [Int], name }
    Scales.swift                          # static [ScaleID: Scale] table (19 scales)
    ChordID.swift                         # enum
    Chord.swift                           # struct { intervals: [Int], name }
    Chords.swift                          # static [ChordID: ChordDefinition] table (16 chords)
    StyleProfileID.swift                  # enum
    StyleProfile.swift                    # struct (ascend/descend/leap biases)
    StyleProfiles.swift                   # static [StyleProfileID: StyleProfile] table
  Document/
    StepAlgo.swift                        # enum + eval extension
    PitchAlgo.swift                       # enum + eval extension
    PitchContext.swift                    # ancillary struct
    NoteShape.swift                       # struct
    GeneratorParams.swift                 # tagged union per-kind
    PhraseModel.swift                     # MODIFIED — GeneratorKind expanded, GeneratorPoolEntry.params
Tests/
  SequencerAITests/
    Musical/
      ScalesTests.swift
      ChordsTests.swift
      StyleProfilesTests.swift
    Document/
      StepAlgoTests.swift
      PitchAlgoTests.swift
      NoteShapeTests.swift
      GeneratorParamsTests.swift
      GeneratorKindTests.swift
      GeneratorPoolEntryTests.swift
```

`project.yml` gains a `Musical` group under `Sources/`.

---

## Task 1: Musical tables — `ScaleID`, `Scale`, `Scales`

**Scope:** Encode the 19 scales from the spec (glaypen-derived) as static Swift data. The `Scale` struct holds the interval list and a display name; lookup via `Scale.for(id:)` is total.

**Files:**
- Create: `Sources/Musical/ScaleID.swift`
- Create: `Sources/Musical/Scale.swift`
- Create: `Sources/Musical/Scales.swift`
- Create: `Tests/SequencerAITests/Musical/ScalesTests.swift`
- Modify: `project.yml` (add `Musical/` group)

**Types:**

```swift
public enum ScaleID: String, Codable, CaseIterable, Equatable, Sendable {
    case chromatic, major, naturalMinor, harmonicMinor, melodicMinor
    case majorPentatonic, minorPentatonic, blues
    case dorian, phrygian, lydian, mixolydian, locrian
    case wholeTone, diminished, augmented
    case gypsy, hungarianMinor, akebono
}

public struct Scale: Equatable, Sendable {
    public let id: ScaleID
    public let name: String
    public let intervals: [Int]    // semitones from root, length 5–12
}
```

**Reference data** (from spec / glaypen):

| ScaleID | Intervals |
|---|---|
| `chromatic` | `[0,1,2,3,4,5,6,7,8,9,10,11]` |
| `major` | `[0,2,4,5,7,9,11]` |
| `naturalMinor` | `[0,2,3,5,7,8,10]` |
| `harmonicMinor` | `[0,2,3,5,7,8,11]` |
| `melodicMinor` | `[0,2,3,5,7,9,11]` |
| `majorPentatonic` | `[0,2,4,7,9]` |
| `minorPentatonic` | `[0,3,5,7,10]` |
| `blues` | `[0,3,5,6,7,10]` |
| `dorian` | `[0,2,3,5,7,9,10]` |
| `phrygian` | `[0,1,3,5,7,8,10]` |
| `lydian` | `[0,2,4,6,7,9,11]` |
| `mixolydian` | `[0,2,4,5,7,9,10]` |
| `locrian` | `[0,1,3,5,6,8,10]` |
| `wholeTone` | `[0,2,4,6,8,10]` |
| `diminished` | `[0,2,3,5,6,8,9,11]` |
| `augmented` | `[0,3,4,7,8,11]` |
| `gypsy` | `[0,2,3,6,7,8,11]` |
| `hungarianMinor` | `[0,2,3,6,7,8,11]` |
| `akebono` | `[0,2,3,7,8]` |

Display names use Title Case: "Chromatic", "Major", "Natural Minor", "Harmonic Minor", …

**Tests:**

1. `ScaleID.allCases.count == 19`
2. Every `ScaleID` has a `Scale` in the static table (`Scale.for(id:)` returns non-nil for all cases).
3. Spot-check intervals: `.major` = `[0,2,4,5,7,9,11]`; `.chromatic.intervals.count == 12`; `.pentatonic(...)` has length 5.
4. Every scale's intervals are strictly ascending, start at 0, and each value is in `0..<12`.

- [x] Write `ScalesTests.swift` with the 4 cases
- [x] Run test — verify fails ("ScaleID not defined")
- [x] Implement `ScaleID`, `Scale`, `Scales.swift` with the table
- [x] Run test — verify passes
- [x] `xcodebuild test` green
- [ ] Commit: `feat(musical): scale reference tables`

---

## Task 2: Musical tables — `ChordID`, `Chord`, `Chords`

**Scope:** Encode the 16 chords from the spec (sequencerbox-derived).

**Files:**
- Create: `Sources/Musical/ChordID.swift`
- Create: `Sources/Musical/Chord.swift`
- Create: `Sources/Musical/Chords.swift`
- Create: `Tests/SequencerAITests/Musical/ChordsTests.swift`

**Types:**

```swift
public enum ChordID: String, Codable, CaseIterable, Equatable, Sendable {
    case majorTriad, minorTriad, augmentedTriad, diminishedTriad
    case major7th, minor7th, dominant7th, diminished7th, augmented7th, halfDiminished7th
    case major6th, minor6th
    case major9th, minor9th
    case major11th, minor11th
}

public struct ChordDefinition: Equatable, Sendable {
    public let id: ChordID
    public let name: String
    public let intervals: [Int]
}
```

**Reference data (from sequencerbox's pitchfunctions.ts):**

| ChordID | Intervals |
|---|---|
| `majorTriad` | `[0,4,7]` |
| `minorTriad` | `[0,3,7]` |
| `augmentedTriad` | `[0,4,8]` |
| `diminishedTriad` | `[0,3,6]` |
| `major7th` | `[0,4,7,11]` |
| `minor7th` | `[0,3,7,10]` |
| `dominant7th` | `[0,4,7,10]` |
| `diminished7th` | `[0,3,6,9]` |
| `augmented7th` | `[0,4,8,10]` |
| `halfDiminished7th` | `[0,3,6,10]` |
| `major6th` | `[0,4,7,9]` |
| `minor6th` | `[0,3,7,9]` |
| `major9th` | `[0,4,7,11,14]` |
| `minor9th` | `[0,3,7,10,14]` |
| `major11th` | `[0,4,7,11,14,17]` |
| `minor11th` | `[0,3,7,10,14,17]` |

**Tests:**

1. `ChordID.allCases.count == 16`
2. Every `ChordID` maps to a `Chord`.
3. Spot-check intervals: `.majorTriad = [0,4,7]`, `.dominant7th = [0,4,7,10]`.
4. Every chord's intervals are strictly ascending and start at 0.

- [x] Write tests
- [x] Implement
- [x] Green
- [ ] Commit: `feat(musical): chord reference tables`

---

## Task 3: Musical tables — `StyleProfileID`, `StyleProfile`, `StyleProfiles`

**Scope:** HotStepper-style Markov-pitch biases, three shipped profiles.

**Files:**
- Create: `Sources/Musical/StyleProfileID.swift`
- Create: `Sources/Musical/StyleProfile.swift`
- Create: `Sources/Musical/StyleProfiles.swift`
- Create: `Tests/SequencerAITests/Musical/StyleProfilesTests.swift`

**Types:**

```swift
public enum StyleProfileID: String, Codable, CaseIterable, Equatable, Sendable {
    case vocal, balanced, jazz
}

public struct StyleProfile: Equatable, Sendable {
    public let id: StyleProfileID
    public let name: String
    /// Distance-from-lastPitch weights in scale-step units. Index i = weight for |delta| == i.
    public let distanceWeights: [Double]    // length 8, sums roughly to 1
    public let tailBase: Double             // residual weight for distances > distanceWeights.count
    public let tailDecay: Double            // exponential decay factor
    public let ascendBias: Double           // multiplier when direction is ascending
    public let descendBias: Double          // multiplier when direction is descending
    public let repeatBias: Double           // multiplier at distance 0
    public let leapPenalty: Double          // multiplier on distances ≥ 3
}
```

**Reference data (verbatim from HotStepper's STYLE_PROFILES):**

- `vocal`: `distanceWeights = [0.16, 0.35, 0.24, 0.12, 0.07, 0.035, 0.016, 0.008]`, `tailBase: 0.008`, `tailDecay: 0.5`, `descendBias: 1.12`, `ascendBias: 0.92`, `repeatBias: 1.08`, `leapPenalty: 0.42`
- `balanced`: `[0.13, 0.31, 0.25, 0.15, 0.08, 0.045, 0.022, 0.012]`, `tailBase: 0.012`, `tailDecay: 0.58`, `descendBias: 1.08`, `ascendBias: 0.94`, `repeatBias: 1.0`, `leapPenalty: 0.55`
- `jazz`: `[0.08, 0.20, 0.21, 0.18, 0.14, 0.09, 0.05, 0.028]`, `tailBase: 0.02`, `tailDecay: 0.7`, `descendBias: 1.02`, `ascendBias: 0.99`, `repeatBias: 0.84`, `leapPenalty: 0.78`

**Tests:**

1. `StyleProfileID.allCases.count == 3`
2. Every id has a profile.
3. Each profile's `distanceWeights` has length 8 and sums to between 0.8 and 1.2 (coarse sanity).
4. `jazz.leapPenalty > vocal.leapPenalty` (jazz tolerates leaps more).

- [ ] Write tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(musical): style profile reference tables`

---

## Task 4: `NoteShape`

**Scope:** Value type for per-note shared knobs, used by all pitched generator instances.

**Files:**
- Create: `Sources/Document/NoteShape.swift`
- Create: `Tests/SequencerAITests/Document/NoteShapeTests.swift`

**Type:**

```swift
public struct NoteShape: Codable, Equatable, Sendable {
    public var velocity: Int      // 0…127
    public var gateLength: Int    // ticks; must be > 0
    public var accent: Bool

    public static let `default` = NoteShape(velocity: 100, gateLength: 4, accent: false)
}
```

**Tests:**

1. `.default` round-trips through `JSONEncoder`/`JSONDecoder`.
2. Equality: two identical shapes are equal; differing velocity makes them unequal.
3. The default satisfies: `0 <= velocity && velocity <= 127 && gateLength > 0`.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): NoteShape shared per-note knobs`

---

## Task 5: `StepAlgo` enum + `fires(at:…)` eval

**Scope:** Five-variant enum with the per-variant step-decision logic. Pure function returning `Bool`; callers pass in an `RNG` for stochastic variants.

**Files:**
- Create: `Sources/Document/StepAlgo.swift`
- Create: `Tests/SequencerAITests/Document/StepAlgoTests.swift`

**Type:**

```swift
public enum StepAlgo: Codable, Equatable, Sendable {
    case manual(pattern: [Bool])
    case randomWeighted(density: Double)                        // 0..1
    case euclidean(pulses: Int, steps: Int, offset: Int)
    case perStepProbability(probs: [Double])                    // length matches pattern step count
    case fromClipSteps(clipID: UUID)                            // stub until clips are real

    public func fires(
        at stepIndex: Int,
        totalSteps: Int,
        rng: inout some RandomNumberGenerator
    ) -> Bool
}
```

**Eval logic:**

- `.manual(pattern)` — return `pattern.indices.contains(stepIndex) ? pattern[stepIndex] : false`
- `.randomWeighted(density)` — `Double.random(in: 0..<1, using: &rng) < density`
- `.euclidean(pulses, steps, offset)` — Bjorklund: compute step-mask once for `(pulses, steps)`, apply rotation by `offset`, return `mask[(stepIndex - offset + steps) % steps]`. Cache the mask per (pulses, steps) inside the enum call if that helps perf; tests don't require the cache.
- `.perStepProbability(probs)` — `probs.indices.contains(stepIndex) ? Double.random(in: 0..<1, using: &rng) < probs[stepIndex] : false`
- `.fromClipSteps(_)` — returns `false` (stub; a comment says "wired when clipPool is real").

**Tests:**

1. `.manual([true, false, true, false])`: stepIndex 0 → true; 1 → false; 2 → true; 4 → false (out of bounds).
2. `.randomWeighted(1.0)`: always fires (with any RNG).
3. `.randomWeighted(0.0)`: never fires.
4. `.randomWeighted(0.5)`: over 1000 ticks with a deterministic seed, fires `500 ± 50` times.
5. `.euclidean(3, 8, 0)`: fires at steps 0, 3, 6 (classic 3-against-8 distribution).
6. `.euclidean(3, 8, 2)`: fires at steps 2, 5, 0 (rotated).
7. `.perStepProbability([1.0, 0.0, 1.0])`: stepIndex 0 → true; 1 → false; 2 → true.
8. `.fromClipSteps(UUID())`: always false (stub).
9. Round-trip Codable for each variant.

Use `SystemRandomNumberGenerator` in non-stochastic tests; for stochastic ones, seed a deterministic generator (wrap `SplitMix64` or use a simple `LinearCongruentialGenerator` helper in the test file).

- [ ] Write 9 tests
- [ ] Implement `StepAlgo` and `fires(at:…)`
- [ ] Implement Bjorklund algorithm (keep standalone — maybe in `Sources/Musical/Euclidean.swift` and reference from here)
- [ ] Green
- [ ] Commit: `feat(document): StepAlgo with per-variant eval`

---

## Task 6: `PitchContext` + `PitchAlgo` enum + `pick(context:…)` eval

**Scope:** Seven-variant enum with per-variant pitch-choice logic. Ancillary `PitchContext` struct passes last-pitch / current-chord / scale-root info from the caller.

**Files:**
- Create: `Sources/Document/PitchContext.swift`
- Create: `Sources/Document/PitchAlgo.swift`
- Create: `Tests/SequencerAITests/Document/PitchAlgoTests.swift`

**Types:**

```swift
public enum PickMode: String, Codable, Equatable, Sendable {
    case sequential, random
}

public enum HoldMode: String, Codable, Equatable, Sendable {
    case pool, latest
}

public struct PitchContext: Equatable, Sendable {
    public let lastPitch: Int?            // MIDI note of most recently emitted, if any
    public let scaleRoot: Int             // MIDI note
    public let scaleID: ScaleID           // used by many algos
    public let currentChord: Chord?       // broadcast chord-context, if any
    public let stepIndex: Int             // used by .manual(sequential)
}

public enum PitchAlgo: Codable, Equatable, Sendable {
    case manual(pitches: [Int], pickMode: PickMode)
    case randomInScale(root: Int, scale: ScaleID, spread: Int)
    case randomInChord(root: Int, chord: ChordID, inverted: Bool, spread: Int)
    case intervalProb(root: Int, scale: ScaleID, degreeWeights: [Double])
    case markov(root: Int, scale: ScaleID, styleID: StyleProfileID, leap: Double, color: Double)
    case fromClipPitches(clipID: UUID, pickMode: PickMode)      // stub
    case external(port: String, channel: Int, holdMode: HoldMode)  // stub for Plan 2; returns last manual-pool or fallback

    public func pick(
        context: PitchContext,
        rng: inout some RandomNumberGenerator
    ) -> Int
}
```

**Eval logic (outline; exact formulas in the implementation):**

- `.manual(pitches, .sequential)` — `pitches[context.stepIndex % pitches.count]` (returns `context.scaleRoot` if pitches empty).
- `.manual(pitches, .random)` — `pitches.randomElement(using: &rng) ?? context.scaleRoot`.
- `.randomInScale(root, scale, spread)` — build scale-pitch pool `[root - spread, root + spread]` intersected with the scale; pick random.
- `.randomInChord(root, chord, inverted, spread)` — build pool of chord intervals + octave variations within `spread`; if `inverted`, shift first interval up an octave.
- `.intervalProb(root, scale, degreeWeights)` — weighted-pick a scale degree using `degreeWeights` (align length to scale degrees by clamping/padding); add degree semitones to `root`.
- `.markov(root, scale, styleID, leap, color)` — build scale pool; if `lastPitch` is nil, random pick. Otherwise weight each candidate by `StyleProfile.distanceWeights[|delta|]` × direction bias; apply `leap` (amplifies leapPenalty when ≥ 0.5) and `color` (probability of a color/approach tone outside the scale). Deterministic given RNG.
- `.fromClipPitches(_)` — stub, returns `context.scaleRoot`.
- `.external(_)` — stub, returns `context.scaleRoot`.

**Tests:**

1. `.manual([60, 62, 64], .sequential)`: stepIndex 0 → 60; 1 → 62; 2 → 64; 3 → 60.
2. `.manual([60, 62], .random)`: over 1000 picks, both values appear > 400 times (deterministic RNG).
3. `.manual([], .random)`: returns `context.scaleRoot`.
4. `.randomInScale(60, .major, 12)`: every result is in `60 ± 12` and is a major-scale note relative to C.
5. `.randomInChord(60, .majorTriad, inverted: false, spread: 12)`: every result ∈ {60, 64, 67, 72, 76, 79, 48, 52, 55, …}.
6. `.intervalProb(60, .major, [0,0,1,0,0,0,0])`: always returns `60 + 4 = 64` (scale index 2 = E; weight [0,0,1,0,0,0,0] picks index 2).
7. `.markov(60, .major, .balanced, leap: 0, color: 0)` with `lastPitch: 60`: over 1000 picks, result has |delta| distribution matching the `balanced` profile's distanceWeights within tolerance.
8. `.fromClipPitches(UUID())`: returns `context.scaleRoot`.
9. `.external(...)`: returns `context.scaleRoot`.
10. Round-trip Codable for each variant.

- [ ] Write tests
- [ ] Implement `PitchContext`, `PitchAlgo`, `PickMode`, `HoldMode`
- [ ] Implement eval
- [ ] Green
- [ ] Commit: `feat(document): PitchAlgo with per-variant eval + PitchContext`

---

## Task 7: `GeneratorParams` tagged union

**Scope:** Per-kind params storage. Each generator instance's kind determines which variant of `GeneratorParams` it carries.

**Files:**
- Create: `Sources/Document/GeneratorParams.swift`
- Create: `Tests/SequencerAITests/Document/GeneratorParamsTests.swift`

**Type:**

```swift
public enum GeneratorParams: Codable, Equatable, Sendable {
    case mono(step: StepAlgo, pitch: PitchAlgo, shape: NoteShape)
    case poly(step: StepAlgo, pitches: [PitchAlgo], shape: NoteShape)
    case drum(steps: [VoiceTag: StepAlgo], shape: NoteShape)
    case template(templateID: UUID)                             // stub; resolves to a library-loaded pre-composed clip
    case slice(step: StepAlgo, sliceIndexes: [Int])             // stub

    public static let defaultMono = GeneratorParams.mono(
        step: .manual(pattern: Array(repeating: false, count: 16)),
        pitch: .manual(pitches: [60, 62, 64, 67], pickMode: .random),
        shape: .default
    )

    public static let defaultDrumKit = GeneratorParams.drum(
        steps: [
            "kick": .manual(pattern: [true,  false, false, false, true,  false, false, false,
                                      true,  false, false, false, true,  false, false, false]),
            "snare": .manual(pattern: [false, false, false, false, true,  false, false, false,
                                       false, false, false, false, true,  false, false, false]),
            "hat": .euclidean(pulses: 8, steps: 16, offset: 0)
        ],
        shape: .default
    )
}

public typealias VoiceTag = String
```

**Tests:**

1. Each variant round-trips `JSONEncoder`/`JSONDecoder`.
2. `defaultMono` equals a freshly-constructed mono with the same params.
3. `defaultDrumKit.steps.count == 3`; contains "kick", "snare", "hat".
4. Equality: differing `step` makes two mono variants unequal.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): GeneratorParams tagged union`

---

## Task 8: Expand `GeneratorKind` enum

**Scope:** Replace the current 3-case `GeneratorKind` (`manualMono`, `drumPattern`, `sliceTrigger`) with the spec's 5-case roster (`monoGenerator`, `polyGenerator`, `drumKit`, `templateGenerator`, `sliceGenerator`). Add compatibility declarations.

**Files:**
- Modify: `Sources/Document/PhraseModel.swift` (the existing `GeneratorKind` enum in this file)
- Create: `Tests/SequencerAITests/Document/GeneratorKindTests.swift`

**Type:**

```swift
public enum GeneratorKind: String, Codable, CaseIterable, Equatable, Sendable {
    case monoGenerator, polyGenerator, drumKit, templateGenerator, sliceGenerator

    public var label: String { … }

    public var compatibleWith: Set<TrackType> {
        switch self {
        case .monoGenerator, .polyGenerator: return [.instrument]   // tighten to mono/poly when TrackType splits
        case .drumKit: return [.drumRack]
        case .templateGenerator: return Set(TrackType.allCases)     // template declares its own narrower type at instance creation
        case .sliceGenerator: return [.sliceLoop]
        }
    }

    public var defaultParams: GeneratorParams {
        switch self {
        case .monoGenerator: return .defaultMono
        case .polyGenerator: return .poly(step: .manual(pattern: Array(repeating: false, count: 16)),
                                          pitches: [.manual(pitches: [60, 64, 67], pickMode: .random)],
                                          shape: .default)
        case .drumKit: return .defaultDrumKit
        case .templateGenerator: return .template(templateID: UUID())
        case .sliceGenerator: return .slice(step: .manual(pattern: Array(repeating: false, count: 16)),
                                            sliceIndexes: [])
        }
    }
}
```

**Legacy Codable migration** — old documents have `GeneratorKind.manualMono / drumPattern / sliceTrigger`. Decoder:

```swift
public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    switch raw {
    case "monoGenerator": self = .monoGenerator
    case "polyGenerator": self = .polyGenerator
    case "drumKit": self = .drumKit
    case "templateGenerator": self = .templateGenerator
    case "sliceGenerator": self = .sliceGenerator
    // legacy
    case "manualMono": self = .monoGenerator
    case "drumPattern": self = .drumKit
    case "sliceTrigger": self = .sliceGenerator
    default: throw DecodingError.dataCorruptedError(
        in: decoder.singleValueContainer(),
        debugDescription: "Unknown GeneratorKind: \(raw)")
    }
}
```

**Tests:**

1. `GeneratorKind.allCases.count == 5`.
2. Every kind has a non-nil `defaultParams` and a non-empty `label`.
3. `GeneratorKind.monoGenerator.compatibleWith.contains(.instrument)`.
4. `GeneratorKind.drumKit.compatibleWith == [.drumRack]`.
5. Legacy decode: JSON `"manualMono"` → `.monoGenerator`; `"drumPattern"` → `.drumKit`; `"sliceTrigger"` → `.sliceGenerator`.
6. Round-trip for new names.

- [ ] Tests
- [ ] Implement enum + migration
- [ ] Green
- [ ] Commit: `feat(document): expand GeneratorKind to spec's 5-case roster with legacy migration`

---

## Task 9: Extend `GeneratorPoolEntry` with `params`

**Scope:** Add the per-instance `params: GeneratorParams` field. Legacy decoder fills `params` from the old kind's `defaultParams`.

**Files:**
- Modify: `Sources/Document/PhraseModel.swift` (the existing `GeneratorPoolEntry` struct)
- Create: `Tests/SequencerAITests/Document/GeneratorPoolEntryTests.swift`

**New shape:**

```swift
public struct GeneratorPoolEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var trackType: TrackType
    public var kind: GeneratorKind
    public var params: GeneratorParams

    public static func makeDefault(
        id: UUID,
        name: String,
        kind: GeneratorKind,
        trackType: TrackType
    ) -> GeneratorPoolEntry {
        GeneratorPoolEntry(id: id, name: name, trackType: trackType, kind: kind, params: kind.defaultParams)
    }
}
```

**Legacy decode:** if `params` is absent in the JSON, set `params = kind.defaultParams`.

**Refresh `defaultPool`:**

```swift
public static let defaultPool: [GeneratorPoolEntry] = [
    GeneratorPoolEntry.makeDefault(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!,
        name: "Manual Mono",
        kind: .monoGenerator,
        trackType: .instrument
    ),
    GeneratorPoolEntry.makeDefault(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2")!,
        name: "Default Kit",
        kind: .drumKit,
        trackType: .drumRack
    ),
    GeneratorPoolEntry.makeDefault(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3")!,
        name: "Slice Trigger",
        kind: .sliceGenerator,
        trackType: .sliceLoop
    )
]
```

**Tests:**

1. `defaultPool.count == 3`; each entry's kind compatible with its trackType.
2. Every `defaultPool` entry's `params` is non-empty and matches its kind's default.
3. Round-trip new-shape JSON.
4. Legacy decode: a JSON blob with old `kind: "manualMono"` and no `params` field decodes to a `monoGenerator` entry with `params = .defaultMono`.
5. `makeDefault` seeds the pool entry's params from the kind.

- [ ] Tests
- [ ] Implement the field + migration + refreshed `defaultPool`
- [ ] Green
- [ ] Commit: `feat(document): GeneratorPoolEntry carries per-kind params; legacy migration`

---

## Task 10: Full-suite verification + existing-test fixups

**Scope:** Run the whole suite. Some tests in `SeqAIDocumentTests.swift` reference `GeneratorPoolEntry` fields or the old `GeneratorKind` cases — they need small updates. No functional change beyond keeping existing tests green with the new shape.

**Files:**
- Modify (if needed): `Tests/SequencerAITests/SeqAIDocumentTests.swift` — update assertions referencing old `GeneratorKind` case names (`manualMono` → `monoGenerator`, etc.) and add `params` to any test fixtures that construct `GeneratorPoolEntry` directly.
- Also: `Tests/SequencerAITests/Engine/AudioInstrumentHostTests.swift` and `PhraseWorkspaceView` — inspect for references.

**Tests:**

- Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' test`
- Acceptance: full suite green. No regressions. New algo / tables / pool tests all pass (Tasks 1–9 accumulated).

- [ ] Run suite, note any failures
- [ ] Adjust existing-test fixtures to compile / pass
- [ ] Re-run — all green
- [ ] Commit: `fix(tests): update fixtures for new GeneratorKind and GeneratorPoolEntry shape`

---

## Task 11: Wiki update

**Scope:** Add `wiki/pages/generator-algos.md` describing the composition, the three musical tables, and the legacy-migration path. Update `wiki/pages/project-layout.md` to list the new `Musical/` module.

**Files:**
- Create: `wiki/pages/generator-algos.md`
- Modify: `wiki/pages/project-layout.md`

Content of the wiki page: short — point at the spec's Components Inventory section as canon, summarise the Swift types and their Codable migration stance, link to each static table.

- [ ] Wiki page
- [ ] project-layout updated with Musical module + updated dependency line (`Engine → Musical` if any block uses it, otherwise `Document → Musical`)
- [ ] Commit: `docs(wiki): generator-algos page + project-layout update`

---

## Task 12: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for steps actually completed
- [ ] Add a `Status:` line after `Parent spec` in this file's header, following Plan 0's pattern (completed-prefix word, tag name, SHA) — placeholders kept so the BT's active-plan detector doesn't mis-fire before completion
- [ ] Commit: `docs(plan): mark 2-generator-algos completed`
- [ ] Tag: `git tag -a v0.0.3-generator-algos -m "Generator algos + musical tables complete: StepAlgo, PitchAlgo, NoteShape, GeneratorParams; Scales / Chords / StyleProfiles tables; GeneratorPoolEntry carries params; legacy migration"`

---

## Goal-to-task traceability (self-review)

| Goal / architectural claim | Task |
|---|---|
| Static `Scales` table (19 scales) | Task 1 |
| Static `Chords` table (16 chords) | Task 2 |
| Static `StyleProfiles` table (3 profiles) | Task 3 |
| `NoteShape` shared per-note knobs | Task 4 |
| `StepAlgo` enum + eval | Task 5 |
| `PitchAlgo` enum + eval + `PitchContext` | Task 6 |
| `GeneratorParams` tagged union per kind | Task 7 |
| `GeneratorKind` expanded to 5-case + compatibility + legacy migration | Task 8 |
| `GeneratorPoolEntry` gains `params`; `defaultPool` refreshed; legacy migration | Task 9 |
| Full suite green, existing tests updated | Task 10 |
| Wiki updated | Task 11 |
| Tag | Task 12 |
| **No engine wiring** (deferred to next plan) | — (called out in header) |
| **No TrackType rename** (deferred to next plan) | — (called out in header) |
| **No Voicing per-tag map** (deferred to next plan) | — (called out in header) |
| **No UI for picking algos** (deferred) | — (called out in header) |

## Open questions resolved for this plan

- **Bjorklund algorithm location:** `Sources/Musical/Euclidean.swift` as a standalone pure function (`bjorklund(pulses:steps:) -> [Bool]`) so it can be reused by future layer / transform code without importing the document module.
- **Deterministic RNG for tests:** the test bundle will define a `SplitMix64` wrapper conforming to `RandomNumberGenerator`. Production code uses `SystemRandomNumberGenerator`.
- **`VoiceTag` type alias:** `typealias VoiceTag = String` for now. When Voicing lands in a later plan, we revisit whether a typed wrapper is worth it.
- **`fromClipSteps` / `fromClipPitches` / `external` / `template` / `slice`** — all stubs returning sensible fallbacks (false for steps, `scaleRoot` for pitches). Real implementations land when clipPool / templates / slice infra / MIDI input arrive in their own plans.
- **Legacy JSON migration** — covered in Task 8 (GeneratorKind) and Task 9 (GeneratorPoolEntry). Old documents round-trip through load → edit → save cleanly.
