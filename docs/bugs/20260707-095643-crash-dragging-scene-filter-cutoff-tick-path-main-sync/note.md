Crash dragging scene filter cutoff triggers tick-path main-sync assertion

Status: OPEN
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
