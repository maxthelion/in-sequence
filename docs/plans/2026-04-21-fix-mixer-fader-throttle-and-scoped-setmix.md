# Throttle Mixer Faders + Scoped setMix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop fader drags in the Mixer and Inspector from firing stray notes and thrashing the engine. Mix-only changes get a dedicated, lock-safe `EngineController.setMix(trackID:, mix:)` path that bypasses the full `apply(documentModel:)` pipeline. UI mixes a *live* mix during drag (zero document mutation, one scoped engine call per drag-tick) and commits the new mix to the document exactly once on drag-end.

**Architecture:** Three changes, each narrow:

1. A new `EngineController.setMix(trackID:, mix:)` method. Writes to the per-track playback sink's volume/pan and (for sample tracks) the sample engine's per-track mixer. Takes `withStateLock` only for dictionary lookups. Does **not** call `apply(documentModel:)`, does **not** mutate `currentDocumentModel`.
2. `MixerView.swift` level/pan controls switched to drag-aware bindings: while dragging, the UI holds a local `@State` override and calls `engineController.setMix(...)` on every tick; on drag-end, it writes the final value back to `document.project` once.
3. `InspectorView.swift` level/pan sliders adopt the same pattern (they drive the same `document.project.selectedTrack.mix` bindings today).

A follow-up task audits the rest of the UI for other non-debounced input that hits `apply(documentModel:)` at per-frame rates.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest.

**Parent bug report:** `docs/plans/2026-04-21-bug-mixer-fader-triggers-notes.md`.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Run `xcodegen generate` after creating new files.

**Status:** Not started. Tag `v0.0.24-mixer-fader-throttle` at completion.

**Depends on:** nothing on the critical path. Can execute against current `main` alongside other plans.

**Deliberately deferred:**

- Engine-side race fix: taking `withStateLock` around the entire `apply(documentModel:)`, or making the tick use a fully locked snapshot end-to-end. Logged for a future plan. The throttle fix collapses the race window but does not remove the underlying bug.
- Reworking `TrackPlaybackSink.setMix` / `SamplePlaybackSink.setTrackMix` signatures. Reuse as-is.
- Undo granularity: during drag, each intermediate mix value is not committed to the document, so the undo stack records only the final value on drag-end. Intentional; matches platform conventions (e.g. Finder file rename).

---

## File Structure

```
Sources/Engine/
  EngineController.swift                          # MODIFIED — new setMix(trackID:, mix:) scoped path

Sources/UI/
  MixerView.swift                                 # MODIFIED — drag-aware level fader + drag-aware pan slider
  InspectorView.swift                             # MODIFIED — drag-aware level + pan sliders
  ThrottledMixControl.swift                       # NEW — shared View/ViewModifier wrapping the drag-aware binding pattern

Tests/SequencerAITests/
  Engine/
    EngineControllerSetMixScopedTests.swift       # NEW — verifies setMix path writes to host+sampleEngine and does NOT route through apply

docs/plans/
  2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md   # THIS FILE — status flips + tagged at Task 6
  2026-04-21-bug-mixer-fader-triggers-notes.md               # parent bug; status flipped at Task 6
```

---

## Task 1: `EngineController.setMix(trackID:, mix:)` — scoped path

Adds a new entry point the UI can call during drags without touching `apply(documentModel:)`. Internally:
1. Lookup the `TrackPlaybackSink` under `withStateLock`.
2. Call `host.setMix(mix)`.
3. If the track has a `.sample` destination, also call `sampleEngine.setTrackMix(trackID:, level:, pan:)`.

Does NOT write `currentDocumentModel`, does NOT modify `pipelineShape`, does NOT rebuild the pipeline, does NOT touch the router.

