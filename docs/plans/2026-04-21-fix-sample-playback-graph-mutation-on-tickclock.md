# Fix Sample Playback Crash: Move Engine Graph Mutation Off TickClock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `SamplePlaybackEngine.play(...)` from crashing the app by eliminating `AVAudioEngine` graph mutation (`attach`, `connect`, `disconnectNodeOutput`) on the `TickClock` dispatch queue. All graph mutation moves to `SamplePlaybackEngine.prepareTrack(_:)`, called from `EngineController`'s main-thread `apply(documentModel:)` path. `play(...)` becomes a pure reader of the already-built graph.

**Architecture:** Per-track dedicated voice pool. At `prepareTrack(trackID:)` time (main), we attach a mixer for that track, attach a fixed number (4) of `AVAudioPlayerNode`s, and connect each voice statically to the mixer. `play(...)` on `TickClock` picks the next voice in that track's pool, calls `scheduleFile` + `play` — no engine graph mutation. `removeTrack(trackID:)` (already main-thread) tears down the pool. A small Obj-C shim wraps `voice.play()` in `@try/@catch` as a belt-and-braces safety net so any future regression logs instead of aborts.

**Tech Stack:** Swift 5.9+, AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioMixerNode`), XCTest, a tiny Obj-C++ file for NSException catching.

**Parent bug report:** `docs/plans/2026-04-21-bug-sample-playback-crash-on-tickclock.md`.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. After creating new files, run `xcodegen generate` before building or testing.

**Status:** Not started. Tag `v0.0.22-fix-sample-playback-graph-mutation` at completion.

**Depends on:** nothing on the critical path. Can execute against current `main` and land in parallel with other plans.

**Deliberately deferred:**

- Replacing the global `SamplePlaybackEngine` with a per-track engine instance. Out of scope.
- Reworking the audio-engine start / stop lifecycle. Out of scope.
- Dynamic polyphony scaling. Out of scope.
- Replacing `AVAudioPlayerNode` with an AUAudioUnit-based sampler. Out of scope.

---

## File Structure

```
Sources/Audio/
  SamplePlaybackEngine.swift                     # MODIFIED — per-track voice pool, prepareTrack(_:), play() no-mutate
  NSExceptionCatch.swift                         # NEW — Swift wrapper around a tiny Obj-C shim
  NSExceptionCatch.h                             # NEW — Obj-C header (umbrella-exposed via bridging header / module map)
  NSExceptionCatch.m                             # NEW — Obj-C implementation that wraps a block in @try/@catch

Sources/Engine/
  EngineController.swift                         # MODIFIED — syncSampleMixers calls prepareTrack(_:) before setTrackMix

Tests/SequencerAITests/
  Audio/
    SamplePlaybackEngineTests.swift              # NEW — pure-Swift tests that do NOT start the AVAudioEngine; verify allocation & bookkeeping
  Engine/
    EngineControllerSamplePrepareTests.swift     # NEW — mock SamplePlaybackSink; verify apply() calls prepareTrack before setTrackMix; verify no play() call until prepared
    MockSamplePlaybackSink.swift                 # NEW — test double capturing calls in order
```

**project.yml note:** Run `xcodegen generate` after creating the new files so they are picked up by the Xcode target.

---

## Task 1: `NSExceptionCatch` — a thin Obj-C `@try/@catch` wrapper

A tiny Obj-C shim. Swift can't catch Objective-C `NSException` directly. We need this so that future regressions in any AVFoundation call surface as a log entry + nil return instead of a process-level `abort()`.

**Files:**
- Create: `Sources/Audio/NSExceptionCatch.h`
- Create: `Sources/Audio/NSExceptionCatch.m`
- Create: `Sources/Audio/NSExceptionCatch.swift`

- [ ] **Step 1: Create the Obj-C header**

Write `Sources/Audio/NSExceptionCatch.h`:

```objective-c
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Invokes `block`; if it raises an NSException, captures it and returns it to
/// the caller. Returns nil if the block completed without raising.
NSException *_Nullable SeqAITryBlock(void (^block)(void));

NS_ASSUME_NONNULL_END
```

- [ ] **Step 2: Create the Obj-C implementation**

Write `Sources/Audio/NSExceptionCatch.m`:

```objective-c
#import "NSExceptionCatch.h"

