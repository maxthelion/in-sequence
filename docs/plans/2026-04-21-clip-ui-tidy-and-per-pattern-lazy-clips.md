# Clip UI Tidy + Per-Pattern Lazy Clips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove two confusing controls from the Track workspace's Clip panel (the clip dropdown and the comma-separated pitches text field), fix the "every pattern shares one clip" default, and allocate per-pattern clips lazily on first step toggle. Pattern palette lights up per slot based on whether that slot's clip has stored content.

**Architecture:** Five file edits + one new helper. No engine changes, no save-format changes. New `Project.ensureClipForCurrentPattern(trackID:)` is called from the step-grid gesture handler before any mutation. `TrackPatternBank.default(for:initialClipID:)` seeds only slot 0 with the initial clip; slots 1–15 start with `clipID = nil`. `TrackPatternSlotPalette` switches its occupancy predicate from "is-scheduled-in-some-phrase" to "has-stored-clip-with-non-empty-content".

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest.

**Parent spec:** `docs/specs/2026-04-21-clip-ui-tidy-and-per-pattern-lazy-clips-design.md`.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. After creating new test files, run `xcodegen generate` before building or testing.

**Status:** Not started. Tag `v0.0.26-clip-ui-tidy` at completion.

**Depends on:** nothing on the critical path. Can execute against current `main`. Does NOT depend on the step-pattern/clip model review (`docs/specs/2026-04-21-step-pattern-clip-model-review-design.md`); the review can run in parallel.

**Deliberately deferred:**

- Unifying `ClipContent` variants, piano-roll editor, paging for >16 steps, per-clip length changes, per-step chords / micro-timing / fills — all belong to the step-pattern/clip model review and its follow-up implementation plan.
- Save-format migration. Documents saved in the old shared-clip shape continue to decode and render; the lazy behavior only affects newly-created banks.
- Drum-kit seed path changes. `addDrumKit` still seeds every member's slot 0 with a clip; slots 1–15 start empty on drum-kit members exactly as on plain mono tracks.
- User-visible "Clear pattern" / "Delete pattern" actions. Not required to ship the tidy.

---

## File Structure

```
Sources/Document/
  PhraseModel.swift                              # MODIFIED — TrackPatternBank.default seeds only slot 0
  Project+TrackSources.swift                     # MODIFIED — new ensureClipForCurrentPattern(trackID:)
  ClipContent+Empty.swift                        # NEW — clipIsEmpty(_ content: ClipContent) -> Bool

Sources/UI/TrackSource/
  TrackSourceEditorView.swift                    # MODIFIED — remove Clip dropdown + clipIDBinding
  TrackPatternSlotPalette.swift                  # MODIFIED — occupancy = stored content non-empty

Sources/UI/TrackSource/Clip/
  ClipContentPreview.swift                       # MODIFIED — remove pitches TextField

Tests/SequencerAITests/Document/
  TrackPatternBankDefaultSeedingTests.swift      # NEW — slot 0 seeded; slots 1–15 nil
  ProjectEnsureClipForCurrentPatternTests.swift  # NEW — lazy allocation + idempotency
  ClipContentEmptyTests.swift                    # NEW — empty-vs-nonempty predicate
```

The step-grid gesture handler is *also* modified (Task 5) — its exact file/location is identified in that task because the current step-grid edit-write path is not fully traced. The task enumerates all current step-pattern-write sites and adapts each.

---

## Task 1: `clipIsEmpty` helper

Small, pure function. Used by the palette occupancy predicate (Task 6) and by any future UI that needs to reason about clip emptiness.

