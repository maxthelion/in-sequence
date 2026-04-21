# Delta-Based `EngineController.apply` — Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `EngineController.apply(documentModel:)` inherently cheap. Today a fader drag, a name edit, or any small document mutation runs the full apply path — iterating every track, reapplying routes, computing `pipelineShape`, potentially rebuilding the pipeline, and touching every per-track runtime under an overly broad lock window. This plan replaces the "compare, then sync everything" pattern with a typed delta taxonomy: each mutation emits a `ProjectDelta`, dispatched to a handler whose cost is proportional to **what actually changed**, not the size of the document.

**Architecture:** Three layers, narrow and composable:

1. **`ProjectDelta` (value type)** — an enumeration describing a single meaningful change to the project state the engine cares about. Cheap to produce, cheap to pattern-match on.
2. **`Project.deltas(from:)`** — a pure, allocation-minimal diff that produces `[ProjectDelta]` by comparing two `Project` snapshots field by field. O(fields) with O(n) for ordered collections where order matters.
3. **`EngineController.apply(deltas:)`** — a dispatcher that routes each delta to a dedicated handler. `apply(documentModel:)` becomes `let deltas = documentModel.deltas(from: currentDocumentModel); apply(deltas: deltas); currentDocumentModel = documentModel`. In Phase 1, only `trackMixChanged` and `selectedTrackChanged` get dedicated handlers. Every other delta falls back to `.coarseResync`, which runs the existing broad sync path (`syncTrackParams`, `syncMidiOutputs`, `syncAudioOutputs`, plus pipeline rebuild checks) so migration can stay staged and reviewable.

This builds directly on the already-landed mixer-fader throttle work (`v0.0.24-mixer-fader-throttle`). That fix reduced how often `apply(documentModel:)` is called from live fader drags; this plan reduces how much each remaining call costs. Together they put the engine update path on a sustainable footing.

**Tech Stack:** Swift 5.9+, OSLog signposts for timing, XCTest. No new dependencies.

**Parent context:** The 2026-04-21 mixer-fader audit (transcript) showed that `apply(documentModel:)` has unsynchronized writes (`currentDocumentModel`, `currentLayerSnapshot`) and a broad sync cost that grows with document size. Throttling the UI removed the most obvious per-frame storm; this plan addresses the remaining structural cost in the apply path itself.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Run `xcodegen generate` after creating any new files under `Sources/` or `Tests/`.

**Status:** Not started. Tag `v0.0.25-engine-apply-deltas` at completion.

**Depends on:** `v0.0.24-mixer-fader-throttle` on current `main`.

**Scope decision (explicit):**

- **In scope (Phase 1):** `ProjectDelta` + diff + dispatch skeleton. Dedicated handlers are implemented only for `trackMixChanged` and `selectedTrackChanged`. All other delta categories are emitted by the diff but routed through `.coarseResync`, which reuses the existing broad sync path as-is.
- **Deferred to a follow-up plan (Phase 2):** per-delta handlers for `trackDestinationChanged`, `tracksInsertedOrRemoved`, `routesChanged`, `patternBanksChanged`, `phrasesChanged`, `clipPoolChanged`, `layersChanged`, `trackGroupsChanged`. Their diff entries exist in Phase 1, but they all route to `.coarseResync` for now. The infra is there; the migration is staged task-by-task so each change is small, reviewable, and independently measurable.
- **Out of scope (logged for another plan):** fixing the unsynchronized `currentDocumentModel` + `currentLayerSnapshot` races. Phase 1 intentionally keeps the existing locking shape; the delta approach narrows the race window but does not close it. This remains a residual correctness risk until the race-fix plan lands.

---

## File Structure

```
Sources/Document/
  ProjectDelta.swift                              # NEW — enum ProjectDelta + minor helper types
  Project+Diff.swift                              # NEW — Project.deltas(from:) implementation

Sources/Engine/
  EngineController.swift                          # MODIFIED — apply(documentModel:) delegates to apply(deltas:); new handlers
    EngineControllerSignpost.swift                  # NEW — OSLog signpost helper for measuring apply + per-handler durations (optional in Phase 1 if kept tiny)

Tests/SequencerAITests/
  Document/
    ProjectDeltaDiffTests.swift                   # NEW — covers diff coverage per delta type
  Engine/
    EngineControllerDeltaDispatchTests.swift      # NEW — verifies mix delta stays scoped and coarse resync fallback still works
```

---

## Task 1: `ProjectDelta` taxonomy

Define an enum that covers every engine-relevant change. Precise granularity now saves migration work later.

