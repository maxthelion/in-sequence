# Realtime Sample Cache And Timing Guards

Date: 2026-06-22

Status: Partially implemented in `codex/timing-probe-poc`

Owner priority: Critical. Playback timing across the whole app must be
rock solid under normal UI use, including view/tab switching, mixer gestures,
phrase navigation, routing changes, and dense drum/slicer playback.

## Problem

Runtime timing traces and code audit show that audible sample timing can still
depend on work that does not belong on the realtime scheduling path:

- sample triggers resolve `sampleID -> AudioSample -> AudioFileRef -> URL` at
  dispatch time, including `FileManager.fileExists`
- `SamplePlaybackEngine` can open/read sample files during playback scheduling
- slicer dispatch resolves sample URLs while preparing slice trigger events
- AU note-on/off and sampler filter parameter changes still reach the main
  actor through fire-and-forget hops
- graph repair/reconnect is correctly main-owned, but main congestion can make
  fallback scheduling late unless misses are visible and rare

The root class is broader than one bug: time-critical playback must consume
prepared immutable data and already-connected audio state. It must not perform
filesystem IO, decode work, graph mutation, synchronous main hops, or unbounded
main-queued control work while a tick/event is being dispatched.

## Product Requirement

When playback is running, switching views or performing normal UI actions must
not make sample, slicer, MIDI, or AU events audibly late. The app should behave
like a hardware groovebox: active kit/sampler/slicer assets are hot before they
are needed, and triggering them is a bounded operation.

Cold asset loading is allowed only outside the tick/event path. If an asset is
not ready, the system must expose a clear readiness/pending state and emit a
diagnostic cache miss. It must not block the tick queue or the main actor to
make the current trigger work.

## Definitions

- Realtime path: `TickClock` callback, `EngineController.processTick`,
  `prepareTick`, `dispatchTick`, router dispatch, note-repeat scheduling,
  sample/slicer trigger dispatch, and any direct helper called from those paths.
- Hot asset: an active document sample/slice source whose audio data or reusable
  playback handle has already been resolved and loaded before transport needs it.
- Prepared graph: AVAudioEngine nodes and routing required to play an active
  track are attached and connected before tick dispatch.
- Main hop latency: elapsed time between queueing a block to `DispatchQueue.main`
  or `MainActor` and that block beginning execution.
- Late event: event dispatch/schedule time happens after its scheduled host time
  by more than the warning/failure threshold below.

## Quantified Bad Behaviour

The diagnostics must classify the following as warnings or failures:

| Class | Warning | Failure |
| --- | --- | --- |
| Tick processing duration | `processTick` exceeds 25% of one step at current BPM | exceeds 50% of one step or 5 ms, whichever is lower |
| Event lateness | sample/slice/MIDI/AU event starts > 2 ms late | starts > 5 ms late |
| Main hop latency from realtime-adjacent code | > 2 ms | > 8 ms, or any hop needed for an event already due |
| Sample cache miss while transport running | any miss | any miss for an armed/active track |
| File IO on realtime path | any detected call | any detected call in CI/static gate |
| Graph mutation on realtime path | any repair fallback | any normal-path mutation, or repeated repair for same track |
| Per-trigger sample decode/open | any detected open/decode after transport start | any detected open/decode during tick/event dispatch |

Thresholds may be tuned after measurement, but the rule cannot be removed:
runtime evidence must tell us whether playback timing is budgeted or only
“seems okay”.

## Required Implementation

### 1. SampleAssetCache

Introduce a cache owned by the audio/engine layer, not by SwiftUI views.

Required behavior:

- key by stable sample ID plus file identity/version
- resolve `AudioFileRef` outside tick/event dispatch
- decode or otherwise prepare sample playback data outside tick/event dispatch
- expose a non-blocking lookup API for the realtime path
- pin all active document sample/slicer/drum-kit assets while transport is
  running
- support asynchronous warmup when documents, kits, destinations, slice sets,
  or sample selections change
- expose readiness state: ready, loading, failed, stale
- log cache loads, misses, evictions, failures, and warmup duration
- bound memory with an explicit budget and LRU or equivalent policy for inactive
  assets