**Files:**
- Create: `Sources/Document/ClipContent+Empty.swift`
- Test: `Tests/SequencerAITests/Document/ClipContentEmptyTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Document/ClipContentEmptyTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ClipContentEmptyTests: XCTestCase {
    func test_stepSequence_allFalse_isEmpty() {
        let content = ClipContent.stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        XCTAssertTrue(clipIsEmpty(content))
    }

    func test_stepSequence_anyTrue_isNotEmpty() {
        var pattern = Array(repeating: false, count: 16)
        pattern[3] = true
        let content = ClipContent.stepSequence(stepPattern: pattern, pitches: [60])
        XCTAssertFalse(clipIsEmpty(content))
    }

    func test_sliceTriggers_allFalse_isEmpty() {
        let content = ClipContent.sliceTriggers(stepPattern: Array(repeating: false, count: 16), sliceIndexes: [])
        XCTAssertTrue(clipIsEmpty(content))
    }

    func test_sliceTriggers_anyTrue_isNotEmpty() {
        var pattern = Array(repeating: false, count: 16)
        pattern[0] = true
        let content = ClipContent.sliceTriggers(stepPattern: pattern, sliceIndexes: [0])
        XCTAssertFalse(clipIsEmpty(content))
    }

    func test_pianoRoll_emptyNotes_isEmpty() {
        let content = ClipContent.pianoRoll(lengthBars: 1, stepsPerBar: 16, notes: [])
        XCTAssertTrue(clipIsEmpty(content))
    }

    func test_pianoRoll_withNote_isNotEmpty() {
        let note = ClipNote(step: 0, length: 1, pitch: 60, velocity: 100)
        let content = ClipContent.pianoRoll(lengthBars: 1, stepsPerBar: 16, notes: [note])
        XCTAssertFalse(clipIsEmpty(content))
    }
}
```

If `ClipNote`'s initialiser signature differs from the guess above (`step:length:pitch:velocity:`), check `Sources/Document/ClipContent.swift` for the real shape and adjust the test. Run the test — a compile error will point to the exact mismatch.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ClipContentEmptyTests \
  2>&1 | tail -25
```

Expected: compile failure — `clipIsEmpty(_:)` does not exist.

- [ ] **Step 3: Create the helper**

Write `Sources/Document/ClipContent+Empty.swift`:

```swift
import Foundation

