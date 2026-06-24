# Bug: adding an AU FX insert to a track crashes (graph-lock re-entrancy)

**Filed:** 2026-06-24 (hit during the audio-routing real-audio pass)
**Severity:** CRASH on a common action (add an AU effect insert to a track)
**Crash report:** `~/Library/Logs/DiagnosticReports/SequencerAI-2026-06-24-165713.ips`
(pid 89038, SIGTRAP — intentional deadlock-guard assertion)

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

When `TrackInsertChainHost.startLoadingAUEffect`'s completion is invoked
**synchronously** (e.g. the AU is cached / loads inline) while the graph lock is
already held by the in-flight insert apply, `performOnMain` runs inline and
`lockGraphLock()` re-enters → the (correctly-working) deadlock guard traps.

The sibling **send-bus** post-load re-entry avoids this by **always hopping
`DispatchQueue.main.async`** before touching the graph (see MixerBusHost AU-load
completion). The **track-insert** re-entry (`rebuildTrackInsertChainAfterLoad`)
does NOT async-hop — that's the bug.

## Is it the routing-cleanup work?

Most likely **pre-existing**, not caused by R0–R2:
`rebuildTrackInsertChainAfterLoad`, `makeTrackInsertChainHost`,
`TrackInsertChainHost`, and the AU-load path were **not modified** by R0/R1/R2.
R2 changed the sibling `applyTrackInsertsOnMain` (removed engine stop/start) but
did not alter the AU load or the locking. **Verify by reproducing on `main`** (add
an AU effect to a track) — if it also crashes there, it's pre-existing.

## Fix direction

Make `rebuildTrackInsertChainAfterLoad` **async-hop** before acquiring the lock
(mirror the send-bus path): `DispatchQueue.main.async { performOnMain { lock… } }`
or guarantee `startLoadingAUEffect`'s completion is always delivered async. Then
the post-load re-entry never runs inside the lock-held synchronous completion.

## Acceptance

Add/remove an AU effect insert on a track (cached and uncached AU) during
playback with no crash; the new AU node wires in and sounds.
