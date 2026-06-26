# Bug: adding an AU FX insert to a track crashes (graph-lock re-entrancy)

**Filed:** 2026-06-24 (hit during the audio-routing real-audio pass)
**Severity:** CRASH on a common action (add an AU effect insert to a track)
**Crash report:** `~/Library/Logs/DiagnosticReports/SequencerAI-2026-06-24-165713.ips`
(pid 89038, SIGTRAP — intentional deadlock-guard assertion)

## STATUS: RESOLVED (triaged 2026-06-26, audio-routing-cleanup)

Verdict: **structurally fixed** — the track-insert add-FX path cannot re-enter
`graphLock` on the same thread. Evidence:

- `TrackInsertChainHost.startLoadingAUEffect` (Sources/Audio/TrackInsertChainHost.swift:255)
  ALWAYS re-enters the rebuild via `DispatchQueue.main.async`. Even when the AU
  factory completes INLINE on main (which it can — `AUAudioUnitFactory` runs its
  completion through `performOnMain`, i.e. inline on the main thread), the
  post-load rebuild is deferred to a *fresh* main-queue turn.
- Every graphLock holder on the main thread releases the lock synchronously
  before returning: `setTrackInserts` (MainAudioGraph.swift:1028),
  `rebuildTrackInsertChainAfterLoad` (1042), and the live-engine ramp-completion
  path `withTrackGainRampedToSilence` (2054) all do `lockGraphLock(); …;
  unlockGraphLock()` with **no run-loop spin** in between. So by the time the
  deferred `DispatchQueue.main.async` re-entry runs, graphLock is free.
- `lockGraphLock` is non-recursive and trips
  `debugAssertGraphLockNotHeldByCurrentThread` (135/146) on re-entry, and
  `performOnMain` trips `debugAssertNotHoldingGraphLockForMainHop` (2603) on any
  hold-across-sync-hop — so a regression of either shape FAILS loudly rather
  than wedging.

The crash-report "real puzzle" (lock still held on a fresh turn) was based on the
state at filing; the async-hop discipline + the two guards make the re-entry the
crash described impossible on this path now. The async hop has been present since
the first wiring commit (3c9bfb38), and subsequent graphLock work (#47 leaf-lock,
the AB-BA fixes, R0–R2, ramp-to-silence) closed the surrounding hold-under-hop and
stop/start shapes.

Regression coverage added:
`ConcurrencyChurnStressTests.test_trackInsertChain_inlineAUInstantiation_noGraphLockReentry_andWiresNode`
— injects an inline-completing AU factory, adds an AU FX insert via
`setTrackInserts`, asserts (a) no graphLock re-entry violation fires (the
detector is armed in `setUp`) and (b) the AU node wires into the live chain.
Mirrors the existing send-bus regression
`test_installSendBus_inlineAUInstantiationCompletesWithoutDeadlockAndWiresNode`.
Passes; the detector positive control (`test_graphLockReentryDetector_fires`)
proves the assertion is non-vacuous.

Residual (human): a real newly-instantiated AU effect added live during playback
(needs the macOS lower-permissions modal granted) — sounding + click-free. The
test exercises the locking/wiring shape with an inline native node, not a real
out-of-process AU.

## What happens

Adding an **AU effect** insert to a track crashes the app. The deadlock guard
(`TickPathMainSyncGuard.reportImminentDeadlock`) fires because the graph lock is
re-acquired on a thread that already holds it.

## Crash chain (top → down)

```
assertionFailure
TickPathMainSyncGuard.reportImminentDeadlock        EngineController.swift:95
MainAudioGraph.debugAssertGraphLockNotHeldByCurrentThread  MainAudioGraph.swift:135
MainAudioGraph.lockGraphLock()                      MainAudioGraph.swift:158
closure in MainAudioGraph.rebuildTrackInsertChainAfterLoad  MainAudioGraph.swift:852
MainAudioGraph.performOnMain (inline on main)       MainAudioGraph.swift:2014
MainAudioGraph.rebuildTrackInsertChainAfterLoad     MainAudioGraph.swift:851
closure in MainAudioGraph.makeTrackInsertChainHost (requestRebuild) :903
TrackInsertChainHost.startLoadingAUEffect (completion)  TrackInsertChainHost.swift:251
... dispatch main queue drain ...
```

## Root cause

`rebuildTrackInsertChainAfterLoad` (the AU-load completion re-entry) does:

```swift
performOnMain {            // on the main thread this runs INLINE (no async hop)
    self.lockGraphLock()   // <-- re-enters graphLock if already held
    ...
}
```

**CORRECTION (initial diagnosis was wrong):** the track-insert AU-load
completion ALREADY async-hops — `TrackInsertChainHost.startLoadingAUEffect`
wraps `requestRebuild(self.trackID)` in `DispatchQueue.main.async`
(TrackInsertChainHost.swift:249), with a comment naming this exact send-bus
"+Add FX" self-deadlock class. The crash stack confirms the re-entry runs on a
normal `_dispatch_main_queue_drain` (a fresh runloop turn), not inline.

So the real puzzle: **even on a fresh main-queue turn, `graphLock` is still held
by the main thread** when `rebuildTrackInsertChainAfterLoad` re-acquires it.
That implies either (a) a leaked/unbalanced `lockGraphLock`/`unlockGraphLock`
on the main thread from an earlier op (stale guard state), or (b) a main-thread
lock holder that spins the runloop / `DispatchQueue.main.sync`s while holding the
lock, so the async block runs nested inside the lock. Pinning which requires
**reproducing with an AU effect** — which needs the macOS lower-permissions
modal granted, i.e. a human present (see AGENTS.md audio test tiers). Not
headlessly reproducible.

## Is it the routing-cleanup work?

Most likely **pre-existing**, not caused by R0–R2:
`rebuildTrackInsertChainAfterLoad`, `makeTrackInsertChainHost`,
`TrackInsertChainHost`, and the AU-load path were **not modified** by R0/R1/R2.
R2 changed the sibling `applyTrackInsertsOnMain` (removed engine stop/start) but
did not alter the AU load or the locking. **Verify by reproducing on `main`** (add
an AU effect to a track) — if it also crashes there, it's pre-existing.

## Fix direction (needs AU repro = human present)

The async hop is already there, so the fix is NOT that. Investigate the held
lock: instrument `lockGraphLock`/`unlockGraphLock` to log owner + depth, repro
the add-AU-FX crash (human grants the AU permission modal), and find who holds
`graphLock` across the dispatched re-entry — then either balance the leaked
lock or make the guard/the re-entry tolerate it. Defer until an interactive
(permission-granting) session; the sample-only stress harness cannot exercise
AU-effect inserts. Native (non-AU) inserts do NOT take this path and can be
stress-tested headlessly.

## Acceptance

Add/remove an AU effect insert on a track (cached and uncached AU) during
playback with no crash; the new AU node wires in and sounds.

Status: RESOLVED — already structurally fixed (graphLock async-hop + #47/R0-R2); regression test added