- never evict assets used by currently active tracks while transport is running

The realtime path must receive a prepared handle, not a file URL that still
needs to be checked or opened.

### 2. Drum Kit Warmup

All samples referenced by an active drum kit must be warmed before playback can
claim “ready”.

Acceptance behavior:

- creating/loading a drum kit starts warmup for every referenced sample
- changing a kit sample warms the new sample before it is used by playback
- pressing play with a cold kit reports “sample playback pending/loading” until
  warmup completes, instead of blocking tick dispatch
- dense drum playback produces zero cache misses after warmup

### 3. Slicer Warmup

Slicer tracks must warm the source sample and any reusable derived playback
data needed for slices.

The implementation may choose one of these shapes:

- predecoded source buffer plus bounded prebuilt slice buffers
- reusable open audio-file handle safe for scheduling without per-trigger IO
- custom player/render path backed by decoded PCM

Whichever shape is chosen, slice triggering must not open files, check file
existence, decode audio, or allocate unbounded buffers per trigger.

Dynamic trim/reverse/choke behavior must remain correct. Mono slicer playback
must stop/reuse the current voice rather than layering slices.

### 4. Realtime Path Static Gate

Add a static gate that runs in CI and can be run locally, for example:

```sh
scripts/diagnostics/realtime-path-lint.sh
```

The gate should fail on forbidden calls in realtime-owned files/functions unless
there is a narrow allow annotation with a reason and test reference.

Forbidden by default in realtime path:

- `FileManager`
- `Data(contentsOf:)`
- `AVAudioFile(forReading:)`
- `AudioFileRef.resolve`
- `DispatchQueue.main.sync`
- unannotated `DispatchQueue.main.async`
- `MainActor.run`
- unannotated `Task { @MainActor ... }`
- graph mutation APIs such as attach/connect/disconnect/reconnect
- blocking waits, semaphores, sleeps, synchronous disk/network APIs

The lint should cover at least:

- `Sources/Engine/EngineController.swift`
- `Sources/Engine/EngineSlicerDispatcher.swift`
- `Sources/Engine/EngineControllerNoteRepeat.swift`
- `Sources/Engine/RouterDispatchState.swift`
- `Sources/Audio/SamplePlaybackEngine.swift`
- sampler/slicer/audio input helpers called from those paths

Allowed exceptions must look deliberate, for example:

```swift
// realtime-allow-main-async: UI-only activity publication, not required for scheduling. Test: TimingProbeReportTests.
```

No anonymous or blanket allow list is acceptable.

### 5. Runtime Guards

Extend the timing probe from the current POC into a general realtime probe:

- event dispatch late time by kind and track
- sample/slice schedule start/end data
- cache lookup result and lookup duration
- cache warmup duration
- main hop queued/started latency by subsystem and reason
- graph repair/reconnect duration and cause
- tick duration and events per tick
- activity markers for workspace/tab/selection/routing/mixer changes

Runtime logging must make this workflow possible:

1. start the app with timing logging enabled
2. press play
3. switch views, change tabs, adjust mixer/routing, trigger slicer/drums
4. run a report that ranks late events and nearby causes

The report must group “late event preceded by main hop”, “late event preceded
by cache miss”, “late event preceded by graph repair”, and “late event during
view/activity churn”.

### 6. Main-Hop Budgeting

Fire-and-forget main hops are not automatically safe. They avoid deadlock but
can still be late.

Every main hop reachable from realtime-adjacent code must be classified:

- UI/status publication: allowed, never required for sound
- exceptional repair: allowed, logged, should be rare
- normal event scheduling/control: not allowed unless a better audio API is
  unavailable and the hop latency is logged with an explicit debt item

Known candidates to classify:

- sample graph repair fallback
- sampler filter parameter updates
- AU instrument note-on/off
- audio-input loop repair/retry
- graph reconnect paths triggered by document/routing changes

## Verification Requirements

The work is not complete until these checks exist and pass.

### Unit Tests

- Sample trigger dispatch does not call `AudioFileRef.resolve`,
  `FileManager.fileExists`, or `AVAudioFile(forReading:)`.