**Files:**
- Create: `Sources/Document/ProjectDelta.swift`
- Test: none in this task — exercised through `Project.deltas(from:)` tests in Task 2.

- [ ] **Step 1: Create `ProjectDelta`**

Write `Sources/Document/ProjectDelta.swift`:

```swift
import Foundation

/// A minimal description of a meaningful change to a `Project` from the
/// engine's point of view. Produced by `Project.deltas(from:)`. Each case
/// carries the minimum information the corresponding `EngineController`
/// handler needs so the handler can run without re-reading the whole
/// document snapshot.
enum ProjectDelta: Equatable {
    // Hot-path deltas — Phase 1 gets dedicated handlers.
    case trackMixChanged(trackID: UUID, mix: TrackMixSettings)
    case selectedTrackChanged(trackID: UUID)

    // Cold-path deltas — Phase 1 routes these to `.coarseResync`. Each will
    // get its own handler in a follow-up plan; the enum cases are declared
    // here so the diff can produce them and the dispatch switch is
    // exhaustive from day one.
    case trackDestinationChanged(trackID: UUID, destination: Destination)
    case trackParameterChanged(trackID: UUID)    // pitches / stepPattern / velocity / gateLength / name / trackType / groupID
    case tracksInsertedOrRemoved                 // any change to the set of track IDs
    case trackGroupsChanged
    case routesChanged
    case patternBanksChanged
    case phrasesChanged
    case clipPoolChanged
    case layersChanged

    /// Escape hatch used for any difference the diff is not yet taught to
    /// categorise, or when the version field itself bumps. The dispatcher's
    /// handler calls the existing broad sync implementation. Expected to
    /// approach zero frequency as Phase 2 migrates each cold-path case.
    case coarseResync
}

extension ProjectDelta {
    /// Stable tag for signpost logging + metrics. Keep short — these strings
    /// land in OSLog signpost names.
    var signpostTag: StaticString {
        switch self {
        case .trackMixChanged: return "mix"
        case .selectedTrackChanged: return "selTrack"
        case .trackDestinationChanged: return "trkDst"
        case .trackParameterChanged: return "trkPrm"
        case .tracksInsertedOrRemoved: return "trkSet"
        case .trackGroupsChanged: return "grpSet"
        case .routesChanged: return "routes"
        case .patternBanksChanged: return "banks"
        case .phrasesChanged: return "phrases"
        case .clipPoolChanged: return "clips"
        case .layersChanged: return "layers"
        case .coarseResync: return "coarse"
        }
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
git add Sources/Document/ProjectDelta.swift project.yml
git commit -m "feat(document): ProjectDelta taxonomy for engine-relevant project changes"
```

---

## Task 2: `Project.deltas(from:)` — the diff

Produces the smallest `[ProjectDelta]` that captures every engine-relevant difference between two `Project` snapshots. Allocation-minimal. No mutation.

