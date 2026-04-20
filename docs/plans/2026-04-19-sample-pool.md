# Audio Sample Pool + Package-Based Document Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the project a content-library of audio samples organised by category (kick, snare, hat, etc.), stored inside a package-based `.seqai` document (a directory masquerading as a file, Logic/Live-style). Users drag-and-drop audio files onto the app; the app classifies them by filename, copies the files into the package, and registers `AudioSample` entries in `document.audioSamplePool`. Drum-part tracks' `Destination.sample(sampleID, SamplerSettings)` points at pool entries; per-track sampler settings (gain, transpose, attack, release) are inline on the Destination and do not leak back into the pool. Drum-kit preset flow prefers pool samples for matching categories, with bundled-starter fallback. A sample-picker UI on a drum track offers prev / next / random buttons that walk pool samples of that category, plus an audition button. The document's audioSamplePool is project-local; the shape is future-proofed so a subsequent plan can add a global library pool and a "promote to global" action without rewriting the data model.

Verified end-to-end by: creating a new project, dragging 10 WAV files onto the app, observing them classified and stored inside `<projectName>.seqai/Samples/`, creating a drum kit preset, the member tracks' destinations picking up the pool's kick/snare/hat samples, the prev/next/audition UI cycling and playing them, closing and reopening the project, samples still resolving.

**Architecture:** `.seqai` becomes a **package document** via `ReferenceFileDocument` + SwiftUI `DocumentGroup` + `UTType` declared with `isPackage: true`. On disk the "file" is a directory:

```
MyProject.seqai/
├── document.json               # the existing Project serialised form
└── Samples/
    ├── sample-<UUID>.wav       # copied on import; filename is the sample's UUID for durability
    ├── sample-<UUID>.aif
    └── sample-<UUID>.caf
```

An `AudioFileRef.storage` enum decouples the pool entry's reference from the storage scheme. MVP only implements `.projectPackage(filename: String)` which resolves relative to the document package. A future `.globalLibrary(id: UUID)` case is declared but decodes-only (MVP throws an error if it encounters one); the same data model accepts the global pool later without breaking documents. Migration: existing flat `.seqai` JSON documents open as legacy, get upgraded in place — the legacy file is read, a new package directory is created alongside, document.json is written inside, the old flat file is renamed `<name>.seqai.legacy.json` (preserved for safety).

Sample playback runs through a new lightweight `SamplePlaybackEngine` that manages one `AVAudioPlayerNode` per active voice (bounded pool; MVP = 16 voices project-wide, round-robin reuse for polyphony). Audition goes through a separate preview bus so previewing doesn't collide with transport playback. Sample classification on import uses filename heuristics only (regex table in `SampleClassifier`); audio-analysis-based classification is deferred.

**Tech Stack:** Swift 5.9+, SwiftUI (`ReferenceFileDocument`, `.fileImporter`, `NSItemProvider` drag-drop), AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioFile`), Foundation (`FileManager`, `URL`, `NSFileWrapper` as implementation detail of `FileDocument`), UniformTypeIdentifiers, XCTest. No new package dependencies.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — §"Vocabulary" (new `AudioSample`, `AudioSamplePool`, `SamplerSettings` entries to add), §"Scoping" (project-scoped pool), §"Drum tracks as groups" (sample backing for drum member tracks), §"Platform and stack" (AVAudioEngine sample playback).

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Package-document UTType declaration lives in `project.yml`'s `Info.plist` section.

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.10-sample-pool` at TBD.

**Depends on:**