- Slicer trigger enqueue/dispatch does not perform file resolution or file open.
- A warmed sample track schedules from cache without touching disk.
- A warmed drum kit plays dense repeated hits with zero cache misses.
- A cold sample while transport is running logs a cache miss/readiness state and
  does not block tick dispatch.
- Mono slicer playback stops/reuses the active voice and does not layer slices.
- Sample output routed to master and group bus both remain connected and audible.

### Static/Lint Tests

- `scripts/diagnostics/realtime-path-lint.sh` fails on an injected
  `AVAudioFile(forReading:)` in `dispatchTick`.
- The same lint fails on an injected `FileManager.default.fileExists` in
  `EngineSlicerDispatcher`.
- The same lint fails on an injected `DispatchQueue.main.sync` in any
  tick-path helper.
- The same lint fails on injected graph mutation calls such as
  `audioGraph.connect(...)` or `engine.disconnectNodeOutput(...)`.
- Allowed main async annotations require a reason and a test name.
- Allowed graph mutation annotations require a reason and a test name.

### Timing/Stress Tests

- Dense drum kit: 16th-note hats/kick/snare at 120, 150, and 180 BPM for at
  least 60 seconds with no failure-threshold late events after warmup.
- Slicer: rapid alternating slices with mono choke and dynamic trim/reverse
  while switching tabs; no layered mono voices and no cache misses.
- UI churn: automated workspace/tab switching while playback runs; sample/slice
  event lateness remains below failure threshold.
- Mixer/routing churn: fader, send, bus route, and group-bus changes while
  playback runs; normal playback does not require graph repair on the tick path.
- Cold start: pressing play before warmup finishes shows pending/readiness state
  and produces no tick-path disk IO.

### Diagnostic Report Acceptance

After a manual “press play and do stuff” session, the timing report must show:

- count and p95/max late event by kind
- p95/max main-hop latency by subsystem and reason
- cache hits/misses by sample/track
- graph repair/reconnect count and duration
- nearest activity markers for late events
- top remediation suggestions ordered by observed impact

The report should exit non-zero when failure thresholds are exceeded in a test
scenario.

## Done Criteria

This bug is resolved only when:

1. active samples/slices/drum-kit assets are warmed before playback depends on
   them
2. tick/event dispatch performs zero filesystem IO and zero audio-file open/decode
3. no normal sample/slice playback path needs the main actor
4. remaining main hops are classified, logged, and bounded
5. static lint prevents reintroducing forbidden realtime-path calls
6. timing stress scenarios pass under UI churn
7. `docs/code-health/2026-06-15-realtime-architecture-debt-queue.md` is updated
   to close or narrow RT-3, RT-4, RT-6, RT-7, and RT-10 as appropriate

## Related Evidence

- `docs/code-health/2026-06-15-realtime-architecture-debt-queue.md`
- `docs/audits/2026-06-12-architecture-verdict.md`
- timing POC logs under `.meta/timing-probe-lag-*.log`
- current POC branch `codex/timing-probe-poc`

## 2026-06-22 POC Implementation Notes

Implemented in this worktree so far:

- `SampleAssetCache` warms active sample/slicer assets during document sample
  mixer sync, keyed by sample ID plus file identity. It exposes non-blocking
  realtime lookup, readiness states (`loading`, `ready`, `failed`, `stale`),
  pinned active assets, explicit memory budget eviction for inactive assets, and
  cache load/miss/failure/eviction diagnostics.
- warmup is synchronous while stopped and asynchronous while the transport is
  running, so a route/sample change during playback records pending readiness
  instead of blocking tick dispatch.
- sample and slicer `ScheduledEvent` payloads carry sample IDs, not file URLs.
- tick/event dispatch looks up prepared assets non-blockingly and drops/logs a
  cache miss instead of resolving or opening files.
- `SamplePlaybackEngine` has prepared-asset play/slice methods; reverse/envelope
  slice buffers are copied from warmed PCM memory instead of reopening the file.
- sample/slicer status reporting now surfaces pending/failed/stale cache states
  so "Sample playback pending" points at asset readiness rather than a silent
  no-op.
