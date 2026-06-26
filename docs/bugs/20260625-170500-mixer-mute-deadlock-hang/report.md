# Bug: pressing mute on a track in the mixer hangs (deadlock)

**Filed:** 2026-06-25 (hit during the audio-routing real-audio validation pass)
**Severity:** HANG (deadlock) on a common action (mute a track in the mixer)
**Evidence:** `mute-hang.sample` (this dir) — `sample` of the live hung process.
**Mode:** real HAL playback (sample-only fixture, NO command channel / NO offline pump).

## What happens

Pressing the mute button on a mixer track wedges the app (beachball). The
process sample shows a mutual deadlock:

- **Tick thread:** `EngineController.prepareTick` → `NSLock.withLock`
  (lifecycle lock in `SamplePlaybackEngine`) → blocked (`semaphore_wait` /
  `mach_msg`). It cannot get the lock.
- **Main thread:** in `EngineController.effectiveMixerMuteState(tracks:buses:)`
  (`EngineControllerRoutingHelpers.swift:99`) then parked in `mach_msg` — the
  mute path is holding/awaiting a lock the tick path needs (or vice-versa).

So the mute mix-apply on main and the tick/sample-engine lock acquisition
deadlock against each other.

## Is it the routing-cleanup work?

**Not the offline-pump commit (47ec199a):** in HAL playback its changes are
inert (`scheduledPlaybackTime` ≡ `effectivePlaybackTime`; the offline barrier
never starts; `quiesceOfflineRenderPump` no-ops). So this is NOT caused by the
pump.

**Candidates:** an R0–R2 lock-order change in `MainAudioGraph`'s live reconnect
paths (graphLock now held across live rewires that overlap the tick path's
lifecycle-lock acquisition), OR pre-existing. **Verify by reproducing on `main`**
(mute a track in the mixer while playing) — classifies regression vs pre-existing.

## Fix direction (after classification)

Establish the lock-order between the mute/mix-apply path (graphLock) and the
tick/sample-engine lifecycle lock, and make them acquire in a consistent order
(or avoid nesting). The deadlock guard (`TickPathMainSyncGuard`) didn't catch
this one because it's a cross-lock deadlock, not graphLock re-entry.

## Acceptance

Mute/unmute any mixer track during playback with no hang; tick path keeps
running.

## Root cause (adversarial review 2026-06-25)
Regression-by-exposure. The lifecycleLock coupling is pre-existing, but our
branch removed the `engine.stop()` that ran before the reconnect — so the
control path now holds `lifecycleLock` across a LIVE `engine.connect/disconnect`
(which synchronizes with the HAL/render thread, unbounded), starving the tick
thread that takes `lifecycleLock` every `prepareTick`. Blocked tick:
SamplePlaybackEngine `setVoiceParam`→withLock (:1828); holder:
setTrackMix/setTrackSends lifecycleLock.withLock across audioGraph mutation,
run inline on main. Root fix in task #47 (don't hold lifecycleLock across engine
mutation). Not the offline pump (revert didn't fix this one).

Status: RESOLVED — lifecycleLock leaf-lock fix (#47)