**Files:**
- Create: `Sources/Document/Project+Diff.swift`
- Test: `Tests/SequencerAITests/Document/ProjectDeltaDiffTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Document/ProjectDeltaDiffTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectDeltaDiffTests: XCTestCase {
    func test_identical_projects_produce_no_deltas() {
        let project = Project.empty
        XCTAssertTrue(project.deltas(from: project).isEmpty)
    }

    func test_mix_level_change_produces_only_trackMixChanged() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].mix.level = 0.5

        let deltas = after.deltas(from: before)
        XCTAssertEqual(deltas, [.trackMixChanged(trackID: trackID, mix: after.selectedTrack.mix)])
    }

    func test_mix_pan_change_produces_only_trackMixChanged() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].mix.pan = -0.75

        let deltas = after.deltas(from: before)
        XCTAssertEqual(deltas, [.trackMixChanged(trackID: trackID, mix: after.selectedTrack.mix)])
    }

    func test_mute_change_produces_trackMixChanged() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].mix.isMuted = true

        let deltas = after.deltas(from: before)
        XCTAssertEqual(deltas, [.trackMixChanged(trackID: trackID, mix: after.selectedTrack.mix)])
    }

    func test_selected_track_change_produces_selectedTrackChanged() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        before.appendTrack(trackType: .monoMelodic)
        let firstID = before.tracks.first!.id
        var after = before
        after.selectedTrackID = firstID

        let deltas = after.deltas(from: before)
        XCTAssertTrue(deltas.contains(.selectedTrackChanged(trackID: firstID)), "got \(deltas)")
    }

    func test_destination_change_produces_trackDestinationChanged() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].destination = .midi(port: .sequencerAIOut, channel: 5, noteOffset: 0)

        let deltas = after.deltas(from: before)
        XCTAssertTrue(deltas.contains(.trackDestinationChanged(trackID: trackID, destination: after.selectedTrack.destination)), "got \(deltas)")
    }

    func test_track_insertion_produces_tracksInsertedOrRemoved() {
        var before = Project.empty
        var after = before
        after.appendTrack(trackType: .monoMelodic)

        let deltas = after.deltas(from: before)
        XCTAssertTrue(deltas.contains(.tracksInsertedOrRemoved), "got \(deltas)")
    }

    func test_mix_change_on_one_track_does_not_affect_unchanged_track() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        before.appendTrack(trackType: .monoMelodic)
        let secondID = before.tracks.last!.id
        var after = before
        after.tracks[after.tracks.count - 1].mix.level = 0.3

        let deltas = after.deltas(from: before)
        XCTAssertEqual(deltas, [.trackMixChanged(trackID: secondID, mix: after.tracks.last!.mix)])
    }

    func test_simultaneous_mix_and_destination_change_produces_both_deltas() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].mix.level = 0.4
        after.tracks[after.selectedTrackIndex].destination = .midi(port: .sequencerAIOut, channel: 2, noteOffset: 0)

        let deltas = Set(after.deltas(from: before))
        XCTAssertTrue(deltas.contains(.trackMixChanged(trackID: trackID, mix: after.selectedTrack.mix)))
        XCTAssertTrue(deltas.contains(.trackDestinationChanged(trackID: trackID, destination: after.selectedTrack.destination)))
    }

    func test_diff_from_empty_to_populated_project_is_coarse_or_exhaustive() {
        // Going from empty to a fully seeded project is a cold-path case.
        // The diff is allowed to emit `.tracksInsertedOrRemoved` + per-field
        // deltas, OR a single `.coarseResync`. Either is correct.
        let before = Project.empty
        var after = before
        _ = after.addDrumKit(.kit808)
        let deltas = after.deltas(from: before)
        XCTAssertFalse(deltas.isEmpty, "non-trivial project diff must emit at least one delta")
    }
}
```

If `Project.empty.selectedTrack` is invalid (e.g. `Project.empty.tracks` is empty), update each test to call `appendTrack` first (the existing tests already do this for their scenarios). If `TrackMixSettings` doesn't conform to `Equatable` yet, the `[.trackMixChanged(...)]` comparison will not compile — add `Equatable` conformance to `TrackMixSettings` in `Sources/Document/TrackMixSettings.swift` (it's a value type; synthesized conformance should be a one-line `Equatable` addition).

- [ ] **Step 2: Run the tests — expect compile failure**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectDeltaDiffTests \
  2>&1 | tail -25
```

Expected: compile failure — `Project.deltas(from:)` does not exist.

- [ ] **Step 3: Implement `Project.deltas(from:)`**

Create `Sources/Document/Project+Diff.swift`:

```swift
import Foundation