- timing probe logs sample/slice frame start/end, cache load/lookup result,
  tick/event lateness, main repair hops, cache evictions, and view/activity
  markers.
- cache lookup timing logs now include both sample ID and track ID when the
  lookup happens from dispatch, so drum-kit and slicer cache readiness can be
  correlated back to the exact active lane rather than only the shared sample.
- timing probe `lateMs` now means positive lateness only; future-scheduled
  events are clamped to `0.000000` so offline/manual tests and lookahead
  scheduling do not pollute reports with negative "late" values.
- immediate sample/slice schedule logs now use `scheduled=unscheduled` and
  `lateMs=0.000000`/`late=0.000000` instead of the previous `-1` sentinel, so
  timing reports and manual log reads do not have to special-case negative
  lateness.
- `scripts/diagnostics/timing-probe-report.sh` now summarizes late event
  count/p95/max by kind, main-hop count/p95/max by reason, cache hits/misses by
  sample and track, cache evictions, graph repair durations, and correlation
  groups for late events near view/activity churn, cache misses/failures/
  evictions, main-hop waits, or graph repairs. It emits ranked remediation
  suggestions ordered by observed impact, can fail CI-style when
  `TIMING_PROBE_FAIL_ON_FAILURES=1` is set, and can analyze either a fresh
  unified-log time window or a saved timing log file.
- `scripts/diagnostics/realtime-path-lint.sh` blocks file resolution/open,
  unannotated main hops, and graph mutation APIs in the engine realtime dispatch
  files. The lint accepts only narrow allow comments with a reason and a test
  reference. The default scan now includes `EngineControllerAudioInput`; it also
  includes `MainAudioGraph` in graph-owner mode, where owned graph mutation is
  allowed but file IO and main-hop rules still apply.
- existing sample-engine graph mutations are now explicitly annotated as
  constructor/setup/teardown, exceptional repair, or test-only graph damage. New
  unannotated `attach`/`connect`/`disconnect`/`reconnect` calls in the scanned
  realtime files fail the lint.
- the default lint set now also covers `SamplerFilterNode`,
  `AudioInstrumentHost`, `EngineControllerAudioInput`, and `MainAudioGraph`, so
  sampler filter parameter main hops, AU note/control main hops, audio-input
  tick helpers, meter publication hops, and graph setup/teardown mutations must
  be explicitly classified. These AU/filter/graph-owner paths are still timing
  debt; they are visible and guarded against anonymous expansion rather than
  solved as fully realtime-safe audio-thread operations.
- focused tests cover sample cache warmup/readiness/eviction, sample warmup not
  reopening per dispatch, realtime lint positive and negative fixtures, and
  manual-rendering isolation for sample trigger controller tests.
- mixer-bus terminal wiring now reissues bus outputs to the pre-master mixer
  with explicit input-bus allocation, matching the offline harness finding that
  pending mixer connections can be invisible to `nextAvailableInputBus`.
- raw-player manual-render coverage proves a simple player routed through a
  mixer bus can render non-silent audio after the documented manual-render
  start/stop priming step.
- raw-player coverage through the same sample-style
  `player -> voice filter -> track mixer -> track filter -> mixer bus` shape
  also renders non-silent audio, so the remaining group-bus regression is not a
  generic mixer-bus or filter-chain topology failure.
- prepared sample voice fan-in now rewires voice filters into the track mixer
  with explicit input-bus allocation during setup/repair; this guards against
  pending manual-render mixer-input collisions, though it does not by itself fix
  the prepared sample group-bus regression.
- mono slicer playback now has focused voice-selection evidence: a dense
  32-trigger alternating-slice test with trim, reverse, filter, pan, gain, and
  envelope variations always selects voice `0` and records that the prior mono
  voice was stopped/reused. A polyphonic control test still proves normal sample
  playback rotates voices.
- slicer dispatch now also has controller-level cache evidence: a rapid
  128-tick alternating-slice clip with per-step trim, reverse, pan, filter,
  envelope, gain, pitch, and `choke=true` dispatches mono slice triggers from
  the warmed source asset after a single warmup file open and no per-trigger
  reopens.