- `2026-04-19-track-group-reshape.md` — the reshape introduces `Destination.inheritGroup` + `TrackGroup`; this plan adds `Destination.sample(...)`. Can execute after reshape lands. (Alternative: this plan can technically land before reshape since sample-destination is additive; but it's cleaner to reshape first so the drum-kit preset uses the new group model.)

**Deliberately deferred:**

- **Global library pool.** The `.globalLibrary(id:)` case on `AudioFileRef.storage` is stubbed. A future plan adds `~/Library/Application Support/sequencer-ai/global-samples/` as a cross-project pool, plus a "Promote to global" / "Import from global" action in the sample browser.
- **Audio-analysis classification** (spectral centroid, envelope shape). MVP = filename heuristics only.
- **Waveform rendering** in the sampler editor UI. MVP shows sample name + length; waveform bitmaps come later.
- **Loop samples / time-stretch** — category `.loop` exists but samples classified as loop just play one-shot at original speed for MVP.
- **Sample normalise / trim / reverse.** `SamplerSettings` only carries gain/transpose/attack/release in MVP; richer manipulations are a follow-up.
- **FLAC / OGG / OPUS.** MVP accepts WAV, AIFF, CAF, MP3 (AVAudioFile-supported).
- **Polyphony within a drum-part track.** MVP = one voice per track (retrigger stops the previous play).
- **Migration from old flat `.seqai` bigger than "wrap into package"** — if future schema changes break the document model entirely, that's a separate migration plan.

---

## File Structure

```
Sources/
  Document/
    SeqAIDocument.swift                      # MODIFIED — ReferenceFileDocument package
    AudioSample.swift                        # NEW — pool entry value type
    AudioSamplePool.swift                    # NEW — project pool + query helpers
    AudioFileRef.swift                       # NEW — storage enum + resolver
    AudioSampleCategory.swift                # NEW — enum + display
    SamplerSettings.swift                    # NEW — per-Destination sampler knobs
    Destination.swift                        # MODIFIED — add .sample case
    Project.swift                 # MODIFIED — audioSamplePool: AudioSamplePool field
  Audio/
    SampleImporter.swift                     # NEW — file copy into package + pool registration
    SampleClassifier.swift                   # NEW — filename regex heuristics
    SamplePlaybackEngine.swift               # NEW — per-track + preview voice management
    SamplePreviewPlayer.swift                # NEW — dedicated preview audition path
  UI/
    SampleDropOverlay.swift                  # NEW — whole-window drag-drop target + import confirmation sheet
    SamplerDestinationEditor.swift           # NEW — prev/next/random/audition/replace
    SampleBrowserSheet.swift                 # NEW — all pool samples grouped by category
    DetailView.swift                         # MODIFIED — embed SamplerDestinationEditor for .sample destinations
    TrackDestinationEditor.swift             # MODIFIED — route sample-destination UI through SamplerDestinationEditor
Tests/
  SequencerAITests/
    Document/
      AudioSampleTests.swift
      AudioSamplePoolTests.swift
      AudioFileRefTests.swift
      SamplerSettingsTests.swift
      DestinationSampleTests.swift
      PackageDocumentMigrationTests.swift
    Audio/
      SampleClassifierTests.swift
      SampleImporterTests.swift                # uses tempDir package
      SamplePlaybackEngineTests.swift          # integration-tagged; uses system DLSMusicDevice fallback
    UI/
      SampleDropOverlayTests.swift
      SamplerDestinationEditorTests.swift
```

`project.yml` gains an `Info.plist` `CFBundleDocumentTypes` entry for the `.seqai` UTType with `LSTypeIsPackage: true`, and additional `CFBundleDocumentTypes` for the audio file UTTypes the drop target accepts.

---

## Task 1: `AudioSampleCategory` + `AudioSample` + `AudioFileRef`

**Scope:** Three small value types. `AudioSample` is minimal per the earlier decision — no gain, no pitch, no tags, no bpm. Just content identity.

**Files:**
- Create: `Sources/Document/AudioSampleCategory.swift`
- Create: `Sources/Document/AudioSample.swift`
- Create: `Sources/Document/AudioFileRef.swift`
- Create: `Tests/SequencerAITests/Document/AudioSampleTests.swift`
- Create: `Tests/SequencerAITests/Document/AudioFileRefTests.swift`

**Types:**

```swift
public enum AudioSampleCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case kick, snare, sidestick, clap
    case hatClosed, hatOpen, hatPedal
    case tomLow, tomMid, tomHi
    case ride, crash, cowbell, tambourine, shaker
    case percussion                       // catchall drum-ish
    case oneShotSynth, oneShotVocal       // non-drum one-shots
    case loop                             // multi-bar loop
    case unknown                          // classifier couldn't decide

    public var displayName: String { ... }
    public var isDrumVoice: Bool { ... }  // true for kick..shaker; false for oneShot/loop/unknown
}

public struct AudioSample: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String                // user-editable; defaults from filename at import
    public var fileRef: AudioFileRef
    public var category: AudioSampleCategory
    public var lengthSeconds: Double?      // filled on import via AVAudioFile; optional
    public let importDate: Date
}

public enum AudioFileRef: Codable, Equatable, Hashable, Sendable {
    /// Sample file lives inside the project package under Samples/<filename>.
    /// Filename is durable (UUID-based) — never a human filename.
    case projectPackage(filename: String)

    /// Future: global library pool. MVP decodes OK but resolver throws `.unsupportedScope`.
    case globalLibrary(id: UUID)

    public enum ResolveError: Swift.Error, Equatable {
        case missing                      // file not on disk
        case unsupportedScope             // .globalLibrary in MVP
        case noPackageRoot                // project not package-backed (legacy in-progress migration)
    }
}
```

**Tests:**

1. `AudioSampleCategory.allCases.count >= 19` (all enum cases present).
2. `AudioSampleCategory.kick.isDrumVoice == true`; `AudioSampleCategory.loop.isDrumVoice == false`.
3. Round-trip Codable for `AudioSample`.
4. `AudioFileRef.projectPackage(filename:)` round-trips.
5. `AudioFileRef.globalLibrary(id:)` round-trips (even though resolver won't handle it in MVP).
6. Unknown raw string → decode error.

- [ ] Tests
- [ ] Implement
- [ ] `xcodebuild test` green
- [ ] Commit: `feat(document): AudioSample + AudioSampleCategory + AudioFileRef`

---

## Task 2: `AudioSamplePool`

**Scope:** Project-scoped container with query helpers.

**Files:**
- Create: `Sources/Document/AudioSamplePool.swift`
- Create: `Tests/SequencerAITests/Document/AudioSamplePoolTests.swift`

**Type:**

```swift
public struct AudioSamplePool: Codable, Equatable, Sendable {
    public var samples: [AudioSample]

    public init(samples: [AudioSample] = [])

    public func samples(in category: AudioSampleCategory) -> [AudioSample]
    public func sample(id: UUID) -> AudioSample?
    public func firstSample(in category: AudioSampleCategory) -> AudioSample?

    /// Cycle to the next sample in the same category. Returns the input's id if it's the only
    /// sample in that category; returns nil if the category is empty.
    public func nextSample(after id: UUID) -> UUID?
    public func previousSample(before id: UUID) -> UUID?
    public func randomSample(in category: AudioSampleCategory) -> AudioSample?

    public mutating func add(_ sample: AudioSample)
    public mutating func remove(id: UUID)
    public mutating func recategorise(id: UUID, to category: AudioSampleCategory)
}
```

**Tests:**

1. Empty pool: `samples(in: .kick).isEmpty`; `firstSample(in: .kick) == nil`.
2. Add 3 kicks + 1 snare: `samples(in: .kick).count == 3`; `samples(in: .snare).count == 1`.
3. `nextSample(after:)` cycles within category; wraps from last to first.
4. `previousSample(before:)` cycles in reverse; wraps.
5. `randomSample(in:)` returns a member of the requested category over 1000 draws (statistical).
6. `remove(id:)` drops the entry.
7. `recategorise(id:to:)` moves the sample between category query results.
8. Round-trip Codable.

- [ ] Tests (8 cases)
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): AudioSamplePool with category queries`

---

## Task 3: `SamplerSettings` + `Destination.sample`

**Scope:** The per-use settings and the new Destination variant.

**Files:**
- Create: `Sources/Document/SamplerSettings.swift`
- Modify: `Sources/Document/Destination.swift`
- Create: `Tests/SequencerAITests/Document/SamplerSettingsTests.swift`
- Create: `Tests/SequencerAITests/Document/DestinationSampleTests.swift`

**Types:**

```swift
public struct SamplerSettings: Codable, Equatable, Sendable {
    public var gain: Double             // dB, -60..+12, default 0
    public var transpose: Int           // semitones, default 0
    public var attackMs: Double         // 0..2000, default 0
    public var releaseMs: Double        // 0..5000, default 0

    public static let `default` = SamplerSettings(
        gain: 0, transpose: 0, attackMs: 0, releaseMs: 0
    )
}

public enum Destination: Codable, Equatable, Sendable {
    case midi(port: MIDIEndpointName?, channel: UInt8, noteOffset: Int)
    case auInstrument(componentID: AudioComponentID, stateBlob: Data?)
    case internalSampler(bankID: InternalSamplerBankID, preset: String)
    case sample(sampleID: UUID, settings: SamplerSettings)     // NEW
    case inheritGroup
    case none
}
```

**Tests:**

1. `SamplerSettings.default` has all zeroes (gain/transpose) / empties (attack/release).
2. Round-trip Codable.
3. Bounds are expressed as clamp extensions (not stored constraints): `clamped()` returns values within gain[-60,+12], transpose[-48,+48], attack[0,2000], release[0,5000].
4. `Destination.sample(...)` round-trips. Equality compares both sampleID and settings.
5. Two `Destination.sample` with same id but different settings are unequal.

- [ ] Tests
- [ ] Implement SamplerSettings + Destination.sample
- [ ] Green
- [ ] Commit: `feat(document): SamplerSettings + Destination.sample variant`

---

## Task 4: Package-based `SeqAIDocument`

**Scope:** Migrate the FileDocument to a package directory. `document.json` inside the package holds the current `Project` JSON; `Samples/` directory hosts copied-in audio files.

**Files:**
- Modify: `Sources/Document/SeqAIDocument.swift` — change `FileDocument` → `ReferenceFileDocument`; conform to package UTType; implement `read(configuration:)` and `snapshot`/`fileWrapper(snapshot:configuration:)` appropriately
- Modify: `project.yml` — add UTType declaration with `LSTypeIsPackage: true`; add accepted audio UTTypes
- Create: `Sources/Document/PackageHelpers.swift` — utilities: resolve the project package URL from a document's read context; get/create `Samples/` subdirectory URL; write/read `document.json`
- Create: `Tests/SequencerAITests/Document/PackageDocumentMigrationTests.swift`

**Legacy migration:**

On `read(configuration:)`:

1. If `configuration.file` is a directory (`isDirectory == true`): read `document.json` inside, decode as usual. This is the new-format path.
2. If it's a flat file: legacy format. Read the JSON. Decode. Flag `needsPackageUpgrade = true`.
3. On next save, the flat file path is renamed to `<path>.legacy.json` and a new package directory is created at the original path. `document.json` gets written inside; `Samples/` dir created empty.

Legacy upgrade happens automatically once; the `.legacy.json` sidecar stays around as a safety net (user can delete).

**Tests:**

1. Reading a flat `.seqai` JSON file produces a document + sets `needsPackageUpgrade` on a session-state flag.
2. Saving after legacy read creates the package directory AND the `.legacy.json` sidecar.
3. Reading a new-format package produces the same document without the upgrade flag.
4. Saving a new-format document writes `document.json` inside the package.
5. `PackageHelpers.samplesDirectoryURL(for:)` returns `<package>/Samples/`; creates the directory if absent.

- [ ] Tests (use `FileManager` + tempDir)
- [ ] Implement `ReferenceFileDocument` + helpers
- [ ] Legacy-flat-file → package migration path
- [ ] Green
- [ ] Commit: `feat(document): package-based .seqai document + legacy flat-file migration`

---

## Task 5: `AudioFileRef` resolver against package

**Scope:** Given an `AudioFileRef.projectPackage(filename:)` and a document's package URL, return a usable `URL`. Throw structured errors on missing files or unsupported scopes.

**Files:**
- Modify: `Sources/Document/AudioFileRef.swift`
- Modify: `Tests/SequencerAITests/Document/AudioFileRefTests.swift`

**API:**

```swift
extension AudioFileRef {
    public func resolve(in packageRoot: URL) throws -> URL {
        switch self {
        case .projectPackage(let filename):
            let url = packageRoot.appendingPathComponent("Samples").appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ResolveError.missing
            }
            return url
        case .globalLibrary:
            throw ResolveError.unsupportedScope
        }
    }
}
```

**Tests:**

1. Resolve a `.projectPackage` ref against a temp package with the file present → returns correct URL.
2. Resolve against a package missing the file → `ResolveError.missing`.
3. Resolve a `.globalLibrary` ref → `ResolveError.unsupportedScope`.

- [ ] Tests
- [ ] Implement resolver
- [ ] Green
- [ ] Commit: `feat(document): AudioFileRef.resolve against package root`

---

## Task 6: `SampleClassifier` — filename heuristics

**Scope:** Regex table → `AudioSampleCategory`. Pure function; no file I/O.

**Files:**
- Create: `Sources/Audio/SampleClassifier.swift`
- Create: `Tests/SequencerAITests/Audio/SampleClassifierTests.swift`

**Implementation:**

```swift
public enum SampleClassifier {
    /// Given a filename (with or without extension), returns a best-guess category.
    /// Returns .unknown if no heuristic matches.
    public static func classify(filename: String) -> AudioSampleCategory {
        let lower = filename.lowercased()
        for rule in RULES where rule.pattern.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            return rule.category
        }
        return .unknown
    }

    private struct Rule { let pattern: NSRegularExpression; let category: AudioSampleCategory }

    private static let RULES: [Rule] = [
        // Order matters: more specific first.
        try! Rule(pattern: #"\b(open.?hat|ohh|oh)\b"#,     category: .hatOpen),
        try! Rule(pattern: #"\b(pedal.?hat|ph)\b"#,        category: .hatPedal),
        try! Rule(pattern: #"\b(closed.?hat|ch|hh|hat)\b"#, category: .hatClosed),
        try! Rule(pattern: #"\b(kick|bd|bass.?drum|kik)\b"#, category: .kick),
        try! Rule(pattern: #"\b(snare|sd|snr)\b"#,         category: .snare),
        try! Rule(pattern: #"\b(sidestick|rim)\b"#,        category: .sidestick),
        try! Rule(pattern: #"\b(clap|handclap|cp)\b"#,     category: .clap),
        try! Rule(pattern: #"\b(tom.?hi|high.?tom|th)\b"#, category: .tomHi),
        try! Rule(pattern: #"\b(tom.?mid|mid.?tom|tm)\b"#, category: .tomMid),
        try! Rule(pattern: #"\b(tom.?lo|low.?tom|floor.?tom|tl)\b"#, category: .tomLow),
        try! Rule(pattern: #"\b(ride|rd)\b"#,              category: .ride),
        try! Rule(pattern: #"\b(crash|cr)\b"#,             category: .crash),
        try! Rule(pattern: #"\b(cowbell|cb)\b"#,           category: .cowbell),
        try! Rule(pattern: #"\b(tambourine|tamb)\b"#,      category: .tambourine),
        try! Rule(pattern: #"\b(shaker|shk)\b"#,           category: .shaker),
        try! Rule(pattern: #"\b(loop|lp)\b"#,              category: .loop),
        try! Rule(pattern: #"\b(vocal|vox|vocalchop)\b"#,  category: .oneShotVocal),
        try! Rule(pattern: #"\b(oneshot|one.?shot|stab|shot)\b"#, category: .oneShotSynth),
        try! Rule(pattern: #"\b(perc|percussion|shaker|bongo|conga)\b"#, category: .percussion)
    ]
}
```

**Tests:**

```swift
// exhaustive: each filename → expected category
XCTAssertEqual(SampleClassifier.classify(filename: "KICK_808_deep.wav"), .kick)
XCTAssertEqual(SampleClassifier.classify(filename: "snare_acoustic_05.aif"), .snare)
XCTAssertEqual(SampleClassifier.classify(filename: "OH_bright.wav"), .hatOpen)
XCTAssertEqual(SampleClassifier.classify(filename: "ch_dense_03.wav"), .hatClosed)
XCTAssertEqual(SampleClassifier.classify(filename: "BD_sub.caf"), .kick)
XCTAssertEqual(SampleClassifier.classify(filename: "TM_mid.aiff"), .tomMid)
XCTAssertEqual(SampleClassifier.classify(filename: "vocal_chop_01.wav"), .oneShotVocal)
XCTAssertEqual(SampleClassifier.classify(filename: "loop_130bpm_drums.wav"), .loop)
XCTAssertEqual(SampleClassifier.classify(filename: "random_noise.wav"), .unknown)
```

~20-30 cases in the test table covering each category + ambiguous cases + case-insensitive + false positives (a track named "kickstarter.wav" should still be .kick — acceptable false positive; user can override).

- [ ] Tests (exhaustive table)
- [ ] Implement classifier
- [ ] Green
- [ ] Commit: `feat(audio): SampleClassifier filename heuristics`

---

## Task 7: `SampleImporter` — copy into package + register in pool

**Scope:** Given a dropped URL and a document, copy the file into the package's `Samples/` directory with a UUID-based filename, create an `AudioSample` entry, return it. Does not mutate the document directly — caller appends to `pool`.

**Files:**
- Create: `Sources/Audio/SampleImporter.swift`
- Create: `Tests/SequencerAITests/Audio/SampleImporterTests.swift`

**API:**

```swift
public enum SampleImporter {
    public struct ImportResult {
        public let sample: AudioSample
        public let copiedURL: URL       // new location in the package
    }

    public enum ImportError: Swift.Error, Equatable {
        case sourceNotFound
        case unsupportedFormat           // extension not in the whitelist
        case copyFailed(String)
        case packageNotWritable
    }

    /// Copy the file at `sourceURL` into the document package's Samples/ directory
    /// (creating the directory if needed), with a filename of the form
    /// "sample-<UUID>.<ext>". Returns an AudioSample tagged with the classifier's
    /// guess.
    public static func `import`(
        from sourceURL: URL,
        into packageRoot: URL,
        now: Date = Date()
    ) throws -> ImportResult
}
```

Accepts extensions: `.wav`, `.aif`, `.aiff`, `.caf`, `.mp3`, `.m4a`.

Fills `AudioSample.lengthSeconds` by opening the copied file via `AVAudioFile` and dividing frame count by sample rate.

**Tests:**

1. Import a real WAV from a fixture: result's copied file exists in `<packageRoot>/Samples/sample-<UUID>.wav`; `AudioSample.category` reflects the classifier output; `AudioSample.lengthSeconds` > 0.
2. Import a file with unsupported extension → `unsupportedFormat` error.
3. Import a missing path → `sourceNotFound` error.
4. Import a file with a name that looks like a kick → `AudioSample.category == .kick`.
5. Import a file with unclassifiable name → `.unknown`.

Fixtures: pre-generate tiny test WAV files (0.1 seconds of silence) in the test target bundle.

- [ ] Tests
- [ ] Implement importer + fixtures
- [ ] Green
- [ ] Commit: `feat(audio): SampleImporter — copy into package + pool registration`

---

## Task 8: Wire `audioSamplePool` onto the document model

**Scope:** Add the field; thread through Codable with a legacy default.

**Files:**
- Modify: `Sources/Document/Project.swift`
- Modify: `Tests/SequencerAITests/Document/SeqAIDocumentTests.swift`

**Change:**

```swift
public struct Project: Codable, Equatable {
    // existing fields ...
    public var audioSamplePool: AudioSamplePool = AudioSamplePool()
    // ...
}
```

Codable: absent field defaults to empty pool. Existing documents decode unchanged.

**Tests:**

1. Fresh document has `audioSamplePool.samples.isEmpty`.
2. Legacy JSON without `audioSamplePool` key decodes with empty pool.
3. Append a sample; round-trip the document; sample persists.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): audioSamplePool field on project model`

---

## Task 9: `SamplePlaybackEngine` + `SamplePreviewPlayer`

**Scope:** Audio-engine components that actually play samples. Lightweight MVP: one shared `AVAudioEngine` with N `AVAudioPlayerNode` voices (MVP = 16). Each note trigger on a `.sample` destination grabs an idle voice or steals the oldest.

**Files:**
- Create: `Sources/Audio/SamplePlaybackEngine.swift`
- Create: `Sources/Audio/SamplePreviewPlayer.swift`
- Create: `Tests/SequencerAITests/Audio/SamplePlaybackEngineTests.swift` (integration-tagged)

**API:**

```swift
public final class SamplePlaybackEngine {
    public init()
    public func start() throws
    public func stop()

    /// Play a sample via the main voice pool. Scheduled at `when` (host time).
    /// Returns a voice handle that the caller can use to stop early.
    public func play(
        sampleURL: URL,
        settings: SamplerSettings,
        at when: AVAudioTime?
    ) throws -> VoiceHandle

    public func stopVoice(_ handle: VoiceHandle)
    public func stopAll()
}

public final class SamplePreviewPlayer {
    public init()
    public func audition(sampleURL: URL) throws     // single-voice preview, stops any previous audition
    public func stop()
}
```

`VoiceHandle` is a lightweight token (UUID wrapped) the engine uses to cancel a voice.

**Engine wiring:** `EngineController` holds one `SamplePlaybackEngine`. Tick-time: when `effectiveDestination(for:)` returns `.sample(sampleID, settings)`, resolve `sample.fileRef.resolve(in: packageRoot)`, call `engine.play(sampleURL:settings:at:)`. For MVP sample events play immediately at tick time; sample-accurate scheduling is deferred to the audio-timing plan.

**Tests (integration-tagged, may skip if AVAudioEngine can't run in the CI env):**

1. Play a test WAV: returns a VoiceHandle; no crash.
2. Play-and-stop: `stopVoice(handle)` silences within a few ms.
3. Settings.gain changes output level (verify by measuring peak amplitude — or trust AVFoundation here and skip).
4. 17 rapid plays (exceeds pool size): oldest voice gets stolen; no crash.
5. Preview player: audition twice in quick succession; only the second one plays; first is cancelled.

- [ ] Tests (integration-tagged)
- [ ] Implement engine + preview player
- [ ] Wire from EngineController
- [ ] Green (skips acceptable if CI can't open audio)
- [ ] Commit: `feat(audio): SamplePlaybackEngine + SamplePreviewPlayer`

---

## Task 10: `SampleDropOverlay` — drag-drop import UI

**Scope:** Overlay that accepts file drops on the whole app window; opens an import confirmation sheet listing the dropped files with guessed categories + user-editable dropdown; Confirm kicks off `SampleImporter.import(...)` for each and appends to the pool.

**Files:**
- Create: `Sources/UI/SampleDropOverlay.swift`
- Modify: `Sources/UI/ContentView.swift` — embed the overlay at the root
- Create: `Tests/SequencerAITests/UI/SampleDropOverlayTests.swift`

**Behaviour:**

- Root view attaches `.onDrop(of: [.audio], isTargeted: $isDragging)` for audio UTTypes
- During drag, dim the window and show "Drop samples to import"
- On drop, collect URLs → show `SampleImportConfirmationSheet` with a list row per file:
  - Filename
  - Guessed category (dropdown, user-editable)
  - Remove button
- Confirm imports all remaining rows via `SampleImporter`; appends to `document.project.audioSamplePool.samples`
- Cancel abandons — no files copied

**Tests:**

- Behavioural:

1. Dropping 3 files opens the sheet with 3 rows.
2. Sheet's category dropdown updates the row's classification.
3. Removing a row drops it from the import list.
4. Confirm calls `SampleImporter.import` once per remaining row; pool grows by that count.

- [ ] Tests (spy on `SampleImporter`)
- [ ] Implement overlay + sheet
- [ ] Green
- [ ] Commit: `feat(ui): drag-drop sample import overlay`

---

## Task 11: `SamplerDestinationEditor` — prev / next / random / audition / replace

**Scope:** The per-track editor when `track.destination` is `.sample(...)`.

**Files:**
- Create: `Sources/UI/SamplerDestinationEditor.swift`
- Modify: `Sources/UI/TrackDestinationEditor.swift` — branch on destination kind; render `SamplerDestinationEditor` when `.sample`
- Create: `Tests/SequencerAITests/UI/SamplerDestinationEditorTests.swift`

**View shape:**

```swift
struct SamplerDestinationEditor: View {
    @Binding var destination: Destination                 // must be .sample; other cases are a precondition
    @Binding var pool: AudioSamplePool
    let packageRoot: URL
    let previewPlayer: SamplePreviewPlayer

    var body: some View {
        // Resolve current sample + settings from destination
        // Show: sample name + category pill + length
        // Controls: [←] [rand] [→] [▶ audition] [Replace…]
        // Below: gain slider, transpose stepper, attack/release sliders
        // Tapping Replace opens SampleBrowserSheet
    }
}
```

Prev/next walk `pool.samples(in: sample.category)`; wrap. Random picks one from the same category. Audition plays through `previewPlayer`. Replace opens a browser sheet showing all samples grouped by category.

**Tests:**

1. Renders sample name + category label from the referenced pool entry.
2. Next button: destination.sampleID updates to the next sample in the category.
3. Wrap: Next on the last sample wraps to the first.
4. Previous: wraps symmetrically.
5. Random: picks a sample from the same category; different from current in ~80% of runs.
6. Audition: calls `previewPlayer.audition(sampleURL:)` with the resolved URL.
7. Gain slider: updates `destination.sample.settings.gain`; clamped to [-60, +12].
8. Replace opens the browser sheet.

- [ ] Tests
- [ ] Implement SamplerDestinationEditor
- [ ] Green
- [ ] Commit: `feat(ui): SamplerDestinationEditor (prev/next/random/audition/settings)`

---

## Task 12: `SampleBrowserSheet`

**Scope:** Modal showing all pool samples grouped by category. User clicks one to select as the track's sample; Close dismisses without change.

**Files:**
- Create: `Sources/UI/SampleBrowserSheet.swift`
- Create: `Tests/SequencerAITests/UI/SampleBrowserSheetTests.swift`

**View shape:**

- Grouped list: one section per `AudioSampleCategory` that has samples in the pool
- Each section header: category display name + count
- Each row: sample name + length; tap selects; checkmark on the currently-selected sample
- Search field at top filters by name (case-insensitive)
- "Import…" button at bottom opens the system file picker to import more samples

**Tests:**

1. Empty pool: renders empty state "No samples yet — drop files here or click Import".
2. 3 kicks + 2 snares: 2 sections; "Kick (3)" and "Snare (2)"; rows per sample.
3. Search "808": filters to matching names.
4. Tap a row: calls the selection callback with the sample's UUID; dismisses.
5. Import button: opens `.fileImporter` (state verification).

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(ui): SampleBrowserSheet`

---

## Task 13: Drum-kit preset integration

**Scope:** Update the reshape plan's `addDrumKit(preset:)` flow to prefer pool samples when available.

**Files:**
- Modify: `Sources/Document/Project.swift` — `addDrumKit(_:)` method (added by reshape plan); this plan updates its body
- Modify: `Tests/SequencerAITests/Document/DrumKitPresetTests.swift` (from reshape plan)

**Logic change:**

For each member track of a preset:

1. Query `document.audioSamplePool.firstSample(in: member.tagCategory)` where `tagCategory = member.tag → AudioSampleCategory` (kick, snare, hatClosed, etc.)
2. If found: `track.destination = .sample(sampleID: firstSample.id, settings: .default)`
3. If not found: `track.destination = .internalSampler(bank: .drumKitDefault, preset: preset.fallbackPresetName(for: tag))` — bundled starter

**Tests:**

1. `addDrumKit(.kit808)` on a document whose pool has a kick sample: the kick track's destination = `.sample(kickSampleID, .default)`.
2. `addDrumKit(.kit808)` on an empty pool: all member tracks fall back to `.internalSampler(...)`.
3. "Apply Project Samples" button re-runs the preference logic against the current pool (extension method: `document.applyPoolSamples(to groupID: TrackGroupID)`).

- [ ] Tests
- [ ] Implement `applyPoolSamples` + update `addDrumKit`
- [ ] Green
- [ ] Commit: `feat(document): drum-kit preset prefers pool samples; applyPoolSamples action`

---

## Task 14: Wiki + project-layout

**Scope:** Document the sample pool + package model.

**Files:**
- Create: `wiki/pages/audio-sample-pool.md`
- Modify: `wiki/pages/project-layout.md`
- Modify: `wiki/pages/track-destinations.md` — note `.sample` destination path

Content of the new page: package structure, sample lifecycle (import → classify → copy → pool entry → reference from destinations), sampler settings as per-use, classifier heuristics summary, future global-library stub.

- [ ] Wiki
- [ ] Commit: `docs(wiki): audio-sample-pool page + layout update`

---

## Task 15: Tag + mark completed

- [ ] Replace `- [ ]` with `- [x]` for completed steps
- [ ] Add `Status:` line after `Parent spec`
- [ ] Commit: `docs(plan): mark sample-pool completed`
- [ ] Tag: `git tag -a v0.0.10-sample-pool -m "Audio sample pool + package document: AudioSample pool, .seqai package, drag-drop import with classification, Destination.sample + SamplerSettings, sampler prev/next/random/audition UI, drum-kit preset pool integration"`

---

## Goal-to-task traceability (self-review)

| Goal / architectural claim | Task |
|---|---|
| `AudioSample` + `AudioSampleCategory` + `AudioFileRef` | Task 1 |
| `AudioSamplePool` + category queries | Task 2 |
| `SamplerSettings` + `Destination.sample` | Task 3 |
| Package-based `.seqai` document + legacy migration | Task 4 |
| `AudioFileRef.resolve` against package | Task 5 |
| Filename classifier | Task 6 |
| Sample importer copies into package + registers in pool | Task 7 |
| `audioSamplePool` on document model | Task 8 |
| Sample playback engine + preview | Task 9 |
| Drag-drop import UI | Task 10 |
| SamplerDestinationEditor (prev/next/random/audition/settings) | Task 11 |
| SampleBrowserSheet | Task 12 |
| Drum-kit preset prefers pool samples | Task 13 |
| Wiki | Task 14 |
| Tag | Task 15 |

## Open questions resolved for this plan

- **Storage model:** package-based `.seqai`, `Samples/` subdirectory inside. Sample filenames are UUID-based for durability (renaming the sample in the pool doesn't touch the file on disk). Legacy flat JSON `.seqai` documents auto-upgrade on open; the pre-upgrade file is renamed `.legacy.json` as a safety net.
- **Global pool future-proofing:** `AudioFileRef.globalLibrary(id:)` case declared but unimplemented. MVP resolver throws `.unsupportedScope` on it; documents can still decode refs they don't resolve. A future plan lights up global-library lookup + a "Promote to global" action on pool entries + an "Import from global" UX; the data model accepts them without change.
- **Per-sample gain/pitch:** NOT on the sample. Per-use settings (`SamplerSettings`) live on `Destination.sample(...)`. Renaming or re-categorising a sample in the pool does NOT reset any track's sampler settings.
- **Classifier:** filename heuristics only for MVP. Audio-analysis (spectral centroid, envelope) deferred.
- **Polyphony:** one voice per drum-part track. Retrigger stops the previous play. Project-wide polyphony cap = 16 voices across all tracks (round-robin reuse).
- **Supported audio formats:** WAV, AIFF, CAF, MP3, M4A. AVAudioFile-native. FLAC/OGG/OPUS deferred.
- **Embedded vs external file trade-off:** embedded (inside package) wins for this plan. Self-contained documents, no broken references when users move files, cross-machine portability. Documents with 50+ samples may reach hundreds of MB — acceptable; users expect this from Logic/Live projects.
- **Sample duplication on import:** if the user drops the same file twice, we create two pool entries with separate UUIDs + separate copies inside the package. Deduplication by content hash is a future optimisation.
- **Promote-to-global stub:** the SampleBrowserSheet's context menu includes a disabled "Promote to global library (coming soon)" entry as a signpost.
- **Manual AU smoke test reference:** unlike the track-destinations plan (which wanted a manual smoke before tagging), this plan can ship tagged with automated tests alone — the AVAudioEngine integration is well-covered by SamplePlaybackEngineTests (or will skip on constrained test envs). No manual gate.