/// Returns true when the clip has no stored playable content.
/// Pattern-palette occupancy and "delete if empty" logic should consult this.
func clipIsEmpty(_ content: ClipContent) -> Bool {
    switch content {
    case let .stepSequence(stepPattern, _):
        return stepPattern.allSatisfy { !$0 }
    case let .sliceTriggers(stepPattern, _):
        return stepPattern.allSatisfy { !$0 }
    case let .pianoRoll(_, _, notes):
        return notes.isEmpty
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ClipContentEmptyTests \
  2>&1 | tail -15
```

Expected: six tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/ClipContent+Empty.swift Tests/SequencerAITests/Document/ClipContentEmptyTests.swift project.yml
git commit -m "feat(document): clipIsEmpty helper for pattern-palette occupancy"
```

---

## Task 2: `TrackPatternBank.default` seeds only slot 0

Changes the factory so new banks have slot 0 with a clipID and slots 1–15 with `clipID = nil`. Everything else on `TrackPatternBank` (and on `TrackPatternSlot`) stays the same.

**Files:**
- Modify: `Sources/Document/PhraseModel.swift` (around line 546–556, `TrackPatternBank.default(for:initialClipID:)`)
- Test: `Tests/SequencerAITests/Document/TrackPatternBankDefaultSeedingTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Document/TrackPatternBankDefaultSeedingTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankDefaultSeedingTests: XCTestCase {
    func test_default_with_initialClipID_seeds_only_slot_zero() {
        let track = StepSequenceTrack.default
        let clipID = UUID()
        let bank = TrackPatternBank.default(for: track, initialClipID: clipID)
        XCTAssertEqual(bank.slots.count, 16)
        XCTAssertEqual(bank.slots[0].sourceRef.clipID, clipID, "slot 0 should keep the seeded clipID")
        for index in 1..<16 {
            XCTAssertNil(bank.slots[index].sourceRef.clipID, "slot \(index) should start with nil clipID")
        }
    }

    func test_default_with_nil_initialClipID_has_no_seeded_clips() {
        let track = StepSequenceTrack.default
        let bank = TrackPatternBank.default(for: track, initialClipID: nil)
        for index in 0..<16 {
            XCTAssertNil(bank.slots[index].sourceRef.clipID, "slot \(index) clipID must be nil when no initial clip supplied")
        }
    }

    func test_default_slots_are_clip_mode_with_no_generator() {
        let track = StepSequenceTrack.default
        let bank = TrackPatternBank.default(for: track, initialClipID: UUID())
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip, "every slot should start in .clip mode")
            XCTAssertNil(slot.sourceRef.generatorID, "every slot should start with no attached generator")
        }
        XCTAssertNil(bank.attachedGeneratorID)
    }
}
```

- [ ] **Step 2: Run the tests — expect failure**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankDefaultSeedingTests \
  2>&1 | tail -20
```

Expected: test_default_with_initialClipID_seeds_only_slot_zero fails (every slot currently has the same clipID). test_default_with_nil_initialClipID_has_no_seeded_clips already passes (nil clipID propagates through today). test_default_slots_are_clip_mode_with_no_generator already passes.

- [ ] **Step 3: Update `TrackPatternBank.default`**

In `Sources/Document/PhraseModel.swift`, locate `TrackPatternBank.default(for:initialClipID:)` (around line 546). Replace its body with:

```swift
static func `default`(for track: StepSequenceTrack, initialClipID: UUID?) -> TrackPatternBank {
    let seededRef = SourceRef(mode: .clip, generatorID: nil, clipID: initialClipID)
    let emptyRef = SourceRef(mode: .clip, generatorID: nil, clipID: nil)
    let slots: [TrackPatternSlot] = (0..<slotCount).map { index in
        let sourceRef = index == 0 ? seededRef : emptyRef
        return TrackPatternSlot(slotIndex: index, sourceRef: sourceRef)
    }
    return TrackPatternBank(trackID: track.id, slots: slots, attachedGeneratorID: nil)
}
```

If `TrackPatternSlot`'s initialiser takes other parameters (e.g. a `name:`), match the existing call sites and pass the same default values.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankDefaultSeedingTests \
  2>&1 | tail -15
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -30
```

Expected: all tests pass. If any existing test asserted that every slot's `clipID` is non-nil after `default`, update the assertion to expect `slot 0 == clipID, slots 1..15 == nil`.

**Known risk:** tests under `Tests/SequencerAITests/Document/ProjectAddDrumKitClipTests.swift` and `ProjectAddDrumGroupTests.swift` (if the drum-group modal plan has landed) may inspect specific slots. Their intent is almost certainly to verify slot 0, not slots 1–15 — update the assertions if needed to match the new seeding.

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/PhraseModel.swift Tests/SequencerAITests/Document/TrackPatternBankDefaultSeedingTests.swift
git commit -m "refactor(document): TrackPatternBank.default seeds only slot 0"
```

---

## Task 3: `Project.ensureClipForCurrentPattern(trackID:)`

The lazy-allocation helper. Idempotent. Returns the clipID of the current pattern slot, allocating a fresh clip if none.

**Files:**
- Modify: `Sources/Document/Project+TrackSources.swift`
- Test: `Tests/SequencerAITests/Document/ProjectEnsureClipForCurrentPatternTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Document/ProjectEnsureClipForCurrentPatternTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectEnsureClipForCurrentPatternTests: XCTestCase {
    func test_ensures_clip_for_empty_slot_allocates_and_returns_uuid() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        project.setSelectedPatternIndex(1, for: trackID) // pattern 2 is empty
        let clipCountBefore = project.clipPool.count

        let clipID = project.ensureClipForCurrentPattern(trackID: trackID)

        XCTAssertNotNil(clipID)
        XCTAssertEqual(project.clipPool.count, clipCountBefore + 1)

        let bank = project.patternBanks.first(where: { $0.trackID == trackID })!
        XCTAssertEqual(bank.slots[1].sourceRef.clipID, clipID)
    }

    func test_ensures_is_idempotent_for_the_same_slot() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        project.setSelectedPatternIndex(2, for: trackID)

        let first = project.ensureClipForCurrentPattern(trackID: trackID)
        let clipCountAfterFirst = project.clipPool.count

        let second = project.ensureClipForCurrentPattern(trackID: trackID)
        let clipCountAfterSecond = project.clipPool.count

        XCTAssertEqual(first, second, "second call should return same clipID")
        XCTAssertEqual(clipCountAfterFirst, clipCountAfterSecond, "second call should not allocate")
    }

    func test_ensures_different_slots_allocate_different_clips() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id

        project.setSelectedPatternIndex(1, for: trackID)
        let clipA = project.ensureClipForCurrentPattern(trackID: trackID)

        project.setSelectedPatternIndex(2, for: trackID)
        let clipB = project.ensureClipForCurrentPattern(trackID: trackID)

        XCTAssertNotNil(clipA)
        XCTAssertNotNil(clipB)
        XCTAssertNotEqual(clipA, clipB)
    }

    func test_ensures_for_unknown_trackID_returns_nil() {
        var project = Project.empty
        let result = project.ensureClipForCurrentPattern(trackID: UUID())
        XCTAssertNil(result)
    }

    func test_ensures_for_already_seeded_slot_returns_existing_clipID() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        project.setSelectedPatternIndex(0, for: trackID)

        let existingClipID = project.patternBanks
            .first(where: { $0.trackID == trackID })?.slots[0].sourceRef.clipID
        XCTAssertNotNil(existingClipID, "precondition: slot 0 should be seeded")

        let clipCountBefore = project.clipPool.count
        let returnedID = project.ensureClipForCurrentPattern(trackID: trackID)

        XCTAssertEqual(returnedID, existingClipID)
        XCTAssertEqual(project.clipPool.count, clipCountBefore, "no allocation for a seeded slot")
    }

    func test_ensured_clip_has_stepSequence_with_all_false_pattern_and_track_pitches() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        let trackPitches = project.tracks.first(where: { $0.id == trackID })!.pitches
        project.setSelectedPatternIndex(4, for: trackID)

        let clipID = project.ensureClipForCurrentPattern(trackID: trackID)
        XCTAssertNotNil(clipID)

        let clip = project.clipPool.first(where: { $0.id == clipID })!
        guard case let .stepSequence(stepPattern, pitches) = clip.content else {
            return XCTFail("expected .stepSequence content; got \(clip.content)")
        }
        XCTAssertEqual(stepPattern, Array(repeating: false, count: 16))
        XCTAssertEqual(pitches, trackPitches)
        XCTAssertEqual(clip.trackType, .monoMelodic)
    }
}
```

- [ ] **Step 2: Run the tests — expect failure**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectEnsureClipForCurrentPatternTests \
  2>&1 | tail -25
```