NSException *_Nullable SeqAITryBlock(void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
```

- [ ] **Step 3: Create the Swift wrapper**

Write `Sources/Audio/NSExceptionCatch.swift`:

```swift
import Foundation

/// Runs `body` inside an Obj-C `@try`/`@catch`. Returns `nil` if `body` returned
/// normally, or the caught `NSException` otherwise. Swift cannot catch Obj-C
/// exceptions directly; this is the bridge.
func trySwiftBlockCatchingNSException(_ body: () -> Void) -> NSException? {
    var captured: NSException?
    captured = SeqAITryBlock {
        body()
    }
    return captured
}
```

- [ ] **Step 4: Expose the Obj-C header to Swift**

The project already uses `xcodegen`. Ensure `project.yml` picks up the new Obj-C files. In `project.yml`, locate the main app target's `sources:` array. The Obj-C header will be compiled automatically into the module if the module map is set up — but `xcodegen generate` may need a bridging header entry. Open `project.yml` and check the `settings:` block for the `SWIFT_OBJC_BRIDGING_HEADER` key; if absent, add:

```yaml
      SWIFT_OBJC_BRIDGING_HEADER: Sources/Audio/NSExceptionCatch.h
```

If `SWIFT_OBJC_BRIDGING_HEADER` already exists and points elsewhere, edit that existing bridging header to `#import "NSExceptionCatch.h"`.

- [ ] **Step 5: Build**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: build succeeds. If the bridging header is missing or the path is wrong, Swift will fail to resolve `SeqAITryBlock`. Fix the `project.yml` `SWIFT_OBJC_BRIDGING_HEADER` key and regenerate.

- [ ] **Step 6: Commit**

```bash
git add Sources/Audio/NSExceptionCatch.h Sources/Audio/NSExceptionCatch.m Sources/Audio/NSExceptionCatch.swift project.yml
git commit -m "feat(audio): NSExceptionCatch shim for trapping AVFoundation NSException"
```

---

## Task 2: `MockSamplePlaybackSink` — test double

A simple in-memory double that records every call in order. Needed by Task 3 to assert the `prepareTrack` → `setTrackMix` → `play` ordering invariants without an AVAudioEngine.

**Files:**
- Create: `Tests/SequencerAITests/Engine/MockSamplePlaybackSink.swift`

- [ ] **Step 1: Create the mock**

Write `Tests/SequencerAITests/Engine/MockSamplePlaybackSink.swift`:

```swift
import Foundation
@testable import SequencerAI

final class MockSamplePlaybackSink: SamplePlaybackSink {
    enum Call: Equatable {
        case start
        case stop
        case prepareTrack(trackID: UUID)
        case setTrackMix(trackID: UUID, level: Double, pan: Double)
        case removeTrack(trackID: UUID)
        case play(trackID: UUID, sampleURL: URL)
        case audition(sampleURL: URL)
        case stopAudition
    }

    private(set) var calls: [Call] = []
    private let lock = NSLock()

    func start() throws {
        lock.lock(); defer { lock.unlock() }
        calls.append(.start)
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        calls.append(.stop)
    }

    func prepareTrack(trackID: UUID) {
        lock.lock(); defer { lock.unlock() }
        calls.append(.prepareTrack(trackID: trackID))
    }

    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
        lock.lock(); defer { lock.unlock() }
        calls.append(.play(trackID: trackID, sampleURL: sampleURL))
        return nil
    }

    func setTrackMix(trackID: UUID, level: Double, pan: Double) {
        lock.lock(); defer { lock.unlock() }
        calls.append(.setTrackMix(trackID: trackID, level: level, pan: pan))
    }

    func removeTrack(trackID: UUID) {
        lock.lock(); defer { lock.unlock() }
        calls.append(.removeTrack(trackID: trackID))
    }

    func audition(sampleURL: URL) {
        lock.lock(); defer { lock.unlock() }
        calls.append(.audition(sampleURL: sampleURL))
    }

    func stopAudition() {
        lock.lock(); defer { lock.unlock() }
        calls.append(.stopAudition)
    }
}
```

If the test file does not have access to `AVAudioTime`, add `import AVFoundation` at the top.

- [ ] **Step 2: Build (tests target will fail because `prepareTrack` is not on the protocol yet)**

This is deliberate — Task 3 adds `prepareTrack` to `SamplePlaybackSink`, which unblocks the mock. Do not try to build the test target yet; move on.

- [ ] **Step 3: Commit**

```bash
git add Tests/SequencerAITests/Engine/MockSamplePlaybackSink.swift project.yml
git commit -m "test(engine): MockSamplePlaybackSink captures call order for engine controller tests"
```

---

## Task 3: Add `prepareTrack(trackID:)` to `SamplePlaybackSink` protocol and `SamplePlaybackEngine`

Lifts mixer + voice pool allocation out of the tick path. After this step, `SamplePlaybackEngine.play(...)` still works the same way it did before — the refactor is done in Task 4.

**Files:**
- Modify: `Sources/Audio/SamplePlaybackEngine.swift`
- Test: `Tests/SequencerAITests/Audio/SamplePlaybackEngineTests.swift`

- [ ] **Step 1: Write a failing test for the new protocol method**

Create `Tests/SequencerAITests/Audio/SamplePlaybackEngineTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

/// These tests do NOT start the AVAudioEngine (which requires audio hardware in CI).
/// They exercise the bookkeeping layer — which tracks are prepared, which voices
/// are allocated per track — without calling into AVFoundation's real graph.
final class SamplePlaybackEngineTests: XCTestCase {
    func test_prepareTrack_is_idempotent() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.prepareTrack(trackID: trackID)
        // No crash, no duplicate attachment. Verifiable via the public
        // `preparedTrackIDs` accessor.
        XCTAssertEqual(engine.preparedTrackIDs, [trackID])
    }

    func test_prepareTrack_then_removeTrack_clears_bookkeeping() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.removeTrack(trackID: trackID)
        XCTAssertTrue(engine.preparedTrackIDs.isEmpty)
    }

    func test_play_without_prepareTrack_returns_nil_and_does_not_crash() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        let handle = engine.play(
            sampleURL: URL(fileURLWithPath: "/tmp/does-not-exist.wav"),
            settings: .default,
            trackID: trackID,
            at: nil
        )
        XCTAssertNil(handle)
    }
}
```

- [ ] **Step 2: Run the test — expect compile failures**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/SamplePlaybackEngineTests \
  2>&1 | tail -20
```

Expected: compile failure — `prepareTrack(trackID:)` and `preparedTrackIDs` do not exist.

- [ ] **Step 3: Extend the protocol and engine with `prepareTrack`**

In `Sources/Audio/SamplePlaybackEngine.swift`, add `prepareTrack(trackID:)` to the protocol:

```swift
protocol SamplePlaybackSink: AnyObject {
    func start() throws
    func stop()
    /// Ensures `trackID` has a ready mixer + voice pool attached to the engine graph.
    /// Safe to call repeatedly. Must be called on a queue that does not race with
    /// `play(...)` — today that is the main thread, called from `EngineController.apply(documentModel:)`.
    func prepareTrack(trackID: UUID)
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle?
    func setTrackMix(trackID: UUID, level: Double, pan: Double)
    func removeTrack(trackID: UUID)
    func audition(sampleURL: URL)
    func stopAudition()
}
```

Add a public accessor for tests (keeps the private dictionary private in production but exposes the set of keys for assertions):

```swift
final class SamplePlaybackEngine: SamplePlaybackSink {
    // existing properties …

    /// Test-only read. Returns the set of track IDs that have an allocated voice pool.
    /// Pure reader; safe to call from any thread.
    var preparedTrackIDs: Set<UUID> {
        Set(trackVoicePools.keys)
    }

    private var trackVoicePools: [UUID: [AVAudioPlayerNode]] = [:]
    private var trackVoiceCursors: [UUID: Int] = [:]
    private static let voicesPerTrack = 4
    // …
}
```

Add the `prepareTrack` method (initial implementation — still tolerant of the old lazy path so Task 4 can incrementally switch play() over):

```swift
    func prepareTrack(trackID: UUID) {
        if trackVoicePools[trackID] != nil { return }

        let mixer = trackMixer(for: trackID)

        var voices: [AVAudioPlayerNode] = []
        for _ in 0..<Self.voicesPerTrack {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: mixer, format: nil)
            voices.append(voice)
        }
        trackVoicePools[trackID] = voices
        trackVoiceCursors[trackID] = 0
    }
