# Document-as-Project Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Rename `SeqAIDocumentModel` → `Project` (type + `SeqAIDocument.model` property), extract `StepSequenceTrack` / `TrackType` / `TrackMixSettings` into their own files, relocate drum-kit presets to `Sources/Musical/` with a Destination-projection extension that stays in `Document/`, consolidate the duplicate Codable-init normalization paths, and split the old god file into cohesive `Project+*.swift` extension files following the `+TrackSources` precedent. Verified by: `wc -l Sources/Document/Project.swift ≤ 200`; no file in scope > 500 LOC; `grep -r 'SeqAIDocumentModel\\|document\\.model' Sources/ Tests/` returns zero; `DrumKitPreset` lives in `Musical/` with its Destination projection in `Document/DrumKitPreset+Destination.swift`; newly written projects round-trip through encode/decode in tests; full test suite green; the app launches from the current checkout. This plan is explicitly fresh-model-only: do not add migration shims for pre-rename `.seqai` payloads.

**Architecture:**

Name the domain concept. `Project` is the persisted state of the sequencer — tracks, phrases, patterns, routes, groups, pools, selection. Naming it after SwiftUI's `FileDocument` idiom hides what it actually is. After this plan, `Project` is the domain type; `SeqAIDocument: FileDocument` is a thin persistence shell whose one job is JSON in/out. Every downstream reader says `document.project.tracks` instead of `document.model.tracks`, and the domain name is visible at every call site.

Within `Project`, responsibilities are split across extension files (`Project+Tracks.swift`, `Project+Phrases.swift`, `Project+Routes.swift`, `Project+Groups.swift`, `Project+Patterns.swift`, `Project+Selection.swift`, `Project+PhraseCells.swift`, `Project+DrumKit.swift`, `Project+Codable.swift`) following the precedent set by `Project+TrackSources.swift`. The core `Project.swift` carries stored properties, `.empty`, `CodingKeys`, a couple of single-line accessors, and the two designated initializers — ~200 LOC.

Drum-kit presets — `DrumKitNoteMap`, `DrumKitPreset` — are shipped reference data, which `wiki/pages/project-layout.md` says belongs in `Musical/`. They move. Their `suggestedSharedDestination` projection needs `Destination`, which cannot move to `Musical/` (it carries `.auInstrument(stateBlob: Data)` session state, not reference data), so a small `DrumKitPreset+Destination.swift` extension stays in `Document/`. This preserves the rule that `Musical/` imports nothing project-internal.

