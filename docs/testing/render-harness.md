# Render harness — combinatorial timing-correctness tests

The render harness builds songs programmatically across the project's
combinatorial axes (track count, track types, sources, mixer buses, sends,
FX inserts, phrase structures, BPM), scripts parameter changes at musical
positions ("playing around while it plays"), renders the master output
**offline** (faster than realtime, no audio device), and asserts that the
output stays on the beat grid, renders identically across runs, and contains
no dropouts or unintended clipping.

Code lives in `Tests/SequencerAITests/RenderHarness/`:

| File | Role |
|------|------|
| `RenderScenario.swift` | Scenario DSL + deterministic fixture synthesis + `Project` assembly |
| `OfflineRenderHarness.swift` | Drives the real engine (`EngineController` + `MainAudioGraph` + `SamplePlaybackEngine`) through `processTick` in AVAudioEngine manual rendering mode |
| `RenderHarnessAnalysis.swift` | Onset detection (reusing `SliceAnalyzer.transientSlices`), grid matching, consistency/dropout/clipping checks |
| `RenderHarnessSmokeTests.swift` | 3 fast scenarios that run in the **default** test gate |
| `RenderHarnessScenarioTests.swift` | The full scenario matrix (env-gated) |
| `RenderHarnessDegradationTests.swift` | Track-count scaling sweep + markdown report (env-gated) |

## Running

The smoke tests run with the normal suite. The matrix and the degradation
sweep are slower and env-gated:

```sh
TEST_RUNNER_SEQUENCERAI_RENDER_HARNESS=1 xcodebuild \
  -project SequencerAI.xcodeproj -scheme SequencerAI -derivedDataPath build-dd \
  test-without-building \
  -only-testing:SequencerAITests/RenderHarnessScenarioTests \
  -only-testing:SequencerAITests/RenderHarnessDegradationTests
```

(`TEST_RUNNER_` is xcodebuild's prefix for forwarding env vars into the test
runner.) The degradation sweep writes
`render-harness-degradation.md`; the test host is sandboxed, so by default
the file lands in the container temp directory (the path is printed) — copy
it to `docs/audits/render-harness-degradation.md`. Set
`SEQUENCERAI_RENDER_HARNESS_REPORT_DIR` to override the output directory.

## How a render works

1. A virgin `AVAudioEngine` is switched to `.offline` manual rendering
   (48 kHz stereo) **before** `MainAudioGraph` builds its topology — once the
   graph has prepared against hardware, the mode switch fails (-80801).
2. The scenario's `Project` is applied while the engine is stopped, after one
   real start/stop cycle. The harness then **canonicalizes the mix topology**
   (re-issues track/bus/send edges with explicitly allocated input buses).
   This is required because production wires the graph dynamically on a
   running device engine; in manual rendering mode those convenience
   connects park as "pending", never activate (silent paths), are invisible
   to `nextAvailableInputBus` (collisions), and trip AVAudioEngine's
   source-node validation on mid-apply restarts.
3. `EngineController.startTransportWithoutClockForTesting(now:)` starts the
   transport without the wall-clock `TickClock`; the harness then drives
   `processTick(tickIndex:now:)` with a synthetic musical timeline and
   renders exactly one tick's worth of frames after each call. Events the
   engine dispatches "immediately" therefore begin at the first frame of
   their step's block — sample-aligned to the grid by construction.
4. `EngineController.scheduledAudioTimeOverrideForTesting` maps event times
   onto the manual-rendering sample clock (host-time `AVAudioTime`s crash
   `AVAudioPlayerNode` in manual mode: `playerTime.sampleTimeValid`).
   Past/now times return nil (= play at the next rendered frame); future
   times (note repeats) become sample-time `AVAudioTime`s.
5. A 0.25 s silent pre-roll precedes tick 0 (the windowed transient detector
   cannot localize an onset at frame 0) and a 0.35 s tail lets the last step
   decay inside the file.

## Assertions and tolerances

