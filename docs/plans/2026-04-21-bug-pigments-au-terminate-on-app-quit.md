# Bug: Pigments AU plugin crashes during app quit (std::terminate in plugin destructors)

**Date reported:** 2026-04-21
**Status:** Open — fix plan written: `docs/plans/2026-04-21-fix-orderly-au-shutdown-on-app-quit.md`
**Severity:** Medium — cosmetic at quit time (user already chose to quit), no data loss. Still surfaces as a crash dialog.
**Reporter:** maxwilliams (Max)

## Symptom

When the user quits the app (`Cmd-Q` / `-[NSApplication terminate:]`) while an Arturia **Pigments** AU is loaded as an instrument destination, the process aborts with `SIGABRT` / `abort() called`. Crash is on the **main thread**. No data is at risk; the crash happens *after* `NSApplication.terminate` calls `exit()`, i.e. the app is already leaving.

Crash reports are typically saved to `~/Library/Logs/DiagnosticReports/`.

## Root cause (from crash report)

Thread 0 (main) stack at the abort:

```
__pthread_kill
pthread_kill
abort
abort_message
demangling_terminate_handler
_objc_terminate
std::__terminate
std::terminate
Pigments (libpigmentsProcessor.dylib)     +0x6BC4A4   ← plugin teardown raises / leaves unhandled
Pigments                                  +0x1B2AE0
__cxa_finalize_ranges                     libsystem_c.dylib
exit                                      libsystem_c.dylib
-[NSApplication terminate:]               AppKit
…
SequencerAIApp.$main()
```

The fault is inside `libpigmentsProcessor.dylib` / `Pigments.vst3`'s static/global C++ destructors, invoked by `__cxa_finalize_ranges` after `-[NSApplication terminate:]` calls `exit(0)`. No SequencerAI Swift frames are on the crashed stack.

### Why the plugin's destructors crash

Our app is SwiftUI-only and has no `NSApplicationDelegate`, so there is **no `applicationWillTerminate(_:)` hook**. `SequencerAIApp` is declared as:

```swift
@main
struct SequencerAIApp: App {
    @State private var engineController = EngineController(
        audioOutput: AudioInstrumentHost(),
        audioOutputFactory: { AudioInstrumentHost() }
    )
    // …
    var body: some Scene { DocumentGroup(newDocument: SeqAIDocument()) { … } … }
}
```

At quit, AppKit calls `terminate:` which calls `exit(0)` directly. Swift objects are *not* deinitialized in a deterministic order before `exit` runs — process exit goes straight to `__cxa_finalize_ranges`, at which point the Pigments plugin's static objects and hosted AU instances try to release resources that are already torn down. Pigments throws a C++ exception in that destructor path (likely because the hosting runtime, the audio engine, the hosted-view controller, or the AU's own background threads are in an undefined state) and the process terminates.

### Relevant hosting code

- `Sources/App/SequencerAIApp.swift` — `@main` SwiftUI entry point; no app-delegate adaptor, no `applicationWillTerminate` hook, no explicit shutdown of `engineController`.
- `Sources/Audio/AudioInstrumentHost.swift` — holds `private var instrument: AVAudioUnitMIDIInstrument?` which wraps the Pigments AU. The only place it sets `instrument = nil` is during instrument-switch, never at app exit.
- `Sources/Audio/AUWindowHost.swift` — singleton `AUWindowHost.shared` holds `windows: [WindowKey: WindowEntry]` with `NSWindow`s that host the AU's view controller. Has no `closeAll()` method; windows are only closed individually via `close(for:)` in response to UI actions.
- `Sources/Engine/EngineController.swift` — `stop()` exists and tears down per-track hosts (`hosts.forEach { $0.stop() }`) plus `sampleEngine.stop()`, but is only invoked by UI transport controls, not by app-quit.

## Reproduction

1. Launch the app.
2. Open a document. On any track, Add Destination → AU Instrument → pick **Arturia Pigments** (or another AU that retains background threads).
3. Open the AU window (Edit Plug-in Window) at least once so the hosted view controller is allocated. Close it.
4. Quit with `Cmd-Q`.
5. Expected: clean exit. Actual: crash dialog with `std::terminate` inside Pigments.

Reproducibility with non-Arturia AUs has not been verified; the bug may affect other AUs with similar teardown patterns.

## Reference: crash-report excerpts

- Crashed thread / queue: `Thread 0 :: Dispatch queue: com.apple.main-thread`.
- Signal: `EXC_CRASH (SIGABRT)`; `libsystem_c.dylib: abort() called`.
- Termination triggered by `-[NSApplication terminate:]` → `exit` → `__cxa_finalize_ranges`.
- Pigments frames dominate the abort stack; no frames from SequencerAI's dylib on the crashed thread.

Full crash text was pasted into the 2026-04-21 agent conversation; the diagnostic report also exists at `~/Library/Logs/DiagnosticReports/SequencerAI-*.ips`.

## Suggested fix directions (turned into a plan)

1. **Add an `NSApplicationDelegateAdaptor`** to `SequencerAIApp` so we own an `NSApplicationDelegate` with `applicationWillTerminate(_:)`. This is the only reliable pre-`exit` hook in an AppKit app.
2. **Teardown order in `applicationWillTerminate(_:)`:**
   - Close all hosted AU windows (`AUWindowHost.shared.closeAll()` — new method).
   - Stop the `EngineController` (cancels the TickClock, stops hosts, stops the sample engine, flushes MIDI).
   - Release all `AVAudioUnit` instances held by `AudioInstrumentHost` (set `instrument = nil`, deallocate background audio threads, etc.) via a new `shutdown()` method that `EngineController.stop()` can fan out to each host.
3. **Belt-and-braces:** before the app delegate returns from `applicationWillTerminate`, a brief run-loop spin (`RunLoop.current.run(until: …)`) gives AU plugins and their background threads a few hundred ms to drain. Keep the spin small (≤500 ms) so quit still feels instantaneous.
4. **Regression coverage:** instrument the shutdown path with `NSLog` entries so the sequence is visible in Console.app. An automated test isn't practical (requires a real AU host); a manual smoke sequence is documented in the plan.

## Not in scope for this report

- Replacing AVFoundation's AU hosting.
- Fixing Pigments' own destructors — we can't; it's third-party.
- Preventing the same issue for a `kill -9` / force-quit. Nothing can intervene there.
- A general-purpose `AUHost` lifecycle framework. Narrow fix only.

## Next step

Execute `docs/plans/2026-04-21-fix-orderly-au-shutdown-on-app-quit.md`.