```

Update `removeTrack(trackID:)` to tear the per-track pool down (add the detach calls to the existing body):

```swift
    func removeTrack(trackID: UUID) {
        if let pool = trackVoicePools.removeValue(forKey: trackID) {
            for voice in pool {
                voice.stop()
                engine.disconnectNodeOutput(voice)
                engine.detach(voice)
            }
        }
        trackVoiceCursors.removeValue(forKey: trackID)

        guard let mixer = trackMixers.removeValue(forKey: trackID) else { return }
        for (i, currentTrackID) in mainVoiceCurrentTrack.enumerated() where currentTrackID == trackID {
            mainVoices[i].stop()
            engine.disconnectNodeOutput(mainVoices[i])
            mainVoiceCurrentTrack[i] = nil
        }
        engine.disconnectNodeOutput(mixer)
        engine.detach(mixer)
    }
```

- [ ] **Step 4: Run the unit tests to verify they pass**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/SamplePlaybackEngineTests \
  2>&1 | tail -20
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite — Task 2's mock will now compile because the protocol has the new method**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass. If any test that constructs a different `SamplePlaybackSink` conformance fails to compile because it does not implement `prepareTrack`, add an empty body to that test double and move on.

- [ ] **Step 6: Commit**

```bash
git add Sources/Audio/SamplePlaybackEngine.swift Tests/SequencerAITests/Audio/SamplePlaybackEngineTests.swift project.yml
git commit -m "feat(audio): SamplePlaybackSink.prepareTrack allocates per-track voice pool on main"
```

---

## Task 4: `play(...)` reads from the per-track voice pool — no graph mutation

Refactor `SamplePlaybackEngine.play(...)` to use the per-track voice pool built by `prepareTrack`. This is the step that eliminates the crash: no `attach`, no `connect`, no `disconnectNodeOutput` in `play`.

**Files:**
- Modify: `Sources/Audio/SamplePlaybackEngine.swift`

- [ ] **Step 1: Rewrite `play(...)`**

Replace the entire `play(sampleURL:settings:trackID:at:)` method in `Sources/Audio/SamplePlaybackEngine.swift` with:

```swift
    @discardableResult
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard isStarted else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }
        guard let pool = trackVoicePools[trackID], !pool.isEmpty else {
            // Track was never prepared — either `apply(documentModel:)` did not
            // run for this track yet, or the track was removed between dispatch
            // and play. Skip the trigger instead of attempting a graph mutation
            // from this queue.
            return nil
        }

        let cursor = trackVoiceCursors[trackID] ?? 0
        let voice = pool[cursor % pool.count]
        trackVoiceCursors[trackID] = (cursor &+ 1) % pool.count

        let handleID = UUID()

        voice.stop()
        voice.volume = linearGain(dB: settings.gain)
        voice.scheduleFile(file, at: when, completionHandler: nil)

        // Wrap voice.play() in an Obj-C @try/@catch. AVAudioPlayerNode.play can
        // raise an NSException (required-condition failures such as
        // !_outputFormat or !_engine->IsRunning()); letting that propagate out
        // of the TickClock dispatch queue terminates the process.
        if let exception = trySwiftBlockCatchingNSException({
            voice.play()
        }) {
            NSLog("[SamplePlaybackEngine] voice.play() raised \(exception.name.rawValue): \(exception.reason ?? "") — track=\(trackID)")
            return nil
        }

        return VoiceHandle(id: handleID)
    }