- **ON-BEAT** (`RenderHarnessAnalysis.verifyGrid`):
  - Every *detected* onset must match an expected grid time within **12 ms**
    (`onsetToleranceSeconds`). Detection reuses the production autoslice
    transient detector (`SliceAnalyzer.transientSlices`), with two
    harness-side adaptations, both needed because the detector was built for
    real recordings at a 30 ms product tolerance:
    ghost markers on digitally-silent backgrounds are dropped (energy gate),
    and each marker is snapped to the local attack (first energy rise before
    the local peak) because raw marker placement wobbles ±15 ms with the
    onset's phase inside the detector's 1024-frame analysis windows.
    Measured alignment error in passing runs is **< 0.5 ms**; 12 ms is kept
    as margin and stays far below half a 16th note even at 200 BPM (75 ms).
  - Every *expected* onset must have energy (RMS > 0.003 ≈ -50 dBFS) within
    **15 ms** of its grid position — this is the strongest check (the grid
    frames come from the harness's own frame accounting), and catches both
    dropouts and late notes. Detector misses (expected onset with verified
    energy but no marker) are reported but don't fail: the detector's recall
    drops on dense material because its local-maximum suppression spans
    ±5 windows (~±107 ms), which is the autoslice product behaving as
    designed, not an engine timing issue.
- **CONSISTENT**: two renders of the same scenario (including scripted
  param-change timelines) must be **bit-identical** (`consistencyTolerance
  = 0`). This holds in practice; if float nondeterminism ever appears, the
  comparison reports the max abs sample difference to recalibrate against.
- **NO DROPOUTS / CLIPPING**: the energy check above, plus master peak
  ≤ 0.999 unless the scenario intends clipping.

## Adding a scenario

Add a test to `RenderHarnessScenarioTests` composing a `RenderScenario`:

```swift
RenderScenario(
    name: "my-scenario",
    bpm: 124,
    bars: 4,
    tracks: [
        .init(name: "Kick", kind: .sample(.kick), steps: [0, 4, 8, 12], level: 0.5,
              sendA: 0.2, busIndex: 0),
        .init(name: "Slices", kind: .slicer, steps: [2, 10], level: 0.5),
    ],
    buses: [.init(name: "Drums", level: 0.9, withFilterInsert: true)],
    sendBusAOccupied: true,
    actions: [
        .init(tick: 16, kind: .setBPM(150)),                       // bar boundary
        .init(tick: 22, kind: .setTrackLevel(trackIndex: 0, level: 0.3)), // mid-bar
    ]
)
```

then `try runGridScenario(scenario)` (plus a second render +
`maxAbsDifference` if you want the consistency axis). Guidelines:

- Step patterns are 16 steps, repeated each bar. Keep simultaneous onsets'
  summed amplitude < 1.0 unless clipping is intended (fixture click peaks:
  kick 0.75, snare 0.6, perc 0.55, hat 0.45, slicer 0.7 — times track level).
- Keep onsets ≥ 75 ms apart (detector minimum distance is 50 ms).
- Send-level actions must stay nonzero -> nonzero. A send crossing zero
  rewires the graph topology (a stop/start in production too), which manual
  rendering mode cannot do mid-render.
- BPM actions are accounted for by the harness automatically: the expected
  grid is derived from the scripted BPM curve.

## Known limitations

- Sample/slicer destinations are covered; AU instrument tracks are not yet
  (`TrackPlaybackSink` is immediate-only and AU loading in headless tests is
  a separate workstream).
- Mid-render *topology* changes (send 0 -> nonzero, bus add/remove) are not
  supported offline — see canonicalization note above. Parameter changes
  (fader/pan/send level/bus level/master gain/BPM) are fully supported.
- The per-tick cost numbers come from a **debug** build; treat them as
  relative (scaling/knee), not absolute.

## Engine hooks used (test-only, additive)

- `EngineController.startTransportWithoutClockForTesting(now:)` — `start()`
  minus the wall-clock TickClock.
- `EngineController.scheduledAudioTimeOverrideForTesting` — replaces
  host-time `AVAudioTime` conversion for scheduled events.

Both are no-ops for production behavior when unused.