extension Project {
    /// Compute the minimal `[ProjectDelta]` that describes what changed
    /// between `old` and `self`. Order of returned deltas is deterministic:
    /// top-level fields first, then per-track deltas in track-array order.
    /// A purely structural or unknown difference collapses to
    /// `.coarseResync` rather than emitting an empty or misleading list —
    /// this keeps `apply(deltas:)` correct even when the diff misses a case.
    func deltas(from old: Project) -> [ProjectDelta] {
        if self == old { return [] }

        var deltas: [ProjectDelta] = []

        // Top-level scalar / ID fields.
        if self.selectedTrackID != old.selectedTrackID {
            deltas.append(.selectedTrackChanged(trackID: self.selectedTrackID))
        }

        // Track set membership.
        let oldIDs = Set(old.tracks.map(\.id))
        let newIDs = Set(self.tracks.map(\.id))
        if oldIDs != newIDs {
            deltas.append(.tracksInsertedOrRemoved)
        }

        // Per-track field diffs. Only tracks present in BOTH snapshots get
        // per-field deltas; additions/removals are subsumed by
        // `.tracksInsertedOrRemoved` above.
        let oldByID = Dictionary(uniqueKeysWithValues: old.tracks.map { ($0.id, $0) })
        for newTrack in self.tracks {
            guard let oldTrack = oldByID[newTrack.id] else { continue }

            if newTrack.mix != oldTrack.mix {
                deltas.append(.trackMixChanged(trackID: newTrack.id, mix: newTrack.mix))
            }
            if newTrack.destination != oldTrack.destination {
                deltas.append(.trackDestinationChanged(trackID: newTrack.id, destination: newTrack.destination))
            }
            if newTrack.pitches != oldTrack.pitches
                || newTrack.stepPattern != oldTrack.stepPattern
                || newTrack.velocity != oldTrack.velocity
                || newTrack.gateLength != oldTrack.gateLength
                || newTrack.name != oldTrack.name
                || newTrack.trackType != oldTrack.trackType
                || newTrack.groupID != oldTrack.groupID
            {
                deltas.append(.trackParameterChanged(trackID: newTrack.id))
            }
        }

        // Cold-path top-level collections. Emit a single delta per field;
        // handlers call into the existing broad sync as their implementation.
        if self.trackGroups != old.trackGroups {
            deltas.append(.trackGroupsChanged)
        }
        if self.routes != old.routes {
            deltas.append(.routesChanged)
        }
        if self.patternBanks != old.patternBanks {
            deltas.append(.patternBanksChanged)
        }
        if self.phrases != old.phrases || self.selectedPhraseID != old.selectedPhraseID {
            deltas.append(.phrasesChanged)
        }
        if self.clipPool != old.clipPool {
            deltas.append(.clipPoolChanged)
        }
        if self.layers != old.layers {
            deltas.append(.layersChanged)
        }

        // Safety net: if we detected a difference (`self != old`) but produced
        // no deltas, something in the `Project` structure is not being
        // considered. Emit `.coarseResync` so the engine re-syncs defensively.
        if deltas.isEmpty {
            deltas.append(.coarseResync)
        }

        return deltas
    }
}
```

If any top-level collection names on `Project` differ from the above (`trackGroups`, `routes`, `patternBanks`, `phrases`, `selectedPhraseID`, `clipPool`, `layers`) — confirm by reading `Sources/Document/Project.swift`. Update field references to match the actual property names. The test `test_identical_projects_produce_no_deltas` + the `Project: Equatable` check at the top gives a fast signal that coverage is exhaustive.

`Project` must be `Equatable` for the `self == old` short-circuit. If it isn't yet, add synthesized conformance where it's declared.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectDeltaDiffTests \
  2>&1 | tail -15
```

Expected: all tests pass.

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
git add Sources/Document/Project+Diff.swift Tests/SequencerAITests/Document/ProjectDeltaDiffTests.swift project.yml
git commit -m "feat(document): Project.deltas(from:) — typed diff emits ProjectDelta list"
```

---

## Task 3: OSLog signpost helper

A tiny helper for wrapping the apply path and each handler in OSLog signposts so performance is measurable from Instruments / Console. Zero runtime cost when signposts are not being recorded.

**Files:**
- Create: `Sources/Engine/EngineControllerSignpost.swift`

- [ ] **Step 1: Create the helper**

Write `Sources/Engine/EngineControllerSignpost.swift`:

```swift
import Foundation
import OSLog

enum EngineSignpost {
    static let log = OSLog(subsystem: "ai.sequencer.SequencerAI", category: .pointsOfInterest)

