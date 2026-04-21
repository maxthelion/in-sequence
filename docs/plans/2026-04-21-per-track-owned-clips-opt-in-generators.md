# Per-Track Owned Clips + Opt-In Attached Generators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shared-generator default with per-track owned clips, and turn the generator into an opt-in resource the user attaches to a track via an explicit button. Drum-kit parts each get their own clip seeded from the preset's `seedPattern`; single tracks get a template-seeded clip from `ClipPoolEntry.defaultPool`; no generator is attached to any track by default.

**Architecture:** Additive — `TrackPatternBank` gains `attachedGeneratorID: UUID?`. `SourceRef` keeps both `generatorID` and `clipID` populated so bypass/remove can round-trip without data loss. `TrackPatternBank.default(for:generatorPool:clipPool:)` is replaced with `TrackPatternBank.default(for:initialClipID:)`. New `Project` methods — `attachNewGenerator(to:)`, `removeAttachedGenerator(from:)`, `setSlotBypassed(_:trackID:slotIndex:)` — drive attach / remove / per-slot bypass. UI: the `Generator` / `Clip` mode pill is replaced with a contextual attach / remove control; per-slot bypass is a small toggle on the slot palette.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest. No new dependencies.

**Parent spec:** `docs/specs/2026-04-21-per-track-owned-clips-opt-in-generators-design.md`.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Status:** Not started. Tag `v0.0.16-per-track-owned-clips` at completion.

**Depends on:** nothing open — drum-track MVP is merged.

**Deliberately deferred:**

- Retroactive migration of existing documents. Old saves decode unchanged; `attachedGeneratorID` defaults to `nil`; legacy slot-level shared-generator refs still resolve for playback but present as "no generator attached" in UI.
- Pool pruning. Remove-from-track does not delete the pool entry.
- Reconciliation of `StepSequenceTrack.stepPattern` with per-part clip content on drum-kit members. Both stay populated; follow-up cleanup.
- Multi-generator-per-track attachments.

---

## File Structure

```
Sources/Document/
  PhraseModel.swift              # MODIFIED — TrackPatternBank.attachedGeneratorID; SourceRef.normalized preserves opposite ID; TrackPatternBank.default(for:initialClipID:); TrackPatternBank.synced preserves attachedGeneratorID
  Project+Tracks.swift           # MODIFIED — appendTrack / addDrumKit build per-track clips
  Project+TrackSources.swift     # MODIFIED — attachNewGenerator / removeAttachedGenerator / setSlotBypassed
  Project+Codable.swift          # MODIFIED — defaultPatternBanks / syncPatternBanks use new constructor
  Project+Selection.swift        # MODIFIED — Project.empty static uses new constructor
  Project+Patterns.swift         # MODIFIED — patternBank(for:) fallback uses new constructor

Sources/UI/TrackSource/
  TrackSourceEditorView.swift        # MODIFIED — replace mode palette with attach/remove; move generator picker into generator panel
  GeneratorAttachmentControl.swift   # NEW — Add Generator / Remove control
  TrackPatternSlotPalette.swift      # MODIFIED — per-slot bypass toggle overlay
  TrackSourceModePalette.swift       # DELETED

Tests/SequencerAITests/Document/
  SourceRefNormalizationTests.swift        # NEW
  TrackPatternBankCodableTests.swift       # NEW
  TrackPatternBankDefaultConstructorTests.swift  # NEW
  TrackPatternBankSyncedTests.swift        # NEW
  ProjectAppendTrackClipTests.swift        # NEW
  ProjectAddDrumKitClipTests.swift         # NEW (existing drum kit tests in SeqAIDocumentTests.swift stay — this adds the new clip-pool assertions)
  ProjectAttachNewGeneratorTests.swift     # NEW
  ProjectRemoveAttachedGeneratorTests.swift  # NEW
  ProjectSetSlotBypassedTests.swift        # NEW
```

---

## Task 1: `SourceRef.normalized` preserves the opposite ID

The whole attach/bypass/remove cycle depends on a slot carrying both a `generatorID` and a `clipID` at once. Today `SourceRef.normalized(...)` uses the `.generator(_:)` / `.clip(_:)` factories which zero out the other field during pattern-bank sync, destroying the data. Fix: update `normalized` to use the full initializer and preserve the opposite ID.

**Files:**
- Modify: `Sources/Document/PhraseModel.swift:796-811`
- Test: `Tests/SequencerAITests/Document/SourceRefNormalizationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/SourceRefNormalizationTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class SourceRefNormalizationTests: XCTestCase {
    func test_normalized_preserves_clipID_when_mode_is_generator() {
        let genID = UUID()
        let clipID = UUID()
        let ref = SourceRef(mode: .generator, generatorID: genID, clipID: clipID)

        let generator = GeneratorPoolEntry(
            id: genID,
            name: "Gen",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .defaultMono
        )

        let normalized = ref.normalized(
            trackType: .monoMelodic,
            generatorPool: [generator],
            clipPool: []
        )

        XCTAssertEqual(normalized.mode, .generator)
        XCTAssertEqual(normalized.generatorID, genID)
        XCTAssertEqual(normalized.clipID, clipID, "clipID must survive generator-mode normalization so bypass/remove can fall back to it")
    }

    func test_normalized_preserves_generatorID_when_mode_is_clip() {
        let genID = UUID()
        let clipID = UUID()
        let ref = SourceRef(mode: .clip, generatorID: genID, clipID: clipID)

        let clip = ClipPoolEntry(
            id: clipID,
            name: "Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        )

        let normalized = ref.normalized(
            trackType: .monoMelodic,
            generatorPool: [],
            clipPool: [clip]
        )

        XCTAssertEqual(normalized.mode, .clip)
        XCTAssertEqual(normalized.clipID, clipID)
        XCTAssertEqual(normalized.generatorID, genID, "generatorID must survive clip-mode normalization so un-bypass can re-engage it")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/SourceRefNormalizationTests \
  2>&1 | tail -40
```

Expected: both tests fail — `normalized.clipID` is `nil` (generator-mode path) and `normalized.generatorID` is `nil` (clip-mode path).

- [ ] **Step 3: Update `SourceRef.normalized` to preserve the opposite ID**

Replace `Sources/Document/PhraseModel.swift:796-811` with:

```swift
    func normalized(
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> SourceRef {
        switch mode {
        case .generator:
            let compatibleID = generatorPool.first(where: { $0.id == generatorID && $0.trackType == trackType })?.id
                ?? generatorPool.first(where: { $0.trackType == trackType })?.id
            return SourceRef(mode: .generator, generatorID: compatibleID, clipID: clipID)
        case .clip:
            let compatibleID = clipPool.first(where: { $0.id == clipID && $0.trackType == trackType })?.id
                ?? clipPool.first(where: { $0.trackType == trackType })?.id
            return SourceRef(mode: .clip, generatorID: generatorID, clipID: compatibleID)
        }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/SourceRefNormalizationTests \
  2>&1 | tail -20
```

