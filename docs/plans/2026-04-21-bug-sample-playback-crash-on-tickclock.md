# Bug: Sample playback crash on TickClock after adding a drum kit

**Date reported:** 2026-04-21
**Status:** ✅ Fixed 2026-04-21 by `docs/plans/2026-04-21-fix-sample-playback-graph-mutation-on-tickclock.md`. Tag `v0.0.22-fix-sample-playback-graph-mutation`.
**Severity:** High — crash aborts the app, no user recovery
**Reporter:** maxwilliams (Max)

## Symptom

App aborts with `SIGABRT` / "abort() called" shortly after the user added a drum track. Crash is in the `ai.sequencer.SequencerAI.TickClock` dispatch queue. Thread 20 is `std::terminate` → `abort_message` via an unhandled C++/Objective-C exception.

## Root cause (from crash report `lastExceptionBacktrace`)

An NSException was raised from `AVAudioPlayerNode.play` and propagated out of the TickClock queue — no C++ handler caught it, so `std::terminate` was invoked.

The exception's call site (innermost to outermost, from `lastExceptionBacktrace`):

```
AVAudioPlayerNodeImpl::StartImpl  (AVFAudio — NSException raised here)
AVAudioNodeImplBase::Start
-[AVAudioPlayerNode play]
SamplePlaybackEngine.play(sampleURL:settings:trackID:at:)   Sources/Audio/SamplePlaybackEngine.swift:91
EngineController.dispatchTick()                              Sources/Engine/EngineController.swift:461
EngineController.processTick(tickIndex:now:)                 Sources/Engine/EngineController.swift:308
closure #3 in EngineController.start()                       Sources/Engine/EngineController.swift:148
closure #1 in closure #1 in TickClock.start(onTick:)         Sources/Engine/TickClock.swift:61
```

The crash line (`Sources/Audio/SamplePlaybackEngine.swift:91`) is the `voice.play()` call inside `SamplePlaybackEngine.play(sampleURL:settings:trackID:at:)`:

```swift
voice.volume = linearGain(dB: settings.gain)
voice.scheduleFile(file, at: when, completionHandler: nil)
voice.play()                                         // <-- line 91, NSException thrown here
```

## Why this probably fires right after adding a drum kit

Adding a drum kit causes `Project.addDrumKit(_:)` to create new drum tracks with `.sample(sampleID:, settings:)` destinations. On the next tick, `EngineController.dispatchTick` sees a `.sampleTrigger` event for a brand-new `trackID` and calls `sampleEngine.play(...)`. Inside `SamplePlaybackEngine.play`:

1. `trackMixer(for: trackID)` does **not** find an existing mixer and lazily creates one, calling `engine.attach(mixer)` and `engine.connect(mixer, to: engine.mainMixerNode, format: nil)` (`SamplePlaybackEngine.swift:135–140`).
2. Because this is the first time this voice has played for this new track, the code also calls `engine.disconnectNodeOutput(voice)` followed by `engine.connect(voice, to: mixer, format: nil)` (lines 84–85).
3. `voice.scheduleFile(...)` is called.
4. `voice.play()` is called — this throws.

All four steps run on the `TickClock` dispatch queue. `AVAudioEngine` graph mutation while the engine is running is supported on modern macOS, but the combination of "attach + connect + disconnect + connect + scheduleFile + play" in a single tick — potentially racing against `EngineController.apply(documentModel:)` on the main thread (which also writes destinations and mixes via `SamplePlaybackEngine.setTrackMix(...)`) — is the plausible trigger. A common `AVAudioPlayerNode.play` exception reason in this pattern is:

- `required condition is false: _outputFormat != nil` — the just-reconnected node did not propagate its output format before `scheduleFile` ran, or
- `required condition is false: _engine->IsRunning()` — the engine paused momentarily during graph mutation.

Either way, the exception propagates out of the `TickClock` dispatch queue because the `closure #3 in EngineController.start()` path has no `do { try … } catch`, no `@try`/`@catch`, and no process-level NSException handler.

## Reproduction (suspected, not yet isolated)

1. Launch the app fresh.
2. Wait until the engine is running (the tick clock is live).
3. On the Tracks page, choose `Add Drum Kit → 808 Kit` (or any preset). Adds four `.sample(...)` drum tracks.
4. Shortly after — on the next tick that schedules a sample trigger for one of the new tracks — the app aborts.

Not yet reproduced in isolation; crash report is the only artifact. Add a repro test before fixing.

## Reference: crash-report excerpts

- Crashed thread / queue: `Thread 20 :: Dispatch queue: ai.sequencer.SequencerAI.TickClock`.
- Signal: `EXC_CRASH (SIGABRT)` — `libsystem_c.dylib: abort() called`.
- Thread 20 stack top:
  - `__pthread_kill` → `pthread_kill` → `abort` → `abort_message` → `demangling_terminate_handler` → `_objc_terminate` → `std::__terminate` → `_dispatch_client_callout` → `_dispatch_continuation_pop` → `_dispatch_source_latch_and_call` → `_dispatch_source_invoke`.
- `lastExceptionBacktrace` (the actual NSException path) as quoted above.
- Main thread (`Thread 0`) was in the middle of a SwiftUI layout pass — `SamplerDestinationWidget.waveform` → `AudioFileRef.resolve` → `URL.appendingPathComponent`. This is likely coincidence (the main-thread stack is captured at the moment of abort), but if repro shows the modal or widget on-screen at crash time, the main thread may also be mutating sample-library state while the audio tick is mutating the engine graph.
- `Thread 19` (`AudioInstrumentHost`) was blocked in `performOnMain` waiting for the main thread — corroborates that the app was busy synchronously crossing thread boundaries at the moment of the crash.

Full report is on the user's machine (`~/Library/Logs/DiagnosticReports/` or pasted into the conversation of 2026-04-21).

## Suggested fix directions (not yet scoped into a plan)

In priority order:

1. **Wrap `voice.play()` in an Objective-C `@try/@catch`** at `SamplePlaybackEngine.play` call site (requires a thin Obj-C or `NSExceptionWrapper` helper, since Swift can't catch Obj-C exceptions directly). Failing gracefully — log the reason, skip the trigger, don't terminate — is the immediate defensive fix.
2. **Pre-attach/connect per-track mixers** when `apply(documentModel:)` processes a new `.sample` destination on the main thread, before any tick dispatches a trigger for that `trackID`. The `trackMixer(for:)` lazy path on TickClock then becomes a pure lookup (no engine mutation).
3. **Pre-connect main voices** to a neutral sink at engine start, rather than deferring connection until first-play. The disconnect-then-reconnect pattern on every track switch is a smaller fault surface if voices always have a valid output format.
4. **Serialize engine graph mutations** on a dedicated `audioEngineQueue`. `attach`, `detach`, `connect`, `disconnectNodeOutput` should never race between TickClock and main.
5. **Add a regression test** that creates a `Project`, adds a drum kit, runs a few TickClock iterations against a fake audio sink, and asserts no exception. This catches the regression even without AVFoundation on CI (use a mock `SamplePlaybackSink`).

## Not in scope for this report

- Wider audit of `AVAudioEngine` thread-safety in the codebase.
- Changing the `SamplePlaybackSink` protocol or the tick scheduling cadence.
- UI changes.

## Next step

Decide: immediate defensive patch (direction 1 + test) or full restructure (directions 2–4). Create a plan once scoped.
