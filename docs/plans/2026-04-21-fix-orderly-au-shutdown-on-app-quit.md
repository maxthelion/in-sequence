# Orderly AU Shutdown on App Quit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Arturia Pigments (and any other AU with C++ teardown state) from crashing the app at `Cmd-Q`. Install an `NSApplicationDelegateAdaptor` on `SequencerAIApp` so we can run explicit teardown inside `applicationWillTerminate(_:)` before AppKit calls `exit(0)`. The teardown closes all hosted AU windows, stops the `EngineController`, and releases every `AVAudioUnit` instance hosted by `AudioInstrumentHost`.

**Architecture:** Four additions and one wiring change. A new `NSApplicationDelegate` subclass (`SequencerAIAppDelegate`) holds a weak reference to the shared `EngineController`. It implements `applicationWillTerminate(_:)`. Inside: (1) call `AUWindowHost.shared.closeAll()` (new method) to close every plug-in UI window; (2) call `engineController.shutdown()` (new method) that fans out `AudioInstrumentHost.shutdown()` (new method) on every live track playback sink plus stops the sample engine; (3) spin the main run loop briefly (≤500 ms) so AU background threads can drain. `SequencerAIApp` adopts the delegate via `@NSApplicationDelegateAdaptor`.

**Tech Stack:** Swift 5.9+, AppKit (`NSApplicationDelegate`, `NSApplicationDelegateAdaptor`), AVFoundation, XCTest.

**Parent bug report:** `docs/plans/2026-04-21-bug-pigments-au-terminate-on-app-quit.md`.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Run `xcodegen generate` after creating any new files under `Sources/`.

**Status:** Not started. Tag `v0.0.23-orderly-au-shutdown` at completion.

**Depends on:** nothing on the critical path. Can execute against current `main` and land alongside other plans.

**Deliberately deferred:**

- Replacing AVFoundation's AU hosting with a custom sandbox process. Out of scope.
- Saving unsaved documents on terminate beyond SwiftUI's `DocumentGroup` defaults. Out of scope.
- Handling `kill -9` / force-quit gracefully. Impossible — nothing can intervene there.
- A general-purpose `AUHost` lifecycle framework. This plan only does the narrow fix.

---

## File Structure

```
Sources/App/
  SequencerAIApp.swift                         # MODIFIED — @NSApplicationDelegateAdaptor wiring
  SequencerAIAppDelegate.swift                 # NEW — owns applicationWillTerminate teardown

Sources/Audio/
  AUWindowHost.swift                           # MODIFIED — add closeAll()
  AudioInstrumentHost.swift                    # MODIFIED — add shutdown(), make disconnect + release explicit

Sources/Engine/
  EngineController.swift                       # MODIFIED — add shutdown() that fans out to hosts + sample engine

Tests/SequencerAITests/
  App/
    SequencerAIAppDelegateTests.swift          # NEW — verifies applicationWillTerminate invokes expected teardown in order
  Engine/
    EngineControllerShutdownTests.swift        # NEW — verifies shutdown() stops hosts, sampleEngine, and releases AUs
  Audio/
    AUWindowHostCloseAllTests.swift            # NEW — verifies closeAll() empties the windows dictionary
```

---

## Task 1: `AUWindowHost.closeAll()`

Adds a single method that closes every open AU plug-in window. Small, focused change.

**Files:**
- Modify: `Sources/Audio/AUWindowHost.swift`
- Test: `Tests/SequencerAITests/Audio/AUWindowHostCloseAllTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Audio/AUWindowHostCloseAllTests.swift`:

```swift
import AppKit
import XCTest
@testable import SequencerAI

/// These tests exercise AUWindowHost's bookkeeping without instantiating a real
/// Audio Unit view controller. We use a stub presenter that synchronously returns
/// an empty NSViewController; that is enough for `open(...)` to commit a windows
/// dictionary entry, which is what `closeAll()` must unwind.
@MainActor
final class AUWindowHostCloseAllTests: XCTestCase {
    func test_closeAll_empties_windows_dictionary() async throws {
        let host = AUWindowHost()
        let presenterA = StubPresenter()
        let presenterB = StubPresenter()
        let keyA = AUWindowHost.WindowKey.track(UUID())
        let keyB = AUWindowHost.WindowKey.track(UUID())

        host.open(for: keyA, presenter: presenterA, title: "A", stateWriteback: { _ in })
        host.open(for: keyB, presenter: presenterB, title: "B", stateWriteback: { _ in })

        // Flush the NSApp main run loop so AUWindowHost's async
        // `requestHostedViewController` completion fires.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(host.isOpen(for: keyA))
        XCTAssertTrue(host.isOpen(for: keyB))

        host.closeAll()

        XCTAssertFalse(host.isOpen(for: keyA))
        XCTAssertFalse(host.isOpen(for: keyB))
    }
}

@MainActor
private final class StubPresenter: AudioUnitWindowPresentable {
    func requestHostedViewController(_ completion: @escaping (NSViewController?) -> Void) {
        completion(NSViewController())
    }

    func captureHostedState() throws -> Data? { nil }
}
```

Note: `AUWindowHost` currently exposes `static let shared` but its initialiser is synthesised and accessible within the module for tests. If Swift complains because `AUWindowHost.init()` is implicitly `private` or `internal` but needs to be callable from tests, add an explicit `override init() { super.init() }` under the existing `static let shared` line — it's a one-line addition.

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/AUWindowHostCloseAllTests \
  2>&1 | tail -20
```

Expected: compile failure — `closeAll()` does not exist.

- [ ] **Step 3: Add `closeAll()`**

In `Sources/Audio/AUWindowHost.swift`, add this method alongside the existing `close(for:)`:

```swift
    func closeAll() {
        log("closeAll count=\(windows.count)")
        let entries = windows
        for (key, entry) in entries {
            writeBackState(for: key, entry: entry)
            entry.window.delegate = nil
            entry.window.close()
        }
        windows.removeAll(keepingCapacity: false)
    }
```

`writeBackState(for:entry:)` is the existing private helper; it persists any AU state blob before we drop the window. The ordering matters: persist-then-close ensures a user who had tweaked an AU just before quit still gets their changes saved.

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/AUWindowHostCloseAllTests \
  2>&1 | tail -15
```

Expected: test passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/Audio/AUWindowHost.swift Tests/SequencerAITests/Audio/AUWindowHostCloseAllTests.swift project.yml
git commit -m "feat(audio): AUWindowHost.closeAll() closes every hosted plug-in window"
```

---

## Task 2: `AudioInstrumentHost.shutdown()`

Gives every `AudioInstrumentHost` an explicit terminal teardown: stop the engine, disconnect + detach the hosted AU, release the instrument reference, and clear any cached state. Distinct from today's `stop()` (which only pauses playback).

**Files:**
- Modify: `Sources/Audio/AudioInstrumentHost.swift`

- [ ] **Step 1: Add `shutdown()` to the `TrackPlaybackSink` protocol**

At `Sources/Audio/AudioInstrumentHost.swift` top-of-file, update the protocol:

```swift
protocol TrackPlaybackSink: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var availableInstruments: [AudioInstrumentChoice] { get }
    var selectedInstrument: AudioInstrumentChoice { get }
    var currentAudioUnit: AVAudioUnit? { get }
    func prepareIfNeeded()
    func startIfNeeded()
    func stop()
    /// Terminal teardown. After this call the host is inert — no more `play`,
    /// `setMix`, or `selectInstrument`. Must drop every `AVAudioUnit` instance
    /// and stop the hosted engine. Called from the app-quit path.
    func shutdown()
    func setMix(_ mix: TrackMixSettings)
    func setDestination(_ destination: Destination)
    func selectInstrument(_ choice: AudioInstrumentChoice)
    func captureStateBlob() throws -> Data?
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int)
}
```

- [ ] **Step 2: Implement `shutdown()` on `AudioInstrumentHost`**

Add this method to `AudioInstrumentHost` in the same file, alongside `stop()`:

```swift
    func shutdown() {
        log("shutdown start")
        stop()

        performOnMain {
            if let instrument = self.instrument {
                self.log("shutdown detaching instrument=\(instrument)")
                if self.engine.isRunning {
                    self.engine.stop()
                }
                self.engine.disconnectNodeOutput(instrument)
                self.engine.detach(instrument)
                self.instrument = nil
                self.updateSnapshotInstrument(nil)
            } else if self.engine.isRunning {
                self.engine.stop()
            }

            self.snapshotAvailable = false
            self.pendingLoadGeneration = nil
        }
        log("shutdown complete")
    }
