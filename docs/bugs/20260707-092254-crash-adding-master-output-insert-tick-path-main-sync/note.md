Crash adding master output insert triggers tick-path main-sync assertion

Status: RESOLVED
Filed: 2026-07-07
Source: pasted macOS crash report

## Summary

SequencerAI crashed while adding/loading a master output insert. The app terminated with `EXC_BREAKPOINT (SIGTRAP)` on the `ai.sequencer.SequencerAI.TickClock` queue after `TickPathMainSyncGuard` reported a forbidden sync-to-main path from the live tick path.

Raw report: `crash-report.txt`

## Observed Crash

- Process: `SequencerAI`
- Date/time: `2026-07-07 09:21:14 +0100`
- macOS: `15.3.2 (24D81)`
- Crashed thread: `Thread 9`, dispatch queue `ai.sequencer.SequencerAI.TickClock`
- Exception: `EXC_BREAKPOINT (SIGTRAP)`
- User action indicated by main-thread stack: clicking Add FX in `MasterOutputColumnView.addFXSheet`, then `SequencerDocumentSession.addMasterOutputInsert(_:)`

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

Main thread at the same time was rebuilding/loading the master output AU chain:

```text
MasterOutputColumnView.addFXSheet
SequencerDocumentSession.addMasterOutputInsert(_:)
EngineController.apply(masterBus:)
MasterBusHost.apply(_:)
MasterBusHost.rebuildAudioGraph()
MasterBusHost.startLoadingAUEffect(insertID:componentID:stateBlob:)
MainAudioGraph.installMasterChains(...)
MainAudioGraph.installChannelMeterTapsIfNeeded()
AVAudioNode.installTapOnBus(...)
```

## Working Hypothesis

Adding a master output insert while the transport/lookahead tick path is active causes master-bus or scene-membership refresh work to run from the tick queue. That refresh calls into `SamplePlaybackEngine.setTrackMix(...)`, which attempts `performOnMain(...)`; the debug guard correctly traps because tick-path code must not synchronously hop to main.

This may be a concurrency/ownership bug between:

- master-bus runtime updates,
- phrase-scene membership gain refresh,
- sample playback track preparation,
- meter tap installation / master graph rebuild,
- and the live tick/lookahead path.

## Repro Notes

Confirmed user repro:

1. Run SequencerAI debug build.
2. Start playback.
3. Open the master output Add FX sheet.
4. Add an FX insert to the master while playback is running.
5. App traps on the TickClock queue during/after master graph rebuild.

The crash report also shows `Jun-6 V` plugin threads, so that may have been the selected AU, but the core repro is master-FX insertion during playback.

## Investigation Notes

This should be treated as an audio hard-rule issue: the tick path must not trigger main-thread graph work. A fix should avoid masking the assertion and instead move the master-bus/scene/mix refresh out of the tick path or make the tick-path portion consume precomputed, thread-safe state only.

Relevant files from the stack:

- `Sources/Engine/EngineController.swift`
- `Sources/Engine/EngineControllerMixSync.swift`
- `Sources/Audio/SamplePlaybackEngine.swift`
- `Sources/Audio/MasterBusHost.swift`
- `Sources/Audio/MainAudioGraph.swift`
- `Sources/UI/Mixer/MasterOutputColumnView.swift`

## ROOT CAUSE + FIX

The crash was caused by phrase-scene playback applying a full master-bus state
from the live tick/lookahead path. That document-style apply refreshed scene
membership and sample mixer state, which can prepare sample tracks and
synchronously consult main-thread audio graph state. The
`TickPathMainSyncGuard` trap was correct: the tick path had reached a
main-bound graph/sample-prep path.

The fix moves phrase-scene A/B selection out of authored `MasterBusState` and
into a live `MasterBusPerformanceOverlayState.abSelectionOverride`. Tick
processing now only records the desired phrase-scene selection under the state
lock and publishes an async control/main update. The main/control side installs
the overlay, refreshes scene membership gains, and lets `MasterBusHost` resolve
the live state without rewriting the persisted master bus.

Verification:

- `EngineControllerPhraseNavigationTests.test_phraseSceneBoundaryDoesNotSynchronouslyHopToMainFromTickPath`
- `EngineControllerPhraseNavigationTests`
- `TickPathMainIsolationTests`
- `SequencerDocumentSessionMasterBusTests`
- `MasterBusHostTests`
- `scripts/diagnostics/realtime-path-lint.sh`
- `scripts/diagnostics/runtime-ownership-lint.sh`

Status: RESOLVED 044f728c
