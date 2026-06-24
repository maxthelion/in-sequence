# Verify: send-FX amount change no longer hangs

**Bug:** `docs/bugs/20260623-135100-send-effect-amount-change-hangs-app` (#15).
**Status:** fix committed (now on `main`); needs **real-audio** confirmation.

## What was fixed
The hang was a synchronous layout storm: `EngineController` `@Observable`
properties (`currentDocumentModel` / `currentTrackMix`) were written on every
send-drag while `stateLock` was held. Fix: marked them `@ObservationIgnored`.

## Why a human
The repro is a live send-FX **amount drag while audio plays** — the deadlock
only manifests with the real audio graph running. CI / offline render can't
reproduce or disprove it.

## How to verify
1. Play a project with at least one track routed to a send (A or B) with an FX
   insert on the send bus.
2. Drag the send amount / send-FX wet control continuously while audio plays.
3. PASS = no beachball / no hang; audio stays live; control responds.
4. Bonus: also drag a track fader + the send simultaneously.
