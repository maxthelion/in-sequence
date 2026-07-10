Crash dragging scene filter cutoff triggers tick-path main-sync assertion

Status: RESOLVED
Filed: 2026-07-07
Source: pasted macOS crash report

## Summary

SequencerAI crashed while editing a Scene FX filter cutoff knob. The app
terminated with `EXC_BREAKPOINT (SIGTRAP)` on the
`ai.sequencer.SequencerAI.TickClock` queue after `TickPathMainSyncGuard`
reported a forbidden sync-to-main path from live tick processing.

Raw report: `crash-report.txt`

## Observed Crash

- Process: `SequencerAI`
- Date/time: `2026-07-07 09:55:38 +0100`
- macOS: `15.3.2 (24D81)`
- Crashed thread: `Thread 18`, dispatch queue `ai.sequencer.SequencerAI.TickClock`
- Exception: `EXC_BREAKPOINT (SIGTRAP)`
- User action indicated by main-thread stack: dragging a `StudioRotaryKnob` in
  `ScenesWorkspaceView.filterEditor`, updating
  `ScenesWorkspaceView.filterCutoffBinding`.

## Key Stack Evidence

Crash thread:

```text
TickPathMainSyncGuard.report(_:)
TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath(_:)
SamplePlaybackEngine.performOnMain<A>(_:)
SamplePlaybackEngine.prepareTrack(trackID:)
SamplePlaybackEngine.setTrackMix(trackID:level:pan:)
EngineController.refreshEffectiveMixerState(for:)
EngineController.refreshSceneMembershipGains(for:)
EngineController.applyMasterBusIfChanged(_:)
EngineController.applyPhraseSceneState(phraseID:snapshot:)
EngineController.playbackPhraseForPrepare(upcomingStep:snapshot:)
EngineController.scheduleActiveNoteRepeatsForCurrentTick(tickIndex:now:)
EngineController.processTickMarked(tickIndex:now:)
```

Main thread at the same time was applying a Scene FX parameter edit and probing
bus readiness/readout:

```text
ScenesWorkspaceView.filterCutoffBinding(insertID:settings:)
SequencerDocumentSession.updateMasterBusInsert(_:in:edit:)
EngineController.apply(masterBus:)
EngineController.refreshSceneMembershipGains(for:)
SamplePlaybackEngine.setTrackSends(trackID:sendA:sendB:)
SamplePlaybackEngine.prepareTrack(trackID:)
SamplePlaybackEngine.publishBusTrackFastPathIfConnected(trackID:busID:pool:)
SamplePlaybackEngine.isBusVoicePoolReadyForPlayback(pool:busID:)
MainAudioGraph.mixerBusReadoutForTesting(busID:)
MixerBusHost.readout()
AVAudioMixerNode.outputVolume
```

## Working Hypothesis

Dragging a Scene FX parameter while playback is running causes master-bus or
scene-membership refresh work to intersect with the tick/lookahead path. The
tick path enters `refreshSceneMembershipGains` / `refreshEffectiveMixerState`
and calls into `SamplePlaybackEngine.setTrackMix`, which attempts
`performOnMain`. The debug guard correctly traps because tick-path code must
not synchronously hop to main.

This is closely related to the previous master-output insert crash, but the
trigger path is different: a live Scene FX parameter edit, not adding a new
master output insert.

## Repro Notes

Likely repro from the stack:

1. Run a debug build with playback active.
2. Open Scenes and an FX/filter editor for a scene/master bus insert.
3. Drag the filter cutoff rotary.
4. The app traps on the TickClock queue while mix/scene membership refresh is
   happening.

The report also shows Buchla Easel V / JUCE audio threads, but the trapped
condition is the app's own tick-path main-sync guard.

## Investigation Notes

Treat this as an audio hard-rule issue. The fix should not suppress the
assertion; it should prevent tick/lookahead work from invoking main-thread
graph, mixer-bus, or sample-playback preparation paths. In particular, inspect
the interaction between scene FX parameter edits, master-bus scoped runtime
updates, scene-membership gain refresh, bus voice-pool readiness checks, and
sample playback track preparation.

Relevant files from the stack:

- `Sources/UI/ScenesWorkspaceView.swift`
- `Sources/Engine/EngineController.swift`
- `Sources/Engine/EngineControllerMixSync.swift`
- `Sources/Audio/SamplePlaybackEngine.swift`
- `Sources/Audio/MainAudioGraph.swift`
- `Sources/Audio/MixerBusHost.swift`
- `Sources/App/SequencerDocumentSession.swift`

## ROOT CAUSE + FIX

This shared the same underlying failure mode as the master-output insert crash.
Dragging a scene FX parameter legitimately applies master-bus changes on the
main/control side, but live phrase-scene playback was also applying master-bus
state from the tick/lookahead path. When those paths overlapped, the tick path
could enter scene-membership and sample-mixer refresh code that prepares sample
tracks and synchronously consults main-thread graph state.

The fix makes phrase-scene A/B selection a live performance overlay rather than
a document/master-bus apply. The tick path now records only the desired
selection and publishes an async overlay update. Scene-membership gain refresh
and `MasterBusHost` overlay resolution happen on the main/control side, so
Scene FX edits can continue to use the document apply path without tick-path
graph/sample-prep work.

Verification:

- `EngineControllerPhraseNavigationTests.test_phraseSceneBoundaryDoesNotSynchronouslyHopToMainFromTickPath`
- `EngineControllerPhraseNavigationTests`
- `TickPathMainIsolationTests`
- `SequencerDocumentSessionMasterBusTests`
- `MasterBusHostTests`
- `scripts/diagnostics/realtime-path-lint.sh`
- `scripts/diagnostics/runtime-ownership-lint.sh`

Status: RESOLVED 044f728c