```

- [ ] **Step 2: Delete the now-dead global voice-pool fields and methods**

The fixed 16-voice global pool is replaced by per-track pools. Delete the following from `SamplePlaybackEngine`:

- `private static let mainVoiceCount = 16`
- `private var mainVoices: [AVAudioPlayerNode] = []`
- `private var mainVoiceHandles: [UUID] = []`
- `private var mainVoiceCurrentTrack: [UUID?] = []`
- `private var nextVoiceIndex = 0`
- The loop in `init()` that populated `mainVoices` / `mainVoiceHandles` / `mainVoiceCurrentTrack`.
- The `stopVoice(_:)` method (voice handles are no longer indexed into `mainVoiceHandles`).
- The `stopAllMainVoices()` method.

Update `stop()` to iterate the per-track pools instead of `mainVoices`:

```swift
    func stop() {
        guard isStarted else { return }
        for pool in trackVoicePools.values {
            for voice in pool { voice.stop() }
        }
        previewNode.stop()
        engine.stop()
        isStarted = false
    }
```

Update `removeTrack(trackID:)` to drop the `mainVoices`-era cleanup now that those fields are gone:

```swift
    func removeTrack(trackID: UUID) {
        if let pool = trackVoicePools.removeValue(forKey: trackID) {
            for voice in pool {
                voice.stop()
                engine.disconnectNodeOutput(voice)
                engine.detach(voice)
            }
        }
        trackVoiceCursors.removeValue(forKey: trackID)

        guard let mixer = trackMixers.removeValue(forKey: trackID) else { return }
        engine.disconnectNodeOutput(mixer)
        engine.detach(mixer)
    }