Expected: compile failure — `ensureClipForCurrentPattern` does not exist.

- [ ] **Step 3: Implement the helper**

In `Sources/Document/Project+TrackSources.swift`, add the following method (insert near `setPatternClipID` or `setPatternSourceRef`, whichever is easier to locate):

```swift
@discardableResult
mutating func ensureClipForCurrentPattern(trackID: UUID) -> UUID? {
    guard patternBanks.contains(where: { $0.trackID == trackID }) else {
        return nil
    }

    let slotIndex = selectedPatternIndex(for: trackID)
    guard let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
        return nil
    }
    let slot = patternBanks[bankIndex].slot(at: slotIndex)
    if let existing = slot.sourceRef.clipID {
        return existing
    }

    guard let track = tracks.first(where: { $0.id == trackID }) else {
        return nil
    }

    let newClip = ClipPoolEntry(
        id: UUID(),
        name: "\(track.name) pattern \(slotIndex + 1)",
        trackType: track.trackType,
        content: .stepSequence(
            stepPattern: Array(repeating: false, count: 16),
            pitches: track.pitches
        )
    )
    clipPool.append(newClip)

    let merged = SourceRef(mode: .clip, generatorID: slot.sourceRef.generatorID, clipID: newClip.id)
    setPatternSourceRef(merged, for: trackID, slotIndex: slotIndex)
    return newClip.id
}
```