- live-render sample-engine tests are deliberately avoided for this regression
  lane because they can initialize the HAL/input path and block on macOS
  microphone permissions. Automated coverage for routing/audio audibility must
  use offline manual rendering unless an interactive, pre-authorized hardware
  test is explicitly requested.
- the same microphone-permission issue affects attempts to run a live copy of
  the app with timing logging from automation. Until an interactive,
  pre-authorized session is available, timing guard work should use saved
  unified logs, synthetic/offline tick drives, and manual-render tests.
- the dense drum cache stress lane is also kept offline/manual: it drives
  `EngineController.processTick` with synthetic host times rather than launching
  the live app or any input/HAL path. This avoids macOS microphone permission
  prompts while still exercising the tick/event dispatch and cache lookup code
  used by drum playback.
- group-bus prepared sample playback now uses a separate bus-safe prepared pool
  instead of the normal shared track-mixer/track-filter fan-in. For bus-routed
  tracks, each voice is wired `AVAudioPlayerNode -> per-voice AVAudioMixerNode
  -> mixer bus`; the per-voice mixers carry the track fader/pan values while the
  prepared bus output remains connected before scheduling. This fixed the
  drum-kit-to-group-bus silent render without routing playback through the UI
  main actor.
- raw controls show why the bus-safe topology was chosen: `player -> per-voice
  mixer -> mixer bus` renders audibly in offline manual rendering, and the
  same production route now passes the sample-to-group-bus audibility
  regression. A separate raw probe still documents a CoreAudio graph-order
  hazard when `SamplePlaybackEngine` is constructed after a preexisting bus;
  the app lifecycle constructs the engine before document bus sync, so that
  probe is skipped as known ordering evidence rather than a normal regression
  gate.
- the deterministic UI-churn timing-report lane now has synthetic saved-log
  fixtures for both outcomes: churn-adjacent sample/slice lateness below the
  5 ms failure threshold exits green while still correlating with activity
  markers, and a churn-adjacent sample event above 5 ms exits non-zero with an
  event-lateness remediation suggestion. This gives CI coverage for the manual
  "press play, switch views, analyze late events" workflow without launching
  the live app or touching the microphone permission path.

Verification added on 2026-06-22:

- `scripts/diagnostics/realtime-path-lint.sh`
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/RealtimePathLintTests`
  passed 10 tests after widening default coverage to include sampler filter, AU
  instrument helper, audio-input, and `MainAudioGraph` graph-owner files. The
  fixtures cover injected file IO, main sync, graph mutation, engine graph
  mutation, graph-owner mutation allowance, graph-owner main-hop rejection, and
  reasoned allow annotations. The macOS test host still logs the known HAL
  proxy/microphone-permission noise during launch, so live app audio tests
  remain unsuitable until run in an interactive, pre-authorized session.
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/SamplePlaybackEngineTests/test_playSliceMonoReusesAndStopsSingleVoice -only-testing:SequencerAITests/SamplePlaybackEngineTests/test_playSliceMonoRapidAlternatingSlicesAlwaysReusesSingleVoice -only-testing:SequencerAITests/SamplePlaybackEngineTests/test_samplePlaybackRemainsPolyphonicByDefault`
  passed, proving the mono slicer path stops/reuses one voice under rapid
  alternating slice triggers while sample playback remains polyphonic by
  default.
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/EngineControllerSampleTriggerTests/test_slicerRapidAlternatingSlicesUseWarmedAssetAndRemainMono`
  passed, proving a slicer clip can dispatch 128 rapid alternating mono/choked
  slice triggers through the warmed source sample after exactly one warmup file
  open and no dispatch-time reopens.
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/EngineControllerSampleTriggerTests/test_denseRepeatedSampleHitsUseWarmedAssetsWithoutAdditionalFileOpens`
  passed, proving three active drum samples can dispatch 64 dense ticks
  (192 sample triggers) after exactly three warmup file opens and no
  dispatch-time reopens. A first rerun was cancelled by an `xcodebuild`
  DerivedData build database lock while another focused test was running; the
  same test passed when rerun sequentially.
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/EngineControllerSampleTriggerTests/test_denseDrumPlaybackForSixtySecondsAtMultipleBPMsUsesWarmedAssetsWithoutAdditionalFileOpens`
  passed, proving a three-track dense drum kit can run 60 seconds each at
  120, 150, and 180 BPM (1,800 synthetic ticks, 5,400 sample trigger
  dispatches) after exactly three warmup file opens and no dispatch-time
  reopens. An initial version of the harness jumped synthetic time/ticks between
  BPM sections and flushed two prepared transition ticks; the final passing
  test keeps tick indices and host time continuous, matching one transport
  changing tempo.
- `bash -n scripts/diagnostics/timing-probe-report.sh`
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/TimingProbeReportTests`
  passed 7 tests, covering report summaries for late events, main-hop waits,
  cache misses, graph repair/reconnect duration, cache lookup counts by
  sample/track, ranked remediation suggestions, activity/cache/main-hop/
  graph-repair correlations, immediate sample/slice schedule lines with
  `scheduled=unscheduled`, non-zero failure-threshold exit behavior, and
  deterministic UI-churn pass/fail lanes. The Xcode host still produced the
  known HAL/proxy noise during startup, but the selected report tests passed.