```

The sequence is deliberate:
1. Stop playback first (drains in-flight notes via the existing `stop()` path).
2. On the main thread, stop the hosted `AVAudioEngine`, disconnect the AU's output node, detach it from the engine, drop the Swift strong reference, and update the snapshot.
3. Clear cached state so any subsequent call short-circuits.

- [ ] **Step 3: Add a guard on other entry points so post-shutdown calls are no-ops**

In the existing `startIfNeeded()`, add at the top:

```swift
        guard instrument != nil || pendingLoadGeneration != nil else {
            log("startIfNeeded skipped — shutdown state")
            return
        }
```

This keeps a post-shutdown call (e.g. a late UI binding firing) from trying to reinstantiate the AU. Only add if the existing body doesn't already handle the nil-instrument / nil-pending case; verify against the actual method body before inserting. (Functionally harmless if duplicate — the guard is redundant with the rest of the logic but clarifies intent.)

- [ ] **Step 4: Build**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds. If any other type conforms to `TrackPlaybackSink` (grep `: TrackPlaybackSink` in `Sources/` and `Tests/`) and doesn't implement `shutdown()`, add a default empty body for those conformances, or synthesise one via a protocol extension only for non-production types. Prefer explicit implementations — silent defaults hide real teardown bugs.

If tests rely on a `TrackPlaybackSink` mock, add `func shutdown() { /* mark shutdown called */ }` to the mock and record the call if the test cares.

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Audio/AudioInstrumentHost.swift
git commit -m "feat(audio): AudioInstrumentHost.shutdown() releases AVAudioUnit at terminal teardown"
```

---

## Task 3: `EngineController.shutdown()`

Composes the terminal teardown: stops the clock, flushes MIDI, calls `shutdown()` on every live host, and stops the sample engine.

**Files:**
- Modify: `Sources/Engine/EngineController.swift`
- Test: `Tests/SequencerAITests/Engine/EngineControllerShutdownTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Engine/EngineControllerShutdownTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class EngineControllerShutdownTests: XCTestCase {
    func test_shutdown_stops_sample_engine() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)
        controller.shutdown()
        XCTAssertTrue(mock.calls.contains(.stop), "expected sampleEngine.stop() during shutdown")
    }

    func test_shutdown_is_idempotent() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)
        controller.shutdown()
        controller.shutdown()
        // Two calls must not crash. We don't assert the exact call count on
        // sampleEngine.stop() here because the second shutdown is a no-op
        // path that may or may not re-issue the call — what matters is that
        // the second call completes without error.
    }

    func test_shutdown_calls_host_shutdown_for_every_live_track_host() {
        let mock = MockSamplePlaybackSink()
        let recordingHostA = RecordingPlaybackSink(name: "A")
        let recordingHostB = RecordingPlaybackSink(name: "B")

        var pendingHosts = [recordingHostA, recordingHostB]
        let controller = EngineController(
            audioOutput: nil,
            audioOutputFactory: {
                pendingHosts.isEmpty ? RecordingPlaybackSink(name: "fallback") : pendingHosts.removeFirst()
            },
            sampleEngine: mock
        )

        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        project.appendTrack(trackType: .monoMelodic)
        controller.apply(documentModel: project)

        controller.shutdown()

        XCTAssertTrue(recordingHostA.shutdownCalled, "host A shutdown()")
        XCTAssertTrue(recordingHostB.shutdownCalled, "host B shutdown()")
    }
}

/// A minimal `TrackPlaybackSink` that records whether shutdown() was invoked.
/// Constructors / accessors return inert values; this double only validates the
/// lifecycle contract.
private final class RecordingPlaybackSink: TrackPlaybackSink {
    let name: String
    private(set) var shutdownCalled = false

    init(name: String) { self.name = name }

    var displayName: String { name }
    var isAvailable: Bool { true }
    var availableInstruments: [AudioInstrumentChoice] { [.builtInSynth] }
    var selectedInstrument: AudioInstrumentChoice { .builtInSynth }
    var currentAudioUnit: AVAudioUnit? { nil }
    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func shutdown() { shutdownCalled = true }
    func setMix(_ mix: TrackMixSettings) {}
    func setDestination(_ destination: Destination) {}
    func selectInstrument(_ choice: AudioInstrumentChoice) {}
    func captureStateBlob() throws -> Data? { nil }
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {}
}
```