If `setPatternSourceRef(_:for:slotIndex:)` does not exist in `Project+TrackSources.swift`, it's in `Sources/Document/Project+TrackSources.swift` — search for the existing `setPatternClipID` implementation to locate the surrounding helpers. Match their convention.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectEnsureClipForCurrentPatternTests \
  2>&1 | tail -15
```

Expected: all six tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/Project+TrackSources.swift Tests/SequencerAITests/Document/ProjectEnsureClipForCurrentPatternTests.swift
git commit -m "feat(document): ensureClipForCurrentPattern allocates clip lazily on first edit"
```

---

## Task 4: Remove the Clip dropdown from `TrackSourceEditorView`

**Files:**
- Modify: `Sources/UI/TrackSource/TrackSourceEditorView.swift`

- [ ] **Step 1: Locate and delete the Clip dropdown block**

Open `Sources/UI/TrackSource/TrackSourceEditorView.swift`. Find the `Picker("Clip", selection: clipIDBinding)` block (currently around lines 118–124). It will look something like:

```swift
Picker("Clip", selection: clipIDBinding) {
    Text("Choose Clip").tag(Optional<UUID>.none)
    ForEach(compatibleClips) { entry in
        Text(entry.name).tag(Optional(entry.id))
    }
}
```

Delete the entire `Picker` block. Also delete any leading `Label("Clip")` or title row that was there only to label the dropdown.

- [ ] **Step 2: Delete the `clipIDBinding` computed property**

Locate `clipIDBinding` (currently around lines 161–169). Delete the property.

- [ ] **Step 3: Delete any now-unreferenced `compatibleClips` computed property**

Search the file for `compatibleClips` to confirm it is only referenced by the deleted dropdown. If so, delete it. If it is used elsewhere (e.g. a preview row), keep it.

- [ ] **Step 4: Update the Clip panel eyebrow label**

The `StudioPanel(title: "Clip", eyebrow: ...)` wrapper previously showed "Direct clip source" when a clip was selected and "No clip selected" when none. Simplify the eyebrow to a single non-conditional label. Recommended value: `"Pattern editor"`. If a dynamic label is still desired, use the current slot's clipID presence:

```swift
StudioPanel(
    title: "Clip",
    eyebrow: isCurrentSlotEmpty ? "Tap a step to start" : "Pattern editor",
    ...
)
```

Where `isCurrentSlotEmpty` is a small computed property based on the active pattern slot's `clipID == nil`. This is optional — a fixed eyebrow is also fine.

- [ ] **Step 5: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds. If a compile error flags an unused variable or a removed helper, clean up inline.