- `scripts/diagnostics/realtime-path-lint.sh` passed directly after the timing
  report and cache-lookup logging changes.
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/EngineControllerSampleTriggerTests/test_denseRepeatedSampleHitsUseWarmedAssetsWithoutAdditionalFileOpens`
  passed after adding track-aware cache lookup logging, proving the dispatch
  path still uses warmed assets and emits sample/track cache-hit diagnostics.
- `xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/MasterRenderTests/test_sampleTrackRoutedToMixerBusAudibilityRegressionIsCaptured -only-testing:SequencerAITests/MasterRenderTests/test_rawPreparedVoicesThroughPerVoiceMixersToMixerBusRenderInManualRendering -only-testing:SequencerAITests/MasterRenderTests/test_rawPreparedVoicesDirectToMixerBusWithSampleEnginePreviewWiringRenderInManualRendering -only-testing:SequencerAITests/MasterRenderTests/test_rawPreparedVoicesThroughPerVoiceMixersToPreexistingMixerBusRenderInManualRendering -only-testing:SequencerAITests/SamplePlaybackEngineTests/test_preparedTrackRoutedToExistingMixerBusFeedsBusInput -only-testing:SequencerAITests/SamplePlaybackEngineTests/test_preparedTrackRoutedToMixerBusInstalledAfterRouteRefeedsBusInput`
  passed with 0 failures and 1 deliberate skip for the separate raw
  preexisting-bus graph-order hazard. The production group-bus sample render is
  now a normal passing audibility assertion, and the route-readout tests prove
  both existing-bus and installed-after-route sync paths build the bus-safe
  prepared pool.

Follow-up before hardware sign-off:

- static lint reachability over every helper reachable from realtime paths:
  graph mutation APIs, sampler filter hops, AU instrument hops, audio-input
  helpers, and `MainAudioGraph` file/main-hop hazards are now covered in the
  default scan, but future graph-owner topology changes should add measured
  stress evidence rather than relying only on static classification.
- live UI-churn capture from a running app with hardware audio remains blocked
  in automation by the macOS microphone/HAL permission path. Until run
  interactively in a pre-authorized session, closure evidence is offline:
  synthetic tick drives, saved-log report fixtures, and manual-render routing
  tests.
- broader main-hop reduction for audio-input repair and graph reconnect
  paths; sampler filter changes and AU note/control hops are now classified in
  the lint, but still represent architecture debt until moved to bounded audio-owned
  state or measured under stress
- live integrated slicer/UI-churn timing capture should still be run in an
  interactive, pre-authorized hardware session before declaring the hardware
  path proven; the automated lane is covered by offline slicer/cache tests and
  deterministic saved-log timing-report fixtures.

Captured lag-log readout from `.meta/timing-probe-lag-check-rerun.log`:

- 374 sample late events, p95 `126.781 ms`, max `13988.924 ms`
- no sample cache misses in that captured log
- no main-hop wait entries in that captured log
- no nearby activity/cache/main-hop marker correlation was available for those
  late events, so more activity markers are still needed around the specific UI
  churn paths