Expected: both tests pass.

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass. If any previously-passing test relied on `normalized` zeroing out the other field (e.g., expecting `generatorID == nil` after switching to clip mode), update the test to reflect the new — intended — semantics.

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/PhraseModel.swift Tests/SequencerAITests/Document/SourceRefNormalizationTests.swift
git commit -m "feat(document): SourceRef.normalized preserves opposite ID across modes"
```

---

## Task 2: `TrackPatternBank.attachedGeneratorID` field + Codable round-trip

Add the new per-track "the track's attached generator" field. Encode unconditionally, decode with `decodeIfPresent` so old documents still load.

**Files:**
- Modify: `Sources/Document/PhraseModel.swift` (TrackPatternBank struct around line 474-542)
- Test: `Tests/SequencerAITests/Document/TrackPatternBankCodableTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/TrackPatternBankCodableTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankCodableTests: XCTestCase {
    func test_bank_round_trips_attachedGeneratorID() throws {
        let trackID = UUID()
        let generatorID = UUID()
        let clipID = UUID()
        let slot = TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID))
        let bank = TrackPatternBank(
            trackID: trackID,
            slots: [slot],
            attachedGeneratorID: generatorID
        )

        let data = try JSONEncoder().encode(bank)
        let decoded = try JSONDecoder().decode(TrackPatternBank.self, from: data)

        XCTAssertEqual(decoded.trackID, trackID)
        XCTAssertEqual(decoded.attachedGeneratorID, generatorID)
    }

    func test_bank_round_trips_nil_attachedGeneratorID() throws {
        let trackID = UUID()
        let slot = TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))
        let bank = TrackPatternBank(trackID: trackID, slots: [slot], attachedGeneratorID: nil)

        let data = try JSONEncoder().encode(bank)
        let decoded = try JSONDecoder().decode(TrackPatternBank.self, from: data)

        XCTAssertNil(decoded.attachedGeneratorID)
    }

    func test_legacy_document_without_field_decodes_as_nil() throws {
        // JSON produced by the pre-attachedGeneratorID schema — field absent.
        let legacyJSON = """
        {
            "trackID": "11111111-1111-1111-1111-111111111111",
            "slots": [
                { "slotIndex": 0, "sourceRef": { "mode": "clip", "clipID": "22222222-2222-2222-2222-222222222222" } }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TrackPatternBank.self, from: legacyJSON)

        XCTAssertNil(decoded.attachedGeneratorID)
        XCTAssertEqual(decoded.trackID, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankCodableTests \
  2>&1 | tail -40
```

Expected: compile failure — `TrackPatternBank` has no `attachedGeneratorID` initializer argument or property.

- [ ] **Step 3: Add `attachedGeneratorID` to `TrackPatternBank`**

Replace the `TrackPatternBank` struct declaration and its current `init` (currently at `Sources/Document/PhraseModel.swift:474-495`) with:

```swift
struct TrackPatternBank: Codable, Equatable, Identifiable, Sendable {
    static let slotCount = 16

    var trackID: UUID
    var slots: [TrackPatternSlot]
    var attachedGeneratorID: UUID?

    var id: UUID { trackID }

    private enum CodingKeys: String, CodingKey {
        case trackID
        case slots
        case attachedGeneratorID
    }

    init(trackID: UUID, slots: [TrackPatternSlot], attachedGeneratorID: UUID? = nil) {
        self.trackID = trackID
        self.slots = TrackPatternBank.normalizedSlots(slots)
        self.attachedGeneratorID = attachedGeneratorID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.trackID = try container.decode(UUID.self, forKey: .trackID)
        let decodedSlots = try container.decode([TrackPatternSlot].self, forKey: .slots)
        self.slots = TrackPatternBank.normalizedSlots(decodedSlots)
        self.attachedGeneratorID = try container.decodeIfPresent(UUID.self, forKey: .attachedGeneratorID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(slots, forKey: .slots)
        try container.encodeIfPresent(attachedGeneratorID, forKey: .attachedGeneratorID)
    }

    func slot(at index: Int) -> TrackPatternSlot {
        slots[min(max(index, 0), Self.slotCount - 1)]
    }

    mutating func setSlot(_ slot: TrackPatternSlot, at index: Int) {
        let clampedIndex = min(max(index, 0), Self.slotCount - 1)
        slots[clampedIndex] = slot.normalized(slotIndex: clampedIndex)
        slots = TrackPatternBank.normalizedSlots(slots)
    }
```

Keep the rest of the struct body (`synced`, `default`, `normalizedSlots`, `defaultSourceRef`) untouched for now — Tasks 3 and 4 will update them.

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankCodableTests \
  2>&1 | tail -20
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass. No existing test should break — the new field has a default value of `nil` and is absent-is-OK on decode.

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/PhraseModel.swift Tests/SequencerAITests/Document/TrackPatternBankCodableTests.swift
git commit -m "feat(document): TrackPatternBank gains attachedGeneratorID with codable round-trip"
```

---

## Task 3: New `TrackPatternBank.default(for:initialClipID:)` constructor

Introduce the new constructor. Keep the old `default(for:generatorPool:clipPool:)` for now; Task 7 will delete it after all callers migrate.

**Files:**
- Modify: `Sources/Document/PhraseModel.swift` (add near line 517)
- Test: `Tests/SequencerAITests/Document/TrackPatternBankDefaultConstructorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/TrackPatternBankDefaultConstructorTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankDefaultConstructorTests: XCTestCase {
    func test_default_points_all_slots_at_initialClipID() {
        let track = StepSequenceTrack.default
        let clipID = UUID()

        let bank = TrackPatternBank.default(for: track, initialClipID: clipID)

        XCTAssertEqual(bank.slots.count, TrackPatternBank.slotCount)
        XCTAssertNil(bank.attachedGeneratorID)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertEqual(slot.sourceRef.clipID, clipID)
            XCTAssertNil(slot.sourceRef.generatorID)
        }
    }

    func test_default_accepts_nil_initialClipID() {
        let track = StepSequenceTrack.default

        let bank = TrackPatternBank.default(for: track, initialClipID: nil)

        XCTAssertEqual(bank.slots.count, TrackPatternBank.slotCount)
        XCTAssertNil(bank.attachedGeneratorID)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertNil(slot.sourceRef.clipID)
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankDefaultConstructorTests \
  2>&1 | tail -40
```

Expected: compile failure — `TrackPatternBank.default(for:initialClipID:)` does not exist.

- [ ] **Step 3: Add the new constructor**

In `Sources/Document/PhraseModel.swift`, add (next to the existing `static func default(...)` at around line 517, i.e. inside the `TrackPatternBank` struct body):

```swift
    static func `default`(
        for track: StepSequenceTrack,
        initialClipID: UUID?
    ) -> TrackPatternBank {
        let sourceRef = SourceRef(mode: .clip, generatorID: nil, clipID: initialClipID)
        return TrackPatternBank(
            trackID: track.id,
            slots: (0..<slotCount).map { TrackPatternSlot(slotIndex: $0, sourceRef: sourceRef) },
            attachedGeneratorID: nil
        )
    }
```

Leave the existing `default(for:generatorPool:clipPool:)` in place — it will be deleted in Task 7 once all callers are migrated.

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankDefaultConstructorTests \
  2>&1 | tail -20
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/PhraseModel.swift Tests/SequencerAITests/Document/TrackPatternBankDefaultConstructorTests.swift
git commit -m "feat(document): add TrackPatternBank.default(for:initialClipID:) constructor"
```

---

## Task 4: `TrackPatternBank.synced` preserves and validates `attachedGeneratorID`

`synced(...)` is called every time `Project.syncPhrasesWithTracks()` runs. Today it reconstructs a fresh `TrackPatternBank` from normalized slots but does not carry `attachedGeneratorID`. Fix: preserve the field, and clear it if the referenced generator no longer exists in the pool.

**Files:**
- Modify: `Sources/Document/PhraseModel.swift:497-515`
- Test: `Tests/SequencerAITests/Document/TrackPatternBankSyncedTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/TrackPatternBankSyncedTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankSyncedTests: XCTestCase {
    private func monoGenerator(id: UUID) -> GeneratorPoolEntry {
        GeneratorPoolEntry(
            id: id,
            name: "Gen",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .defaultMono
        )
    }

    func test_synced_preserves_attachedGeneratorID_when_present_in_pool() {
        let track = StepSequenceTrack.default
        let generatorID = UUID()
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))],
            attachedGeneratorID: generatorID
        )

        let synced = bank.synced(
            track: track,
            generatorPool: [monoGenerator(id: generatorID)],
            clipPool: []
        )

        XCTAssertEqual(synced.attachedGeneratorID, generatorID)
    }

    func test_synced_clears_attachedGeneratorID_when_missing_from_pool() {
        let track = StepSequenceTrack.default
        let missingID = UUID()
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))],
            attachedGeneratorID: missingID
        )

        let synced = bank.synced(
            track: track,
            generatorPool: [],
            clipPool: []
        )

        XCTAssertNil(synced.attachedGeneratorID, "dangling attachedGeneratorID should be dropped when the entry is gone")
    }

    func test_synced_clears_attachedGeneratorID_on_trackType_mismatch() {
        let track = StepSequenceTrack.default // monoMelodic
        let generatorID = UUID()
        let polyGenerator = GeneratorPoolEntry(
            id: generatorID,
            name: "Poly",
            trackType: .polyMelodic,
            kind: .polyGenerator,
            params: .poly(step: .manual(pattern: Array(repeating: false, count: 16)), pitches: [.manual(pitches: [60], pickMode: .random)], shape: .default)
        )
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))],
            attachedGeneratorID: generatorID
        )

        let synced = bank.synced(
            track: track,
            generatorPool: [polyGenerator],
            clipPool: []
        )

        XCTAssertNil(synced.attachedGeneratorID, "attachedGeneratorID pointing at an incompatible-trackType entry should be dropped")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankSyncedTests \
  2>&1 | tail -40
```

Expected: `test_synced_preserves_attachedGeneratorID_when_present_in_pool` fails — `synced` drops the field because the re-constructed bank uses the default-nil initializer.

- [ ] **Step 3: Update `synced` to preserve + validate `attachedGeneratorID`**

Replace `Sources/Document/PhraseModel.swift:497-515` with:

```swift
    func synced(
        track: StepSequenceTrack,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> TrackPatternBank {
        let fallbackSourceRef = Self.defaultSourceRef(for: track, generatorPool: generatorPool)
        let validatedAttachedID: UUID? = {
            guard let attachedGeneratorID else { return nil }
            let exists = generatorPool.contains(where: { $0.id == attachedGeneratorID && $0.trackType == track.trackType })
            return exists ? attachedGeneratorID : nil
        }()
        return TrackPatternBank(
            trackID: trackID,
            slots: slots.enumerated().map { index, slot in
                slot.normalized(
                    slotIndex: index,
                    trackType: track.trackType,
                    generatorPool: generatorPool,
                    clipPool: clipPool,
                    fallbackSourceRef: fallbackSourceRef
                )
            },
            attachedGeneratorID: validatedAttachedID
        )
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/TrackPatternBankSyncedTests \
  2>&1 | tail -20
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite to check for regressions**

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
git add Sources/Document/PhraseModel.swift Tests/SequencerAITests/Document/TrackPatternBankSyncedTests.swift
git commit -m "feat(document): TrackPatternBank.synced preserves and validates attachedGeneratorID"
```

---

## Task 5: `Project.appendTrack` creates a per-track template clip

`appendTrack` currently calls the old `TrackPatternBank.default(for:generatorPool:clipPool:)`. Switch it to: pick a matching template from `ClipPoolEntry.defaultPool`, copy with a fresh UUID, append to `clipPool`, build the bank with the new constructor.

**Files:**
- Modify: `Sources/Document/Project+Tracks.swift:3-20`
- Test: `Tests/SequencerAITests/Document/ProjectAppendTrackClipTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/ProjectAppendTrackClipTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAppendTrackClipTests: XCTestCase {
    func test_appendTrack_appends_a_matching_template_clip_to_pool() {
        var project = Project.empty
        let priorClipCount = project.clipPool.count
        let priorGeneratorCount = project.generatorPool.count

        project.appendTrack(trackType: .monoMelodic)

        XCTAssertEqual(project.clipPool.count, priorClipCount + 1, "appendTrack should add exactly one clip to the pool")
        XCTAssertEqual(project.generatorPool.count, priorGeneratorCount, "appendTrack must not mutate the generator pool")

        let addedClip = project.clipPool.last!
        XCTAssertEqual(addedClip.trackType, .monoMelodic)
    }

    func test_appendTrack_bank_points_at_the_new_clip_with_no_generator_attached() {
        var project = Project.empty

        project.appendTrack(trackType: .polyMelodic)

        let newTrack = project.selectedTrack
        let bank = project.patternBank(for: newTrack.id)
        let expectedClipID = project.clipPool.last!.id

        XCTAssertNil(bank.attachedGeneratorID, "new track should have no generator attached")
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertEqual(slot.sourceRef.clipID, expectedClipID)
        }
    }

    func test_appendTrack_slice_picks_slice_template() {
        var project = Project.empty

        project.appendTrack(trackType: .slice)

        let addedClip = project.clipPool.last!
        XCTAssertEqual(addedClip.trackType, .slice)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAppendTrackClipTests \
  2>&1 | tail -40
```

Expected: all three tests fail — `appendTrack` doesn't append to `clipPool`.

- [ ] **Step 3: Update `appendTrack` to create a per-track clip**

Replace `Sources/Document/Project+Tracks.swift:3-20` with:

```swift
import Foundation

extension Project {
    mutating func appendTrack(trackType: TrackType = .monoMelodic) {
        let nextTrack = StepSequenceTrack(
            name: Self.defaultTrackName(for: trackType, index: tracks.count + 1),
            trackType: trackType,
            pitches: Self.defaultPitches(for: trackType),
            stepPattern: Self.defaultStepPattern(for: trackType),
            destination: Self.defaultDestination(for: trackType),
            velocity: StepSequenceTrack.default.velocity,
            gateLength: StepSequenceTrack.default.gateLength
        )
        tracks.append(nextTrack)
        let ownedClip = Self.makeOwnedClip(for: nextTrack)
        clipPool.append(ownedClip)
        patternBanks.append(
            TrackPatternBank.default(for: nextTrack, initialClipID: ownedClip.id)
        )
        selectedTrackID = nextTrack.id
        syncPhrasesWithTracks()
    }
```

Add a new helper inside the same file (anywhere in the extension, a reasonable spot is next to `defaultDestination`):

```swift
    static func makeOwnedClip(for track: StepSequenceTrack) -> ClipPoolEntry {
        guard let template = ClipPoolEntry.defaultPool.first(where: { $0.trackType == track.trackType }) else {
            // No template for this trackType — synthesise an empty step-sequence clip.
            return ClipPoolEntry(
                id: UUID(),
                name: "\(track.name) clip",
                trackType: track.trackType,
                content: .stepSequence(
                    stepPattern: Array(repeating: false, count: 16),
                    pitches: track.pitches
                )
            )
        }
        return ClipPoolEntry(
            id: UUID(),
            name: "\(track.name) clip",
            trackType: template.trackType,
            content: template.content
        )
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAppendTrackClipTests \
  2>&1 | tail -20
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass. Pay attention to `SeqAIDocumentTests.test_append_track_syncs_layer_defaults_and_phrase_cells` — it previously ran against the old default-bank shape (all slots pointing at the shared generator). Its assertions are about *layers* and *phrase cells*, not the bank's sourceRef mode, so it should still pass. If any assertions about slot `sourceRef.mode == .generator` exist in that file, update them to the new expectation (`.clip`).

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/Project+Tracks.swift Tests/SequencerAITests/Document/ProjectAppendTrackClipTests.swift
git commit -m "feat(document): appendTrack creates per-track clip; no generator attached"
```

---

## Task 6: `Project.addDrumKit` creates per-part seeded clips

Each preset member's `seedPattern` becomes the content of an owned clip for that member track. No generator added to the pool.

**Files:**
- Modify: `Sources/Document/Project+Tracks.swift:22-63`
- Test: `Tests/SequencerAITests/Document/ProjectAddDrumKitClipTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/ProjectAddDrumKitClipTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumKitClipTests: XCTestCase {
    func test_addDrumKit_808_appends_four_seeded_clips_to_pool() throws {
        var project = Project.empty
        let priorClipCount = project.clipPool.count
        let priorGeneratorCount = project.generatorPool.count

        let groupID = try XCTUnwrap(project.addDrumKit(.kit808))

        XCTAssertEqual(project.clipPool.count, priorClipCount + 4)
        XCTAssertEqual(project.generatorPool.count, priorGeneratorCount, "drum-kit creation must not add generator pool entries")

        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        XCTAssertEqual(memberIDs.count, 4)

        let presetMembers = DrumKitPreset.kit808.members
        for (memberID, presetMember) in zip(memberIDs, presetMembers) {
            let bank = project.patternBank(for: memberID)
            XCTAssertNil(bank.attachedGeneratorID, "drum part must have no generator attached")

            let clipID = try XCTUnwrap(bank.slots.first?.sourceRef.clipID)
            let clip = try XCTUnwrap(project.clipEntry(id: clipID))

            XCTAssertEqual(clip.trackType, .monoMelodic)
            XCTAssertEqual(clip.name, presetMember.trackName)
            guard case let .stepSequence(stepPattern, pitches) = clip.content else {
                return XCTFail("drum-part clip content must be .stepSequence; got \(clip.content)")
            }
            XCTAssertEqual(stepPattern, presetMember.seedPattern)
            XCTAssertEqual(pitches, [DrumKitNoteMap.baselineNote])

            for slot in bank.slots {
                XCTAssertEqual(slot.sourceRef.mode, .clip)
                XCTAssertEqual(slot.sourceRef.clipID, clipID)
            }
        }
    }

    func test_addDrumKit_techno_appends_four_seeded_clips() throws {
        var project = Project.empty
        let priorCount = project.clipPool.count

        _ = try XCTUnwrap(project.addDrumKit(.techno))

        XCTAssertEqual(project.clipPool.count, priorCount + 4)
    }

    func test_addDrumKit_acoustic_appends_three_seeded_clips() throws {
        var project = Project.empty
        let priorCount = project.clipPool.count

        _ = try XCTUnwrap(project.addDrumKit(.acousticBasic))

        XCTAssertEqual(project.clipPool.count, priorCount + 3)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAddDrumKitClipTests \
  2>&1 | tail -40
```

Expected: all three tests fail — `addDrumKit` does not append to `clipPool`.

- [ ] **Step 3: Update `addDrumKit` to create per-part seeded clips**

Replace `Sources/Document/Project+Tracks.swift:22-63` with:

```swift
    @discardableResult
    mutating func addDrumKit(_ preset: DrumKitPreset) -> TrackGroupID? {
        guard !preset.members.isEmpty else {
            return nil
        }

        let groupID = TrackGroupID()
        var newTracks: [StepSequenceTrack] = []
        var newBanks: [TrackPatternBank] = []

        for member in preset.members {
            let track = StepSequenceTrack(
                name: member.trackName,
                trackType: .monoMelodic,
                pitches: [DrumKitNoteMap.baselineNote],
                stepPattern: member.seedPattern,
                destination: .inheritGroup,
                groupID: groupID,
                velocity: StepSequenceTrack.default.velocity,
                gateLength: StepSequenceTrack.default.gateLength
            )
            let clip = ClipPoolEntry(
                id: UUID(),
                name: member.trackName,
                trackType: .monoMelodic,
                content: .stepSequence(
                    stepPattern: member.seedPattern,
                    pitches: [DrumKitNoteMap.baselineNote]
                )
            )
            clipPool.append(clip)
            newTracks.append(track)
            newBanks.append(TrackPatternBank.default(for: track, initialClipID: clip.id))
        }

        tracks.append(contentsOf: newTracks)
        patternBanks.append(contentsOf: newBanks)
        trackGroups.append(
            TrackGroup(
                id: groupID,
                name: preset.displayName,
                color: preset.suggestedGroupColor,
                memberIDs: newTracks.map(\.id),
                sharedDestination: preset.suggestedSharedDestination,
                noteMapping: Dictionary(
                    uniqueKeysWithValues: zip(newTracks, preset.members).map { track, member in
                        (
                            track.id,
                            Int(DrumKitNoteMap.note(for: member.tag)) - DrumKitNoteMap.baselineNote
                        )
                    }
                )
            )
        )
        selectedTrackID = newTracks.first?.id ?? selectedTrackID
        syncPhrasesWithTracks()
        return groupID
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAddDrumKitClipTests \
  2>&1 | tail -20
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -40
```

Expected: all tests pass. The existing `SeqAIDocumentTests.test_add_drum_kit_creates_group_and_inherit_cells` tests group/cell structure, not source refs — should still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/Project+Tracks.swift Tests/SequencerAITests/Document/ProjectAddDrumKitClipTests.swift
git commit -m "feat(document): addDrumKit creates per-part seeded clips; no generator attached"
```

---

## Task 7: Migrate remaining callers to the new constructor and delete the old one

Four call sites still use `TrackPatternBank.default(for:generatorPool:clipPool:)`: `Project+Patterns.swift:10`, `Project+Selection.swift:15`, `Project+Codable.swift:202` (`defaultPatternBanks`) and `Project+Codable.swift:214` (`syncPatternBanks`). Migrate them to the new constructor, then delete the old one. A fifth caller — `Project+Tracks.swift:75` (`setSelectedTrackType`) — also needs migration.

**Files:**
- Modify: `Sources/Document/Project+Tracks.swift:65-82` (`setSelectedTrackType`)
- Modify: `Sources/Document/Project+Selection.swift:15`
- Modify: `Sources/Document/Project+Patterns.swift:8-15`
- Modify: `Sources/Document/Project+Codable.swift:196-217`
- Modify: `Sources/Document/PhraseModel.swift:517-527` (delete old `default`)

- [ ] **Step 1: Update `setSelectedTrackType` to migrate the bank to a compatible clip**

Replace `Sources/Document/Project+Tracks.swift:65-82` with:

```swift
    mutating func setSelectedTrackType(_ trackType: TrackType) {
        guard !tracks.isEmpty else {
            return
        }

        tracks[selectedTrackIndex].trackType = trackType
        let updatedTrack = tracks[selectedTrackIndex]
        let fallbackClipID = clipPool.first(where: { $0.trackType == trackType })?.id
        patternBanks = patternBanks.map { bank in
            guard bank.trackID == selectedTrackID else {
                return bank
            }
            return TrackPatternBank.default(for: updatedTrack, initialClipID: fallbackClipID)
        }
        syncPhrasesWithTracks()
    }
```

- [ ] **Step 2: Update `Project.empty` in `Project+Selection.swift`**

Replace `Sources/Document/Project+Selection.swift:4-32` — specifically the `patternBanks` array — with:

```swift
    static let empty = Project(
        version: 1,
        tracks: [
            .default
        ],
        trackGroups: [],
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: [],
        layers: PhraseLayerDefinition.defaultSet(for: [.default]),
        routes: [],
        patternBanks: [
            TrackPatternBank.default(for: .default, initialClipID: nil)
        ],
        selectedTrackID: StepSequenceTrack.default.id,
        phrases: [
            .default(
                tracks: [.default],
                layers: PhraseLayerDefinition.defaultSet(for: [.default]),
                generatorPool: GeneratorPoolEntry.defaultPool,
                clipPool: []
            )
        ],
        selectedPhraseID: PhraseModel.default(
            tracks: [.default],
            layers: PhraseLayerDefinition.defaultSet(for: [.default]),
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        ).id
    )
```

- [ ] **Step 3: Update `patternBank(for:)` in `Project+Patterns.swift`**

Replace `Sources/Document/Project+Patterns.swift:8-15` with:

```swift
    func patternBank(for trackID: UUID) -> TrackPatternBank {
        if let existing = patternBanks.first(where: { $0.trackID == trackID }) {
            return existing
        }
        let track = tracks.first(where: { $0.id == trackID }) ?? .default
        let fallbackClipID = clipPool.first(where: { $0.trackType == track.trackType })?.id
        return TrackPatternBank.default(for: track, initialClipID: fallbackClipID)
    }
```

- [ ] **Step 4: Update `defaultPatternBanks` and `syncPatternBanks` in `Project+Codable.swift`**

Replace `Sources/Document/Project+Codable.swift:196-217` with:

```swift
    static func defaultPatternBanks(
        for tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> [TrackPatternBank] {
        tracks.map { track in
            let fallbackClipID = clipPool.first(where: { $0.trackType == track.trackType })?.id
            return TrackPatternBank.default(for: track, initialClipID: fallbackClipID)
        }
    }

    private static func syncPatternBanks(
        _ patternBanks: [TrackPatternBank],
        with tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> [TrackPatternBank] {
        tracks.map { track in
            let fallbackClipID = clipPool.first(where: { $0.trackType == track.trackType })?.id
            let existing = patternBanks.first(where: { $0.trackID == track.id })
                ?? TrackPatternBank.default(for: track, initialClipID: fallbackClipID)
            return existing.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
        }
    }
```

(`generatorPool` stays in the signature even though no longer read inside — it's still used elsewhere and will continue being threaded through. Both signatures unchanged.)

- [ ] **Step 5: Delete the old `TrackPatternBank.default` constructor**

Delete `Sources/Document/PhraseModel.swift:517-527` — the entire block:

```swift
    static func `default`(
        for track: StepSequenceTrack,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> TrackPatternBank {
        let defaultSourceRef = defaultSourceRef(for: track, generatorPool: generatorPool)
        return TrackPatternBank(
            trackID: track.id,
            slots: (0..<slotCount).map { TrackPatternSlot(slotIndex: $0, sourceRef: defaultSourceRef) }
        )
    }
```

Also delete the now-dead helper at `Sources/Document/PhraseModel.swift:536-541`:

```swift
    private static func defaultSourceRef(
        for track: StepSequenceTrack,
        generatorPool: [GeneratorPoolEntry]
    ) -> SourceRef {
        .generator(generatorPool.first(where: { $0.trackType == track.trackType })?.id)
    }
```

- [ ] **Step 6: Build and verify there are no remaining references to the old constructor**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: build succeeds. If the compiler complains about missing `default(for:generatorPool:clipPool:)`, a caller was missed — grep and update:

```bash
```

Use Grep with pattern `TrackPatternBank\.default\(for:\s*.*generatorPool:` to find any stragglers.

- [ ] **Step 7: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -40
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/Document/Project+Tracks.swift Sources/Document/Project+Selection.swift Sources/Document/Project+Patterns.swift Sources/Document/Project+Codable.swift Sources/Document/PhraseModel.swift
git commit -m "refactor(document): migrate callers to TrackPatternBank.default(for:initialClipID:); drop old constructor"
```

---

## Task 8: `Project.attachNewGenerator(to:)`

Attaches a fresh generator pool entry to the named track. All 16 slots flip to `.generator` mode with `generatorID = new.id`; each slot's existing `clipID` is preserved so remove/bypass has a clip to fall back to.

**Files:**
- Modify: `Sources/Document/Project+TrackSources.swift` (append)
- Test: `Tests/SequencerAITests/Document/ProjectAttachNewGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/ProjectAttachNewGeneratorTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAttachNewGeneratorTests: XCTestCase {
    func test_attachNewGenerator_appends_one_pool_entry_of_matching_track_type() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let priorCount = project.generatorPool.count

        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        XCTAssertEqual(project.generatorPool.count, priorCount + 1)
        XCTAssertEqual(added.trackType, .monoMelodic)
        XCTAssertTrue(project.generatorPool.contains(where: { $0.id == added.id }))
    }

    func test_attachNewGenerator_sets_attachedGeneratorID_on_bank() throws {
        var project = Project.empty
        project.appendTrack(trackType: .polyMelodic)
        let track = project.selectedTrack

        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        let bank = project.patternBank(for: track.id)
        XCTAssertEqual(bank.attachedGeneratorID, added.id)
    }

    func test_attachNewGenerator_flips_all_slots_to_generator_mode_preserving_clipID() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let priorClipID = project.patternBank(for: track.id).slot(at: 0).sourceRef.clipID

        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        let bank = project.patternBank(for: track.id)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .generator)
            XCTAssertEqual(slot.sourceRef.generatorID, added.id)
            XCTAssertEqual(slot.sourceRef.clipID, priorClipID, "clipID must be preserved across attach")
        }
    }

    func test_attachNewGenerator_returns_nil_for_unknown_track() {
        var project = Project.empty
        let added = project.attachNewGenerator(to: UUID())
        XCTAssertNil(added)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAttachNewGeneratorTests \
  2>&1 | tail -40
```

Expected: compile failure — `attachNewGenerator(to:)` does not exist.

- [ ] **Step 3: Implement `attachNewGenerator(to:)`**

In `Sources/Document/Project+TrackSources.swift`, append (inside the `extension Project`):

```swift
    @discardableResult
    mutating func attachNewGenerator(to trackID: UUID) -> GeneratorPoolEntry? {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return nil
        }

        let track = tracks[trackIndex]
        guard let templateKind = GeneratorKind.allCases.first(where: { $0.compatibleWith.contains(track.trackType) }) else {
            return nil
        }

        let nextIndex = generatorPool.filter { $0.trackType == track.trackType }.count + 1
        let newEntry = GeneratorPoolEntry(
            id: UUID(),
            name: "\(templateKind.label) \(nextIndex)",
            trackType: track.trackType,
            kind: templateKind,
            params: templateKind.defaultParams
        )
        generatorPool.append(newEntry)

        var bank = patternBanks[bankIndex]
        bank.attachedGeneratorID = newEntry.id
        for index in 0..<bank.slots.count {
            let existing = bank.slots[index]
            let newRef = SourceRef(mode: .generator, generatorID: newEntry.id, clipID: existing.sourceRef.clipID)
            bank.slots[index] = TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef)
        }
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
        return newEntry
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAttachNewGeneratorTests \
  2>&1 | tail -20
```

Expected: all four tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/Project+TrackSources.swift Tests/SequencerAITests/Document/ProjectAttachNewGeneratorTests.swift
git commit -m "feat(document): Project.attachNewGenerator creates pool entry and flips slots"
```

---

## Task 9: `Project.removeAttachedGenerator(from:)`

Detaches the track's generator. Each slot's mode flips to `.clip`, but `sourceRef.generatorID` stays populated so un-attach could re-engage (out of scope here). The pool entry is **not** deleted.

**Files:**
- Modify: `Sources/Document/Project+TrackSources.swift` (append)
- Test: `Tests/SequencerAITests/Document/ProjectRemoveAttachedGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/ProjectRemoveAttachedGeneratorTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectRemoveAttachedGeneratorTests: XCTestCase {
    func test_remove_clears_attachedGeneratorID() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        _ = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        project.removeAttachedGenerator(from: track.id)

        let bank = project.patternBank(for: track.id)
        XCTAssertNil(bank.attachedGeneratorID)
    }

    func test_remove_flips_slots_to_clip_mode_preserving_clipID_and_generatorID() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let ownedClipID = project.patternBank(for: track.id).slot(at: 0).sourceRef.clipID
        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        project.removeAttachedGenerator(from: track.id)

        let bank = project.patternBank(for: track.id)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertEqual(slot.sourceRef.clipID, ownedClipID, "remove must fall back to the slot's clipID")
            XCTAssertEqual(slot.sourceRef.generatorID, added.id, "generatorID is retained so un-attach could re-engage")
        }
    }

    func test_remove_does_not_delete_pool_entry() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        let priorCount = project.generatorPool.count

        project.removeAttachedGenerator(from: track.id)

        XCTAssertEqual(project.generatorPool.count, priorCount, "remove-from-track must not prune the pool")
        XCTAssertTrue(project.generatorPool.contains(where: { $0.id == added.id }))
    }

    func test_remove_is_noop_when_no_generator_attached() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let priorBank = project.patternBank(for: track.id)

        project.removeAttachedGenerator(from: track.id)

        let bank = project.patternBank(for: track.id)
        XCTAssertEqual(bank, priorBank)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectRemoveAttachedGeneratorTests \
  2>&1 | tail -40
```

Expected: compile failure — `removeAttachedGenerator(from:)` does not exist.

- [ ] **Step 3: Implement `removeAttachedGenerator(from:)`**

Append in `Sources/Document/Project+TrackSources.swift`:

```swift
    mutating func removeAttachedGenerator(from trackID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        var bank = patternBanks[bankIndex]
        guard bank.attachedGeneratorID != nil else {
            return
        }

        bank.attachedGeneratorID = nil
        for index in 0..<bank.slots.count {
            let existing = bank.slots[index]
            let newRef = SourceRef(
                mode: .clip,
                generatorID: existing.sourceRef.generatorID,
                clipID: existing.sourceRef.clipID
            )
            bank.slots[index] = TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef)
        }
        let track = tracks[trackIndex]
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectRemoveAttachedGeneratorTests \
  2>&1 | tail -20
```

Expected: all four tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/Project+TrackSources.swift Tests/SequencerAITests/Document/ProjectRemoveAttachedGeneratorTests.swift
git commit -m "feat(document): Project.removeAttachedGenerator detaches without pruning pool"
```

---

## Task 10: `Project.setSlotBypassed(_:trackID:slotIndex:)`

Per-slot override: when a generator is attached, flip a single slot's mode between `.generator` and `.clip` without touching any IDs.

**Files:**
- Modify: `Sources/Document/Project+TrackSources.swift` (append)
- Test: `Tests/SequencerAITests/Document/ProjectSetSlotBypassedTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/ProjectSetSlotBypassedTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectSetSlotBypassedTests: XCTestCase {
    private func projectWithAttachedGenerator() throws -> (Project, UUID) {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        _ = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        return (project, track.id)
    }

    func test_bypass_true_flips_only_the_named_slot_to_clip_mode() throws {
        var (project, trackID) = try projectWithAttachedGenerator()

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 3)

        let bank = project.patternBank(for: trackID)
        XCTAssertEqual(bank.slot(at: 3).sourceRef.mode, .clip)
        for index in 0..<TrackPatternBank.slotCount where index != 3 {
            XCTAssertEqual(bank.slot(at: index).sourceRef.mode, .generator, "slot \(index) must stay engaged")
        }
    }

    func test_bypass_false_re_engages_the_slot() throws {
        var (project, trackID) = try projectWithAttachedGenerator()
        project.setSlotBypassed(true, trackID: trackID, slotIndex: 7)

        project.setSlotBypassed(false, trackID: trackID, slotIndex: 7)

        XCTAssertEqual(project.patternBank(for: trackID).slot(at: 7).sourceRef.mode, .generator)
    }

    func test_bypass_preserves_generatorID_and_clipID() throws {
        var (project, trackID) = try projectWithAttachedGenerator()
        let priorSlot = project.patternBank(for: trackID).slot(at: 5)

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 5)

        let bypassed = project.patternBank(for: trackID).slot(at: 5)
        XCTAssertEqual(bypassed.sourceRef.generatorID, priorSlot.sourceRef.generatorID)
        XCTAssertEqual(bypassed.sourceRef.clipID, priorSlot.sourceRef.clipID)
    }

    func test_bypass_is_noop_when_no_generator_attached() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        let priorBank = project.patternBank(for: trackID)

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 3)

        XCTAssertEqual(project.patternBank(for: trackID), priorBank)
    }

    func test_bypass_clamps_slotIndex_out_of_range() throws {
        var (project, trackID) = try projectWithAttachedGenerator()

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 999)

        // The last slot (index 15) should be the clamped target.
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: 15).sourceRef.mode, .clip)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectSetSlotBypassedTests \
  2>&1 | tail -40
```

Expected: compile failure — `setSlotBypassed(_:trackID:slotIndex:)` does not exist.

- [ ] **Step 3: Implement `setSlotBypassed`**

Append in `Sources/Document/Project+TrackSources.swift`:

```swift
    mutating func setSlotBypassed(_ bypassed: Bool, trackID: UUID, slotIndex: Int) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }
        var bank = patternBanks[bankIndex]
        guard bank.attachedGeneratorID != nil else {
            return
        }

        let clamped = min(max(slotIndex, 0), TrackPatternBank.slotCount - 1)
        let existing = bank.slot(at: clamped)
        let newMode: TrackSourceMode = bypassed ? .clip : .generator
        let newRef = SourceRef(
            mode: newMode,
            generatorID: existing.sourceRef.generatorID,
            clipID: existing.sourceRef.clipID
        )
        bank.setSlot(
            TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef),
            at: clamped
        )
        let track = tracks[trackIndex]
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectSetSlotBypassedTests \
  2>&1 | tail -20
```

Expected: all five tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/Project+TrackSources.swift Tests/SequencerAITests/Document/ProjectSetSlotBypassedTests.swift
git commit -m "feat(document): Project.setSlotBypassed flips single-slot mode without touching IDs"
```

---

## Task 11: UI — `GeneratorAttachmentControl` view

A new compact SwiftUI view: when no generator is attached, shows an "Add Generator" button; when attached, shows the name + a Remove button.

**Files:**
- Create: `Sources/UI/TrackSource/GeneratorAttachmentControl.swift`

- [ ] **Step 1: Create the view**

Write `Sources/UI/TrackSource/GeneratorAttachmentControl.swift`:

```swift
import SwiftUI

struct GeneratorAttachmentControl: View {
    let attachedGenerator: GeneratorPoolEntry?
    let accent: Color
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let attached = attachedGenerator {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attached.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                    Text(attached.kind.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 0)

                Button(action: onRemove) {
                    Text("Remove")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().stroke(StudioTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onAdd) {
                    Text("Add Generator")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(accent.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify the new file compiles**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: build succeeds. (The file is not yet referenced; it is included in the project via the xcodegen-generated target, which globs `Sources/UI/TrackSource/*.swift` — confirm by inspecting `project.yml` if the file fails to appear in the target.)

If the build fails with "cannot find type `GeneratorAttachmentControl` in scope" when Task 12 references it, regenerate the project with `xcodegen generate` and retry.

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/TrackSource/GeneratorAttachmentControl.swift
git commit -m "feat(ui): GeneratorAttachmentControl — Add Generator / Remove control"
```

---

## Task 12: UI — `TrackSourceEditorView` uses the new control; delete `TrackSourceModePalette`

Replace the mode palette (Generator / Clip pill) with `GeneratorAttachmentControl`. Visibility of the generator editor panel now keys off `bank.attachedGeneratorID != nil`, not `sourceRef.mode`. The generator picker (for re-pointing at other pool entries) stays inside the generator editor panel.

**Files:**
- Modify: `Sources/UI/TrackSource/TrackSourceEditorView.swift`
- Delete: `Sources/UI/TrackSource/TrackSourceModePalette.swift`

- [ ] **Step 1: Replace the Source panel body and conditional panels**

Open `Sources/UI/TrackSource/TrackSourceEditorView.swift`. Replace the full file body with:

```swift
import SwiftUI

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    let accent: Color

    private var track: StepSequenceTrack { document.project.selectedTrack }
    private var bank: TrackPatternBank { document.project.patternBank(for: track.id) }
    private var selectedPatternIndex: Int { document.project.selectedPatternIndex(for: track.id) }
    private var selectedPattern: TrackPatternSlot { document.project.selectedPattern(for: track.id) }
    private var occupiedPatternSlots: Set<Int> {
        Set(document.project.phrases.map { $0.patternIndex(for: track.id, layers: document.project.layers) })
    }
    private var attachedGenerator: GeneratorPoolEntry? {
        document.project.generatorEntry(id: bank.attachedGeneratorID)
    }
    private var compatibleGenerators: [GeneratorPoolEntry] { document.project.compatibleGenerators(for: track) }
    private var compatibleClips: [ClipPoolEntry] { document.project.compatibleClips(for: track) }
    private var currentClip: ClipPoolEntry? { document.project.clipEntry(id: selectedPattern.sourceRef.clipID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Source", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    TrackPatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots,
                        bypassState: bypassState,
                        onBypassToggle: { slotIndex in
                            let currentlyBypassed = (bank.slot(at: slotIndex).sourceRef.mode == .clip)
                            document.project.setSlotBypassed(!currentlyBypassed, trackID: track.id, slotIndex: slotIndex)
                        }
                    )

                    GeneratorAttachmentControl(
                        attachedGenerator: attachedGenerator,
                        accent: accent,
                        onAdd: {
                            _ = document.project.attachNewGenerator(to: track.id)
                        },
                        onRemove: {
                            document.project.removeAttachedGenerator(from: track.id)
                        }
                    )
                }
            }

            if let attached = attachedGenerator {
                generatorEditorPanel(for: attached)
            }
            clipPanel
        }
    }

    private var bypassState: TrackPatternSlotPalette.BypassState {
        guard bank.attachedGeneratorID != nil else {
            return .notApplicable
        }
        var bypassed: Set<Int> = []
        for (index, slot) in bank.slots.enumerated() where slot.sourceRef.mode == .clip {
            bypassed.insert(index)
        }
        return .applicable(bypassed: bypassed)
    }

    @ViewBuilder
    private func generatorEditorPanel(for generator: GeneratorPoolEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Generator", eyebrow: generator.kind.label, accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    if compatibleGenerators.count > 1 {
                        Picker("Generator", selection: generatorIDBinding) {
                            ForEach(compatibleGenerators) { entry in
                                Text(entry.name).tag(Optional(entry.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Text(generator.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                }
            }

            GeneratorParamsEditorView(
                generator: generator,
                clipChoices: compatibleClips,
                accent: accent
            ) { updated in
                document.project.updateGeneratorEntry(id: generator.id) { entry in
                    entry.params = updated
                }
            }
        }
    }

    @ViewBuilder
    private var clipPanel: some View {
        if let clip = currentClip {
            StudioPanel(title: "Clip", eyebrow: clip.name, accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 14) {
                    if compatibleClips.count > 1 {
                        Picker("Clip", selection: clipIDBinding) {
                            ForEach(compatibleClips) { entry in
                                Text(entry.name).tag(Optional(entry.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    ClipContentPreview(content: clip.content) { updated in
                        document.project.updateClipEntry(id: clip.id) { entry in
                            entry.content = updated
                        }
                    }
                }
            }
        } else {
            StudioPanel(title: "Clip", eyebrow: "No clip selected", accent: StudioTheme.violet) {
                StudioPlaceholderTile(
                    title: "No Clip For This Slot",
                    detail: "Pick a clip from the pool or let the track create one via Add Generator.",
                    accent: StudioTheme.violet
                )
            }
        }
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { document.project.selectedPatternIndex(for: track.id) },
            set: { document.project.setSelectedPatternIndex($0, for: track.id) }
        )
    }

    private var generatorIDBinding: Binding<UUID?> {
        Binding(
            get: { bank.attachedGeneratorID },
            set: { newValue in
                guard let newValue else { return }
                var updatedBank = bank
                updatedBank.attachedGeneratorID = newValue
                for index in 0..<updatedBank.slots.count {
                    let slot = updatedBank.slots[index]
                    let newRef = SourceRef(
                        mode: slot.sourceRef.mode,
                        generatorID: newValue,
                        clipID: slot.sourceRef.clipID
                    )
                    updatedBank.slots[index] = TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: newRef)
                }
                if let bankIndex = document.project.patternBanks.firstIndex(where: { $0.trackID == track.id }) {
                    document.project.patternBanks[bankIndex] = updatedBank.synced(
                        track: track,
                        generatorPool: document.project.generatorPool,
                        clipPool: document.project.clipPool
                    )
                }
            }
        )
    }

    private var clipIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedPattern.sourceRef.clipID },
            set: { newValue in
                guard let newValue else { return }
                document.project.setPatternClipID(newValue, for: track.id, slotIndex: selectedPatternIndex)
            }
        )
    }
}
```

- [ ] **Step 2: Delete the now-unused mode palette**

```bash
git rm Sources/UI/TrackSource/TrackSourceModePalette.swift
```

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -40
```

Expected: compile failure on `TrackPatternSlotPalette(...)` — the new call passes `bypassState` and `onBypassToggle` parameters the current palette does not accept. This is fixed in Task 13.

- [ ] **Step 4: Check for remaining references to `TrackSourceModePalette`**

Use Grep with pattern `TrackSourceModePalette` across `Sources/` and `Tests/`. If any matches remain, they're in tests or other UI code — remove or update them. Expected: the only expected match after deletion is zero.

- [ ] **Step 5: Check for call sites of the old `setPatternSourceMode` / `setPatternGeneratorID` helpers in UI code**

Use Grep with pattern `setPatternSourceMode|setPatternGeneratorID` across `Sources/UI/`. Both helpers in `Project+TrackSources.swift` and `Project+Patterns.swift` are still needed for setting a specific clip id via the clip picker (still in use via `clipIDBinding` → `setPatternClipID`) — but `setPatternGeneratorID` and `setPatternSourceMode` are no longer driven from UI. Leave them in place for now (dead-code detection is a separate pass); they are not removed here because the new generator-ID binding code path uses a different mechanism that manipulates `attachedGeneratorID` directly. Mark these as deprecated by a one-line code comment inside each, for a follow-up to delete:

At `Sources/Document/Project+TrackSources.swift:39-45`, prepend each function body with a single-line comment:

```swift
    mutating func setPatternSourceRef(_ sourceRef: SourceRef, for trackID: UUID, slotIndex: Int) {
        // Still used by the clip picker path. Retained.
```

```swift
    mutating func setPatternGeneratorID(_ generatorID: UUID, for trackID: UUID, slotIndex: Int) {
        // Unused by new UI; retained for compatibility with `Project+Phrases.swift` paths. Candidate for follow-up removal.
```

(Keep these comments single-line per the project style — no multi-paragraph docstrings.)

- [ ] **Step 6: Commit the UI shift (the build still fails; Task 13 finishes it)**

```bash
git add Sources/UI/TrackSource/TrackSourceEditorView.swift Sources/Document/Project+TrackSources.swift
git rm Sources/UI/TrackSource/TrackSourceModePalette.swift
git commit -m "feat(ui): TrackSourceEditorView uses GeneratorAttachmentControl; drop mode palette"
```

---

## Task 13: UI — per-slot bypass toggle on `TrackPatternSlotPalette`

Add a `BypassState` parameter and an `onBypassToggle` callback so a small overlay button per slot can flip bypass when a generator is attached.

**Files:**
- Modify: `Sources/UI/TrackSource/TrackPatternSlotPalette.swift`

- [ ] **Step 1: Rewrite the palette to accept bypass state**

Replace the full contents of `Sources/UI/TrackSource/TrackPatternSlotPalette.swift` with:

```swift
import SwiftUI

struct TrackPatternSlotPalette: View {
    enum BypassState: Equatable {
        case notApplicable
        case applicable(bypassed: Set<Int>)
    }

    @Binding var selectedSlot: Int
    let occupiedSlots: Set<Int>
    let bypassState: BypassState
    let onBypassToggle: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                slotButton(at: slotIndex)
            }
        }
    }

    @ViewBuilder
    private func slotButton(at slotIndex: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                selectedSlot = slotIndex
            } label: {
                HStack(spacing: 6) {
                    Text("\(slotIndex + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)

                    Circle()
                        .fill(indicatorFill(for: slotIndex))
                        .frame(width: 6, height: 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(backgroundFill(for: slotIndex))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(borderColor(for: slotIndex), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if case .applicable(let bypassed) = bypassState {
                Button {
                    onBypassToggle(slotIndex)
                } label: {
                    Text(bypassed.contains(slotIndex) ? "C" : "G")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(bypassBadgeForeground(bypassed.contains(slotIndex)))
                        .frame(width: 14, height: 14)
                        .background(bypassBadgeFill(bypassed.contains(slotIndex)), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: 4)
            }
        }
    }

    private func backgroundFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.2)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.08)
        }
        return Color.white.opacity(0.03)
    }

    private func borderColor(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.7)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.28)
        }
        return StudioTheme.border
    }

    private func indicatorFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.6)
        }
        return Color.white.opacity(0.08)
    }

    private func bypassBadgeFill(_ isBypassed: Bool) -> Color {
        isBypassed ? StudioTheme.violet.opacity(0.55) : StudioTheme.cyan.opacity(0.55)
    }

    private func bypassBadgeForeground(_ isBypassed: Bool) -> Color {
        StudioTheme.text
    }
}
```

- [ ] **Step 2: Verify that no other caller of `TrackPatternSlotPalette` exists**

Use Grep with pattern `TrackPatternSlotPalette` across `Sources/`. The only call site should be `TrackSourceEditorView.swift`. If any other view constructs the palette, update it to pass `bypassState: .notApplicable` and `onBypassToggle: { _ in }`.

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: build succeeds.

- [ ] **Step 4: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -40
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/TrackSource/TrackPatternSlotPalette.swift
git commit -m "feat(ui): TrackPatternSlotPalette shows per-slot bypass toggle when generator attached"
```

---

## Task 14: Manual smoke test + tag

Run the app, create the described scenarios, verify end-to-end. Then tag.

**Files:** none (verification + tag)

- [ ] **Step 1: Build and run**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' build && open /Users/maxwilliams/Library/Developer/Xcode/DerivedData/SequencerAI-*/Build/Products/Debug/SequencerAI.app
```

- [ ] **Step 2: Verify the new-project flow**

- Open a fresh project.
- Inspect: exactly one default track, exactly one clip in the clip pool matching that track's type.
- The Source panel should show an "Add Generator" button (not a Generator/Clip pill).

- [ ] **Step 3: Verify drum-kit creation**

- Add Drum Kit → 808.
- Inspect: four new tracks (Kick / Snare / Hat / Clap), four new clips appended to `clipPool` with the preset's seedPattern. `generatorPool` unchanged.
- Each of the four track's Source panel shows "Add Generator" (no generator attached).
- Transport play: the classic 808 pattern should be audible (kick on every beat, snare on 2/4, hat on 16ths, clap on beat 3 every two bars).

- [ ] **Step 4: Verify attach / bypass / remove**

- Select a drum part track. Press "Add Generator". Expect: the button flips to showing the new generator's name + "Remove". The 16-slot palette shows "G" badges on every slot. Transport play: the track is now driven by the generator (not the clip pattern).
- Click the "G" badge on slot 3. Expect: it flips to "C" and that slot plays the clip, while others remain on the generator.
- Click the "C" badge back. Expect: returns to "G".
- Press "Remove". Expect: button flips back to "Add Generator"; slot badges disappear; transport play returns to the clip pattern.

- [ ] **Step 5: Open a legacy project (pre-this-change)**

- Open a `.seqai` file saved before these changes (the auto repo has some fixtures; or save a document while Task 1–6 are still pre-commit, then open after).
- Expect: the document opens, plays correctly (shared-generator slot refs still resolve), and the Source panel shows "Add Generator" for each track (cosmetic regression — accepted).

- [ ] **Step 6: Update plan status + tag**

Edit `docs/plans/2026-04-21-per-track-owned-clips-opt-in-generators.md`: change `**Status:** Not started.` to `**Status:** ✅ Completed 2026-04-21. Tag v0.0.16-per-track-owned-clips.`

```bash
git add docs/plans/2026-04-21-per-track-owned-clips-opt-in-generators.md
git commit -m "docs(plan): mark per-track-owned-clips completed"
git tag v0.0.16-per-track-owned-clips
```

- [ ] **Step 7: Update the wiki**

Dispatch the `wiki-maintainer` subagent (or edit directly) to refresh:
- `wiki/pages/document-model.md` — document the new `attachedGeneratorID` field on `TrackPatternBank`; note that slots now carry both `generatorID` and `clipID` at once and the preserve-on-mode-switch invariant.
- `wiki/pages/drum-track-mvp.md` — note that drum-kit creation now produces per-part clips in the pool; no shared generator.

Commit the wiki update as `docs(wiki): per-track owned clips + attached generator model`.

---

## Self-Review Notes

**Spec coverage check:**
- Data model: `attachedGeneratorID` → Task 2. `SourceRef` preserve-both → Task 1. ✓
- Document construction: new constructor → Task 3. `appendTrack` → Task 5. `addDrumKit` → Task 6. Old-caller migration → Task 7. ✓
- Attach / remove / bypass: Tasks 8, 9, 10. ✓
- UI surface: Tasks 11 (control), 12 (editor view + delete palette), 13 (slot bypass). ✓
- Backward compatibility: Task 2 covers the decode path; Task 14 Step 5 manually verifies legacy-doc open. ✓
- Test plan: Each functional task owns its test file — Source ref normalization, bank codable, bank synced, append-track, add-drum-kit, attach / remove / bypass. ✓

**Placeholder scan:** No TBDs. Every step has concrete code or an exact command.

**Type consistency:** `attachedGeneratorID` used identically across all tasks. `TrackPatternBank.default(for:initialClipID:)` signature consistent. `BypassState` / `onBypassToggle` parameter names match between Tasks 12 and 13.