- [ ] **Step 6: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/UI/TrackSource/TrackSourceEditorView.swift
git commit -m "refactor(ui): remove Clip dropdown from Track workspace"
```

---

## Task 5: Wire `ensureClipForCurrentPattern` into the step-grid gesture handler

**Before editing: find the current step-grid mutation.** The design doc flags this as the riskiest touch because the current write path isn't fully traced. Start with the audit below, then adapt the code.

**Files:**
- Modify: whichever file handles the step-grid tap. Likely `Sources/UI/TrackSource/Clip/StepGridView.swift` or `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`. Confirmed in Step 1 below.

- [ ] **Step 1: Enumerate every step-toggle write site**

Run:

```bash
# Find everywhere that mutates a step-pattern boolean via user gesture.
# The interesting sites are gestures (Button, TapGesture, DragGesture)
# that write into `stepPattern[...]` or call `cycleStep(...)`.
```

Use the Grep tool with pattern `cycleStep|stepPattern\[|toggleStep|setStep` under `Sources/UI/`. For each hit, report the file:line and the mutation it performs (e.g. "writes to `document.project.tracks[i].stepPattern`", "writes to `document.project.updateClipEntry`"). Capture in your head (or a scratch file) the union of write paths — there should be at most 1–2.

Also check `Sources/Document/StepSequenceTrack.swift:78` (the `cycleStep(at:)` method) — find all callers via Grep `cycleStep\(at:`. These are the "edits the track's step pattern" sites.

Classify each write site:
- **Writes to `track.stepPattern`**: these need to change to write to the clip's stepPattern instead, *after* calling `ensureClipForCurrentPattern(trackID:)`. That migration is large — if there are many, the task may need to be split.
- **Writes to the clip's `ClipContent.stepSequence.stepPattern`**: these just need to be prefixed with `ensureClipForCurrentPattern` to allocate a clip if missing.
- **Writes to both**: pick one path (the clip's) and remove the other.

- [ ] **Step 2: Decide the target shape based on the audit**

If all step-grid writes today go through the **clip path** (i.e. `updateClipEntry` with `.stepSequence`), then Task 5 is a one-liner prefix:

```swift
// Before:
document.project.updateClipEntry(id: currentClipID) { entry in
    guard case var .stepSequence(stepPattern, pitches) = entry.content else { return }
    stepPattern[cellIndex].toggle()
    entry.content = .stepSequence(stepPattern: stepPattern, pitches: pitches)
}

// After:
guard let clipID = document.project.ensureClipForCurrentPattern(trackID: trackID) else { return }
document.project.updateClipEntry(id: clipID) { entry in
    guard case var .stepSequence(stepPattern, pitches) = entry.content else { return }
    stepPattern[cellIndex].toggle()
    entry.content = .stepSequence(stepPattern: stepPattern, pitches: pitches)
}
```

If any step-grid write today goes through the **track path** (`document.project.tracks[i].cycleStep(at: cellIndex)`), the choice is:

(a) **Preferred:** migrate the track-path write to the clip path. This also fixes any latent dual-storage divergence. Use the code block above.
(b) **Conservative:** keep the track-path write, and additionally mirror the write to the clip after calling `ensureClipForCurrentPattern`. This doubles the write surface but avoids changing playback semantics. Acceptable as a short-term patch; a TODO comment in the code should flag this and reference the step-pattern / clip model review spec.

Pick (a) unless the audit in Step 1 surfaces reasons why the track-path write is load-bearing in a non-obvious way. If in doubt, ship (b) with a TODO — the step-pattern review spec will resolve it.

- [ ] **Step 3: Apply the edit**

Apply the chosen shape to every write site identified in Step 1. Each site must call `ensureClipForCurrentPattern(trackID:)` before any write, and must bail silently if the call returns `nil` (defensive — the current-pattern bank entry should always exist, but if it doesn't, we'd rather no-op than crash).

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds.

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
git add <modified step-grid file(s)>
git commit -m "feat(ui): step grid allocates per-pattern clip lazily on first toggle"
```

---

## Task 6: Update `TrackPatternSlotPalette` occupancy predicate

**Files:**
- Modify: `Sources/UI/TrackSource/TrackPatternSlotPalette.swift`

- [ ] **Step 1: Locate the current occupancy computation**

Open `Sources/UI/TrackSource/TrackPatternSlotPalette.swift`. Find where the palette decides which pattern buttons appear "filled" vs "empty". The current computation is likely based on `occupiedPatternSlots` — a property (or closure) derived from `document.project.phrases.map { patternIndex(...) }`.

- [ ] **Step 2: Replace the occupancy predicate**

Change the predicate to consult the pattern bank + clip pool directly. Depending on how the view is structured, this may be a property on the view, a helper passed in from `TrackSourceEditorView`, or computed inline in the `ForEach` body. The final logic must be:

```swift
private func isSlotOccupied(slotIndex: Int, bank: TrackPatternBank, clipPool: [ClipPoolEntry]) -> Bool {
    guard let clipID = bank.slot(at: slotIndex).sourceRef.clipID,
          let clip = clipPool.first(where: { $0.id == clipID })
    else {
        return false
    }
    return !clipIsEmpty(clip.content)
}
```

Wire this into the button's visual state (the `isSelected` style is a separate concern — the selected button is whichever `selectedPatternIndex` matches the slot; don't change that logic).

- [ ] **Step 3: Remove any now-unused `occupiedPatternSlots` helper**

If `occupiedPatternSlots` (or its equivalent) was only consumed by this view, delete it. If it's consumed elsewhere (e.g. phrase workspace), leave it.

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds.

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/UI/TrackSource/TrackPatternSlotPalette.swift
git commit -m "refactor(ui): pattern palette occupancy reflects stored clip content"
```

---

## Task 7: Remove the pitches TextField from `ClipContentPreview`

**Files:**
- Modify: `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`

- [ ] **Step 1: Delete the pitches TextField**

Open `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`. Under `case .stepSequence`, delete the `TextField(...)` block (currently around lines 25–40) that edits pitches via comma parsing. The surrounding render of the stepPattern preview (if any) stays.

- [ ] **Step 2: Delete the now-unused `onChange` parameter path for pitches**

If the view has a `onChange: ((ClipContent) -> Void)?` closure parameter that is only used by the TextField, trace every caller. If the callers pass `onChange: nil` after Task 4 (clip dropdown removed) or similar, consider removing the parameter entirely. If other callers still need it, leave it.

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds.

- [ ] **Step 4: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/TrackSource/Clip/ClipContentPreview.swift
git commit -m "refactor(ui): remove pitches comma-text field from clip preview"
```

---

## Task 8: Manual smoke + plan status + tag

**Files:** none beyond doc updates.

- [ ] **Step 1: Build and open the app**

```bash
./scripts/open-latest-build.sh
```

- [ ] **Step 2: Verify the fresh-track flow**

- Open a new document. Add a mono track. Open the Track workspace.
- Expected: Clip panel shows pattern palette + step grid. No `Clip:` dropdown. No `60, 62, 64, 67` text field.
- Expected: palette button 1 is filled; buttons 2–16 are empty.

- [ ] **Step 3: Verify lazy per-pattern allocation**

- Tap pattern 2 → step grid renders empty.
- Tap step 4 in the grid → palette button 2 becomes filled. Clip pool now has one extra entry.
- Tap pattern 1 → its seeded clip renders unchanged.
- Tap pattern 3 → empty. Tap step 2 → palette button 3 becomes filled. Pattern 2 and 3 are independent.

- [ ] **Step 4: Verify empty-clip handling**

- In pattern 2 (now with step 4 on), toggle step 4 off.
- Expected: palette button 2 returns to the empty visual state (the slot's `clipID` is still set, but the clip's stepPattern is all-false so `clipIsEmpty` returns true).

- [ ] **Step 5: Verify drum-kit flow still works**

- Add a drum kit (Add Drum Group → 808 Kit).
- Expected: each drum member's pattern 1 is seeded and filled; patterns 2–16 are empty.
- Tap pattern 2 on one of the drum members, toggle a step → the drum member's pattern 2 allocates a clip independently.

- [ ] **Step 6: Verify backwards compatibility with old saves**

- Open a previously-saved project (any that predates this change).
- Expected: no crash, every pattern renders. Pattern palette may report all 16 buttons as filled (because the old shared clip has content) or all as empty — depending on the saved clip's stepPattern.

- [ ] **Step 7: Flip plan status + tag**

Edit `docs/plans/2026-04-21-clip-ui-tidy-and-per-pattern-lazy-clips.md`: replace `**Status:** Not started.` with:

```
**Status:** ✅ Completed 2026-04-21. Tag `v0.0.26-clip-ui-tidy`. Verified via focused tests (TrackPatternBankDefaultSeedingTests, ProjectEnsureClipForCurrentPatternTests, ClipContentEmptyTests), full suite, and manual smoke.
```

Commit + tag:

```bash
git add docs/plans/2026-04-21-clip-ui-tidy-and-per-pattern-lazy-clips.md
git commit -m "docs(plan): mark clip-ui-tidy completed"
git tag -a v0.0.26-clip-ui-tidy -m "Clip UI tidy: remove dropdown + pitches field, per-pattern lazy clips"
```

- [ ] **Step 8: Dispatch `wiki-maintainer` to refresh clip / pattern docs**

Brief:
- Diff range: `<previous-tag>..HEAD`.
- Plan: `docs/plans/2026-04-21-clip-ui-tidy-and-per-pattern-lazy-clips.md`.
- Task: document the new per-pattern lazy clip allocation, the pattern palette occupancy semantics ("has stored clip with non-empty content"), and the removal of the Clip dropdown + pitches text field. Cross-link to the step-pattern/clip model review spec (`docs/specs/2026-04-21-step-pattern-clip-model-review-design.md`) as the tracker for the deeper refactor.
- Commit under `docs(wiki):` prefix.

---

## Self-Review

**Spec coverage:**
- Remove Clip dropdown — Task 4. ✓
- Remove pitches TextField — Task 7. ✓
- Lazy per-pattern clip allocation — Task 3 (helper) + Task 5 (wiring). ✓
- Pattern palette occupancy reflects stored content — Task 6. ✓
- `TrackPatternBank.default` seeds only slot 0 — Task 2. ✓
- `clipIsEmpty` helper — Task 1. ✓
- Manual smoke for all four described scenarios (fresh track, lazy allocation, empty-clip handling, drum-kit flow) — Task 8 Steps 2–5. ✓
- Backwards compatibility with old saves — Task 8 Step 6. ✓

**Placeholder scan:** no TBDs or TODOs in any step. Task 5 Step 1 asks the implementer to enumerate step-write sites before editing; this is a deliberate audit, not a placeholder. ✓

**Type consistency:**
- `clipIsEmpty(_ content: ClipContent) -> Bool` signature in Task 1 matches the call site in Task 6. ✓
- `Project.ensureClipForCurrentPattern(trackID: UUID) -> UUID?` signature in Task 3 matches Task 5. ✓
- `TrackPatternBank.default(for:initialClipID:)` still returns `TrackPatternBank` with 16 slots; only the per-slot `sourceRef.clipID` distribution changed. Existing callers don't see a type change. ✓
- `TrackPatternSlot.sourceRef.clipID` is already optional (`UUID?`). No schema change needed. ✓

**Risks:**
- **Task 5 is the riskiest task.** The current step-grid write path is not fully mapped; Step 1 is a deliberate audit. Implementer should commit small: one commit per distinct write-site change, so any issue is easy to revert. If the audit surfaces more than three write sites, split Task 5 into sub-tasks 5a, 5b, 5c.
- **Backwards-compat on palette occupancy.** Old saves have every slot pointing at the same clip. Post-change, the palette will show every slot as either filled or empty together (reflecting the shared clip's state). That is a visual change but not a regression; the Task 8 Step 6 verifies no crash and records the expected visual. Users who want independent patterns on a saved project will need to either wait for a future migration plan or re-create the affected tracks.
- **Drum-kit tests** — `ProjectAddDrumKitClipTests` and `ProjectAddDrumGroupTests` (if it has landed) may inspect slot contents. Task 2 Step 5 flags this as a likely adjustment.
- **UI screenshot baselines.** If the repo has a screenshot-diff gate, the Clip panel will definitely change and the baseline must be updated. No mention of an automated screenshot gate in this plan's research, so treat it as informational.

---

## Hand-off to the step-pattern / clip model review

After this plan ships, the next reasonable step is to execute the step-pattern / clip model review spec (`docs/specs/2026-04-21-step-pattern-clip-model-review-design.md`). That review will:

- Audit the dual storage of `StepSequenceTrack.stepPattern` and `ClipContent.stepSequence.stepPattern` that this plan deliberately left untouched.
- Measure the tick hot path's allocation and time cost.
- Propose a direction that covers per-step chords, micro-timing, fills/ratchets, per-step velocity, per-step gate length — while preserving O(1) per-step lookup with zero allocations.

The step-pattern review's Plan 3 refactor can rebase cleanly over this plan's changes because this plan does not touch any storage fields or save-format shape.
