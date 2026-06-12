# Concurrency Lane

Two complementary lanes hunt the deadlock/race classes catalogued in
[docs/audits/2026-06-12-concurrency.md](../audits/2026-06-12-concurrency.md).
They exist because the audit's verdict was "conventions → mechanisms": every
threading rule that used to live in a comment now has a detector that fails a
test or a sanitizer run instead of wedging the app.

## Lane 1 — churn stress tests (deterministic detectors)

`Tests/SequencerAITests/Engine/ConcurrencyChurnStressTests.swift` drives
bounded churn loops shaped like the audit's findings (D1–D4, the sampled
send-bus Add-FX self-deadlock, and the laggy-slider/mixer-latency shape),
with three detection layers that FAIL — never hang:

1. **Contract detectors** (`TickPathMainSyncGuard.violationHandlerForTesting`):
   tick-path main-sync (D2), main-sync while holding `stateLock` (D1), and
   graphLock re-entry / main-hop-under-graphLock (the send-bus class). These
   fire the instant the bad edge is taken — no interleaving luck needed.
   Positive-control tests prove each detector fires, so the "no violations"
   assertions cannot pass vacuously.
2. **Liveness watchdogs**: every churn worker runs off-main and is awaited
   with `XCTWaiter` + timeout (the house style from
   `TickPathMainIsolationTests`). A wedge surfaces as a failed wait, not a
   hung runner — the main thread never sync-joins an engine queue.
3. **Bounded-work counters**: value-only mix/send churn must not move
   `sendBusTopologyInstallCountForTesting` /
   `reconnectTrackOutputCountForTesting` (mixer-latency causes 2/3).

### Running

Two fast smokes + the positive controls run in the default gate
automatically. The full set is env-gated:

```sh
env TEST_RUNNER_SEQUENCERAI_STRESS=1 xcodebuild test-without-building \
  -project SequencerAI.xcodeproj -scheme SequencerAI \
  -destination 'platform=macOS' -derivedDataPath build-dd \
  -only-testing:SequencerAITests/ConcurrencyChurnStressTests
```

(The env var must be in `xcodebuild`'s environment — `TEST_RUNNER_`-prefixed
variables are forwarded to the test host; passing it as a build-setting
argument does NOT work.)

## Lane 2 — Thread Sanitizer (probabilistic, instruction-level)

The `SequencerAI-TSan` scheme (project.yml) runs the same test suite with
`enableThreadSanitizer`. It catches what the deterministic detectors cannot:
unannotated cross-thread memory access (the audit's R-class findings), lock
inversions TSan models, and races in paths no contract detector wraps.

This lane is **nightly/on-demand, not in the default gate**: TSan slows the
suite ~5–20× and CoreAudio device IO under TSan can stall for minutes when
`coreaudiod` is degraded (see the repo memory notes). The scheme skips
`MainAudioGraphDeviceSwitchTests` for that reason (real kAUStartIO device
IO; device-switch races are not what this lane hunts).

### Running

```sh
env TEST_RUNNER_TSAN_OPTIONS="suppressions=$(pwd)/Tests/SequencerAITests/tsan-suppressions.txt" \
  xcodebuild test \
  -project SequencerAI.xcodeproj -scheme SequencerAI-TSan \
  -destination 'platform=macOS' -derivedDataPath build-dd
```

### Triage policy

Every TSan report is one of:

- **Real**: fix it if small, otherwise record it in
  `docs/audits/2026-06-12-tsan-findings.md` with enough stack context to
  pick up later. Real races are NEVER suppressed.
- **Benign by design**: add a suppression to
  `Tests/SequencerAITests/tsan-suppressions.txt` with a per-entry
  justification comment explaining the design that makes it benign
  (e.g. seqlock-style generation-checked reads, meter atomics read racily
  on purpose). An unjustified suppression is a process bug.

Findings from each run are appended to
`docs/audits/2026-06-12-tsan-findings.md`.

## The mechanisms behind the lanes

- `TickPathMainSyncGuard` (Sources/Engine/EngineController.swift):
  `processTick` marks its thread; every sync-to-main helper in Sources/Audio
  reports before parking on main, and also fires when the calling thread
  holds `stateLock` (D1). Default is a TRAP (assertionFailure) in DEBUG —
  no waived hops remain. The last one (the audio-input capture-format read
  at record start) now reads a lock-protected snapshot that main publishes
  at every graph reconfiguration point
  (`MainAudioGraph.publishAudioInputCaptureFormatsOnMain`); tests install
  `violationHandlerForTesting` to observe without crashing the host.
- `TickPathMainSyncGuard.reportImminentDeadlock`: TRAPS in DEBUG. Used by
  MainAudioGraph's graphLock discipline (re-entry on the owning thread,
  main-hop while holding graphLock) — the alternative is a guaranteed wedge
  a few instructions later.
- DEBUG lock-depth tracking on both `stateLock` (EngineController) and
  `graphLock` (MainAudioGraph, per-instance) feeds those assertions; both
  have test-only positive controls.
