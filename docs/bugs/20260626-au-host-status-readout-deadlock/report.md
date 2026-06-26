# Bug: app hangs (AB-BA deadlock) when the command channel polls AU output state during AU setup

**Filed:** 2026-06-26 — found during the human real-audio verification pass (#42).
**Severity:** HANG (deadlock) — froze the app on launch with a real AU + the
command channel enabled.
**Evidence:** `au-hang.sample.txt` (a `sample` of the live frozen process).

## What happened
Launched with a real AU (Arturia Analog Lab V) fixture + the visual command
channel. The app froze: playhead stuck, `transport=play` never applied, UI showed
"Audio instrument unavailable" (the AU never finished connecting).

## Root cause — AB-BA deadlock
- **AU host queue** runs `AudioInstrumentHost.connectLoadedInstrument` → `performOnMain`
  = `DispatchQueue.main.sync` (AU setup hops to main). Arturia is slow to set up
  (async preset loader + JUCE threads), so it sits in this sync.
- **Main thread**, in `ContentView.body`'s command-channel status writer
  (`VisualScenarioCommandRunner.writeStatus` → `routingStressStatusLines` →
  `EngineController.trackAppliedOutputBusIDForTesting` →
  `AudioInstrumentHost.currentOutputBusIDForTesting`), did a `queue.sync` onto the
  AU host queue.
- main waits for the host queue; the host queue waits for main → frozen.

The P1 review had flagged `currentOutputBusIDForTesting`'s `queue.sync` as
"test-only," but it is reachable from the status writer **on main**, which runs
whenever the command channel is active — exactly the rig/verification setup. The
rig never hit it because it is sample-only (no AU, so the host queue never runs
`connectLoadedInstrument`).

## Fix
`currentOutputBusIDForTesting` / `currentOutputGainForTesting` now read an output
routing **snapshot** under the leaf `snapshotLock` (published on every
`outputMixer`/`currentOutputBusID` change) instead of hopping the host queue —
the same pattern the D3 deadlock fix already uses for `snapshotAudioUnit`. No
main→host-queue `sync`, so the AB-BA cycle cannot form.

## Scope
Diagnostic/command-channel path only — in normal app use (no command channel)
nothing on main syncs to the host queue, so production was not affected. But it
broke every AU-present verification/QA run that used the command channel, and it
masked the AU itself (connect never completed → "unavailable" → silent).

## Acceptance
Launch a real-AU fixture with the command channel: app stays responsive, status
file keeps updating, transport plays, the AU completes its connection. (Verified
live: post-fix the app is responsive and the status writer updates.)