If `MockSamplePlaybackSink` from the other plan (`fix-sample-playback-graph-mutation-on-tickclock`) has already landed, reuse that file instead of re-declaring. If it has not, create the minimal version needed: stub `start`/`stop`/`prepareTrack`/`play`/`setTrackMix`/`removeTrack`/`audition`/`stopAudition` with a `calls: [Call]` array. Calls recorded in order.

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerShutdownTests \
  2>&1 | tail -20
```

Expected: compile failure — `EngineController.shutdown()` does not exist.

- [ ] **Step 3: Implement `EngineController.shutdown()`**

In `Sources/Engine/EngineController.swift`, add this method below the existing `stop()` (around line 175):

```swift
    func shutdown() {
        flushAllPendingMIDINoteOffs(now: ProcessInfo.processInfo.systemUptime)
        clock.stop()
        let hosts = withStateLock { Array(audioOutputsByTrackID.values) }
        hosts.forEach { $0.shutdown() }
        isRunning = false
        lastNoteTriggerUptime = 0
        lastNoteTriggerCount = 0
        sampleEngine.stop()
        withStateLock {
            generatedEvaluationStatesByTrackID = [:]
            preparedTickIndex = nil
            audioOutputsByTrackID.removeAll(keepingCapacity: false)
        }
    }
```

This is `stop()` with three additions:
1. Invokes `shutdown()` on each host (not `stop()`) so the AU is released, not just paused.
2. Clears `audioOutputsByTrackID` so any late `apply(documentModel:)` doesn't try to reuse a released host.
3. Safe to call twice — the second call finds an empty `hosts` array, stops the already-stopped sample engine (sampleEngine `stop()` is guarded by `isStarted`), and clears already-empty dictionaries.

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerShutdownTests \
  2>&1 | tail -15
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Engine/EngineController.swift Tests/SequencerAITests/Engine/EngineControllerShutdownTests.swift
git commit -m "feat(engine): EngineController.shutdown() fans out to hosts + sampleEngine for terminal teardown"
```

---

## Task 4: `SequencerAIAppDelegate` — the `applicationWillTerminate` hook

Owns the app-quit teardown. A plain `NSObject` + `NSApplicationDelegate`. Adopted by `SequencerAIApp` via `@NSApplicationDelegateAdaptor`.

**Files:**
- Create: `Sources/App/SequencerAIAppDelegate.swift`
- Test: `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift`:

```swift
import AppKit
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerAIAppDelegateTests: XCTestCase {
    func test_applicationWillTerminate_invokes_teardown_in_expected_order() {
        var events: [String] = []
        let delegate = SequencerAIAppDelegate()
        delegate.closeAllWindows = { events.append("closeAll") }
        delegate.shutdownEngine = { events.append("shutdown") }
        delegate.drainRunLoop = { _ in events.append("drain") }

        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(events, ["closeAll", "shutdown", "drain"])
    }

    func test_applicationWillTerminate_is_idempotent() {
        var closeAllCallCount = 0
        var shutdownCallCount = 0
        let delegate = SequencerAIAppDelegate()
        delegate.closeAllWindows = { closeAllCallCount += 1 }
        delegate.shutdownEngine = { shutdownCallCount += 1 }
        delegate.drainRunLoop = { _ in }

        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(closeAllCallCount, 1, "closeAll should run exactly once")
        XCTAssertEqual(shutdownCallCount, 1, "shutdown should run exactly once")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/SequencerAIAppDelegateTests \
  2>&1 | tail -20
```

Expected: compile failure — `SequencerAIAppDelegate` does not exist.

- [ ] **Step 3: Implement the delegate**

Create `Sources/App/SequencerAIAppDelegate.swift`:

```swift
import AppKit
import Foundation

/// Owns the app's `applicationWillTerminate(_:)` hook so we can release hosted
/// Audio Unit instances before AppKit calls `exit(0)` — without this, some
/// third-party AUs (e.g. Arturia Pigments) crash during `__cxa_finalize_ranges`
/// while tearing down their C++ static destructors. See
/// `docs/plans/2026-04-21-bug-pigments-au-terminate-on-app-quit.md`.
@MainActor
final class SequencerAIAppDelegate: NSObject, NSApplicationDelegate {
    /// Injected by `SequencerAIApp` at construction. The adaptor is `@State`-owned,
    /// so the closures can retain references the delegate itself does not own.
    var closeAllWindows: () -> Void = { AUWindowHost.shared.closeAll() }
    var shutdownEngine: () -> Void = {}
    var drainRunLoop: (TimeInterval) -> Void = { interval in
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    private var hasTornDown = false

    func applicationWillTerminate(_ notification: Notification) {
        guard !hasTornDown else {
            NSLog("[SequencerAIAppDelegate] applicationWillTerminate skipped — already torn down")
            return
        }
        hasTornDown = true
        NSLog("[SequencerAIAppDelegate] applicationWillTerminate teardown begin")
        closeAllWindows()
        shutdownEngine()
        drainRunLoop(0.3)
        NSLog("[SequencerAIAppDelegate] applicationWillTerminate teardown end")
    }
}
```

The closure-based shape makes the delegate testable without an `EngineController` or `NSApp`. Production wiring in Task 5 supplies the real closures.

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/SequencerAIAppDelegateTests \
  2>&1 | tail -15
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/SequencerAIAppDelegate.swift Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift project.yml
git commit -m "feat(app): SequencerAIAppDelegate with applicationWillTerminate teardown + tests"
```

---

## Task 5: Wire the delegate into `SequencerAIApp`

**Files:**
- Modify: `Sources/App/SequencerAIApp.swift`

- [ ] **Step 1: Replace `SequencerAIApp` with the delegate-adopting version**

Replace the contents of `Sources/App/SequencerAIApp.swift` with:

```swift
import SwiftUI

@main
struct SequencerAIApp: App {
    @NSApplicationDelegateAdaptor(SequencerAIAppDelegate.self) private var appDelegate
    @State private var engineController: EngineController

    init() {
        do {
            let root = try AppSupportBootstrap.appSupportRoot()
            try AppSupportBootstrap.ensureLibraryStructure(root: root)
        } catch {
            NSLog("AppSupportBootstrap failed: \(error)")
        }

        do {
            _ = try SampleLibraryBootstrap.ensureLibraryInstalled()
        } catch {
            NSLog("[SequencerAIApp] sample library bootstrap failed: \(error)")
        }
        _ = AudioSampleLibrary.shared
        _ = MIDISession.shared

        let engineController = EngineController(
            audioOutput: AudioInstrumentHost(),
            audioOutputFactory: { AudioInstrumentHost() }
        )
        _engineController = State(wrappedValue: engineController)
    }