**Files:**
- Modify: `Sources/Engine/EngineController.swift`
- Test: `Tests/SequencerAITests/Engine/EngineControllerSetMixScopedTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Engine/EngineControllerSetMixScopedTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class EngineControllerSetMixScopedTests: XCTestCase {
    func test_setMix_calls_setTrackMix_on_sample_engine_for_sample_tracks() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        _ = project.addDrumKit(.kit808)  // produces .sample destinations when library has samples
        controller.apply(documentModel: project)

        let sampleTrackID = project.tracks.last(where: {
            if case .sample = $0.destination { return true }
            return false
        })?.id

        guard let sampleTrackID else {
            throw XCTSkip("no .sample destination produced in this environment; skipping")
        }

        let countBeforeSetMix = mock.calls.count
        var mix = TrackMixSettings.default
        mix.level = 0.42
        mix.pan = -0.3

        controller.setMix(trackID: sampleTrackID, mix: mix)

        let newCalls = Array(mock.calls.dropFirst(countBeforeSetMix))
        XCTAssertTrue(newCalls.contains(where: { call in
            if case let .setTrackMix(trackID, level, pan) = call,
               trackID == sampleTrackID,
               abs(level - 0.42) < 0.0001,
               abs(pan - (-0.3)) < 0.0001 {
                return true
            }
            return false
        }), "expected setTrackMix(trackID: \(sampleTrackID), level: 0.42, pan: -0.3); got \(newCalls)")
    }

    func test_setMix_does_not_invoke_prepareTrack_or_removeTrack() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        _ = project.addDrumKit(.kit808)
        controller.apply(documentModel: project)

        guard let sampleTrackID = project.tracks.last(where: {
            if case .sample = $0.destination { return true }
            return false
        })?.id else {
            throw XCTSkip("no sample track; skipping")
        }

        let countBeforeSetMix = mock.calls.count
        controller.setMix(trackID: sampleTrackID, mix: .default)

        let newCalls = Array(mock.calls.dropFirst(countBeforeSetMix))
        for call in newCalls {
            switch call {
            case .prepareTrack, .removeTrack, .start, .stop, .play, .audition, .stopAudition:
                XCTFail("setMix should not trigger \(call)")
            case .setTrackMix:
                continue
            }
        }
    }

    func test_setMix_for_unknown_track_is_a_noop() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)
        let countBefore = mock.calls.count
        controller.setMix(trackID: UUID(), mix: .default)
        XCTAssertEqual(mock.calls.count, countBefore, "unknown trackID must not call into sampleEngine")
    }
}
```

If `MockSamplePlaybackSink` is not yet in the tree (it lands with the per-track-voice-pool plan), create the minimum needed here:
- Add `MockSamplePlaybackSink` to `Tests/SequencerAITests/Engine/MockSamplePlaybackSink.swift` with a `calls: [Call]` array and `Call` enum covering at least `setTrackMix(trackID:level:pan:)`, `start`, `stop`, `removeTrack`, `play`, `audition`, `stopAudition`, and `prepareTrack` (even if `prepareTrack` is not yet on the `SamplePlaybackSink` protocol, add it to the mock; the compiler will ignore the extra method).

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerSetMixScopedTests \
  2>&1 | tail -25
```

Expected: compile failure — `EngineController.setMix(trackID:, mix:)` does not exist.

- [ ] **Step 3: Implement `setMix(trackID:, mix:)`**

In `Sources/Engine/EngineController.swift`, add the method near the other mix helpers (immediately after `func apply(track: StepSequenceTrack)`):

```swift
    /// Scoped mix update: writes volume/pan to the track's playback sink and, for
    /// `.sample`-destined tracks, to the sample engine's per-track mixer. Does NOT
    /// rebuild the pipeline, NOT mutate `currentDocumentModel`, NOT reapply routes.
    /// Call this from high-frequency UI (fader drags) to avoid thrashing the main
    /// apply path.
    func setMix(trackID: UUID, mix: TrackMixSettings) {
        let host = withStateLock { audioOutputsByTrackID[trackID] }
        host?.setMix(mix)

        let isSampleTrack: Bool = {
            guard let track = currentDocumentModel.tracks.first(where: { $0.id == trackID }) else {
                return false
            }
            if case .sample = track.destination { return true }
            return false
        }()

        if isSampleTrack {
            sampleEngine.setTrackMix(
                trackID: trackID,
                level: mix.clampedLevel,
                pan: mix.clampedPan
            )
        }
    }