```

If `stopVoice(_:)` or `stopAllMainVoices()` were called from anywhere else in `Sources/`, delete those calls too. Grep before editing:

```bash
```

Use the Grep tool to search `Sources/` for `stopVoice(` and `stopAllMainVoices(`. If there are callers, replace them with a loop over `trackVoicePools.values` (stopping all voices in all pools) or drop the call entirely if it was unreachable.

- [ ] **Step 3: Build**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds. If callers to the deleted methods still exist, fix them inline.

- [ ] **Step 4: Run the focused tests from Task 3**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/SamplePlaybackEngineTests \
  2>&1 | tail -15
```

Expected: all three tests still pass. `test_play_without_prepareTrack_returns_nil_and_does_not_crash` now exercises the early-return branch rather than the lazy-create branch, so it's specifically pinning the new invariant.

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass. Any test that indirectly relied on the old lazy-in-`play()` path (uncommon) should be updated to call `prepareTrack(trackID:)` before `play(...)`; that change is local and small.

- [ ] **Step 6: Commit**

```bash
git add Sources/Audio/SamplePlaybackEngine.swift
git commit -m "fix(audio): play() reads per-track voice pool without mutating engine graph"
```

---

## Task 5: `EngineController.syncSampleMixers(for:)` calls `prepareTrack` before `setTrackMix`

Ensures every sample-destined track has its voice pool before any tick can dispatch a trigger for it.

**Files:**
- Modify: `Sources/Engine/EngineController.swift`
- Test: `Tests/SequencerAITests/Engine/EngineControllerSamplePrepareTests.swift`

- [ ] **Step 1: Write a failing test**

Create `Tests/SequencerAITests/Engine/EngineControllerSamplePrepareTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class EngineControllerSamplePrepareTests: XCTestCase {
    func test_applying_a_project_with_a_sample_track_prepares_it_before_setting_mix() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        // Install a sample destination on the first mono track via addDrumKit (uses .sample when a library sample exists).
        _ = project.addDrumKit(.kit808)
        controller.apply(documentModel: project)

        let sampleTrackCalls = mock.calls.filter { call in
            if case .prepareTrack = call { return true }
            if case .setTrackMix = call { return true }
            return false
        }
        // The first call for any given sample track must be prepareTrack.
        var seen: Set<UUID> = []
        for call in sampleTrackCalls {
            switch call {
            case .prepareTrack(let trackID):
                seen.insert(trackID)
            case .setTrackMix(let trackID, _, _):
                XCTAssertTrue(seen.contains(trackID), "setTrackMix called before prepareTrack for track=\(trackID)")
            default:
                break
            }
        }
        XCTAssertFalse(seen.isEmpty, "expected at least one prepareTrack call after adding a drum kit")
    }

    func test_removing_a_sample_track_emits_removeTrack_after_prepare() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        _ = project.addDrumKit(.kit808)
        controller.apply(documentModel: project)

        // Remove the kit by replacing the tracks list with the original empty one.
        let beforeRemoveCallCount = mock.calls.count
        controller.apply(documentModel: .empty)

        let newCalls = Array(mock.calls.dropFirst(beforeRemoveCallCount))
        XCTAssertTrue(newCalls.contains(where: { call in
            if case .removeTrack = call { return true }
            return false
        }), "expected removeTrack after applying a project without the previously-prepared sample tracks")
    }
}
```

- [ ] **Step 2: Run the tests — expect failure**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerSamplePrepareTests \
  2>&1 | tail -20
```

Expected: `test_applying_a_project_with_a_sample_track_prepares_it_before_setting_mix` fails because `EngineController` does not call `prepareTrack` yet.

- [ ] **Step 3: Update `syncSampleMixers(for:)`**

In `Sources/Engine/EngineController.swift`, modify `syncSampleMixers(for:)` (around line 904) to call `prepareTrack` before `setTrackMix`:

```swift
    private func syncSampleMixers(for documentModel: Project) {
        var sampleTrackIDs: Set<UUID> = []
        for track in documentModel.tracks {
            guard case .sample = track.destination else { continue }
            sampleTrackIDs.insert(track.id)

            // Prepare the voice pool before writing any mix state. Must happen
            // here (main / apply-time) so play() on TickClock never mutates the
            // engine graph.
            sampleEngine.prepareTrack(trackID: track.id)

            sampleEngine.setTrackMix(
                trackID: track.id,
                level: track.mix.clampedLevel,
                pan: track.mix.clampedPan
            )
        }

        let previouslyLiveTrackIDs = withStateLock { liveSampleTrackIDs }
        for removed in previouslyLiveTrackIDs.subtracting(sampleTrackIDs) {
            sampleEngine.removeTrack(trackID: removed)
        }

        withStateLock { liveSampleTrackIDs = sampleTrackIDs }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerSamplePrepareTests \
  2>&1 | tail -15
```

Expected: both tests pass.

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
git add Sources/Engine/EngineController.swift Tests/SequencerAITests/Engine/EngineControllerSamplePrepareTests.swift
git commit -m "fix(engine): apply(documentModel:) prepares sample-track voice pools before any tick"
```

---

## Task 6: Manual smoke + plan status + tag

Verify the original crash no longer reproduces.

**Files:** none beyond doc updates

- [ ] **Step 1: Build and open the app**

```bash
./scripts/open-latest-build.sh
```

- [ ] **Step 2: Reproduce the original scenario**

- Open a fresh project.
- Press play (or let the transport start automatically if the project is live).
- On the Tracks page, tap `Add Drum Kit → 808 Kit` (today's dropdown) OR, if the add-drum-group-modal plan has also landed, tap `Add Drum Group → Templated → 808 Kit → Create Group`.
- Wait several seconds while the transport ticks. Previously: app aborts. Expected now: app keeps ticking; the new drum tracks audition correctly if their samples resolve; if the library is empty and destinations fall back to `.internalSampler`, there is no sample trigger at all (pre-existing behavior).

- [ ] **Step 3: Verify the belt-and-braces NSException trap**

- Introduce a temporary fault locally to simulate a future regression: in `SamplePlaybackEngine.play(...)`, immediately before `voice.play()`, insert `engine.disconnectNodeOutput(voice)`. Rebuild.
- Reproduce the scenario above. Instead of crashing, the app should log `[SamplePlaybackEngine] voice.play() raised …` to stderr and continue running.
- Remove the temporary fault and rebuild. This step is not committed — it is a manual verification of the `trySwiftBlockCatchingNSException` wrap. Any commit with the fault still in place is wrong; double-check `git status` shows a clean worktree afterwards.

- [ ] **Step 4: Flip the bug-report status + mark the fix-plan complete + tag**

In `docs/plans/2026-04-21-bug-sample-playback-crash-on-tickclock.md`, replace the `**Status:** Open — not yet reproduced in isolation; fix not scoped` line with:

```
**Status:** ✅ Fixed 2026-04-21 by `docs/plans/2026-04-21-fix-sample-playback-graph-mutation-on-tickclock.md`. Tag v0.0.22-fix-sample-playback-graph-mutation.
```

In this plan (`docs/plans/2026-04-21-fix-sample-playback-graph-mutation-on-tickclock.md`), replace the `**Status:** Not started.` line with:

```
**Status:** ✅ Completed 2026-04-21. Tag v0.0.22-fix-sample-playback-graph-mutation. Verified via focused SamplePlaybackEngineTests, EngineControllerSamplePrepareTests, full suite, and manual drum-kit-while-playing smoke.
```

Commit + tag:

```bash
git add docs/plans/2026-04-21-bug-sample-playback-crash-on-tickclock.md docs/plans/2026-04-21-fix-sample-playback-graph-mutation-on-tickclock.md
git commit -m "docs(plan): mark sample-playback graph-mutation fix completed"
git tag -a v0.0.22-fix-sample-playback-graph-mutation -m "Fix TickClock crash: per-track voice pools prepared on main; play() no graph mutation"
```

- [ ] **Step 5: Dispatch `wiki-maintainer` to refresh `wiki/pages/audio-engine.md` (or create it) with the per-track voice pool invariant**

Brief:
- Diff range: `<previous-tag>..HEAD`.
- Plan: `docs/plans/2026-04-21-fix-sample-playback-graph-mutation-on-tickclock.md`.
- Task: document that `SamplePlaybackEngine` graph mutation happens exclusively in `prepareTrack` / `removeTrack` on the main thread, and that `play(...)` is a pure reader of the per-track voice pool. Cross-link to the bug report.
- Commit under `docs(wiki):` prefix.

---

## Self-Review

**Spec coverage (bug report → plan):**
- Suggested direction 1 (defensive `@try/@catch`) — Task 1 (shim) + Task 4 Step 1 (wrap `voice.play()`). ✓
- Suggested direction 2 (pre-attach per-track mixers on main) — Task 3 (prepareTrack attaches mixer) + Task 5 (EngineController calls it in apply). ✓
- Suggested direction 3 (pre-connect voices) — Task 3 (prepareTrack creates and connects the per-track pool). ✓
- Suggested direction 4 (serialize graph mutations) — achieved as a consequence of direction 2+3: no graph mutation on TickClock at all. Dedicated serial queue deliberately not introduced (YAGNI). ✓
- Suggested direction 5 (regression test) — Task 5 Step 1 (`EngineControllerSamplePrepareTests`) + Task 3 Step 1 (`SamplePlaybackEngineTests`). ✓

**Placeholder scan:** no TBDs. Every step has exact commands and exact code. The one bash snippet left unfilled in Task 4 Step 2 is a deliberate use of the Grep tool rather than a shell command, with explicit guidance on what to do with the results. ✓

**Type consistency:**
- `SamplePlaybackSink` protocol extension in Task 3 (adds `prepareTrack(trackID:)`) matches the `MockSamplePlaybackSink` conformance in Task 2 and the call site in Task 5. ✓
- `trackVoicePools: [UUID: [AVAudioPlayerNode]]` + `trackVoiceCursors: [UUID: Int]` + `voicesPerTrack` declared in Task 3 are used in Task 4's rewritten `play(...)`, `stop()`, and `removeTrack(trackID:)`. ✓
- `trySwiftBlockCatchingNSException` defined in Task 1 is used by Task 4. ✓
- `preparedTrackIDs` test-only accessor added in Task 3 is referenced by the test file created in Task 3 Step 1. ✓

**Risks:**
- **Bridging header path:** Task 1 Step 4 assumes `project.yml` either has or accepts `SWIFT_OBJC_BRIDGING_HEADER: Sources/Audio/NSExceptionCatch.h`. If the project already has a different bridging header, import `NSExceptionCatch.h` into that existing one instead of replacing it.
- **Per-track polyphony change:** today's 16 global voices become 4 per track. A project with many active sample tracks gets *more* effective polyphony (4 × track count), not less. If a project has dozens of sample tracks, total voice count climbs proportionally. Acceptable for the fix; tune `voicesPerTrack` later if needed.
- **Existing tests referencing deleted methods:** `stopVoice(_:)` / `stopAllMainVoices()` are deleted in Task 4 Step 2. Grep caveat noted in-step.
- **CI without audio hardware:** the new unit tests do not start the `AVAudioEngine`, so they run fine on CI. The only AVAudioEngine-driven verification is the manual smoke in Task 6.
- **`apply(documentModel:)` threading:** this plan assumes `syncSampleMixers(for:)` runs on the main thread today (it does — `apply(documentModel:)` is invoked from `EngineController.apply(documentModel:)` which is called by SwiftUI bindings on main). If a future refactor moves `apply` off main, `prepareTrack` must follow. Document the invariant in the audio-engine wiki page (Task 6 Step 5).
