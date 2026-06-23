# Live Timing Verification: Send-Effect Hang And Sample Lag

Date: 2026-06-23
Branch/worktree: `codex/timing-probe-poc` in `.worktrees/timing-probe-poc`
Evidence:

- `.meta/live-verification/timing-live-postmortem-20260623-094452.log`
- `.meta/live-verification/timing-live-report.txt`
- `.meta/live-verification/SequencerAI-hang-send-effect.sample.txt`

## User-Visible Failure

During an interactive timing-probe run, playback audibly lagged while switching
views. The app then hung when the user tried to send a track to a send effect.

This run used the timing/cache POC with:

- `TimingProbeEnabled = true`
- `SampleTriggerTraceEnabled = true`

## What The Probe Proves

The sample cache was not the primary bottleneck in this run:

- Cache lookups: 1,582 hits, 1 miss.
- Real sample warmups were small: `Atlantis Amen.wav` 1.64 ms, `kick-01.wav`
  0.84 ms, `snare-01.wav` 0.46 ms, `hat-closed-01.wav` 0.13 ms.

The dominant audio failure was prepared sample-player disconnection:

- 505 `player started when in a disconnected state` failures.
- 506 queued `post-failure-repair` main hops.
- 506 started `post-failure-repair` main hops.
- 10 `graph-repair subsystem=sample cause=prepared-track` events.

The repair path was much too expensive for live transport:

- `post-failure-repair` main-hop wait p95: 421.462 ms, max: 4,194.982 ms.
- `repair` main-hop wait p95/max: 3,786.360 ms.
- Graph repair p95/max: 256.985 ms.
- Slowest process tick: 2,078.379 ms.

After the large repair burst, the tick clock remained offset by about 2.48 s for
hundreds of ticks, so the scheduler did not recover its musical timebase after
the stall.

## Correlation

The relevant view/activity breadcrumbs were:

- 09:42:20 track -> mixer
- 09:42:30 mixer -> tracks
- 09:42:43 tracks -> track
- 09:43:03 track -> tracks
- 09:43:10 tracks -> phrase
- 09:43:23 phrase -> mixer

The worst audio disruption clustered at 09:42:40-09:42:43:

- Four prepared-track graph repairs around 255-257 ms each.
- Process ticks at 2,078 ms, 518 ms, and 262 ms.
- Sample events over 3.7 s late.
- Tick-clock lateness around 2.48 s, which then persisted.

The reported send-effect hang occurred after the 09:43:23 mixer switch. The log
does not currently contain send-level, send-effect, or route-mutation
breadcrumbs around that action. The postmortem tail only shows repeated
`flushToDocumentSync` entries, so the exact send mutation has to be inferred
from the user's report and the process sample.

## Process Sample

The hang sample shows the main thread spending most of its time in AppKit/SwiftUI
layout/rendering around the mixer strip, including:

- `MixerChannelStrip.sendsSection` in `Sources/UI/MixerView.swift`
- `MixerChannelStrip.trackOutputSelector` in `Sources/UI/MixerView.swift`
- `EngineController.channelMeterPublisher(for:)`
- `MasterMeterPublisher.publishPendingToMain(now:)`

The sample also shows active AVAudio render/tap stacks and channel meter
processing. This suggests the send-effect hang is at least partly UI/meter/layout
pressure during a route/send mutation, while the audio lag is strongly tied to
sample graph disconnections and per-trigger repair storms.

## Suspected Root Cause

The POC improves normal sample playback by adding an in-memory prepared-sample
fast path, but prepared player nodes can still become disconnected during
route/graph churn. When playback then hits a disconnected player, the error path
queues a main-thread graph repair for each failing trigger. Under transport, that
turns one graph-shape bug into a retry/repair storm.

Current repair code path:

- `Sources/Audio/SamplePlaybackEngine.swift` calls `requestPreparedTrackRepair`
  after schedule/play failures.
- `requestPreparedTrackRepair` dispatches to the main queue.
- The main closure calls `repairPreparedTrackGraph`, which disconnects,
  reattaches, and reconnects prepared player/filter/mixer graph nodes.

That recovery strategy is not acceptable during live playback.

## POC Safety Patch

The POC branch now defers failed fast-path prepared-sample repair instead of
queueing a main-thread graph repair from the trigger path.

New behavior:

- failed prepared fast-path playback removes the track from the fast-path-ready
  set;
- the track ID is marked in a deferred repair set;
- the trigger is dropped and `sample-fast-path result=repair-deferred` /
  `schedule-failed` breadcrumbs are emitted;
- later explicit setup/prepare paths repair the graph and clear the deferred
  marker.

This does not solve the underlying disconnection. It prevents the POC from
amplifying that existing bug into an unbounded post-failure repair storm while
keeping the timing evidence and sample-cache fast path mergeable.

## Remedial Work

1. Stop repairing prepared sample graphs from the per-trigger failure path while
   transport is running.
   - Mark the track or bus pool unhealthy.
   - Drop or silence only that failing trigger.
   - Coalesce repair to a single pending operation.
   - Prefer repair when stopped, before transport starts, or in an explicit
     route-apply phase.

2. Add tests for route/send-effect churn while transport is active.
   - Route a drum/sample track through master, mixer bus, and send-effect paths.
   - Change sends/output while repeated sample events are scheduled.
   - Assert no disconnected-player failures, no repeated repair requests, and no
     graph mutation from tick dispatch.

3. Add sparse activity breadcrumbs for route/send mutations.
   - Track output route changes.
   - Send level changes that instantiate or reconnect send-effect paths.
   - Send effect creation/removal/reordering.
   - Include track/bus/send IDs and whether transport is running.

4. Bound mixer UI/meter publication pressure during route changes.
   - Avoid repeated `channelMeterPublisher(for:)` lookup work from strip body
     rendering.
   - Throttle or suspend per-channel meter publication while route graph changes
     are applying.
   - Measure mixer body recomputation and send-section render cost in debug
     builds.

5. Re-anchor or intentionally resynchronize the tick clock after a catastrophic
   scheduler stall.
   - A single 2 s stall must not leave all future ticks permanently 2 s late.
   - The recovery policy should be explicit: skip missed ticks, restart phase, or
     stop transport with a diagnostic.

6. Fix the timing report so cache hits are not suggested as cache-readiness
   problems.
   - Only `missing`, `load`, eviction, or slow lookup/load events should produce
     cache remediation suggestions.

## Done Checks

The work is not complete until an interactive or scripted run can show:

- Zero `player started when in a disconnected state` logs during view switching
  and send/route changes.
- Zero `post-failure-repair` main hops during live transport.
- Zero graph repairs initiated from normal sample trigger dispatch.
- `process-tick` p95 below 2 ms during playback; max below 10 ms for the
  view-switch/send-route scenario.
- `sample` and `slice` late-event p95 below 2 ms, with no event above 5 ms in the
  scenario.
- Tick-clock lateness recovers after any forced stall according to the chosen
  policy.
- Send-effect route changes emit enough breadcrumbs for the timing report to
  correlate late events or hangs with the exact route/send action.
- The timing report no longer lists cache hits as cache remediation suggestions.