```

Important: `currentDocumentModel` is read here without `withStateLock`. The existing `apply(documentModel:)` also writes `currentDocumentModel` without the lock (this is logged for a separate race-fix plan). For the scoped `setMix` path, a stale read is harmless: either the track still has a `.sample` destination (we call the sample engine correctly) or it doesn't and the call is skipped — in either case no engine graph mutation or note emission occurs. Do NOT attempt to widen `withStateLock` here — that is the other plan.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerSetMixScopedTests \
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
git add Sources/Engine/EngineController.swift Tests/SequencerAITests/Engine/EngineControllerSetMixScopedTests.swift Tests/SequencerAITests/Engine/MockSamplePlaybackSink.swift
git commit -m "feat(engine): EngineController.setMix(trackID:mix:) scoped path for high-frequency UI"
```

---

## Task 2: `ThrottledMixControl` — shared drag-aware binding helper

A small view/view-modifier that both `MixerView` and `InspectorView` consume. Holds a local `@State var liveValue: Double` during a drag, invokes a `onChange: (Double) -> Void` closure on every tick (which calls `engineController.setMix`), and fires a `onCommit: (Double) -> Void` on drag-end (which writes back to `document.project`).

**Files:**
- Create: `Sources/UI/ThrottledMixControl.swift`

This is a pure helper — no tests. Exercised transitively by `MixerView` / `InspectorView` in Task 3/4 and by the manual smoke in Task 6.

- [ ] **Step 1: Create the helper**

Write `Sources/UI/ThrottledMixControl.swift`:

```swift
import SwiftUI

/// Shared state for a drag-aware mix control (level or pan). The owning view
/// reads the committed value from its document binding and calls `begin` on
/// gesture start, `update` on every drag tick, and `commit` on drag end.
///
/// While a drag is in progress, `liveValue` is used for rendering and for
/// feeding the scoped engine callback; the document binding is NOT touched.
/// On commit, the document binding gets one write with the final value.
@MainActor
final class ThrottledMixValue: ObservableObject {
    @Published private(set) var liveValue: Double?

    func begin(with initial: Double) {
        liveValue = initial
    }

    /// True if `value` is the same as the last reported value to within `epsilon`.
    /// The caller should skip the engine callback in that case — no perceptible
    /// change and no point thrashing the audio engine.
    func update(_ value: Double, epsilon: Double = 0.0005) -> Bool {
        guard let current = liveValue else {
            liveValue = value
            return true
        }
        if abs(current - value) < epsilon {
            return false
        }
        liveValue = value
        return true
    }

    func commit() -> Double? {
        let final = liveValue
        liveValue = nil
        return final
    }

    var isDragging: Bool { liveValue != nil }

    /// The value the UI should render. If a drag is in progress, use the live
    /// value; otherwise use the document-backed value passed in.
    func rendered(committed: Double) -> Double {
        liveValue ?? committed
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/ThrottledMixControl.swift project.yml
git commit -m "feat(ui): ThrottledMixValue — drag-aware mix binding helper"
```

---

## Task 3: `MixerView` — drag-aware level fader + pan slider

Rewire the `VerticalLevelFader` gesture and the pan `Slider` so the document is mutated only on drag-end, and the engine receives the scoped `setMix` call on every drag tick.

**Files:**
- Modify: `Sources/UI/MixerView.swift`

This is UI work with no new automated tests. Exercised by the manual smoke in Task 6.

- [ ] **Step 1: Add engine-controller access and a throttled-value state to the channel strip**

`MixerView.swift`'s channel strip needs two things it does not have today:
- A reference to `EngineController` (via `@Environment(EngineController.self)`).
- A `@StateObject var mixValue = ThrottledMixValue()` per strip (one for level, one for pan — or one shared instance with separate `liveValue` tracking; for clarity, use two instances: `levelValue` and `panValue`).

