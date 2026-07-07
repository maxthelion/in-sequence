# Crash: QA capture track sound-source transition detaches track send nodes

Status: OPEN
Filed: 2026-07-07
Source: full QA surface capture run on `main` at `044f728c`

## Summary

The full `qa-surface-coverage` visual capture crashed SequencerAI while moving
through the track sound-source rows. The capture later completed when the
affected rows were retried in isolated launches, which points at a lifecycle /
transition crash rather than a permanently uncapturable screen.

This is distinct from the July 7 tick-path main-sync crashes. Those crashed on
the `TickClock` queue after phrase-scene playback synchronously reached
main-bound mix/graph work. This crash is on the main thread inside
`AVAudioEngine.detachNode`, reached from sample-track teardown / output
disconnect.

Raw report: `crash.ips`

## Observed Crash

- Process: `SequencerAI`
- Date/time: `2026-07-07 21:00:56 +0100`
- macOS: `15.3.2 (24D81)`
- Capture run: `20260707-201705-in-sequence-qa-surface-coverage-main-044f728c`
- Scenario row before failure: `19a-track-sound-empty`
- Exception: `EXC_BAD_ACCESS (SIGSEGV)`, `KERN_INVALID_ADDRESS at 0x0`
- Faulting thread: main thread

Key stack:

```text
AVAudioEngineGraph::RemoveNode(AVAudioNode*, NSError**)
-[AVAudioNode didDetachFromEngine:error:]
AVAudioEngineImpl::DetachNode(AVAudioNode*, bool, NSError**)
-[AVAudioEngine detachNode:]
MainAudioGraph.removeTrackSendNodes(for:) MainAudioGraph.swift:2796
MainAudioGraph.disconnectOutput(_:) MainAudioGraph.swift:440
SamplePlaybackEngine.removeTrack(trackID:) SamplePlaybackEngine.swift:1286
SamplePlaybackEngine.rampMixersToSilenceThenDetach(_:detach:) SamplePlaybackEngine.swift:1330
```

## Repro Evidence

The first monolithic full capture run crashed after `19a-track-sound-empty`.
Running the remaining rows one-at-a-time and then retrying
`19a-track-sound-empty` succeeded, so the best current repro is the full-suite
transition sequence rather than a standalone row.

Useful commands:

```sh
PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/full-latest-20260707" \
  scripts/visual-scenarios/qa-surface-coverage.sh
```

The completed gallery after isolated retries:

```text
http://localhost:4747/gallery?run=20260707-201705-in-sequence-qa-surface-coverage-main-044f728c
```

## Relationship To Existing Bugs

Not the same as:

- `20260707-092254-crash-adding-master-output-insert-tick-path-main-sync`
- `20260707-095643-crash-dragging-scene-filter-cutoff-tick-path-main-sync`

Those involved `TickPathMainSyncGuard` and forbidden sync-to-main from the tick
path. This crash has no tick-path guard frame and faults in AVFAudio node
removal on the main thread.

Related class:

- `20260629-121929-au-removal-while-playing-crash`

That older report is also graph/lifecycle teardown, but it faults on the audio
render thread inside a third-party AU after AU removal while playing. This new
report is sample-track/send-node teardown during an automated surface transition.
Treat them as related architecture risks, not duplicates.

## Working Hypothesis

`MainAudioGraph.disconnectOutput(_:)` always calls
`removeTrackSendNodes(for:)` before disconnecting the source node. During a
track sound-source transition, sample track teardown can call
`disconnectOutput` on captured mixer/filter nodes after a short ramp. The
associated send fanout/send nodes are dissolved and detached immediately.

The crash suggests that at least one send-node detach can still be unsafe in the
current graph state, possibly because:

- a send node is still connected or internally referenced when `detach` runs;
- repeated source transitions cause two teardown paths to race or double-own the
same send-node fanout;
- `disconnectOutput`'s automatic send-node teardown is too broad for nodes that
are being removed as part of a larger sample-track teardown;
- `AVAudioEngine` needs track-send node detaches deferred or pooled instead of
detached inline during rapid source transitions.

The fix must follow the audio hard rules: no `engine.stop()/start()` topology
band-aid during playback, no render-thread work, and no hard disconnect of a
sounding path without ramping to silence first.

## Acceptance

- The full monolithic `qa-surface-coverage.sh` run completes all active rows
  without crashing or requiring isolated retries.
- A focused automated regression covers the track sound-source transition that
  removes a sample track and its track-send nodes.
- The fix does not introduce `engine.stop()/start()` for topology changes during
  playback.
- `scripts/diagnostics/realtime-path-lint.sh` passes.
- `scripts/diagnostics/runtime-ownership-lint.sh` passes.
- `scripts/visual-scenarios/routing-stress.sh` passes, or the plan records a
  precise reason it cannot be run in the current environment.