    var body: some Scene {
        DocumentGroup(newDocument: SeqAIDocument()) { file in
            ContentView(document: file.$document)
                .environment(engineController)
        }
        .defaultSize(width: 1500, height: 960)
        .onChange(of: engineControllerReference) { _, controller in
            appDelegate.shutdownEngine = { [weak controller] in
                controller?.shutdown()
            }
        }

        Settings {
            PreferencesView()
        }
    }

    private var engineControllerReference: ObjectIdentifier {
        ObjectIdentifier(engineController)
    }
}
```

The `@NSApplicationDelegateAdaptor` gives us an `NSApplicationDelegate` instance managed by SwiftUI. We then wire the delegate's `shutdownEngine` closure to call `engineController.shutdown()`. The `onChange(of: engineControllerReference)` modifier fires exactly once at initial render (and again only if the controller is swapped). The `[weak controller]` capture avoids a retain cycle if the delegate outlives the state (which it won't, practically, but the pattern is safer).

Note: if `EngineController` is a value type (struct), `@State` and `ObjectIdentifier` won't compose — but the current `EngineController` is a reference type (seen by usage `@State private var engineController = EngineController(...)` + `environment(engineController)`). If a future refactor makes it a value type, hold it inside a small `@MainActor final class EngineControllerBox` and adapt accordingly.

- [ ] **Step 2: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds. If `.onChange(of:)` requires a `Hashable & Equatable` value, the `ObjectIdentifier` wrapper satisfies both. If the macOS SwiftUI 6.x `.onChange` requires the two-argument form (`{ _, _ in }`), the example above already uses it.

- [ ] **Step 3: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/SequencerAIApp.swift
git commit -m "feat(app): adopt NSApplicationDelegateAdaptor to run AU shutdown at terminate"
```

---

## Task 6: Manual smoke + plan status + tag

**Files:** none beyond doc updates

- [ ] **Step 1: Build and open the app**

```bash
./scripts/open-latest-build.sh
```

- [ ] **Step 2: Reproduce the original scenario**

- Open a document. On any track, set destination to `AU Instrument → Arturia Pigments` (or whichever AU originally triggered the crash).
- Open the AU window (Edit Plug-in Window), tweak anything, close the window.
- Press `Cmd-Q`. Expected: the app exits cleanly. Previously: crash dialog with `std::terminate` in Pigments' destructor.
- In Console.app (filter by `SequencerAI`), verify the teardown log sequence:
  - `[AUWindowHost] closeAll count=1`
  - `[AudioInstrumentHost] shutdown start`
  - `[AudioInstrumentHost] shutdown detaching instrument=…`
  - `[AudioInstrumentHost] shutdown complete`
  - `[SequencerAIAppDelegate] applicationWillTerminate teardown end`

- [ ] **Step 3: Verify no regression for non-AU tracks**

- Open a document with only `.midi` and `.sample` tracks. `Cmd-Q`. Expected: clean exit, no crash, teardown log still shows the sequence above (minus AU-specific lines).

- [ ] **Step 4: Verify no regression for the non-quit path**

- Open a document, add an AU instrument, play for a few bars, stop transport, close the document (`Cmd-W`) without quitting the app. Expected: the window closes, the document is ready to save, and opening a new document still lets you load an AU instrument.

- [ ] **Step 5: Flip the bug-report status + mark this plan complete + tag**

Edit `docs/plans/2026-04-21-bug-pigments-au-terminate-on-app-quit.md`: replace its `**Status:** Open — fix plan written …` with:

```
**Status:** ✅ Fixed 2026-04-21 by `docs/plans/2026-04-21-fix-orderly-au-shutdown-on-app-quit.md`. Tag `v0.0.23-orderly-au-shutdown`.
```

Edit this plan: replace `**Status:** Not started.` with:

```
**Status:** ✅ Completed 2026-04-21. Tag `v0.0.23-orderly-au-shutdown`. Verified via focused unit tests, full suite, and manual AU-quit smoke.
```

Commit + tag:

```bash
git add docs/plans/2026-04-21-bug-pigments-au-terminate-on-app-quit.md docs/plans/2026-04-21-fix-orderly-au-shutdown-on-app-quit.md
git commit -m "docs(plan): mark orderly-au-shutdown fix completed"
git tag -a v0.0.23-orderly-au-shutdown -m "Orderly AU shutdown on Cmd-Q: delegate adaptor, closeAll + shutdown fan-out"
```

- [ ] **Step 6: Dispatch `wiki-maintainer` to refresh the audio hosting docs**

Brief:
- Diff range: `<previous-tag>..HEAD`.
- Plan: `docs/plans/2026-04-21-fix-orderly-au-shutdown-on-app-quit.md`.
- Task: document the app-quit teardown order (closeAll → engineController.shutdown → runloop drain), the `shutdown()` entry point on `TrackPlaybackSink`, and cross-link the bug report. Mention the requirement that any future `TrackPlaybackSink` conformance must release its `AVAudioUnit` inside `shutdown()`.
- Commit under `docs(wiki):` prefix.

---

## Self-Review

**Bug-report coverage (report → plan):**
- `NSApplicationDelegateAdaptor` + `applicationWillTerminate` — Task 4 + Task 5. ✓
- Close AU windows on terminate — Task 1 (`closeAll`) + Task 4 default closure. ✓
- Stop engine and release AU instances — Task 2 (`AudioInstrumentHost.shutdown`) + Task 3 (`EngineController.shutdown`) + Task 5 closure wiring. ✓
- Short run-loop spin for plugin background threads — Task 4 `drainRunLoop(0.3)`. ✓
- Regression log entries visible in Console.app — `NSLog` calls in `AUWindowHost.closeAll`, `AudioInstrumentHost.shutdown`, `SequencerAIAppDelegate.applicationWillTerminate`. ✓
- Manual smoke covering repro + the non-AU path + the non-quit path — Task 6. ✓

**Placeholder scan:** no TBDs. Every step has exact code or exact commands. The one conditional (bridging-header path equivalent) is a note about `AUWindowHost.init()` visibility; the in-step guidance is concrete. ✓

**Type consistency:**
- `TrackPlaybackSink.shutdown()` added in Task 2 is called by `EngineController.shutdown()` in Task 3; any mock double in Task 3's test must implement it — documented inline. ✓
- `AUWindowHost.closeAll()` signature in Task 1 is the same signature referenced by `SequencerAIAppDelegate.closeAllWindows` default in Task 4. ✓
- `EngineController.shutdown()` signature in Task 3 matches the call `controller?.shutdown()` wired in Task 5. ✓
- `@NSApplicationDelegateAdaptor(SequencerAIAppDelegate.self)` in Task 5 requires the delegate to be `NSObject & NSApplicationDelegate`, which Task 4 satisfies (`final class SequencerAIAppDelegate: NSObject, NSApplicationDelegate`). ✓

**Risks:**
- **AU background threads taking longer than 300 ms to drain:** the spin is a heuristic. If a future AU needs more time, raise `drainRunLoop` to 500 ms. Keep the cap small so `Cmd-Q` stays responsive.
- **`@NSApplicationDelegateAdaptor` initialisation order vs `@State engineController`:** SwiftUI constructs `@State` first, then adaptors. The wiring in Task 5 uses `.onChange(of:)` so the closure is installed after the body is composed — not in `init()`. Verify during the manual smoke that Console logs show the expected order; if the `onChange` fires after the engine is torn down (unlikely), move the wiring to a `.task` modifier instead.
- **Documents with unsaved changes:** SwiftUI's `DocumentGroup` handles "Save changes?" dialog before `terminate:` is called. Our delegate runs inside `terminate:`, after that dialog. So we never interfere with save prompts.
- **Force quit / `kill -9`:** nothing to do; the process is killed without running `applicationWillTerminate`. Stated in the bug report as out of scope.
- **Multi-document scenarios:** all documents share the single `engineController` (constructed in `SequencerAIApp.init()`), so one `shutdown()` covers them all. `AUWindowHost.shared.closeAll()` is also global. No per-document teardown needed.
