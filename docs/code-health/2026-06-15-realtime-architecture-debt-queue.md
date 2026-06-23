# Realtime architecture debt queue

Date: 2026-06-15.

This queue turns the June 12 architecture/concurrency/latency audits into
closeable engineering work. The important correction is process-level: audit
findings are not closed by being described, and they are not closed by fixing
one symptom. Each item below needs a concrete code change plus an acceptance
gate that would fail if the class comes back.

Primary sources:

- `docs/audits/2026-06-12-architecture-verdict.md`
- `docs/audits/2026-06-12-concurrency.md`
- `docs/audits/2026-06-12-mixer-latency.md`
- `docs/audits/2026-06-12-abstraction-layers.md`
- `docs/testing/concurrency-lane.md`
- `docs/testing/render-harness.md`

## Closure Rule

An item can move to **Closed** only when all three are true:

1. the code path named by the audit has been removed, inverted, or made safe
2. a focused regression or guard exists
3. a wider gate covers the behavior class, not only the exact old line

If only one symptom is fixed, mark the item **Partially mitigated**.

## Queue

| ID | Status | Source | Problem | Acceptance gate |
| --- | --- | --- | --- | --- |
| RT-1 | Partially mitigated | concurrency D1/D2, architecture verdict §1 | Tick/audio work must never synchronously wait on the main thread. Several classes have been fixed, but this remains the central invariant and must be enforced mechanically. | `TickPathMainSyncGuard` traps in DEBUG, positive/negative tests cover tick markers, and churn tests run without any guard violations. |
| RT-2 | Open | concurrency D1 | No sync-to-main while holding `stateLock`, especially audio-input capture begin/format lookup paths. | A test or guard proves `withStateLock` depth is zero before any `performOnMain*` or direct `DispatchQueue.main.sync` helper can run. |
| RT-3 | Partially mitigated | concurrency D2, recent sample scheduling trace | Fire-and-forget main scheduling removes deadlocks but can still miss short transient playback when a host-time is stale by the time the main queue runs it. The prepared sample fast path now avoids the normal sample/slice trigger hop through the main actor; repair fallbacks remain logged debt. | Render or focused sample-engine tests prove stale host-time sample playback becomes immediate, future host-time remains scheduled, and dense hats remain audible. |
| RT-4 | Open | concurrency D3 | AU/instrument host paths still have main/host-queue AB-BA risk around preset/state readout and per-note main hops. | Host-note and preset/state operations have async or non-blocking contracts; churn covers note-on/off plus preset/open/stop without deadlock. |
| RT-5 | Open | concurrency D4/R1 | Tick-adjacent code must not mutate `@Observable` state or read mutable document state without a published immutable snapshot. | Tests or static guards cover observable writes from tick paths; tick path consumes immutable snapshot data only. |
| RT-6 | Partially mitigated | concurrency B6 | Sample file open/cache work must not run on the tick path under `lifecycleLock`. A `SampleAssetCache` now warms active sample/slicer assets from document apply, sample/slice dispatch consumes prepared assets by sample ID, and realtime lint blocks file resolution/open calls in engine dispatch files. Remaining closure work is async readiness/pending UI plus dense stress evidence. | Sample cache is warmed or asynchronously resolved; dense sample playback does not perform file IO on the tick queue. |
| RT-7 | Open | mixer latency audit | Scoped mixer UI changes must not fan out into an O(everything) graph refresh on every drag tick. | Mixer fader/bus/send drags update only the affected graph endpoints; stress scenario verifies UI drag does not make ticks late. |
| RT-8 | Open | abstraction F6, architecture verdict §2 | Meter publication must have one narrow pump, not multiple main-queue 60 Hz publishers that broaden SwiftUI invalidation. | Master/channel meters share one bank or equivalent narrow publisher; view invalidation remains scoped under meter churn. |
| RT-9 | Open | abstraction F9 | Slicer/waveform views must not perform raw audio-file IO on the main thread. | Slicer views use an audio-layer metadata/waveform service; UI tests or review checks reject `AVAudioFile(forReading:)` in view files. |
| RT-10 | Partially mitigated | red-team/render harness briefs | The app needs a repeatable realtime evidence gate, not only unit tests. The timing probe now records tick/event lateness, sample/slice schedule data, cache hits/misses, main-hop repair waits, and workspace/activity markers; `scripts/diagnostics/timing-probe-report.sh` summarizes late events, cache misses, main-hop waits, and warmup durations. | A short deterministic render/churn lane runs dense sample playback, UI movement, start/stop, and routing changes, then records pass/fail evidence. |

## Why These Were Not Enough Before

The June 12 audits correctly described the architecture problem, and some fixes
landed afterwards. The missing piece was a closure ledger. Broad audit prose
made it too easy for agents to fix a nearby deadlock, declare the local symptom
done, and miss a neighboring timing regression.

The hi-hat investigation is the example to remember. The earlier
`SamplePlaybackEngine` change made playback fire-and-forget on main, which was
the right direction for deadlock safety. But the acceptance condition was too
narrow: it assumed scheduled `AVAudioTime` preserved timing even if the main
queue ran late. Runtime tracing showed that short samples could be scheduled
after their host time and become effectively inaudible. That converts RT-3 from
"fixed" to "partially mitigated until stale-host-time behavior is covered."

## Routing Guidance

Treat RT-1 through RT-3 as the current highest-priority realtime debt because
they directly affect audible playback correctness. RT-7 follows closely because
it can reintroduce the same symptom through UI pressure.

Future feature builders touching engine, audio, mixer, slicer, or transport
code should check this file before implementation and update the relevant row
when they add a guard or find fresh evidence.