    @inlinable
    static func interval<T>(_ name: StaticString, _ work: () -> T) -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return work()
    }

    @inlinable
    static func event(_ name: StaticString, _ message: String) {
        os_signpost(.event, log: log, name: name, "%{public}s", message)
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
git add Sources/Engine/EngineControllerSignpost.swift project.yml
git commit -m "feat(engine): OSLog signpost helper for engine apply measurements"
```

---

## Task 4: `EngineController.apply(deltas:)` dispatcher + hot-path handlers + `apply(documentModel:)` migration

Refactor `EngineController.apply(documentModel:)` into `deltas-based` dispatch. Phase 1 implements the hot-path handlers inline; all other deltas route to a `.coarseResync` fallback that calls the existing broad sync logic unchanged.

**Files:**
- Modify: `Sources/Engine/EngineController.swift`
- Test: `Tests/SequencerAITests/Engine/EngineControllerDeltaDispatchTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Engine/EngineControllerDeltaDispatchTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class EngineControllerDeltaDispatchTests: XCTestCase {
    func test_pure_mix_change_dispatches_only_setMix_no_coarse_resync() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        _ = project.addDrumKit(.kit808)
        controller.apply(documentModel: project)

        guard let sampleTrackID = project.tracks.last(where: {
            if case .sample = $0.destination { return true }
            return false
        })?.id else {
            throw XCTSkip("no .sample destination produced in this environment")
        }

        let countBeforeMixChange = mock.calls.count

        var updated = project
        if let idx = updated.tracks.firstIndex(where: { $0.id == sampleTrackID }) {
            updated.tracks[idx].mix.level = 0.33
        }
        controller.apply(documentModel: updated)

        let newCalls = Array(mock.calls.dropFirst(countBeforeMixChange))
        let setMixCount = newCalls.filter { call in
            if case .setTrackMix = call { return true }
            return false
        }.count

        // One setTrackMix call for the changed track, and NO other calls —
        // no prepareTrack, no removeTrack, no play, no stop. That's the
        // Phase 1 acceptance criterion for the hot-path.
        XCTAssertEqual(setMixCount, 1, "expected exactly 1 setTrackMix for the mix change; got \(newCalls)")
        for call in newCalls {
            switch call {
            case .setTrackMix:
                continue
            case .prepareTrack, .removeTrack, .play, .audition, .stopAudition, .start, .stop:
                XCTFail("unexpected call on pure mix change: \(call)")
            }
        }
    }

    func test_pure_mix_change_does_not_trigger_coarse_resync_signpost() {
        // We cannot inspect OSLog output from a unit test. Instead, we expose
        // a test-only counter on EngineController that increments every time
        // the `.coarseResync` branch fires. Verify it stays at zero for a
        // pure-mix-change apply.
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        _ = project.addDrumKit(.kit808)
        controller.apply(documentModel: project)

        let coarseBefore = controller.debug_coarseResyncCount
        var updated = project
        updated.tracks[updated.tracks.count - 1].mix.level = 0.5
        controller.apply(documentModel: updated)

        XCTAssertEqual(
            controller.debug_coarseResyncCount - coarseBefore, 0,
            "mix change must not trigger coarseResync"
        )
    }

    func test_destination_change_triggers_coarse_resync_in_phase1() {
        // In Phase 1 `.trackDestinationChanged` routes to coarseResync.
        // This test pins that expectation so Phase 2 can flip it.
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        controller.apply(documentModel: project)

        let coarseBefore = controller.debug_coarseResyncCount
        var updated = project
        updated.tracks[updated.selectedTrackIndex].destination = .midi(port: .sequencerAIOut, channel: 3, noteOffset: 0)
        controller.apply(documentModel: updated)

        XCTAssertEqual(
            controller.debug_coarseResyncCount - coarseBefore, 1,
            "phase 1: destination change should trigger one coarseResync"
        )
    }
}
```

- [ ] **Step 2: Run the tests — expect failure**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerDeltaDispatchTests \
  2>&1 | tail -25
```

Expected: compile failure — `controller.debug_coarseResyncCount` does not exist.

- [ ] **Step 3: Refactor `apply(documentModel:)` into delta dispatch**

In `Sources/Engine/EngineController.swift`, replace the body of `apply(documentModel:)` (currently lines 192–211) with:

```swift
    func apply(documentModel: Project) {
        EngineSignpost.interval("apply") {
            let deltas = documentModel.deltas(from: currentDocumentModel)
            let previous = currentDocumentModel
            currentDocumentModel = documentModel
            apply(deltas: deltas, previous: previous, next: documentModel)
        }
    }
```

Note: `currentDocumentModel` is written here unlocked, same as before. Closing the race is out of scope for this plan (stated up front). The dispatch pattern does not make the race worse — it uses the same single-writer model.

Add the dispatcher and handlers below `apply(documentModel:)`:

```swift
    private var coarseResyncCounter: Int = 0
    /// Test-only accessor; do not read from production code.
    var debug_coarseResyncCount: Int { coarseResyncCounter }

    private func apply(deltas: [ProjectDelta], previous: Project, next: Project) {
        for delta in deltas {
            EngineSignpost.interval(delta.signpostTag) {
                handle(delta: delta, previous: previous, next: next)
            }
        }
    }

    private func handle(delta: ProjectDelta, previous: Project, next: Project) {
        switch delta {
        case let .trackMixChanged(trackID, mix):
            setMix(trackID: trackID, mix: mix)

        case let .selectedTrackChanged(trackID):
            selectedOutput = Self.effectiveDestination(for: trackID, in: next).destination.kind
            if let track = next.tracks.first(where: { $0.id == trackID }) {
                currentTrackMix = track.mix
            }

        case .trackDestinationChanged,
             .trackParameterChanged,
             .tracksInsertedOrRemoved,
             .trackGroupsChanged,
             .routesChanged,
             .patternBanksChanged,
             .phrasesChanged,
             .clipPoolChanged,
             .layersChanged,
             .coarseResync:
            coarseResync(previous: previous, next: next)
        }
    }

    /// Fallback that runs the pre-delta broad sync logic for every cold-path
    /// delta. Phase 2 replaces the call sites one delta at a time; when all
    /// cold-path cases have dedicated handlers, this method can be deleted.
    private func coarseResync(previous: Project, next: Project) {
        coarseResyncCounter += 1

        flushDetachedMIDINoteOffs(from: previous, to: next, now: ProcessInfo.processInfo.systemUptime)
        selectedOutput = Self.effectiveDestination(for: next.selectedTrack.id, in: next).destination.kind
        currentTrackMix = next.selectedTrack.mix
        router.applyRoutesSnapshot(next.routes)

        do {
            if withStateLock({ pipelineShape != Self.pipelineShape(for: next) || executor == nil }) {
                try buildPipeline(for: next)
            } else {
                syncTrackParams(for: next)
                syncMidiOutputs(for: next)
                syncAudioOutputs(for: next)
            }
        } catch {
            NSLog("EngineController coarseResync failed: \(error)")
        }
    }
```

