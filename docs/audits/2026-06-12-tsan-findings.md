# TSan Lane Findings — 2026-06-12 (first run)

Run: `SequencerAI-TSan` scheme, full SequencerAITests minus the scheme's
skips (`MainAudioGraphDeviceSwitchTests`), Debug, arm64, no suppressions
installed. Branch `feature/concurrency-lane`.

Triage policy: docs/testing/concurrency-lane.md. Each report is REAL
(fix or record) or BENIGN-BY-DESIGN (suppress with justification).

## Summary

- Full pass: 200 of 201 suites executed (the scheme skips
  `MainAudioGraphDeviceSwitchTests`); xcodebuild relaunches the test host
  after each TSan-failed test, so the run spans multiple pids.
- **13 TSan reports → 4 distinct findings**: 0 product races between two
  production threads; 1 real product-source hygiene bug (an
  unsynchronized test-observation counter — fixed); 1 test-induced race
  in the new stress tests (fixed); 1 test-driver artifact (documented,
  follow-up suggested); 1 benign-by-design family (suppressed with
  justification, 8 of the 13 reports).
- 2 additional non-TSan failures, both environmental: a wall-clock
  phrase-navigation test flaked under the ~5-20× TSan slowdown
  (`test_stepOrderPendingToggleAppliesBeforeFirstBoundaryStepIsDispatched`
  — two extra steps dispatched before the boundary toggle landed), and
  `test_audioInputRouting_documentOutputBusMutationPreservesActiveSendFanoutWhileRunning`
  failed after exactly the known ~18-minute degraded-coreaudiod HAL stall
  (1080.9s; see repo memory notes). Neither is a race report.

## Reports

### 1. `EngineController.audioInputRuntimeRevision` — modify (main) vs read (stress worker)

- **Where**: `ConcurrencyChurnStressTests.runTransportChurn` "read" worker
  calls `audioInputRuntime(for:)` off main; its first statement is the
  `@Observable` registration read `_ = audioInputRuntimeRevision`, racing
  with the main-thread revision bump (`publishToMain { revision &+= 1 }`).
- **Verdict**: TEST-INDUCED, fixed in the tests (not suppressed). Every
  production caller of `audioInputRuntime(for:)` /
  `audioInputRuntimeTrackIDs` is main-thread UI (SidebarView,
  TracksMatrixView, TrackWorkspaceView, VisualScenarioCommandRunner); the
  observable surface is main-confined by design, and the engine side only
  writes the revision through `publishToMain`. The race existed only
  because the stress worker stands in for main. The stress tests now use
  `audioInputRuntimeForStressTesting(_:)` — the same `stateLock`
  contention read without the observable registration — so the lane stays
  clean and a future off-main production reader still gets reported.

### 2. `Executor.tick` — manual test tick (main) vs TickClock tick (tick queue)

- **Where**: e.g. `EngineControllerSampleTriggerTests.
  test_mixMute_suppressesSampleDispatch`: the test calls
  `controller.start()` (real TickClock begins calling `processTick` on the
  tick queue) and then ALSO drives `processTick(tickIndex:now:)` manually
  from the test main thread. Two concurrent `processTick` executions race
  on `Executor`'s per-tick state. Several engine suites share this driver
  pattern (multiple pids reported the same stack).
- **Verdict**: TEST-DRIVER ARTIFACT — not a product bug, recorded here
  rather than suppressed. The product contract is that `processTick` runs
  only on the serial TickClock queue (`EngineController.start()` wires it
  at EngineController.swift:693); no production path calls it from a
  second thread concurrently (the VisualScenarioCommandRunner manual ticks
  are the debug QA harness). **Follow-up worth doing**: the synchronous
  test-driver convention ("apply, then processTick manually") should not
  overlap with a started clock — tests that need `start()` for transport
  state should drive ticks via the clock alone, stop it before manual
  ticks, or use the purpose-built clockless start
  (`startTransportWithoutClockForTesting`, added for the offline render
  harness). Fixing the handful of suites that overlap is mechanical but
  out of this wave's bounds; until then this stack will reappear in lane
  runs.
  No suppression added: the report is a legitimate canary for any FUTURE
  second `processTick` caller, and suppressing `Executor.tick` would mask
  real races across the whole prepare/dispatch surface.

### 3. MIDI packet-recorder helpers — `init` (main) vs first CoreMIDI callback

- **Where**: `IntegrationMIDIPacketRecorder` (EngineIntegrationTests),
  `LockedPacketStore` (MIDIClientSendTests), `LockedMIDIPacketStore`
  (MidiOutTests) — multiple reports across the three helpers, all the
  same shape: the helper's `init` writes its fields on the test main
  thread; the first `append` runs on CoreMIDI's receive thread
  (`CADeprecated::CAPThread`).
- **Verdict**: BENIGN BY DESIGN — suppressed
  (`Tests/SequencerAITests/tsan-suppressions.txt`). Every post-init access
  in all three helpers is NSLock-guarded (verified by reading them); the
  flagged pair is construction vs first use on the receive thread. The
  happens-before edge is `MIDIDestinationCreate`'s registration round
  trip through MIDIServer (cross-process): the receive thread cannot
  invoke the handler before registration completes, and registration
  happens strictly after `init` returns. TSan cannot observe
  cross-process ordering, so it reports the pair as unordered.

### 4. `EngineController.applyPlaybackSnapshotCallCount` — unsynchronized `+= 1`

- **Where**: `PlaybackSnapshotConcurrencyTests.
  test_snapshot_concurrentReadsAndWrites_noTornRead` deliberately calls
  `apply(playbackSnapshot:)` from concurrent workers; the test-observation
  counter bump at the top of `apply` was a plain `+= 1` on `@Observable`
  storage — an unsynchronized read-modify-write (and an off-main
  observable write).
- **Verdict**: REAL (product-source hygiene, test-only impact) — FIXED.
  The counter is now `@ObservationIgnored` backed by `AtomicInt64`
  (`increment()`/`load()`); the public `applyPlaybackSnapshotCallCount`
  is a read-only computed property (all test usages only read it).
  `apply(playbackSnapshot:)`'s real work was already safe
  (`TickStateBuffer` copy-in under its own lock).

## Scary-rating

Nothing in the run indicts shipped concurrency design: no report has two
production threads on both sides. The wave-1/wave-2 mechanisms
(fire-and-forget tick-side hops, publishToMain discipline, snapshot
reads, lock-depth assertions) hold up under TSan with the churn loops
running.
