# Send-effect amount change hangs the app (deadlock / render-livelock)

FUNCTIONAL bug (hang, not a crash; no crash report, process stays alive).

## Repro
Play a project, then change a channel's **send-effect amount** in the mixer → the
app hangs (audio + UI freeze).

## Diagnosis (from a live `sample` of the wedged process, see hang-sample.txt)
- **TickClock thread** blocked on the engine `stateLock` inside `prepareTick`.
- **Main thread** wedged in a SwiftUI/AppKit layout cycle (CATransaction commit →
  `layoutSubtreeIfNeeded`, 435/435 samples, never returns to the run loop), reached
  via `ObservationGraphMutation.apply`.
- **Audio render thread** starved (2/435 samples actually rendering).

Mechanism: the send-effect `@Observable` mutation drives a synchronous main-thread
layout storm **while the engine `stateLock` is held**, starving the tick and audio
render. This is the mixer render-livelock class (cf. branches
`fix/mixer-render-livelock`, `fix/device-apply-route-resync`; debt RT-7 "mixer drag
fan-out to O(everything) graph refresh"). Reporter notes this "was thought fixed" —
so it regressed or was only partially fixed.

## Likely fix
Release `stateLock` before the `@Observable` bump that triggers synchronous layout,
and/or debounce the mixer graph fan-out so a send-amount drag doesn't refresh the
whole graph per change. Verify with the timing probe (no slow-tick / starvation on
send-amount change while playing).

## Provenance
Found live during the 2026-06-23 observer-sweep W3.13 timing capture. Confirmed NOT
caused by the observer-sweep branch (send-fx mutation path byte-identical main vs
branch).

## Decision (2026-06-23, user)
Fix now. Likely approach: release stateLock before the @Observable bump that triggers synchronous layout, and/or debounce the mixer graph fan-out. User will verify audio behaviour after (CI can't drive real audio).