Important invariants:

- `apply(deltas:previous:next:)` runs deltas in the order the diff produced them. Since `coarseResync` is itself idempotent (runs the full sync), multiple cold-path deltas in the same apply call will each trigger it. To avoid redundant work, de-dupe: in Phase 1, if any cold-path delta is present, collapse them into a single `coarseResync` call.

Adjust `apply(deltas:previous:next:)` to do the de-dupe:

```swift
    private func apply(deltas: [ProjectDelta], previous: Project, next: Project) {
        var sawCoarsePath = false
        for delta in deltas {
            EngineSignpost.interval(delta.signpostTag) {
                switch delta {
                case let .trackMixChanged(trackID, mix):
                    setMix(trackID: trackID, mix: mix)

                case let .selectedTrackChanged(trackID):
                    selectedOutput = Self.effectiveDestination(for: trackID, in: next).destination.kind
                    if let track = next.tracks.first(where: { $0.id == trackID }) {
                        currentTrackMix = track.mix
                    }

                case .trackDestinationChanged,
                     .trackParameterChanged,
                     .tracksInsertedOrRemoved,
                     .trackGroupsChanged,
                     .routesChanged,
                     .patternBanksChanged,
                     .phrasesChanged,
                     .clipPoolChanged,
                     .layersChanged,
                     .coarseResync:
                    sawCoarsePath = true
                }
            }
        }
        if sawCoarsePath {
            EngineSignpost.interval("coarse") {
                coarseResync(previous: previous, next: next)
            }
        }
    }
```

De-dupe means: a fader drag + a track-added change in the same apply still runs exactly one `coarseResync`. Hot-path deltas (mix, selectedTrack) still run inline.

Keep the existing `setMix(trackID:, mix:)` method from the other plan (`docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md`). If that plan has not landed yet, implement a minimal version here — the inline implementation should not touch `currentDocumentModel` and should use `withStateLock` only for the dictionary lookup:

```swift
    func setMix(trackID: UUID, mix: TrackMixSettings) {
        let host = withStateLock { audioOutputsByTrackID[trackID] }
        host?.setMix(mix)
        if let track = currentDocumentModel.tracks.first(where: { $0.id == trackID }),
           case .sample = track.destination
        {
            sampleEngine.setTrackMix(
                trackID: trackID,
                level: mix.clampedLevel,
                pan: mix.clampedPan
            )
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineControllerDeltaDispatchTests \
  2>&1 | tail -20
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

Expected: all tests pass. The existing `apply(documentModel:)` behavior is preserved for every cold-path scenario because `coarseResync` calls the identical sequence that the old method did.

- [ ] **Step 6: Commit**

```bash
git add Sources/Engine/EngineController.swift Tests/SequencerAITests/Engine/EngineControllerDeltaDispatchTests.swift
git commit -m "feat(engine): apply(documentModel:) dispatches ProjectDelta list; mix change is O(1)"
```

---

## Task 5: Perf measurement — baseline + post-change numbers

Quantify the improvement. Without numbers, we don't know whether the refactor actually paid off, or whether the hot path is cheap enough to handle unthrottled fader drags.

**Files:**
- No production changes.
- Create: `Tests/SequencerAITests/Engine/EngineApplyPerfTests.swift`

- [ ] **Step 1: Write the perf test**

Create `Tests/SequencerAITests/Engine/EngineApplyPerfTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