Add to the struct holding the per-track strip view (look for where `@Binding var track: StepSequenceTrack` is declared; that's the strip view). Add near the existing `@Binding` declarations:

```swift
    @Environment(EngineController.self) private var engineController
    @StateObject private var levelValue = ThrottledMixValue()
    @StateObject private var panValue = ThrottledMixValue()
```

Also grab the track ID into a `let` to avoid capturing `self` in the drag closures:

```swift
    private var trackID: UUID { track.id }
```

- [ ] **Step 2: Rewire `VerticalLevelFader` to use a drag-aware binding**

`VerticalLevelFader` currently takes `@Binding var level: Double` directly. Replace its usage in the channel strip (around `MixerView.swift:74`) with a drag-aware wrapper. The simplest refactor is to inline the gesture handling in the channel strip rather than keep it inside `VerticalLevelFader`. Replace the current `VerticalLevelFader` call site:

```swift
VerticalLevelFader(level: $track.mix.level, isMuted: track.mix.isMuted)
    .frame(width: 36, height: 150)
```

with:

```swift
VerticalLevelFader(
    renderedLevel: levelValue.rendered(committed: track.mix.level),
    isMuted: track.mix.isMuted,
    onDragChanged: { newValue in
        handleLevelDrag(newValue)
    },
    onDragEnded: {
        handleLevelEnded()
    }
)
.frame(width: 36, height: 150)
```

Change `VerticalLevelFader` (at the bottom of the file) from:

```swift
private struct VerticalLevelFader: View {
    @Binding var level: Double
    let isMuted: Bool
    …
    .gesture(
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let next = 1 - (value.location.y / max(height, 1))
                level = min(max(next, 0), 1)
            }
    )
```

to:

```swift
private struct VerticalLevelFader: View {
    let renderedLevel: Double
    let isMuted: Bool
    let onDragChanged: (Double) -> Void
    let onDragEnded: () -> Void
    …
    .gesture(
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let next = 1 - (value.location.y / max(height, 1))
                onDragChanged(min(max(next, 0), 1))
            }
            .onEnded { _ in
                onDragEnded()
            }
    )
```

Replace the internal `private var clampedLevel: Double { min(max(level, 0), 1) }` reference with the plumbed `renderedLevel` (which the caller has already clamped via the throttled value helper).

Add the handler methods to the channel-strip view struct:

```swift
    private func handleLevelDrag(_ newValue: Double) {
        guard levelValue.update(newValue) else { return }
        var updatedMix = track.mix
        updatedMix.level = newValue
        engineController.setMix(trackID: trackID, mix: updatedMix)
    }

    private func handleLevelEnded() {
        guard let finalValue = levelValue.commit() else { return }
        track.mix.level = finalValue   // commits to document exactly once
    }
```

- [ ] **Step 3: Rewire the pan `Slider`**

The pan slider at `MixerView.swift:90` needs the same pattern. Swift's native `Slider` supports an `onEditingChanged` callback and an implicit drag gesture. Replace:

```swift
Slider(value: $track.mix.pan, in: -1...1)
    .tint(StudioTheme.violet)
    .frame(width: 88)
```

with:

```swift
Slider(
    value: Binding(
        get: { panValue.rendered(committed: track.mix.pan) },
        set: { newValue in
            handlePanDrag(newValue)
        }
    ),
    in: -1...1,
    onEditingChanged: { editing in
        if editing {
            panValue.begin(with: track.mix.pan)
        } else {
            handlePanEnded()
        }
    }
)
.tint(StudioTheme.violet)
.frame(width: 88)
```

Add the handlers:

```swift
    private func handlePanDrag(_ newValue: Double) {
        guard panValue.update(newValue) else { return }
        var updatedMix = track.mix
        updatedMix.pan = newValue
        engineController.setMix(trackID: trackID, mix: updatedMix)
    }

    private func handlePanEnded() {
        guard let finalValue = panValue.commit() else { return }
        track.mix.pan = finalValue
    }
```

Note: for the level fader we drive `begin(with:)` implicitly on the first `update(...)` call (the helper handles nil `liveValue`). For the pan slider we use Swift's `onEditingChanged` to call `begin(...)` explicitly, because the slider's thumb can be clicked without dragging and we want to capture the pre-click value so a micro-move doesn't snap through the whole range. The asymmetry is intentional — both are correct for their respective gesture shapes.

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds. If `MixerView` does not have `@Environment(EngineController.self)` available because it receives the track through a non-environment pathway, trace the parent chain — `ContentView` already installs the environment via `environment(engineController)` (see `Sources/UI/ContentView.swift:14`), so any descendant can pull it via `@Environment(EngineController.self)`.

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
git add Sources/UI/MixerView.swift
git commit -m "feat(ui): mixer level + pan commit to document only on drag-end; scoped setMix during drag"
```

---

## Task 4: `InspectorView` — same pattern for inspector mix sliders

The Inspector shows level and pan for the selected track (seen at `Sources/UI/InspectorView.swift:46, 54`). Apply the same throttled-binding refactor.

**Files:**
- Modify: `Sources/UI/InspectorView.swift`

- [ ] **Step 1: Add engine-controller + throttled-value state**

Near the top of the inspector view struct, add:

```swift
    @Environment(EngineController.self) private var engineController
    @StateObject private var levelValue = ThrottledMixValue()
    @StateObject private var panValue = ThrottledMixValue()
```

- [ ] **Step 2: Replace the level slider**

Locate the existing level `Slider` at `Sources/UI/InspectorView.swift:46`:

```swift
Slider(value: $document.project.selectedTrack.mix.level, in: 0...1)
```

Replace with:

```swift
Slider(
    value: Binding(
        get: { levelValue.rendered(committed: document.project.selectedTrack.mix.level) },
        set: { newValue in
            guard levelValue.update(newValue) else { return }
            let trackID = document.project.selectedTrack.id
            var updatedMix = document.project.selectedTrack.mix
            updatedMix.level = newValue
            engineController.setMix(trackID: trackID, mix: updatedMix)
        }
    ),
    in: 0...1,
    onEditingChanged: { editing in
        if editing {
            levelValue.begin(with: document.project.selectedTrack.mix.level)
        } else if let finalValue = levelValue.commit() {
            document.project.selectedTrack.mix.level = finalValue
        }
    }
)
```

- [ ] **Step 3: Replace the pan slider**

At `Sources/UI/InspectorView.swift:54`, apply the same pattern:

```swift
Slider(
    value: Binding(
        get: { panValue.rendered(committed: document.project.selectedTrack.mix.pan) },
        set: { newValue in
            guard panValue.update(newValue) else { return }
            let trackID = document.project.selectedTrack.id
            var updatedMix = document.project.selectedTrack.mix
            updatedMix.pan = newValue
            engineController.setMix(trackID: trackID, mix: updatedMix)
        }
    ),
    in: -1...1,
    onEditingChanged: { editing in
        if editing {
            panValue.begin(with: document.project.selectedTrack.mix.pan)
        } else if let finalValue = panValue.commit() {
            document.project.selectedTrack.mix.pan = finalValue
        }
    }
)
```

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/InspectorView.swift
git commit -m "feat(ui): inspector level + pan adopt drag-aware binding + scoped setMix"
```

---

## Task 5: Audit — other non-debounced UI inputs that mutate the document

Find and report every place in `Sources/UI/` that writes `document.project` in response to a continuous gesture (`DragGesture`, raw `Slider` value binding, `Stepper` with repeat-fire, `TextField` that commits on every keystroke) without an explicit drag-end / edit-end commit point. Propose remediation per site.

The audit is **a report, not a code change**. Each site either:
- Needs the `ThrottledMixValue` pattern (fader-like continuous inputs).
- Needs `onEditingChanged` / drag-end commit (discrete controls that happen to use a raw binding).
- Is safe as-is (the gesture already commits once per gesture, e.g. button tap, step-cell toggle, menu selection).

**Files:**
- Modify (append report section): this plan file, at the bottom.

- [ ] **Step 1: Survey the UI layer**

Use the Grep tool to find candidate call sites:

- `Slider(value:` — any slider without an `onEditingChanged` needs inspection. Grep pattern: `Slider\(value:`.
- `DragGesture` — any drag gesture that writes `document.project` in `.onChanged` without an `.onEnded` commit. Grep pattern: `DragGesture`.
- `Stepper(value:` — steppers with `autorepeat` can mutate the document at ~5 Hz on press-and-hold. Grep pattern: `Stepper\(value:`.
- `TextField` that binds directly to `document.project` — every keystroke rebuilds the engine model. Grep pattern: `TextField.*\$document\.project` (may need multiline).
- Any binding path of the form `$document.project.…` used in a continuous-change control.

Collect: file:line, the binding chain (`$document.project.foo.bar`), the gesture/control type, and whether a drag-end commit exists.

- [ ] **Step 2: Append the audit report to this plan**

Append a new section titled "Audit (2026-04-21)" at the bottom of this file. For each site, use this format:

```markdown
#### <Sources/UI/Path.swift>:<line>

- **Control:** <control type>
- **Binding:** `<binding chain>`
- **Commit boundary:** <present | absent>
- **Risk:** <high | medium | low>
- **Proposed fix:** <reuse ThrottledMixValue | add onEditingChanged commit | safe as-is (reason)>
```

Known sites to include in the audit (use this as a seed; confirm each, add any others):

- `Sources/UI/MixerView.swift:178` — level `DragGesture` — **fixed in Task 3**.
- `Sources/UI/MixerView.swift:90` — pan `Slider` — **fixed in Task 3**.
- `Sources/UI/InspectorView.swift:46` — level `Slider` — **fixed in Task 4**.
- `Sources/UI/InspectorView.swift:54` — pan `Slider` — **fixed in Task 4**.
- `Sources/UI/TransportBar.swift:59` — BPM `Slider` via `bpmBinding`. During playback, every drag-tick reapplies BPM to the engine. Inspect the `bpmBinding` write path: does it mutate `document.project` or go directly to `EngineController.setBPM(_:)`? If the latter, probably safe. If the former, needs the same throttled pattern.
- `Sources/UI/SamplerDestinationWidget.swift:95` — gain `Slider` uses `onEditingChanged` — confirm the document write only happens on commit; if so, safe.
- `Sources/UI/PhraseCellEditors/ScalarValueEditor.swift:18` — scalar-value `Slider` — inspect; cell editing is typically behind a sheet, so the commit may already be deferred, but confirm.
- `Sources/UI/PhraseWorkspaceView.swift` — grep for `DragGesture` and `Slider(value:`; some phrase-cell / timeline drags may mutate the document continuously.
- `Sources/UI/TrackDestinationEditor.swift` — already calls `engineController.apply(documentModel:)` several times in response to destination changes, but those are discrete button-triggered (not continuous). Audit whether any destination parameter stepper/slider inside that view is continuous.
- `Sources/UI/RouteEditorSheet.swift` — sheet-scoped. Confirm it writes back on save, not on every keystroke.
- `Sources/UI/TrackSource/Widgets/SourceParameterStepperRow.swift` — parameter stepper with `autorepeat` may fire at ~5 Hz and write `document.project`. Likely lower-frequency than a drag, but still worth confirming.

- [ ] **Step 3: Triage**

At the bottom of the appended audit section, add a "Follow-ups" subsection listing every site marked `high` or `medium` risk as candidates for a later plan. Do **not** fix them in this plan unless the audit surfaces one that is actively causing the same note-firing bug. Keep scope tight.

- [ ] **Step 4: Commit**

```bash
git add docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md
git commit -m "docs(plan): append UI-input audit to mixer-fader throttle plan"
```

---

## Task 6: Manual smoke + plan status + tag

**Files:** none beyond doc updates

- [ ] **Step 1: Build and open the app**

```bash
./scripts/open-latest-build.sh
```

- [ ] **Step 2: Verify the repro is fixed**

- Open a document with at least one track routed to an AU instrument and at least one drum kit (sample destinations).
- Press play.
- Drag level faders aggressively on both AU and sample tracks. Previously: stray notes fire. Expected now: level changes smoothly, no stray notes, audio volume follows the fader.
- Drag pan sliders similarly. Expected: pan follows smoothly, no stray notes.
- Pause playback. Drag faders. Expected: no audio (nothing was playing) and levels still visibly follow.
- Resume playback. Release a fader in a new position. Expected: the level is committed and persists across tempo/transport changes.

- [ ] **Step 3: Verify the audit report is present**

Re-read `docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md`. Confirm the "Audit (2026-04-21)" section exists at the bottom and that every high/medium-risk site is in the Follow-ups list.

- [ ] **Step 4: Flip the bug-report status + mark this plan complete + tag**

Edit `docs/plans/2026-04-21-bug-mixer-fader-triggers-notes.md`: replace `**Status:** Open — fix plan written …` with:

```
**Status:** ✅ Fixed 2026-04-21 by `docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md`. Tag `v0.0.24-mixer-fader-throttle`.
```

Edit this plan: replace `**Status:** Not started.` with:

```
**Status:** ✅ Completed 2026-04-21. Tag `v0.0.24-mixer-fader-throttle`. Verified via focused EngineControllerSetMixScopedTests, full suite, and manual drag-fader-while-playing smoke.
```

Commit + tag:

```bash
git add docs/plans/2026-04-21-bug-mixer-fader-triggers-notes.md docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md
git commit -m "docs(plan): mark mixer-fader-throttle fix completed"
git tag -a v0.0.24-mixer-fader-throttle -m "Throttle mixer faders: scoped setMix + drag-end commits; UI-input audit attached"
```

- [ ] **Step 5: Dispatch `wiki-maintainer` to note the engine-input invariant**

Brief:
- Diff range: `<previous-tag>..HEAD`.
- Plan: `docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md`.
- Task: document the invariant that high-frequency UI gestures must not drive `EngineController.apply(documentModel:)`. Any control that wants to write to the engine in real time must use a scoped method (e.g. `setMix(trackID:, mix:)`, `setBPM(_:)`) and commit to `document.project` exactly once at gesture end. Cross-link to the bug report and the per-track voice-pool plan (both related to engine/UI isolation).
- Commit under `docs(wiki):` prefix.

---

## Self-Review

**Bug-report coverage (report → plan):**
- Scoped engine path that bypasses `apply(documentModel:)` — Task 1. ✓
- Mixer level + pan commit only on drag-end — Task 3. ✓
- Inspector level + pan adopt the same pattern — Task 4. ✓
- Audit of other UI inputs — Task 5. ✓
- Manual smoke verifying the repro is gone — Task 6. ✓

**Placeholder scan:** no TBDs. Every step has exact code or exact commands. The audit task (Task 5) is described as "append to this plan" with a precise report format; the known-sites list is explicit. ✓

**Type consistency:**
- `ThrottledMixValue` API (`begin(with:)`, `update(_:epsilon:)`, `commit()`, `rendered(committed:)`, `isDragging`) declared in Task 2 is used by Tasks 3 and 4 exactly as declared. ✓
- `EngineController.setMix(trackID:, mix:)` signature in Task 1 matches call sites in Tasks 3 and 4. ✓
- `TrackMixSettings` mutation pattern (`var updatedMix = track.mix; updatedMix.level = …`) relies on `mix` being a mutable struct with `level` / `pan` stored properties, which is already true per `Sources/Document/TrackMixSettings.swift`. ✓

**Risks:**
- **Discarding intermediate values on drag end:** the document only records the final value; undo collapses to one step per gesture. Stated as intentional in "Deliberately deferred".
- **A drag that is cancelled (window loses focus mid-drag):** SwiftUI fires neither `onEnded` nor `onEditingChanged(false)` on all cancellation paths. If `levelValue.liveValue` remains non-nil, the UI will continue to show the live value but the document will never commit. To defend: wire a `.onDisappear` that calls `handleLevelEnded()` / `handlePanEnded()` to flush a pending value. Worth adding to Task 3 Step 2 and Task 4 Step 2 as a one-line guard — concrete form:

```swift
.onDisappear {
    if let final = levelValue.commit() { track.mix.level = final }
    if let final = panValue.commit() { track.mix.pan = final }
}
```

Include this guard on the channel-strip top-level `VStack` / `HStack`.

- **Main-thread-only access to `ThrottledMixValue`:** the helper is `@MainActor`. SwiftUI bindings run on main; no cross-thread access. ✓
- **Engine-side race still present:** the throttle collapses the practical repro window but does not fix the underlying `currentDocumentModel` / `currentLayerSnapshot` race. Stated up front in "Deliberately deferred". Any future plan that routes high-frequency events through `apply(documentModel:)` should first land the race fix.