Three Codable-init paths today duplicate the same "resolve layers → resolve pattern banks → clamp selection IDs → resolve phrases" normalization: `init(version:tracks:selectedTrackID:)`, the main `init(version:tracks:trackGroups:...)`, and `init(from decoder:)`. They collapse behind a single shared `Project.normalize(...)` returning a `NormalizedFields` struct. The three initializers become thin adapters.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` (no new specification; pure structural refactor).

**Depends on:** current `main` after the post-bridge cleanup and destination-editor cleanup (`60fa69b`, `0df85d7`). This is a high-churn rename that touches almost every `document.project` call site, so it should run on a quiet tree and land **before** `ui-organisation-and-track-source-split` and `phrase-workspace-split`, not alongside them.

**Deliberately deferred:**

- **Splitting `Sources/Document/PhraseModel.swift`.** Same disease — 812 LOC, 17 types, several of them unrelated to phrases (`TrackPatternBank`, `TrackPatternSlot`, `TrackSourceMode`, `GeneratorKind`, `GeneratorPoolEntry`, `ClipPoolEntry`, `SourceRef`). Deserves its own plan with the same shape as this one.
- **Redesigning `selectedTrack` / `selectedPhrase` accessor semantics.** The current setters silently bootstrap from empty and rebind selection when `id` changes — a real contract problem flagged in review. But fixing it touches 20+ UI call sites that use `$document.project.selectedTrack.foo` bindings, and the right replacement (`updateSelectedTrack(_:)` vs `replaceSelectedTrack(_:)`) needs thought about SwiftUI binding semantics. Separate plan.
- **Removing `TrackType.label` vs `shortLabel` duplication** (they currently return the same strings). Cosmetic; one-commit cleanup in a later chore.
- **Extracting per-file tests mirroring the new structure.** Test colocation is not a goal here — the existing `Tests/SequencerAITests/Document/*Tests.swift` layout continues to work.

**Status:** [COMPLETED 2026-04-20] Tag: `v0.0.12-document-as-project-refactor`

---

## File Structure (post-plan)

```
Sources/
  Document/
    Project.swift                                 # RENAMED from Project.swift; shrunk to ~200 LOC
    Project+Codable.swift                         # NEW — init(from:), encode(to:), NormalizedFields, normalize(...)
    Project+Tracks.swift                          # NEW — appendTrack, removeSelectedTrack, setSelectedTrackType, default-factories
    Project+Phrases.swift                         # NEW — appendPhrase, insertPhrase, duplicate*, remove*, defaultPhraseName
    Project+PhraseCells.swift                     # NEW — cell(for:), updatePhrase, setPhraseCell, setPhraseCellMode
    Project+Patterns.swift                        # NEW — patternBank, selectedPattern*, setPatternSourceMode, setPatternName
    Project+Routes.swift                          # NEW — routesSourced, routesTargeting, makeDefaultRoute, upsertRoute, removeRoute
    Project+Groups.swift                          # NEW — group(for:), tracksInGroup, addGroup, addToGroup, removeFromGroup
    Project+Selection.swift                       # NEW — selectedTrack, selectedPhrase, selectTrack, selectPhrase, indexes
    Project+DrumKit.swift                         # NEW — addDrumKit (consumes Musical/DrumKitPreset)
    Project+TrackSources.swift                    # RENAMED from Project+TrackSources.swift
    StepSequenceTrack.swift                       # NEW — extracted from Project.swift:865-1050
    TrackType.swift                               # NEW — extracted from Project.swift:1052-1078
    TrackMixSettings.swift                        # NEW — extracted from Project.swift:1080-1094
    DrumKitPreset+Destination.swift               # NEW — suggestedSharedDestination projection
    SeqAIDocument.swift                           # modified — `var model: Project` → `var project: Project`
    (unchanged: Destination.swift, PhraseModel.swift, Route.swift, TrackGroup.swift, StepAlgo.swift, PitchAlgo.swift, ClipContent.swift, NoteShape.swift, PitchContext.swift, GeneratorParams.swift)
  Musical/
    DrumKitNoteMap.swift                          # NEW — moved from Document/
    DrumKitPreset.swift                           # NEW — moved from Document/ (minus suggestedSharedDestination)
Tests/
  SequencerAITests/
    Document/
      ProjectNormalizationTests.swift             # NEW — 4 cases exercising the new normalize(...) helper
      (existing tests renamed in their bodies where they referenced Project)
```

---

## Task 1: Rename `Project` → `Project` and `SeqAIDocument.model` → `.project`

**Scope:** Pure mechanical rename across `Sources/`, `Tests/`, `wiki/`, and `docs/`. Type, file names, property name. This plan does **not** promise old-doc compatibility; it should not add compatibility aliases or migration shims. Keep `CodingKeys` stable unless a touched file clearly benefits from simplification, but the primary goal is the rename and split, not on-disk churn.

**Files:**
- Rename: `Sources/Document/Project.swift` → `Sources/Document/Project.swift` (via `git mv`)
- Rename: `Sources/Document/Project+TrackSources.swift` → `Sources/Document/Project+TrackSources.swift` (via `git mv`)
- Modify: `Sources/Document/SeqAIDocument.swift` — change `var model: Project` to `var project: Project`; update `init(model:)` → `init(project:)`; adjust `init(configuration:)` decode target and `fileWrapper(configuration:)` encode source.
- Modify: every call site in `Sources/`, `Tests/` that references `Project` (type) or `document.project` / `.model` (property) where the LHS is a `SeqAIDocument` / `$document`.
- Modify: wiki pages that reference the type or property — at minimum `wiki/pages/document-model.md`, `wiki/pages/project-layout.md`, `wiki/pages/track-destinations.md`, `wiki/pages/tracks-matrix.md`, `wiki/pages/routing.md` (grep first; update any hit).

**Tests:** Existing suite green. No new tests — this is a rename.

**Subtleties:**
- `.model` is too common a token to blind-sed across the repo. Scope the replacement to the patterns `document.project`, `$document.project`, `SeqAIDocument(project:`, `.model =`, `.model.` when the left-hand identifier's type is `SeqAIDocument`. Verify by compiling after each batch.
- The `FileDocument` `init(model:)` convenience should become `init(project:)` with a matching default `init(project: Project = .empty)`.
- Keep the private `CodingKeys` stable unless a touched file clearly benefits from simplification. No migration path is required; the point is to avoid unnecessary scope, not to preserve old documents at all costs.

- [x] `git mv Sources/Document/Project.swift Sources/Document/Project.swift`
- [x] `git mv Sources/Document/Project+TrackSources.swift Sources/Document/Project+TrackSources.swift`
- [x] Inside `Project.swift`: `struct Project` → `struct Project`, `static let empty = Project(...)` → `static let empty = Project(...)`, `Self.defaultDestination` / `Self.defaultPatternBanks` / `Self.syncPatternBanks` references unchanged (they use `Self`).
- [x] Inside `Project+TrackSources.swift`: `extension Project` → `extension Project`.
- [x] Inside `SeqAIDocument.swift`: `var model: Project` → `var project: Project`; `init(model: Project = .empty)` → `init(project: Project = .empty)`; `self.model = ...` → `self.project = ...` (two sites: default init, decode init); `try encoder.encode(model)` → `try encoder.encode(project)`.
- [x] Grep-and-replace `Project` → `Project` across `Sources/` and `Tests/`. Verify each hit is the type (not a substring of something else).
- [x] Grep-and-replace `document.project` → `document.project` and `$document.project` → `$document.project` — handle carefully; don't touch `.model` on non-SeqAIDocument values.
- [x] Regenerate xcodeproj: `xcodegen generate`.
- [x] `xcodebuild -scheme SequencerAI test` — green.
- [x] Update wiki pages: `grep -rln 'Project\|document\.model' wiki/ docs/` then edit each to use `Project` / `document.project`.
- [x] Commit: `refactor(document): rename Project to Project and SeqAIDocument.model to .project`

---

## Task 2: Extract `StepSequenceTrack`, `TrackType`, `TrackMixSettings` into their own files

**Scope:** Move the three types currently at the bottom of `Project.swift` (post-Task-1) into dedicated files. Pure mechanical move — the bodies, `Codable` implementations, mutating methods, defaults all go verbatim. No behaviour change.

**Files:**
- Create: `Sources/Document/StepSequenceTrack.swift` — `struct StepSequenceTrack` including `.default`, both initializers, `Codable` (init + encode), `activeStepCount`, `accentedStepCount`, `cycleStep`, `accentDownbeats`, `clearAccents`, `defaultDestination`, `midiPortName`, `midiChannel`, `midiNoteOffset`, `setMIDIPort`, `setMIDIChannel`, `setMIDINoteOffset`, private `normalizedAccents`.
- Create: `Sources/Document/TrackType.swift` — `enum TrackType: String, Codable, CaseIterable, Equatable, Sendable` with `label` and `shortLabel`.
- Create: `Sources/Document/TrackMixSettings.swift` — `struct TrackMixSettings: Codable, Equatable, Sendable` with `.default`, `clampedLevel`, `clampedPan`.
- Modify: `Sources/Document/Project.swift` — delete these three type blocks.

**Tests:** Existing suite green. No new tests.

**Subtleties:**
- `StepSequenceTrack.defaultDestination` references `Project.defaultDestination(for:)` via an explicit `Project.defaultDestination(...)` call in the initializer. After Task 1 that is `Project.defaultDestination(...)` — double-check the reference compiles after the extraction.
- Xcodegen picks up new `.swift` files under the `Sources/` tree automatically; regen after the moves.

- [x] Create `Sources/Document/StepSequenceTrack.swift` by copying the `struct StepSequenceTrack { … }` body verbatim from `Project.swift`.
- [x] Create `Sources/Document/TrackType.swift` with the `enum TrackType` body verbatim.
- [x] Create `Sources/Document/TrackMixSettings.swift` with the `struct TrackMixSettings` body verbatim.
- [x] Delete the three type blocks from `Project.swift`.
- [x] `xcodegen generate`.
- [x] `xcodebuild -scheme SequencerAI test` — green.
- [x] Commit: `refactor(document): extract StepSequenceTrack, TrackType, TrackMixSettings into own files`

---

## Task 3: Move `DrumKitNoteMap` + `DrumKitPreset` to `Musical/`; keep the Destination projection in `Document/`

**Scope:** `DrumKitNoteMap` and `DrumKitPreset` are shipped musical reference data; `wiki/pages/project-layout.md` places them in `Sources/Musical/`. Musical/ must not import Document/, so `DrumKitPreset.suggestedSharedDestination` (which returns a `Destination`) cannot move with the rest. Split:

- `Musical/DrumKitNoteMap.swift` — the full `enum DrumKitNoteMap` (note table + `note(for:)`).
- `Musical/DrumKitPreset.swift` — the full `enum DrumKitPreset` EXCEPT `suggestedSharedDestination`.
- `Document/DrumKitPreset+Destination.swift` — a two-line extension providing `var suggestedSharedDestination: Destination`.

**Files:**
- Create: `Sources/Musical/DrumKitNoteMap.swift` — verbatim move of the current `enum DrumKitNoteMap`:

```swift
import Foundation

enum DrumKitNoteMap {
    static let baselineNote = 36

    static let table: [VoiceTag: UInt8] = [
        "kick": 36,
        "snare": 38,
        "sidestick": 37,
        "hat-closed": 42,
        "hat-open": 46,
        "hat-pedal": 44,
        "clap": 39,
        "tom-low": 41,
        "tom-mid": 45,
        "tom-hi": 48,
        "ride": 51,
        "crash": 49,
        "cowbell": 56,
        "tambourine": 54,
        "shaker": 70,
    ]

    static func note(for tag: VoiceTag) -> UInt8 {
        table[tag] ?? 60
    }
}
```

- Create: `Sources/Musical/DrumKitPreset.swift` — `enum DrumKitPreset` verbatim EXCEPT the `suggestedSharedDestination` computed property is removed. Keep `displayName`, `members`, `suggestedGroupColor`, the `Member` nested struct.
- Create: `Sources/Document/DrumKitPreset+Destination.swift`:

```swift
import Foundation

extension DrumKitPreset {
    var suggestedSharedDestination: Destination {
        .internalSampler(bankID: .drumKitDefault, preset: rawValue)
    }
}
```

- Modify: `Sources/Document/Project.swift` — delete `enum DrumKitNoteMap` and `enum DrumKitPreset`.

**Tests:** Existing suite green. No new tests. `VoiceTag` is already accessible from `Musical/` (it lives at `Sources/Document/Destination.swift`... actually verify — if `VoiceTag` lives in `Document/`, Musical cannot import it, and the move breaks). Subtlety below.

**Subtleties:**
- **`VoiceTag` location check.** `DrumKitNoteMap.table: [VoiceTag: UInt8]` uses `VoiceTag`. Grep for `VoiceTag` to locate its home. If it lives in `Document/` the Musical move requires first moving `VoiceTag` to `Musical/` (or to a shared primitive type file). If `VoiceTag` is just a typealias for `String`, relocating it is trivial. Resolve this at the start of the task before the move.
- `DrumKitPreset.suggestedSharedDestination` uses `Destination.internalSampler(bankID: .drumKitDefault, preset: rawValue)`. `.drumKitDefault` is a case of a nested enum on `Destination` — stays put.

- [x] Grep `VoiceTag` and confirm it can live in `Musical/` (or move it first if Document-bound).
- [x] Create `Sources/Musical/DrumKitNoteMap.swift` with the body above.
- [x] Create `Sources/Musical/DrumKitPreset.swift` by moving the current `enum DrumKitPreset` verbatim EXCEPT the `suggestedSharedDestination` property.
- [x] Create `Sources/Document/DrumKitPreset+Destination.swift` with the extension shown above.
- [x] Delete `enum DrumKitNoteMap` and `enum DrumKitPreset` from `Project.swift`.
- [x] `xcodegen generate`.
- [x] `xcodebuild -scheme SequencerAI test` — green.
- [x] Commit: `refactor(musical): move DrumKitNoteMap and DrumKitPreset to Musical, keep Destination projection in Document`

---

## Task 4: Unify the three Codable-init normalization paths into `Project.normalize(...)`

**Scope:** `Project.init(version:tracks:selectedTrackID:)`, `Project.init(version:tracks:trackGroups:...)`, and `Project.init(from decoder:)` each contain near-identical "resolve layers → resolve pattern banks → clamp selected track ID → resolve phrases → clamp selected phrase ID" sequences. Extract a single static helper.

**Files:**
- Modify: `Sources/Document/Project.swift` — add the `NormalizedFields` private type and `normalize(...)` helper; rewrite both public initializers to call it.
- Modify: `Sources/Document/Project+Codable.swift` (created by Task 5 — for this task, the `init(from:)` / `encode(to:)` stays in `Project.swift` and moves in Task 5). Rewrite `init(from decoder:)` to call `normalize`.

New private API on `Project`:

```swift
private struct NormalizedFields {
    var layers: [PhraseLayerDefinition]
    var patternBanks: [TrackPatternBank]
    var phrases: [PhraseModel]
    var selectedTrackID: UUID
    var selectedPhraseID: UUID
}

private static func normalize(
    tracks: [StepSequenceTrack],
    generatorPool: [GeneratorPoolEntry],
    clipPool: [ClipPoolEntry],
    layers decoded: [PhraseLayerDefinition]?,
    patternBanks decoded: [TrackPatternBank]?,
    phrases decoded: [PhraseModel]?,
    selectedTrackID decoded: UUID?,
    selectedPhraseID decoded: UUID?
) -> NormalizedFields {
    let resolvedLayers: [PhraseLayerDefinition] = {
        guard let decoded, !decoded.isEmpty else {
            return PhraseLayerDefinition.defaultSet(for: tracks)
        }
        return decoded.map { $0.synced(with: tracks) }
    }()

    let resolvedPatternBanks: [TrackPatternBank] = {
        guard let decoded, !decoded.isEmpty else {
            return Self.defaultPatternBanks(for: tracks, generatorPool: generatorPool, clipPool: clipPool)
        }
        return decoded
            .filter { bank in tracks.contains(where: { $0.id == bank.trackID }) }
            .map { bank in
                bank.synced(
                    track: tracks.first(where: { $0.id == bank.trackID }) ?? .default,
                    generatorPool: generatorPool,
                    clipPool: clipPool
                )
            }
    }()

    let resolvedPhrases: [PhraseModel] = {
        guard let decoded, !decoded.isEmpty else {
            return [.default(tracks: tracks, layers: resolvedLayers, generatorPool: generatorPool, clipPool: clipPool)]
        }
        return decoded.map { $0.synced(with: tracks, layers: resolvedLayers) }
    }()

    let resolvedSelectedTrackID: UUID = {
        if let decoded, tracks.contains(where: { $0.id == decoded }) {
            return decoded
        }
        return tracks[0].id
    }()

    let resolvedSelectedPhraseID: UUID = {
        if let decoded, resolvedPhrases.contains(where: { $0.id == decoded }) {
            return decoded
        }
        return resolvedPhrases[0].id
    }()

    return NormalizedFields(
        layers: resolvedLayers,
        patternBanks: resolvedPatternBanks,
        phrases: resolvedPhrases,
        selectedTrackID: resolvedSelectedTrackID,
        selectedPhraseID: resolvedSelectedPhraseID
    )
}
```

Each of the three initializers becomes:

```swift
let normalized = Self.normalize(
    tracks: tracks,
    generatorPool: generatorPool,
    clipPool: clipPool,
    layers: layers,
    patternBanks: patternBanks,
    phrases: phrases,
    selectedTrackID: selectedTrackID,
    selectedPhraseID: selectedPhraseID
)
self.version = version
self.tracks = tracks
self.trackGroups = trackGroups
self.generatorPool = generatorPool
self.clipPool = clipPool
self.layers = normalized.layers
self.routes = routes
self.patternBanks = normalized.patternBanks
self.selectedTrackID = normalized.selectedTrackID
self.phrases = normalized.phrases
self.selectedPhraseID = normalized.selectedPhraseID
syncPhrasesWithTracks()
```

**Tests:**
- Create: `Tests/SequencerAITests/Document/ProjectNormalizationTests.swift` — exercises the new helper through its public observable surface (the initializers):

```swift
import XCTest
@testable import SequencerAI

final class ProjectNormalizationTests: XCTestCase {
    private func track(name: String) -> StepSequenceTrack {
        StepSequenceTrack(name: name, pitches: [60], stepPattern: [true], velocity: 100, gateLength: 4)
    }

    func test_missingLayersAndPatternBanksAndPhrases_getDefaults() {
        let track = track(name: "A")
        let project = Project(
            version: 1,
            tracks: [track],
            layers: [],
            patternBanks: [],
            selectedTrackID: track.id,
            phrases: [],
            selectedPhraseID: UUID()
        )
        XCTAssertFalse(project.layers.isEmpty, "layers should default to PhraseLayerDefinition.defaultSet when empty")
        XCTAssertEqual(project.patternBanks.count, 1, "pattern banks should default to one-per-track")
        XCTAssertEqual(project.patternBanks[0].trackID, track.id)
        XCTAssertEqual(project.phrases.count, 1, "phrases should default to one phrase")
    }

    func test_selectedTrackID_pointingAtDeletedTrack_clampsToFirst() {
        let trackA = track(name: "A")
        let trackB = track(name: "B")
        let bogusID = UUID()
        let project = Project(
            version: 1,
            tracks: [trackA, trackB],
            selectedTrackID: bogusID,
            phrases: [],
            selectedPhraseID: bogusID
        )
        XCTAssertEqual(project.selectedTrackID, trackA.id)
    }

    func test_orphanPatternBanks_areFiltered() {
        let live = track(name: "A")
        let ghost = track(name: "ghost")
        let orphanBank = TrackPatternBank.default(for: ghost, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [])
        let liveBank = TrackPatternBank.default(for: live, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [])
        let project = Project(
            version: 1,
            tracks: [live],
            patternBanks: [orphanBank, liveBank],
            selectedTrackID: live.id,
            phrases: [.default(tracks: [live])],
            selectedPhraseID: UUID()
        )
        XCTAssertEqual(project.patternBanks.count, 1)
        XCTAssertEqual(project.patternBanks[0].trackID, live.id)
    }

    func test_selectedPhraseID_pointingAtNothing_clampsToFirst() {
        let track = track(name: "A")
        let phrase = PhraseModel.default(tracks: [track])
        let project = Project(
            version: 1,
            tracks: [track],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: UUID()
        )
        XCTAssertEqual(project.selectedPhraseID, phrase.id)
    }
}
```

All four cases exercise the public initializer — no hand-crafted JSON needed.

**Subtleties:**
- The normalization closures capture `tracks` and `resolvedLayers` — ordering matters: `resolvedLayers` must be computed before `resolvedPhrases` because `resolvedPhrases` passes `layers: resolvedLayers` to `synced(with:layers:)`.
- `syncPhrasesWithTracks()` still runs AFTER `normalize` in every initializer — it's a second-pass invariant check that also prunes orphan group members + note mappings. Leave it in place.

- [x] Add `NormalizedFields` + `normalize(...)` as `private` to `Project`.
- [x] Rewrite `init(version:tracks:selectedTrackID:)` to call `normalize`.
- [x] Rewrite `init(version:tracks:trackGroups:...)` to call `normalize` — delete the duplicated let-chains.
- [x] Rewrite `init(from decoder:)` to call `normalize` — delete its duplicated let-chains.
- [x] Create `Tests/SequencerAITests/Document/ProjectNormalizationTests.swift` with the four cases above.
- [x] `xcodebuild -scheme SequencerAI test` — green (new tests + existing tests).
- [x] Commit: `refactor(document): consolidate Project init normalization through shared helper`

---

## Task 5: Extract method clusters into `Project+*.swift` extension files

**Scope:** Split the bulk of `Project`'s method body across cohesive extensions, following the `+TrackSources` precedent. Each extension file holds methods that belong to one responsibility cluster. `Project.swift` ends up as stored properties, `.empty`, `CodingKeys`, private `syncPhrasesWithTracks`, a couple of single-line accessors (`patternLayer`, `layer(id:)`), and the two designated initializers that call the Task-4 `normalize` helper.

**Files:** (all NEW, all in `Sources/Document/`)

- `Project+Codable.swift` — `init(from decoder:)`, `encode(to:)`, private `NormalizedFields`, private `normalize(...)` (moved from `Project.swift` post-Task-4).
- `Project+Tracks.swift` — `appendTrack(trackType:)`, `removeSelectedTrack()`, `setSelectedTrackType(_:)`, `static defaultTrackName(for:index:)`, `static defaultPitches(for:)`, `static defaultStepPattern(for:)`, `static defaultDestination(for:)` (kept `static` on `Project`, just relocated to this file).
- `Project+Phrases.swift` — `appendPhrase()`, `insertPhrase(below:)`, `duplicateSelectedPhrase()`, `duplicatePhrase(id:)`, `removeSelectedPhrase()`, `removePhrase(id:)`, `static defaultPhraseName(for:)`.
- `Project+PhraseCells.swift` — `cell(for:layerID:phraseID:)`, `updatePhrase(id:_:)`, `setPhraseCell`, `setPhraseCellMode`, `selectedPatternIndex(for:)`, `setSelectedPatternIndex`.
- `Project+Patterns.swift` — `patternBank(for:)`, `selectedPattern(for:)`, `selectedSourceRef(for:)`, `selectedSourceMode(for:)`, `setPatternSourceMode`, `setPatternName`, private `defaultSourceRef(for:trackType:)`, `static defaultPatternBanks(...)`, `static syncPatternBanks(...)`.
- `Project+Routes.swift` — `routesSourced(from:)`, `routesTargeting(_:)`, `makeDefaultRoute(from:)`, `upsertRoute`, `removeRoute`.
- `Project+Groups.swift` — `group(for:)`, `tracksInGroup(_:)`, `addGroup`, `addToGroup`, `removeFromGroup`.
- `Project+Selection.swift` — `selectedTrackIndex`, `selectedTrack` (computed property — stays unchanged for this plan), `selectedPhraseIndex`, `selectedPhrase`, `selectTrack(id:)`, `selectPhrase(id:)`.
- `Project+DrumKit.swift` — `addDrumKit(_:)` (consumes `DrumKitPreset` from `Musical/`).

`Project.swift` final contents:

```swift
import Foundation

struct Project: Codable, Equatable {
    var version: Int
    var tracks: [StepSequenceTrack]
    var trackGroups: [TrackGroup]
    var generatorPool: [GeneratorPoolEntry]
    var clipPool: [ClipPoolEntry]
    var layers: [PhraseLayerDefinition]
    var routes: [Route]
    var patternBanks: [TrackPatternBank]
    var selectedTrackID: UUID
    var phrases: [PhraseModel]
    var selectedPhraseID: UUID

    enum CodingKeys: String, CodingKey {
        case version, tracks, trackGroups, generatorPool, clipPool
        case layers, routes, patternBanks, selectedTrackID, phrases, selectedPhraseID
    }

    static let empty = Project(/* … unchanged … */)

    var patternLayer: PhraseLayerDefinition? {
        layers.first(where: { $0.target == .patternIndex })
    }

    func layer(id: String) -> PhraseLayerDefinition? {
        layers.first(where: { $0.id == id })
    }

    init(version: Int, tracks: [StepSequenceTrack], selectedTrackID: UUID) { /* calls normalize */ }
    init(version: Int, tracks: [StepSequenceTrack], trackGroups: [TrackGroup] = [], /* … */) { /* calls normalize */ }

    mutating func syncPhrasesWithTracks() { /* unchanged; becomes internal, not private — used from extension files */ }
}
```

Note `syncPhrasesWithTracks` must change from `private` to no-access-modifier (internal) so extension files can call it. (Extensions in the same module can access `internal` members of the main type.)

**Tests:** Pure file reorganization. Existing suite green. No new tests.

**Subtleties:**
- `CodingKeys` becomes `enum CodingKeys: String, CodingKey` (non-private) so `Project+Codable.swift` can reach it. (In Swift, `private` members of a type are not visible to extensions in other files — `fileprivate` would work only within `Project.swift`; `internal` or no-modifier makes it visible to the whole target, which is fine for a Codable enum.)
- `NormalizedFields` and `normalize(...)` can stay `private` because they only need to be visible within `Project+Codable.swift`.
- Each extension file starts with `import Foundation`; add `import` for anything else only if needed (most extensions need only `Project`'s own types).
- Verify each extension file compiles stand-alone — it should only use `Project` stored properties plus the other extension methods. No cycle is possible because extensions share a type's namespace.
- `syncPhrasesWithTracks` is called from `Project+Tracks.swift` (`appendTrack`, `removeSelectedTrack`, `setSelectedTrackType`) and `Project+Groups.swift` is a candidate but doesn't currently call it; it relies on `Project.init` / `syncPhrasesWithTracks` to prune orphan group memberIDs. Leave the current call sites as-is.

- [x] Create `Project+Codable.swift` — move `init(from:)`, `encode(to:)`, `NormalizedFields`, `normalize(...)` from `Project.swift`.
- [x] Create `Project+Tracks.swift` — move the track CRUD methods + static default-factories.
- [x] Create `Project+Phrases.swift` — move phrase CRUD + `defaultPhraseName`.
- [x] Create `Project+PhraseCells.swift` — move cell getters + setters + `updatePhrase`.
- [x] Create `Project+Patterns.swift` — move pattern-bank accessors + setters + static helpers.
- [x] Create `Project+Routes.swift` — move route methods.
- [x] Create `Project+Groups.swift` — move group methods.
- [x] Create `Project+Selection.swift` — move selection accessors and setters.
- [x] Create `Project+DrumKit.swift` — move `addDrumKit`.
- [x] Strip `Project.swift` down to the core — stored properties, `CodingKeys`, `.empty`, `patternLayer`, `layer(id:)`, `syncPhrasesWithTracks`, two initializers.
- [x] Change `private enum CodingKeys` → `enum CodingKeys` (internal) if needed.
- [x] Change `private mutating func syncPhrasesWithTracks()` → `mutating func syncPhrasesWithTracks()` (internal).
- [x] `xcodegen generate`.
- [x] `xcodebuild -scheme SequencerAI test` — green.
- [x] `wc -l Sources/Document/Project.swift` — confirm ≤ 200.
- [x] Commit: `refactor(document): split Project into focused extension files`

---

## Task 6: Verify

**Checks:**
- `wc -l Sources/Document/Project.swift` — ≤ 200.
- `find Sources/Document -name '*.swift' -exec wc -l {} +` — no file touched by this plan over 500 LOC.
- `grep -rn 'Project' Sources/ Tests/ wiki/ docs/` — zero hits.
- `grep -rn 'document\.model' Sources/ Tests/` — zero hits (all replaced by `.project`).
- `grep -rln 'DrumKitPreset\|DrumKitNoteMap' Sources/Document/` — only `DrumKitPreset+Destination.swift`.
- `grep -rln 'DrumKitPreset\|DrumKitNoteMap' Sources/Musical/` — the two new files.
- `xcodebuild -scheme SequencerAI test` — full suite green.
- Launch smoke: the app opens successfully from the current checkout after the refactor.
- Behavioural smoke: project round-trip and drum-kit composition remain covered by the `ProjectTests` / `ProjectNormalizationTests` document slice and the full-suite run.

- [x] All `grep` / `wc` checks pass.
- [x] Test suite green.
- [x] Launch smoke: current-checkout app opens successfully.
- [x] Behavioural smoke: project round-trip and drum-kit creation remain covered by tests.
- [x] Commit: `chore: verify document-as-project-refactor`

---

## Task 7: Tag + mark completed

- [x] Replace `- [x]` with `- [x]` for all completed tasks in this file.
- [x] Add `**Status:** [COMPLETED YYYY-MM-DD]` line directly under `**Parent spec:**`.
- [x] Commit: `docs(plan): mark document-as-project-refactor completed`
- [x] Tag: `git tag -a v0.0.12-document-as-project-refactor -m "Document model renamed to Project and split into focused extension files"`

---

## Goal-to-task traceability

| Architectural goal | Task |
|---|---|
| Domain type is named `Project`, not `Project` | 1 |
| `SeqAIDocument.model` renamed to `.project` | 1 |
| `StepSequenceTrack` / `TrackType` / `TrackMixSettings` live in own files | 2 |
| `DrumKitNoteMap` / `DrumKitPreset` live in `Musical/` | 3 |
| `DrumKitPreset.suggestedSharedDestination` projection stays in `Document/` | 3 |
| Three Codable-init normalizations unified through one helper | 4 |
| Method clusters split into `Project+*.swift` extensions | 5 |
| `Project.swift` core file ≤ 200 LOC | 5, 6 |
| No file in scope > 500 LOC | 6 |
| Fresh-model round-trip encode/decode remains correct | 6 |

---

## Open questions

- **Task 3 depends on `VoiceTag`'s location.** If `VoiceTag` lives in `Document/`, Task 3 can't move `DrumKitNoteMap` to `Musical/` without first relocating `VoiceTag`. Resolve at task start: grep for `VoiceTag` declaration. If it's a `Document/`-bound type, either (a) move `VoiceTag` to `Musical/` first as a small pre-task, or (b) keep `DrumKitNoteMap` in `Document/` and only move `DrumKitPreset` (which indexes into the map via tag strings, not `VoiceTag` directly). Prefer (a) if `VoiceTag` is a typealias or simple value type.
- **`selectedPatternIndex(for:)` placement.** It reads a phrase cell to derive a pattern index — arguably belongs in either `Project+Patterns.swift` or `Project+PhraseCells.swift`. Current plan puts it in `+PhraseCells`. If the implementer finds that feels forced, moving to `+Patterns` is fine — document the decision in the commit.
- **Coordination with the UI plans.** `ui-organisation-and-track-source-split` and `phrase-workspace-split` both touch `document.project` call sites. This rename should land first so those plans build directly against `Project` / `document.project` instead of creating another churn layer to rebase later.
- **Should `Project.empty` have named convenience factories?** E.g. `Project.empty`, `Project.singleTrack(name:)`, `Project.drumKit(.techno)`. Not in this plan — YAGNI; `Project.empty` plus `addDrumKit` already cover the current call sites.
- **Extension of `Project` from other modules.** Currently none. If a future `Engine/` file wants to add `Project` methods, the extension file must live in `Engine/` not `Document/` (extension location tells you which module owns the addition). Worth a one-line note in `wiki/pages/project-layout.md` when this plan lands.
