# Crash: removing an AU instrument on a drum part WHILE PLAYING (note-on into a detaching AU)

**Filed:** 2026-06-29 (owner hit it live; verifying the new-bugs build)
**Area:** AU instrument lifecycle teardown — `AudioInstrumentHost.disconnectCurrentInstrument`
  / `MainAudioGraph.detach` (`Sources/Audio/AudioInstrumentHost.swift`,
  `Sources/Audio/MainAudioGraph.swift`)
**Severity:** CRASH — SIGSEGV on the audio render thread
**Status:** OPEN

## Repro
Load an AU instrument on a drum-part track, start playback, then click the X to
remove the AU (return the part to `.none`) while the transport is running.

## Crash (evidence: `crash.ips`)
- `EXC_BAD_ACCESS (SIGSEGV)`, `KERN_INVALID_ADDRESS at 0x15c` (a null-ish pointer
  + small offset → freed/uninitialised AU voice state).
- Faulting thread 14 `com.apple.audio.IOThread.client`, **inside the third-party
  AU**:
  ```
  adsr::TimeStretchSampler::noteOn(int, int, float) + 160
  adsr::TimeStretchSampler::renderNextBlock(...)
  SampleManagerPluginProcessor::processBlock(...)
  JuceAU::Render(...) → AUBase::DoRender → AudioUnitRender → AVAudioEngine render
  ```
- No app thread was inside our teardown code at the crash instant — consistent
  with the detach having already run, then the render thread pulling a queued,
  sample-stamped **note-ON** into the now-freed AU.

## Diagnosis
This is a **teardown-while-rendering race**, NOT a regression from the
2026-06-29 UI/preset work:
- The removal path is `session.setEditedDestination(.none, …)` →
  `AudioInstrumentHost.disconnectCurrentInstrument()` →
  `stopAllNotes()` (sends note-OFFs) → `MainAudioGraph.detach()`
  (`disconnectNodeInput`/`Output` + `engine.detach`) on a RUNNING engine.
- `stopAllNotes()` only sends note-OFFs. A note-ON that was already scheduled
  (sample-stamped at a future frame) into the AU's own MIDI queue on a prior tick
  — before removal — is NOT cancellable via `scheduleMIDIEventBlock`. When the
  render reaches that frame, the AU starts a voice and dereferences sample state
  that the detach/dealloc is freeing → crash in the AU's `noteOn`.
- The host's existing D2/D4 guards (`auMutationLock`, `instrument?.auAudioUnit ===
  au`) correctly stop NEW scheduling onto a detached AU, but they do nothing about
  events ALREADY handed to the AU.

The 2026-06-29 changes to `AudioInstrumentHost` were confined to `loadPreset`
(an All-Notes-Off after `currentPreset =`) — a different path; they do not touch
disconnect/detach/note-scheduling.

## Candidate fix (needs real-AU verification — human-present tier)
Flush the AU's pending render state before detaching, in
`disconnectCurrentInstrument`, after the output is disconnected (engine no longer
pulls the node) and before `detach`:
- Disconnect the AU's **output first** so the engine stops pulling it, THEN
- call `instrument.auAudioUnit.reset()` to clear its render state + queued events
  (and/or an immediate **All-Sound-Off** CC 120 to force-release voices), THEN
- `detach`.
Optionally defer the actual `engine.detach` (leave the node attached-but-silenced)
until a safe point if `reset()` alone proves insufficient for this AU.

Cannot be acoustically/stability-verified offline (third-party AU + render-thread
timing) — confirm with the same real-AU session that owes the
`20260629-101847` A/B.

## Acceptance
- Removing an AU instrument mid-playback never crashes; the part returns to the
  `.none` sound-source chooser cleanly with no hung/late note into the dead AU.