/// Measures the per-call cost of `EngineController.apply(documentModel:)` on
/// a project with a modest number of tracks. The mix-change scenario is the
/// hot path we explicitly tuned; the assertion is qualitative (mix change
/// should be at least an order of magnitude cheaper than a full resync) and
/// robust to absolute-time variation across machines.
final class EngineApplyPerfTests: XCTestCase {
    func test_mix_change_is_meaningfully_cheaper_than_coarse_resync() {
        let mock = MockSamplePlaybackSink()
        let controller = EngineController(sampleEngine: mock)

        var project = Project.empty
        for _ in 0..<8 {
            project.appendTrack(trackType: .monoMelodic)
        }
        _ = project.addDrumKit(.kit808)
        controller.apply(documentModel: project)  // prime

        // Measure a single mix change (hot path).
        var mutated = project
        mutated.tracks[0].mix.level = 0.5

        let mixDuration = measureBlockMillis {
            for _ in 0..<100 {
                controller.apply(documentModel: mutated)
                mutated.tracks[0].mix.level += 0.001  // keep changing so diff is non-empty
            }
        }

        // Measure a destination change, which currently routes to coarseResync.
        var resyncBase = project
        let firstMonoID = resyncBase.tracks[0].id

        let resyncDuration = measureBlockMillis {
            for i in 0..<100 {
                var mutated = resyncBase
                let channel = UInt8(i % 16)
                mutated.tracks[0].destination = .midi(port: .sequencerAIOut, channel: channel, noteOffset: 0)
                controller.apply(documentModel: mutated)
                resyncBase = mutated
            }
        }

        _ = firstMonoID
        NSLog("[EngineApplyPerfTests] mix=\(mixDuration)ms resync=\(resyncDuration)ms ratio=\(resyncDuration / max(mixDuration, 0.0001))")

        // Ratio should be >= 5x. On a modest-sized project the resync is 1–2
        // orders of magnitude slower in practice. 5x is a loose floor that
        // passes robustly across CI machines while still flagging a
        // regression if the hot path gets heavy.
        XCTAssertGreaterThan(resyncDuration / max(mixDuration, 0.0001), 5.0,
            "mix path is supposed to be >= 5x cheaper than coarseResync; mix=\(mixDuration)ms resync=\(resyncDuration)ms")
    }

    private func measureBlockMillis(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000.0
    }
}
```

This test is qualitative on purpose: absolute-time assertions are flaky on CI. The ratio assertion is robust — if the mix handler regressed to doing a coarseResync-equivalent, the ratio would collapse to ~1 and the test would fail cleanly.

- [ ] **Step 2: Run the test**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/EngineApplyPerfTests \
  2>&1 | tail -20
```

Expected: test passes. Record the actual `mix=…ms resync=…ms ratio=…` line from the log in the commit message below so the numbers are captured in history.

- [ ] **Step 3: Commit**

```bash
git add Tests/SequencerAITests/Engine/EngineApplyPerfTests.swift
# Replace <NUMBERS> with the actual mix/resync ratio from the test log.
git commit -m "test(engine): pin mix-change apply to be >= 5x cheaper than coarseResync

Observed on dev machine: <NUMBERS>"
```

---

## Task 6: Manual smoke + plan status + tag

**Files:** none beyond doc updates

- [ ] **Step 1: Build and open the app**

```bash
./scripts/open-latest-build.sh
```

- [ ] **Step 2: Verify the hot path is cheap — Instruments observation**

- Open Instruments, create a blank template, add the **os_signpost** instrument, target the SequencerAI process.
- In the app: open a document, add a drum kit, press play.
- Start the recording. Drag a level fader for ~5 seconds.
- Stop the recording. In the signpost timeline, filter by subsystem `ai.sequencer.SequencerAI`. You should see many `apply` signposts, each containing a `mix` child signpost and **no `coarse` signpost**.
- Note the per-`apply` duration. Expected: sub-millisecond on a modest project. Previously: high-single-digit ms on every fader tick due to `coarseResync` every time.
- Screenshot the timeline + notable durations and drop them in the PR description or commit body if landing via PR.

- [ ] **Step 3: Verify correctness has not regressed**

- Open a document, add a drum kit, play.
- Change a track's destination (AU → Sampler → MIDI). Expected: audio correctly follows the destination change. Behind the scenes this triggers a `coarseResync`; the behavior should match pre-delta.
- Change BPM. Expected: tempo follows.
- Add a second drum kit while playing. Expected: the new tracks come alive on the next tick, no stray notes, audio is stable. (This is also covered by the per-track voice pool plan; confirm both plans compose cleanly.)
- Mute / unmute tracks. Expected: immediate silence / return, no glitches.

- [ ] **Step 4: Flip this plan's status + tag**

Edit this plan: replace `**Status:** Not started.` with:

```
**Status:** ✅ Phase 1 completed 2026-04-21. Tag `v0.0.25-engine-apply-deltas`. Phase 2 (per-delta cold-path handlers) tracked in a follow-up plan. Verified via focused ProjectDeltaDiffTests, EngineControllerDeltaDispatchTests, EngineApplyPerfTests, full suite, and Instruments signpost smoke.
```

Commit + tag:

```bash
git add docs/plans/2026-04-21-engine-apply-delta-based-performance.md
git commit -m "docs(plan): mark engine-apply-delta-based phase 1 completed"
git tag -a v0.0.25-engine-apply-deltas -m "Phase 1: apply(documentModel:) dispatches ProjectDelta; hot path (mix) O(1)"
```

- [ ] **Step 5: Dispatch `wiki-maintainer` to document the new invariants**

Brief:
- Diff range: `<previous-tag>..HEAD`.
- Plan: `docs/plans/2026-04-21-engine-apply-delta-based-performance.md`.
- Task: document (a) `ProjectDelta` taxonomy and the hot-path / cold-path split, (b) the invariant that every new `Project` field must be considered in `Project.deltas(from:)` or else the diff collapses to `.coarseResync`, (c) that high-frequency UI should still prefer scoped methods (e.g. `setMix`) over `apply(documentModel:)` even with the delta dispatch, because scoped methods skip the diff cost entirely. Cross-link to the mixer-fader throttle plan.
- Commit under `docs(wiki):` prefix.

---

## Phase 2 — follow-up (scope sketch, to land as its own plan)

After Phase 1 is in, cold-path deltas get dedicated handlers one by one. Suggested landing order:

1. **`trackDestinationChanged`** — single-track destination write path; no pipeline rebuild unless destination *kind* changes (i.e. pipelineShape changes). Today's `syncAudioOutputs(for:)` already handles per-track setup; factor out a `syncDestination(trackID:, destination:)` that reuses it.
2. **`tracksInsertedOrRemoved`** — partial pipeline build: install hosts / runtimes for added tracks, tear down for removed, leave others untouched.
3. **`trackGroupsChanged`** — recompute `effectiveDestination` cache only for affected tracks.
4. **`routesChanged`** — already factored behind `router.applyRoutesSnapshot`; this one is close to free.
5. **`patternBanksChanged`**, **`phrasesChanged`**, **`clipPoolChanged`**, **`layersChanged`** — generator-side state; may need per-delta handlers that patch `generatedEvaluationStatesByTrackID` surgically.
6. **`trackParameterChanged`** — most of these (stepPattern, pitches, velocity) only affect the running generator's input on the next tick; no engine graph mutation needed.

Phase 2 plan should also finally close the `currentDocumentModel` / `currentLayerSnapshot` race now that every delta handler is small and locally reasonable.

---

## Self-Review

**Scope discipline:** Phase 1 is explicit about what it delivers (infrastructure + hot-path) and what it defers (cold-path handlers, race fix). The plan does not promise a full-migration rewrite in one change. ✓

**Placeholder scan:** no TBDs. Every code block is concrete. The Task 5 commit message placeholder (`<NUMBERS>`) is an instruction to fill in actual measurements at commit time, not an unfinished spec. ✓

**Type consistency:**
- `ProjectDelta` cases declared in Task 1 match the `deltas(from:)` producer in Task 2 and the `handle(delta:previous:next:)` dispatcher in Task 4. The `switch` in Task 4 is exhaustive over every case defined in Task 1. ✓
- `Project.deltas(from:)` signature matches its call site in Task 4. ✓
- `setMix(trackID:, mix:)` is shared with the mixer-fader throttle plan; if that plan has not landed, Task 4 includes the minimal inline implementation that matches the same signature. ✓

**Risks:**
- **Missing `Project` field in the diff:** any new field on `Project` must be added to `deltas(from:)` or else `self != old` is true but no deltas are produced, tripping the `.coarseResync` safety net. That's a correctness-preserving fallback — performance degrades to the old path, but behavior does not regress. Wiki update in Task 6 Step 5 calls this out for future maintainers.
- **Coarse-resync de-dupe assumption:** the dispatcher runs at most one coarseResync per apply, even if several cold-path deltas were produced. Correct because coarseResync is idempotent (it reads `next` end-to-end). Phase 2 removes the dedupe as individual handlers take over.
- **Performance test variance on CI:** Task 5's ratio-based assertion (`>= 5x`) is robust to absolute-time noise. If CI still flakes, widen to `>= 3x` — the qualitative point (hot path is an order-of-magnitude cheaper) survives.
- **Race window unchanged:** `currentDocumentModel = documentModel` is still a single unlocked main-thread write. The window is shorter (we're not doing the full sync after it) but not closed. Explicitly deferred; Phase 2 plan handles it.
- **`apply(deltas:)` called with externally-produced deltas:** the dispatcher is currently `private`, so this cannot happen from outside. If a future plan wants to route typed deltas directly (e.g. a fader calling `apply(deltas: [.trackMixChanged(...)])`), make it `internal` — it already handles the hot path correctly.
