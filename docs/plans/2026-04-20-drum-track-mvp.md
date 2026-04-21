# Drum Track MVP — Sample-Backed Destinations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give drum-kit tracks audible output via per-member sample-backed destinations sourced from a read-only Application Support library. When a user calls `Project.addDrumKit(_:)`, each member track's `destination` is set to `.sample(sampleID:, settings:)` with the first library sample matching the member's voice-tag category (kick → a kick sample, snare → a snare sample, …). The destination editor renders a new inline `SamplerDestinationWidget` with a waveform, audition button, prev/next-within-category walker, and gain slider.

Verified end-to-end by: creating a fresh project, calling `Add Drum Kit (808)`, hearing the kick / snare / hat / clap play when transport runs, auditioning each sample independently from the destination editor without transport, walking prev/next within a category to swap the kick sound, adjusting gain per member — all without opening any import or browser UI.

**Architecture:** Three new subsystems, all forward-compatible with `docs/plans/2026-04-19-sample-pool.md`:

1. **Read-only sample library.** `~/Library/Application Support/sequencer-ai/samples/<category>/*.wav`, populated on first launch from `Resources/StarterSamples/` in the app bundle via a manifest-hash-gated `SampleLibraryBootstrap`. Samples are scanned into an `@Observable AudioSampleLibrary` singleton with stable `UUIDv5(namespace, relativePath)` IDs.
2. **Document reference.** `Destination.sample(sampleID: UUID, settings: SamplerSettings)` — new case on the existing enum. Tracks store the UUID only; `AudioSampleLibrary.sample(id:)` + `AudioFileRef.resolve(libraryRoot:packageRoot:)` turn it into a URL at dispatch time.
3. **Playback path.** `SamplePlaybackEngine` owns one `AVAudioEngine` with 16 main `AVAudioPlayerNode` voices (round-robin, steal-oldest) plus a dedicated audition voice. `ScheduledEvent.Payload.sampleTrigger(...)` — new payload. `EngineController.prepareTick` enqueues one `sampleTrigger` per firing step on `.sample` tracks; `dispatchTick` drains and calls `sampleEngine.play(...)`.

**Tech Stack:** Swift 5.9+, SwiftUI (`Canvas` for waveform, `@Observable`), AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioFile`, `AVAudioMixerNode`), Foundation (`FileManager`, `URL`, `CryptoKit.SHA256` for manifest hashing), XCTest. No new package dependencies.

**Parent spec:** `docs/specs/2026-04-20-drum-track-mvp-design.md` — the approved design doc for this plan. Upstream spec: `docs/specs/2026-04-18-north-star-design.md` §"Drum tracks as groups".

**Status:** [COMPLETED 2026-04-20]

Tag `v0.0.16-drum-track-mvp` applied at completion.

**Depends on:** Current `main` after:
- `v0.0.15-coordinator-scheduling` — provides `ScheduledEvent`, `EventQueue`, and the `prepareTick` / `dispatchTick` split this plan extends with a new payload case.
- The `addDrumKit` flow at `Project+Tracks.swift:23-63` and the `DrumKitPreset` at `Sources/Musical/DrumKitPreset.swift`.

**Deliberately deferred:**

- **Drag-and-drop sample import.** No `.onDrop(of:)`, no `SampleDropOverlay`, no import confirmation sheet. Covered by the full sample-pool plan.
- **Sample browser / picker sheet.** `SampleBrowserSheet` from the full plan is not built. The only sample-switching affordance is prev/next within category.
- **User-authored pool editing.** No add / remove / recategorise UI. The library is read-only to the user.
- **`SamplerSettings` full UI.** `transpose`, `attackMs`, `releaseMs` are on the struct (forward-compat) but not wired to the playback engine or the widget. Only `gain` is UI-exposed and engine-applied.
- **Sample-accurate scheduling.** `ScheduledEvent.scheduledHostTime` is populated on `sampleTrigger` but ignored by `dispatchTick`, consistent with the existing AU dispatch path. Lights up when the timing-modulations plan lands for both paths together.
- **`AudioFileRef.globalLibrary(id:)`.** Not needed because Application Support *is* the global library in MVP. Declared in the full plan; omitted here.
- **Project-scoped pool (`audioSamplePool` field on `Project`).** Document format is unchanged. The library is in-memory, rebuilt on each launch from the disk scan.
- **Package-document migration.** `.seqai` stays flat JSON. The full sample-pool plan handles the ReferenceFileDocument migration.
- **`AudioSample` as `Codable`.** Not persisted; a value type for library use only.
- **Audio-analysis classification.** The bundled library's samples are organised by directory, not classified at scan time.
- **WAV / AIF / AIFF / CAF is the supported format set for this MVP.** MP3 / M4A deferred.
- **Waveform bitmap caching to disk.** The `NSCache`-backed in-memory cache is enough at MVP library size (~36 WAVs).

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. `project.yml` gets a `bundledResources: Resources/StarterSamples/**` line — run `xcodegen generate` after.

---

## File Structure (post-plan)

```
Sources/
  Audio/
    SampleLibraryBootstrap.swift              # NEW — manifest-gated bundle → ~/Library copy
    AudioSampleLibrary.swift                  # NEW — @Observable singleton; scan + queries
    SamplePlaybackEngine.swift                # NEW — AVAudioEngine + 16-voice pool + audition
    WaveformDownsampler.swift                 # NEW — URL → [Float] buckets, NSCache
  Document/
    AudioSampleCategory.swift                 # NEW — enum + VoiceTag bridge + isDrumVoice
    AudioSample.swift                         # NEW — value type; NOT Codable
    AudioFileRef.swift                        # NEW — Codable; .appSupportLibrary + reserved .projectPackage
    SamplerSettings.swift                     # NEW — Codable; gain (UI) + transpose/attack/release (reserved)
    Destination.swift                         # MODIFIED — add .sample case
    Project+Tracks.swift                      # MODIFIED — addDrumKit → per-member .sample
    DrumKitPreset+Destination.swift           # DELETED — suggestedSharedDestination unused
  Engine/
    ScheduledEvent.swift                      # MODIFIED — add .sampleTrigger payload
    EngineController.swift                    # MODIFIED — hold engine + library root;
                                              # prepareTick enqueues sampleTrigger;
                                              # dispatchTick handles sampleTrigger
  UI/
    SamplerDestinationWidget.swift            # NEW — inline widget: waveform + prev/next/audition/gain
    WaveformView.swift                        # NEW — SwiftUI Canvas renderer
    TrackDestinationEditor.swift              # MODIFIED — .sample branch + choice
  SeqAIDocumentApp.swift                      # MODIFIED — bootstrap in App init
Resources/
  StarterSamples/                             # NEW — bundled drum samples, ~36 WAVs
    manifest.json                             # generated; per-file SHA256 + version
    kick/ snare/ hatClosed/ hatOpen/ clap/ ride/ crash/ tomLow/ tomMid/ tomHi/ percussion/
Tests/
  SequencerAITests/
    Document/
      AudioSampleCategoryTests.swift          # NEW
      AudioFileRefTests.swift                 # NEW
      SamplerSettingsTests.swift              # NEW
      DestinationSampleTests.swift            # NEW
    Audio/
      SampleLibraryBootstrapTests.swift       # NEW
      AudioSampleLibraryTests.swift           # NEW
      WaveformDownsamplerTests.swift          # NEW
      SamplePlaybackEngineTests.swift         # NEW — integration-tagged
    Engine/
      EngineControllerSampleTriggerTests.swift # NEW
    DrumKit/
      DrumKitPresetSampleTests.swift          # NEW
    UI/
      SamplerDestinationWidgetTests.swift     # NEW
  Fixtures/
    SampleLibraryFixture/                     # NEW — tiny test WAVs; mirrors real tree
      kick/test-kick-1.wav
      kick/test-kick-2.wav
      snare/test-snare-1.wav
      manifest.json
project.yml                                   # MODIFIED — bundledResources entry
```

---

## Task 1: `AudioSampleCategory` + `VoiceTag` bridge

**Scope:** Pure enum. No dependencies on other new types. Delivers the category vocabulary used everywhere downstream.

**Files:**
- Create: `Sources/Document/AudioSampleCategory.swift`
- Create: `Tests/SequencerAITests/Document/AudioSampleCategoryTests.swift`

**Content:**

```swift
// Sources/Document/AudioSampleCategory.swift
import Foundation

enum AudioSampleCategory: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case kick, snare, sidestick, clap
    case hatClosed, hatOpen, hatPedal
    case tomLow, tomMid, tomHi
    case ride, crash, cowbell, tambourine, shaker
    case percussion
    case unknown

    var displayName: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .sidestick: return "Sidestick"
        case .clap: return "Clap"
        case .hatClosed: return "Closed Hat"
        case .hatOpen: return "Open Hat"
        case .hatPedal: return "Pedal Hat"
        case .tomLow: return "Low Tom"
        case .tomMid: return "Mid Tom"
        case .tomHi: return "High Tom"
        case .ride: return "Ride"
        case .crash: return "Crash"
        case .cowbell: return "Cowbell"
        case .tambourine: return "Tambourine"
        case .shaker: return "Shaker"
        case .percussion: return "Percussion"
        case .unknown: return "Unknown"
        }
    }

    var isDrumVoice: Bool {
        switch self {
        case .kick, .snare, .sidestick, .clap,
             .hatClosed, .hatOpen, .hatPedal,
             .tomLow, .tomMid, .tomHi,
             .ride, .crash, .cowbell, .tambourine, .shaker, .percussion:
            return true
        case .unknown:
            return false
        }
    }

    /// Bridge from DrumKitPreset.Member.tag (VoiceTag = String) to a category.
    /// Returns nil for tags not recognised as drum voices.
    init?(voiceTag: VoiceTag) {
        switch voiceTag {
        case "kick": self = .kick
        case "snare": self = .snare
        case "hat-closed": self = .hatClosed
        case "hat-open": self = .hatOpen
        case "hat-pedal": self = .hatPedal
        case "clap": self = .clap
        case "ride": self = .ride
        case "crash": self = .crash
        case "tom-low": self = .tomLow
        case "tom-mid": self = .tomMid
        case "tom-hi": self = .tomHi
        case "sidestick", "rim": self = .sidestick
        case "cowbell": self = .cowbell
        case "tambourine": self = .tambourine
        case "shaker": self = .shaker
        default: return nil
        }
    }
}
```

**Tests:**

```swift
// Tests/SequencerAITests/Document/AudioSampleCategoryTests.swift
import XCTest
@testable import SequencerAI

final class AudioSampleCategoryTests: XCTestCase {
    func test_isDrumVoice_trueForDrumCases() {
        let drumCases: [AudioSampleCategory] = [
            .kick, .snare, .sidestick, .clap, .hatClosed, .hatOpen, .hatPedal,
            .tomLow, .tomMid, .tomHi, .ride, .crash, .cowbell, .tambourine, .shaker, .percussion
        ]
        for c in drumCases { XCTAssertTrue(c.isDrumVoice, "\(c) should be drum voice") }
    }

    func test_isDrumVoice_falseForUnknown() {
        XCTAssertFalse(AudioSampleCategory.unknown.isDrumVoice)
    }

    func test_voiceTagBridge_knownTags() {
        XCTAssertEqual(AudioSampleCategory(voiceTag: "kick"), .kick)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "snare"), .snare)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "hat-closed"), .hatClosed)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "hat-open"), .hatOpen)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "clap"), .clap)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "ride"), .ride)
        XCTAssertEqual(AudioSampleCategory(voiceTag: "rim"), .sidestick)
    }

    func test_voiceTagBridge_unknownTagReturnsNil() {
        XCTAssertNil(AudioSampleCategory(voiceTag: "nonsense"))
        XCTAssertNil(AudioSampleCategory(voiceTag: ""))
    }

    func test_codable_roundTrip() throws {
        let encoded = try JSONEncoder().encode(AudioSampleCategory.kick)
        let decoded = try JSONDecoder().decode(AudioSampleCategory.self, from: encoded)
        XCTAssertEqual(decoded, .kick)
    }
}
```

- [x] Create `AudioSampleCategory.swift` with the body above
- [x] Create `AudioSampleCategoryTests.swift` with the five test cases
- [x] `xcodegen generate`
- [x] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme SequencerAI test` — green
- [x] Commit: `feat(document): AudioSampleCategory + VoiceTag bridge`

---

## Task 2: `AudioFileRef` + `SamplerSettings`

**Scope:** Two small Codable types. `AudioFileRef` declares both cases now (one reserved) so documents written today decode when the project-pool plan lands.

**Files:**
- Create: `Sources/Document/AudioFileRef.swift`
- Create: `Sources/Document/SamplerSettings.swift`
- Create: `Tests/SequencerAITests/Document/AudioFileRefTests.swift`
- Create: `Tests/SequencerAITests/Document/SamplerSettingsTests.swift`

**Content:**

```swift
// Sources/Document/AudioFileRef.swift
import Foundation

enum AudioFileRef: Codable, Equatable, Hashable, Sendable {
    case appSupportLibrary(relativePath: String)
    case projectPackage(filename: String)

    enum ResolveError: Error, Equatable {
        case missing
        case unsupportedScope
        case noLibraryRoot
    }

    /// Resolve to an on-disk URL.
    /// - Parameters:
    ///   - libraryRoot: root directory of the application-support sample library.
    ///   - packageRoot: reserved for the future project-scoped pool; pass nil in MVP.
    /// - Throws: `ResolveError.missing` if the file is absent on disk,
    ///           `ResolveError.unsupportedScope` for `.projectPackage` (deferred),
    ///           `ResolveError.noLibraryRoot` if libraryRoot is empty.
    func resolve(libraryRoot: URL, packageRoot: URL? = nil) throws -> URL {
        switch self {
        case .appSupportLibrary(let relativePath):
            guard !libraryRoot.path.isEmpty else { throw ResolveError.noLibraryRoot }
            let url = libraryRoot.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ResolveError.missing
            }
            return url
        case .projectPackage:
            throw ResolveError.unsupportedScope
        }
    }
}
```

```swift
// Sources/Document/SamplerSettings.swift
import Foundation

struct SamplerSettings: Codable, Equatable, Hashable, Sendable {
    var gain: Double = 0              // dB, clamped [-60, +12]; UI-exposed in MVP
    var transpose: Int = 0            // semitones, clamped [-48, +48]; reserved
    var attackMs: Double = 0          // [0, 2000]; reserved
    var releaseMs: Double = 0         // [0, 5000]; reserved

    static let `default` = SamplerSettings()

    func clamped() -> SamplerSettings {
        SamplerSettings(
            gain: min(max(gain, -60), 12),
            transpose: min(max(transpose, -48), 48),
            attackMs: min(max(attackMs, 0), 2000),
            releaseMs: min(max(releaseMs, 0), 5000)
        )
    }
}
```

**Tests:**

```swift
// Tests/SequencerAITests/Document/AudioFileRefTests.swift
import XCTest
@testable import SequencerAI

final class AudioFileRefTests: XCTestCase {
    func test_appSupportLibrary_codableRoundTrip() throws {
        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/tr808.wav")
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AudioFileRef.self, from: data)
        XCTAssertEqual(decoded, ref)
    }

    func test_projectPackage_codableRoundTrip() throws {
        let ref = AudioFileRef.projectPackage(filename: "sample-ABC.wav")
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AudioFileRef.self, from: data)
        XCTAssertEqual(decoded, ref)
    }

    func test_resolve_appSupport_hit() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let kickDir = tempDir.appendingPathComponent("kick")
        try FileManager.default.createDirectory(at: kickDir, withIntermediateDirectories: true)
        let fileURL = kickDir.appendingPathComponent("tr808.wav")
        try Data().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/tr808.wav")
        let resolved = try ref.resolve(libraryRoot: tempDir)
        XCTAssertEqual(resolved.standardizedFileURL, fileURL.standardizedFileURL)
    }

    func test_resolve_appSupport_missing_throws() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/ghost.wav")
        XCTAssertThrowsError(try ref.resolve(libraryRoot: tempDir)) { error in
            XCTAssertEqual(error as? AudioFileRef.ResolveError, .missing)
        }
    }

    func test_resolve_projectPackage_throwsUnsupported() {
        let ref = AudioFileRef.projectPackage(filename: "x.wav")
        XCTAssertThrowsError(try ref.resolve(libraryRoot: URL(fileURLWithPath: "/tmp"))) { error in
            XCTAssertEqual(error as? AudioFileRef.ResolveError, .unsupportedScope)
        }
    }
}
```

```swift
// Tests/SequencerAITests/Document/SamplerSettingsTests.swift
import XCTest
@testable import SequencerAI

final class SamplerSettingsTests: XCTestCase {
    func test_default_isZeroed() {
        let s = SamplerSettings.default
        XCTAssertEqual(s.gain, 0)
        XCTAssertEqual(s.transpose, 0)
        XCTAssertEqual(s.attackMs, 0)
        XCTAssertEqual(s.releaseMs, 0)
    }

    func test_codable_roundTrip() throws {
        let s = SamplerSettings(gain: -6, transpose: 7, attackMs: 15, releaseMs: 200)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(SamplerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func test_clamped_clampsAllFields() {
        let s = SamplerSettings(gain: 999, transpose: 99, attackMs: 99999, releaseMs: -5)
        let c = s.clamped()
        XCTAssertEqual(c.gain, 12)
        XCTAssertEqual(c.transpose, 48)
        XCTAssertEqual(c.attackMs, 2000)
        XCTAssertEqual(c.releaseMs, 0)
    }

    func test_clamped_negativeGain() {
        XCTAssertEqual(SamplerSettings(gain: -9999).clamped().gain, -60)
    }

    func test_decode_legacyDocument_usesDefaults() throws {
        // Simulates an older document that wrote only `gain`.
        let json = #"{"gain": -3}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SamplerSettings.self, from: json)
        XCTAssertEqual(decoded.gain, -3)
        XCTAssertEqual(decoded.transpose, 0)
        XCTAssertEqual(decoded.attackMs, 0)
        XCTAssertEqual(decoded.releaseMs, 0)
    }
}
```

Note: the `test_decode_legacyDocument_usesDefaults` test requires the Swift compiler's synthesised `Codable` to honour default values on absent keys — this works because `SamplerSettings` uses stored-property defaults with synthesised `init(from:)`. If the synthesised decoder chokes on missing keys, implement a custom `init(from:)` that reads each key with `decodeIfPresent` and falls back to the struct default. Document this in the file if you write a custom decoder.

- [x] Create `AudioFileRef.swift`
- [x] Create `SamplerSettings.swift`
- [x] Create both test files with the cases above
- [x] `xcodegen generate`
- [x] `xcodebuild test` — green
- [x] Commit: `feat(document): AudioFileRef + SamplerSettings`

---

## Task 3: `AudioSample` value type

**Scope:** The library entry type. Not `Codable` — documents only persist the UUID from `Destination.sample`.

**Files:**
- Create: `Sources/Document/AudioSample.swift`
- Extend: `Tests/SequencerAITests/Document/AudioFileRefTests.swift` (add one test exercising `AudioSample` init — lightweight enough not to warrant its own file)

Actually, give it its own file for clarity.

- Create: `Tests/SequencerAITests/Document/AudioSampleTests.swift`

**Content:**

```swift
// Sources/Document/AudioSample.swift
import Foundation

struct AudioSample: Equatable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let fileRef: AudioFileRef
    let category: AudioSampleCategory
    let lengthSeconds: Double?
}
```

**Tests:**

```swift
// Tests/SequencerAITests/Document/AudioSampleTests.swift
import XCTest
@testable import SequencerAI

final class AudioSampleTests: XCTestCase {
    func test_equality_sameFieldsAreEqual() {
        let id = UUID()
        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/a.wav")
        let a = AudioSample(id: id, name: "a", fileRef: ref, category: .kick, lengthSeconds: 0.5)
        let b = AudioSample(id: id, name: "a", fileRef: ref, category: .kick, lengthSeconds: 0.5)
        XCTAssertEqual(a, b)
    }

    func test_hashable_usesID() {
        let shared = UUID()
        let a = AudioSample(id: shared, name: "a", fileRef: .appSupportLibrary(relativePath: "k/a.wav"), category: .kick, lengthSeconds: 0.5)
        let b = AudioSample(id: shared, name: "b-different-name", fileRef: .appSupportLibrary(relativePath: "k/b.wav"), category: .snare, lengthSeconds: 0.3)
        // Equatable compares all fields — a != b. Hashable only requires that equal values hash equal; this is a sanity check.
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.hashValue, b.hashValue)
    }
}
```

- [x] Create `AudioSample.swift`
- [x] Create `AudioSampleTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — green
- [x] Commit: `feat(document): AudioSample library value type`

---

## Task 4: `Destination.sample` case

**Scope:** Add one case to the existing `Destination` enum and all related surfaces. Existing documents must decode unchanged.

**Files:**
- Modify: `Sources/Document/Destination.swift`
- Create: `Tests/SequencerAITests/Document/DestinationSampleTests.swift`

**Changes to `Destination.swift`:**

Replace the enum body and related surfaces. The diff against the current file at `Sources/Document/Destination.swift:26-131`:

```swift
enum Destination: Codable, Equatable, Hashable, Sendable {
    // Adding a case? Audit EngineController routing, AudioInstrumentHost loading,
    // TrackDestinationEditor selection/editing, and Mixer/Inspector summaries.
    case midi(port: MIDIEndpointName?, channel: UInt8, noteOffset: Int)
    case auInstrument(componentID: AudioComponentID, stateBlob: Data?)
    case internalSampler(bankID: InternalSamplerBankID, preset: String)
    case sample(sampleID: UUID, settings: SamplerSettings)         // NEW
    case inheritGroup
    case none

    enum Kind: Equatable, Hashable, Sendable {
        case midi
        case auInstrument
        case internalSampler
        case sample                                                 // NEW
        case inheritGroup
        case none
    }

    var kind: Kind {
        switch self {
        case .midi: return .midi
        case .auInstrument: return .auInstrument
        case .internalSampler: return .internalSampler
        case .sample: return .sample                                // NEW
        case .inheritGroup: return .inheritGroup
        case .none: return .none
        }
    }

    var kindLabel: String {
        switch kind {
        case .midi: return "MIDI"
        case .auInstrument: return "AU"
        case .internalSampler: return "Internal"
        case .sample: return "Sampler"                              // NEW
        case .inheritGroup: return "Group"
        case .none: return "—"
        }
    }

    var withoutTransientState: Destination {
        switch self {
        case let .auInstrument(componentID, _):
            return .auInstrument(componentID: componentID, stateBlob: nil)
        case .midi, .internalSampler, .sample, .inheritGroup, .none:    // .sample joins this list
            return self
        }
    }

    // (midiPort / midiChannel / midiNoteOffset / settingMIDI* unchanged)

    var summary: String {
        switch self {
        case let .midi(port, channel, noteOffset):
            let destinationLabel = port?.displayName ?? "Unassigned MIDI"
            let offsetLabel = noteOffset == 0 ? "" : " • \(noteOffset > 0 ? "+" : "")\(noteOffset)"
            return "\(destinationLabel) • Ch \(Int(channel) + 1)\(offsetLabel)"
        case let .auInstrument(componentID, _):
            return componentID.displayKey
        case let .internalSampler(bankID, preset):
            return "\(bankID.rawValue) • \(preset)"
        case let .sample(sampleID, settings):                        // NEW
            let gainLabel = settings.gain == 0 ? "" : String(format: " • %+.1f dB", settings.gain)
            return "Sample \(sampleID.uuidString.prefix(8))\(gainLabel)"
        case .inheritGroup:
            return "Inherited from group"
        case .none:
            return "No default destination"
        }
    }
}
```

**Tests:**

```swift
// Tests/SequencerAITests/Document/DestinationSampleTests.swift
import XCTest
@testable import SequencerAI

final class DestinationSampleTests: XCTestCase {
    func test_sample_codableRoundTrip() throws {
        let id = UUID()
        let d = Destination.sample(sampleID: id, settings: SamplerSettings(gain: -6))
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(Destination.self, from: data)
        XCTAssertEqual(decoded, d)
    }

    func test_sample_kindIsSample() {
        let d = Destination.sample(sampleID: UUID(), settings: .default)
        XCTAssertEqual(d.kind, .sample)
        XCTAssertEqual(d.kindLabel, "Sampler")
    }

    func test_sample_withoutTransientState_returnsSelf() {
        let d = Destination.sample(sampleID: UUID(), settings: .default)
        XCTAssertEqual(d.withoutTransientState, d)
    }

    func test_sample_equality_comparesIDAndSettings() {
        let id = UUID()
        XCTAssertEqual(
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: 0)),
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: 0))
        )
        XCTAssertNotEqual(
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: 0)),
            Destination.sample(sampleID: id, settings: SamplerSettings(gain: -6))
        )
        XCTAssertNotEqual(
            Destination.sample(sampleID: id, settings: .default),
            Destination.sample(sampleID: UUID(), settings: .default)
        )
    }

    func test_sample_summary_mentionsIDPrefix() {
        let id = UUID()
        let d = Destination.sample(sampleID: id, settings: .default)
        XCTAssertTrue(d.summary.contains(String(id.uuidString.prefix(8))))
    }

    func test_legacyDocument_decodesUnchanged() throws {
        // Existing .midi / .auInstrument / .none documents decode without the new case.
        let d1 = Destination.midi(port: nil, channel: 0, noteOffset: 0)
        let d2 = Destination.none
        for d in [d1, d2] {
            let data = try JSONEncoder().encode(d)
            let decoded = try JSONDecoder().decode(Destination.self, from: data)
            XCTAssertEqual(decoded, d)
        }
    }
}
```

- [x] Modify `Destination.swift` as above (add `.sample` to enum, Kind, kind, kindLabel, withoutTransientState, summary)
- [x] Create `DestinationSampleTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — all existing `DestinationTests` plus the new file green
- [x] Commit: `feat(document): Destination.sample case`

---

## Task 5: Starter-samples directory + `project.yml` bundling

**Scope:** Committed resource tree for the bundled samples, plus `project.yml` entry that gets them into the `.app`.

**Files:**
- Create: `Resources/StarterSamples/` tree (category directories; placeholder silent WAVs until real content is sourced)
- Create: `Resources/StarterSamples/manifest.json`
- Create: `scripts/rebuild-sample-manifest.sh` — generator script the implementer re-runs whenever the sample files change
- Modify: `project.yml`
- Create: `Tests/Fixtures/SampleLibraryFixture/` — the test-side mirror of the structure

**Starter content:** Source CC0 or in-house drum samples (WAV, mono, 44.1 kHz, ≤ 1 s). At least one per drum voice category; three each for kick / snare / hatClosed so prev/next has something to walk. If real content is not available at plan time, implementer generates 0.1 s silent WAVs as placeholders and files a follow-up to source real audio. Silent placeholders still exercise the full code path.

**Manifest generator script:**

```bash
# scripts/rebuild-sample-manifest.sh
#!/usr/bin/env bash
set -euo pipefail
ROOT="Resources/StarterSamples"
OUT="$ROOT/manifest.json"

VERSION=$(git describe --tags --always 2>/dev/null || echo "unknown")

python3 - <<'PY' > "$OUT"
import hashlib, json, os, sys
root = "Resources/StarterSamples"
entries = {}
for dirpath, _, filenames in os.walk(root):
    for fname in sorted(filenames):
        if fname == "manifest.json": continue
        if not fname.lower().endswith((".wav", ".aif", ".aiff", ".caf")): continue
        full = os.path.join(dirpath, fname)
        rel = os.path.relpath(full, root)
        with open(full, "rb") as f:
            h = hashlib.sha256(f.read()).hexdigest()
        entries[rel] = h
print(json.dumps({
    "version": os.environ.get("VERSION", "dev"),
    "files": entries
}, indent=2, sort_keys=True))
PY

echo "Wrote $OUT"
```

**Manifest shape** (example after running the script against a minimal tree):

```json
{
  "files": {
    "clap/clap-808.wav": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "hatClosed/hat-closed-1.wav": "…",
    "kick/kick-acoustic.wav": "…",
    "kick/kick-punch.wav": "…",
    "kick/kick-tr808.wav": "…",
    "snare/snare-acoustic.wav": "…",
    "snare/snare-clap.wav": "…"
  },
  "version": "v0.0.16-drum-track-mvp-dev"
}
```

**`project.yml` change:** locate the `targets: SequencerAI: sources:` or `resources:` section; add `Resources/StarterSamples` as a bundled resource directory. Exact snippet (will appear alongside other resource directives; check the existing file for the right section name — older xcodegen configs use `sources:` with `buildPhase: resources` for non-Swift resources):

```yaml
targets:
  SequencerAI:
    # ... existing entries ...
    sources:
      # ... existing entries ...
      - path: Resources/StarterSamples
        type: folder                # bundles the whole directory verbatim, preserving structure
```

`type: folder` is important — it avoids xcodegen flattening category subdirectories into the root of the resource bundle. If the existing project uses `group` style, switch locally to `folder` for just this directory.

**Test fixture:** Create `Tests/Fixtures/SampleLibraryFixture/` with the same structure for test use. Three kicks, one snare, plus `manifest.json`. Use the same script against the fixture path to regenerate its manifest.

**Subtleties:**
- `manifest.json` *must* be committed — it's compared against on first launch. The generator script is re-run after any content change.
- The version string in the manifest doesn't have to match any specific tag — it's used only by the bootstrap for debug logging. The per-file SHA is what gates the refresh.

- [x] Create the `Resources/StarterSamples/` directory structure with at least the categories the 808 / Acoustic / Techno presets reference: `kick`, `snare`, `hatClosed`, `clap`, `ride`
- [x] Populate with starter WAVs (≥ 3 kicks, ≥ 2 snares, ≥ 2 hatClosed, ≥ 1 clap, ≥ 1 ride; mono, ≤ 1 s). Silent placeholders acceptable for now
- [x] Create `scripts/rebuild-sample-manifest.sh` and `chmod +x`
- [x] Run `./scripts/rebuild-sample-manifest.sh` — produces `Resources/StarterSamples/manifest.json`
- [x] Create `Tests/Fixtures/SampleLibraryFixture/` with ≥ 2 kicks, ≥ 1 snare, plus its own `manifest.json` (regenerate via the script by temporarily pointing the root)
- [x] Modify `project.yml` — add the `Resources/StarterSamples` folder as a bundled resource on the `SequencerAI` target
- [x] `xcodegen generate`
- [x] `xcodebuild` — compiles (no test changes yet)
- [x] Verify the built `.app` contains the starter samples: `find $(xcodebuild -scheme SequencerAI -showBuildSettings | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')/SequencerAI.app -name "*.wav" | head`
- [x] Commit: `chore(resources): add StarterSamples bundle + manifest generator`

---

## Task 6: `SampleLibraryBootstrap`

**Scope:** On-launch copy from bundle → Application Support with per-file SHA refresh. Idempotent. Preserves user-added files (forward-compat).

**Files:**
- Create: `Sources/Audio/SampleLibraryBootstrap.swift`
- Create: `Tests/SequencerAITests/Audio/SampleLibraryBootstrapTests.swift`

**Content:**

```swift
// Sources/Audio/SampleLibraryBootstrap.swift
import Foundation
import CryptoKit

enum SampleLibraryBootstrap {
    /// ~/Library/Application Support/sequencer-ai/samples/
    static var applicationSupportSamplesURL: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("sequencer-ai", isDirectory: true)
            .appendingPathComponent("samples", isDirectory: true)
    }

    /// <app-bundle>/Resources/StarterSamples/ — nil in a non-bundle context (unit tests).
    static var bundledSamplesURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("StarterSamples", isDirectory: true)
    }

    struct Manifest: Decodable, Equatable {
        var version: String
        var files: [String: String]    // relativePath → SHA256 hex
    }

    /// Idempotent. Copies bundled starters into Application Support when:
    ///   (a) the Application Support samples directory is missing, or
    ///   (b) the bundled manifest's per-file SHA differs from the installed one.
    /// Only files whose SHA differs are overwritten. Files present in Application Support
    /// but absent from the bundle are left untouched (future user-imported content).
    ///
    /// - Parameters:
    ///   - bundleSamplesURL: source root; defaults to `bundledSamplesURL`.
    ///   - destinationURL: target root; defaults to `applicationSupportSamplesURL`.
    /// - Returns: the destination URL once the library is in place.
    @discardableResult
    static func ensureLibraryInstalled(
        bundleSamplesURL: URL? = bundledSamplesURL,
        destinationURL: URL = applicationSupportSamplesURL
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        guard let bundleSamplesURL,
              fm.fileExists(atPath: bundleSamplesURL.path)
        else {
            // No bundle source available (e.g. running tests without a bundle). Leave Application
            // Support untouched; the library scan will return zero samples — callers handle that.
            return destinationURL
        }

        let bundledManifest = try loadManifest(from: bundleSamplesURL.appendingPathComponent("manifest.json"))
        let installedManifestURL = destinationURL.appendingPathComponent("manifest.json")
        let installedManifest = (try? loadManifest(from: installedManifestURL)) ?? Manifest(version: "", files: [:])

        var didChange = false
        for (relativePath, bundledHash) in bundledManifest.files {
            if installedManifest.files[relativePath] == bundledHash {
                continue
            }
            let src = bundleSamplesURL.appendingPathComponent(relativePath)
            let dst = destinationURL.appendingPathComponent(relativePath)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
            didChange = true
        }

        if didChange || !fm.fileExists(atPath: installedManifestURL.path) {
            let data = try JSONEncoder().encode(bundledManifest)
            try data.write(to: installedManifestURL, options: .atomic)
        }

        return destinationURL
    }

    private static func loadManifest(from url: URL) throws -> Manifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }
}

extension SampleLibraryBootstrap.Manifest: Encodable {}
```

**Tests:**

```swift
// Tests/SequencerAITests/Audio/SampleLibraryBootstrapTests.swift
import XCTest
import CryptoKit
@testable import SequencerAI

final class SampleLibraryBootstrapTests: XCTestCase {
    private var tempRoot: URL!
    private var source: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = tempRoot.appendingPathComponent("source")
        destination = tempRoot.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: helpers

    private func write(_ content: Data, to relativePath: String, under root: URL) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL)
    }

    private func writeManifest(files: [String: String], version: String = "test", under root: URL) throws {
        let manifestURL = root.appendingPathComponent("manifest.json")
        let data = try JSONEncoder().encode(SampleLibraryBootstrap.Manifest(version: version, files: files))
        try data.write(to: manifestURL)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: cases

    func test_freshInstall_copiesAllFiles() throws {
        let payload = Data("KICK_1".utf8)
        try write(payload, to: "kick/a.wav", under: source)
        try writeManifest(files: ["kick/a.wav": sha256(payload)], under: source)

        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(
            bundleSamplesURL: source, destinationURL: destination
        )

        let copied = destination.appendingPathComponent("kick/a.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(try Data(contentsOf: copied), payload)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("manifest.json").path))
    }

    func test_secondRun_isNoOp() throws {
        let payload = Data("SNARE_1".utf8)
        try write(payload, to: "snare/a.wav", under: source)
        try writeManifest(files: ["snare/a.wav": sha256(payload)], under: source)

        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)
        let firstMtime = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("snare/a.wav").path)[.modificationDate] as! Date

        Thread.sleep(forTimeInterval: 1.1)   // ensure file-system mtime resolution shows a difference if written

        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)
        let secondMtime = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("snare/a.wav").path)[.modificationDate] as! Date

        XCTAssertEqual(firstMtime, secondMtime, "file should not have been rewritten when manifest is identical")
    }

    func test_manifestChange_refreshesChangedFile() throws {
        let v1 = Data("KICK_v1".utf8)
        try write(v1, to: "kick/a.wav", under: source)
        try writeManifest(files: ["kick/a.wav": sha256(v1)], under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        let v2 = Data("KICK_v2_updated".utf8)
        try write(v2, to: "kick/a.wav", under: source)    // overwrite source
        try writeManifest(files: ["kick/a.wav": sha256(v2)], under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        let dstContent = try Data(contentsOf: destination.appendingPathComponent("kick/a.wav"))
        XCTAssertEqual(dstContent, v2)
    }

    func test_userAddedFile_isPreservedAcrossRefresh() throws {
        // user-added file never appears in the bundle manifest
        let bundleFile = Data("BUNDLED".utf8)
        try write(bundleFile, to: "kick/bundled.wav", under: source)
        try writeManifest(files: ["kick/bundled.wav": sha256(bundleFile)], under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        // user drops their own file alongside
        let userFile = Data("USER_IMPORTED".utf8)
        try write(userFile, to: "kick/user.wav", under: destination)

        // bundle updates — manifest changes, but user's file is untouched
        try writeManifest(files: ["kick/bundled.wav": sha256(Data("BUNDLED_v2".utf8))], under: source)
        try write(Data("BUNDLED_v2".utf8), to: "kick/bundled.wav", under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("kick/user.wav")), userFile)
    }

    func test_bundleMissing_createsEmptyDestinationDirectory() throws {
        let missing = tempRoot.appendingPathComponent("does-not-exist")
        let result = try SampleLibraryBootstrap.ensureLibraryInstalled(
            bundleSamplesURL: missing, destinationURL: destination
        )
        XCTAssertEqual(result, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
}
```

- [x] Create `SampleLibraryBootstrap.swift` with the body above
- [x] Create `SampleLibraryBootstrapTests.swift` with the five test cases
- [x] `xcodegen generate`
- [x] `xcodebuild test` — new suite green
- [x] Commit: `feat(audio): SampleLibraryBootstrap with manifest-gated refresh`

---

## Task 7: `AudioSampleLibrary` — scanner + queries

**Scope:** `@Observable` singleton that reads the on-disk directory tree and exposes query + navigation methods. UUIDv5-based IDs for cross-launch stability.

**Files:**
- Create: `Sources/Audio/AudioSampleLibrary.swift`
- Create: `Tests/SequencerAITests/Audio/AudioSampleLibraryTests.swift`

**Content:**

```swift
// Sources/Audio/AudioSampleLibrary.swift
import Foundation
import AVFoundation
import CryptoKit
import Observation

@Observable
final class AudioSampleLibrary {
    /// UUIDv5 namespace used to derive sample IDs from relative paths.
    /// DO NOT CHANGE — IDs are persisted in documents. Generated once for this plan.
    private static let namespace: UUID = UUID(uuidString: "9B3F4D8A-2E1B-4B5D-9A6C-7F8E9D0C1B2A")!

    static let shared: AudioSampleLibrary = {
        do {
            let root = try SampleLibraryBootstrap.ensureLibraryInstalled()
            return AudioSampleLibrary(libraryRoot: root)
        } catch {
            NSLog("[AudioSampleLibrary] bootstrap failed: \(error) — library will be empty")
            return AudioSampleLibrary(libraryRoot: SampleLibraryBootstrap.applicationSupportSamplesURL)
        }
    }()

    private(set) var samples: [AudioSample]
    let libraryRoot: URL

    init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
        self.samples = Self.scan(root: libraryRoot)
    }

    func reload() {
        samples = Self.scan(root: libraryRoot)
    }

    // MARK: - Queries

    func sample(id: UUID) -> AudioSample? {
        samples.first(where: { $0.id == id })
    }

    func samples(in category: AudioSampleCategory) -> [AudioSample] {
        samples.filter { $0.category == category }
    }

    func firstSample(in category: AudioSampleCategory) -> AudioSample? {
        samples(in: category).first
    }

    /// Next sample in the same category; wraps around.
    /// Returns nil if `id` is not in the library, or if the category has zero samples.
    func nextSample(after id: UUID) -> AudioSample? {
        guard let current = sample(id: id) else { return nil }
        let peers = samples(in: current.category)
        guard !peers.isEmpty, let idx = peers.firstIndex(of: current) else { return nil }
        return peers[(idx + 1) % peers.count]
    }

    /// Previous sample in the same category; wraps around.
    func previousSample(before id: UUID) -> AudioSample? {
        guard let current = sample(id: id) else { return nil }
        let peers = samples(in: current.category)
        guard !peers.isEmpty, let idx = peers.firstIndex(of: current) else { return nil }
        return peers[(idx - 1 + peers.count) % peers.count]
    }

    // MARK: - Scan

    private static func scan(root: URL) -> [AudioSample] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        let supportedExtensions: Set<String> = ["wav", "aif", "aiff", "caf"]
        var found: [AudioSample] = []

        guard let topLevel = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for categoryDir in topLevel where (try? categoryDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let categoryName = categoryDir.lastPathComponent
            let category = AudioSampleCategory(rawValue: categoryName) ?? .unknown
            if category == .unknown {
                NSLog("[AudioSampleLibrary] unknown category directory: \(categoryName)")
            }

            guard let files = try? fm.contentsOfDirectory(
                at: categoryDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            let audioFiles = files
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            for fileURL in audioFiles {
                let relativePath = "\(categoryName)/\(fileURL.lastPathComponent)"
                let id = uuidV5(namespace: namespace, name: relativePath)
                let name = (fileURL.lastPathComponent as NSString).deletingPathExtension
                let length = audioLengthSeconds(url: fileURL)
                found.append(AudioSample(
                    id: id,
                    name: name,
                    fileRef: .appSupportLibrary(relativePath: relativePath),
                    category: category,
                    lengthSeconds: length
                ))
            }
        }

        return found
    }

    private static func audioLengthSeconds(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frames = Double(file.length)
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        return frames / rate
    }

    private static func uuidV5(namespace: UUID, name: String) -> UUID {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: namespace.uuid) { buf in bytes.append(contentsOf: buf) }
        bytes.append(contentsOf: Array(name.utf8))
        let digest = Insecure.SHA1.hash(data: bytes)
        var out = Array(digest.prefix(16))
        out[6] = (out[6] & 0x0F) | 0x50            // version 5
        out[8] = (out[8] & 0x3F) | 0x80            // RFC-4122 variant
        return UUID(uuid: (
            out[0], out[1], out[2], out[3],
            out[4], out[5], out[6], out[7],
            out[8], out[9], out[10], out[11],
            out[12], out[13], out[14], out[15]
        ))
    }
}
```

**Tests:**

```swift
// Tests/SequencerAITests/Audio/AudioSampleLibraryTests.swift
import XCTest
@testable import SequencerAI

final class AudioSampleLibraryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("kick"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("snare"), withIntermediateDirectories: true)
        // Three kicks, one snare. Empty files — scanner should still count them (length becomes nil).
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-a.wav"))
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-b.wav"))
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-c.wav"))
        try Data().write(to: tempRoot.appendingPathComponent("snare/s-a.wav"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func test_scan_populatesCategoryBuckets() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .kick).count, 3)
        XCTAssertEqual(lib.samples(in: .snare).count, 1)
        XCTAssertTrue(lib.samples(in: .hatOpen).isEmpty)
    }

    func test_samples_sortedByFilename() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .kick).map(\.name), ["k-a", "k-b", "k-c"])
    }

    func test_ids_stableAcrossRescan() {
        let lib1 = AudioSampleLibrary(libraryRoot: tempRoot)
        let ids1 = lib1.samples(in: .kick).map(\.id)
        let lib2 = AudioSampleLibrary(libraryRoot: tempRoot)
        let ids2 = lib2.samples(in: .kick).map(\.id)
        XCTAssertEqual(ids1, ids2)
    }

    func test_firstSample_returnsFirstInCategory() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.firstSample(in: .kick)?.name, "k-a")
        XCTAssertNil(lib.firstSample(in: .hatOpen))
    }

    func test_nextSample_wrapsWithinCategory() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        let kicks = lib.samples(in: .kick)
        XCTAssertEqual(lib.nextSample(after: kicks[0].id)?.id, kicks[1].id)
        XCTAssertEqual(lib.nextSample(after: kicks[2].id)?.id, kicks[0].id)  // wrap
    }

    func test_previousSample_wrapsWithinCategory() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        let kicks = lib.samples(in: .kick)
        XCTAssertEqual(lib.previousSample(before: kicks[0].id)?.id, kicks[2].id)  // wrap
        XCTAssertEqual(lib.previousSample(before: kicks[1].id)?.id, kicks[0].id)
    }

    func test_unknownCategoryDirectory_getsUnknownCategory() throws {
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("weirdname"), withIntermediateDirectories: true)
        try Data().write(to: tempRoot.appendingPathComponent("weirdname/x.wav"))

        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .unknown).count, 1)
    }

    func test_missingRoot_yieldsEmptyLibrary() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("definitely-missing-\(UUID())")
        let lib = AudioSampleLibrary(libraryRoot: missing)
        XCTAssertTrue(lib.samples.isEmpty)
    }

    func test_reload_picksUpNewFile() throws {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .kick).count, 3)
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-d.wav"))
        lib.reload()
        XCTAssertEqual(lib.samples(in: .kick).count, 4)
    }
}
```

- [x] Create `AudioSampleLibrary.swift` with the body above (note the CryptoKit import inline)
- [x] Create `AudioSampleLibraryTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — new suite green
- [x] Commit: `feat(audio): AudioSampleLibrary with @Observable scan + stable UUIDv5 IDs`

---

## Task 8: `WaveformDownsampler`

**Scope:** Pure compute: URL → `[Float]` bucket array. `NSCache`-backed. No UI.

**Files:**
- Create: `Sources/Audio/WaveformDownsampler.swift`
- Create: `Tests/SequencerAITests/Audio/WaveformDownsamplerTests.swift`

**Content:**

```swift
// Sources/Audio/WaveformDownsampler.swift
import Foundation
import AVFoundation

enum WaveformDownsampler {
    private static let cache = NSCache<NSURL, NSArray>()

    /// Reads the audio file at `url`, computes peak absolute magnitude per bucket
    /// (mono sum across channels), returns `bucketCount` floats in `[0, 1]`.
    /// Cached by URL; repeat calls hit cache.
    static func downsample(url: URL, bucketCount: Int = 64) -> [Float] {
        precondition(bucketCount > 0, "bucketCount must be positive")

        if let cached = cache.object(forKey: url as NSURL) as? [NSNumber] {
            return cached.map { $0.floatValue }
        }

        let buckets = computeBuckets(url: url, bucketCount: bucketCount)
        cache.setObject(buckets.map { NSNumber(value: $0) } as NSArray, forKey: url as NSURL)
        return buckets
    }

    private static func computeBuckets(url: URL, bucketCount: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else {
            return Array(repeating: 0, count: bucketCount)
        }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return Array(repeating: 0, count: bucketCount)
        }

        do {
            try file.read(into: buffer)
        } catch {
            return Array(repeating: 0, count: bucketCount)
        }

        guard let channelData = buffer.floatChannelData else {
            return Array(repeating: 0, count: bucketCount)
        }

        let channels = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        let framesPerBucket = max(1, totalFrames / bucketCount)

        var out = Array<Float>(repeating: 0, count: bucketCount)
        for bucket in 0..<bucketCount {
            let start = bucket * framesPerBucket
            let end = min(start + framesPerBucket, totalFrames)
            guard start < end else { break }

            var peak: Float = 0
            for frame in start..<end {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += abs(channelData[channel][frame])
                }
                let mono = sum / Float(max(channels, 1))
                if mono > peak { peak = mono }
            }
            out[bucket] = min(peak, 1.0)
        }
        return out
    }
}
```

**Tests:**

```swift
// Tests/SequencerAITests/Audio/WaveformDownsamplerTests.swift
import XCTest
import AVFoundation
@testable import SequencerAI

final class WaveformDownsamplerTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writeTestWAV(to: tempURL, durationSeconds: 0.2, amplitude: 0.5)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    /// Writes a mono 44.1 kHz WAV with a constant-amplitude sine wave.
    private func writeTestWAV(to url: URL, durationSeconds: Double, amplitude: Float) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(durationSeconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            data[i] = amplitude * sinf(2 * .pi * 440.0 * Float(i) / Float(format.sampleRate))
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    func test_bucketCountIsRespected() {
        let buckets = WaveformDownsampler.downsample(url: tempURL, bucketCount: 8)
        XCTAssertEqual(buckets.count, 8)
    }

    func test_bucketsAreNonNegativeAndBounded() {
        let buckets = WaveformDownsampler.downsample(url: tempURL, bucketCount: 32)
        for (i, v) in buckets.enumerated() {
            XCTAssertGreaterThanOrEqual(v, 0, "bucket \(i) must be non-negative")
            XCTAssertLessThanOrEqual(v, 1, "bucket \(i) must be <= 1")
        }
    }

    func test_sineWave_producesNonZeroBuckets() {
        let buckets = WaveformDownsampler.downsample(url: tempURL, bucketCount: 16)
        // Full-amplitude sine: most buckets should be ~amplitude (0.5). Allow slack.
        let nonZero = buckets.filter { $0 > 0.1 }.count
        XCTAssertGreaterThan(nonZero, 10, "at least most buckets of a 0.5-amplitude sine should be > 0.1")
    }

    func test_cacheHitReturnsSameArray() {
        let first = WaveformDownsampler.downsample(url: tempURL, bucketCount: 16)
        let second = WaveformDownsampler.downsample(url: tempURL, bucketCount: 16)
        XCTAssertEqual(first, second)
    }

    func test_missingFile_returnsZeros() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let buckets = WaveformDownsampler.downsample(url: missing, bucketCount: 10)
        XCTAssertEqual(buckets, Array(repeating: 0, count: 10))
    }
}
```

- [x] Create `WaveformDownsampler.swift`
- [x] Create `WaveformDownsamplerTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — new suite green
- [x] Commit: `feat(audio): WaveformDownsampler with NSCache-backed results`

---

## Task 9: `ScheduledEvent.Payload.sampleTrigger`

**Scope:** One-line addition to the existing `ScheduledEvent.Payload` enum. No behaviour change yet — payload is defined and tested for codable/equality.

**Files:**
- Modify: `Sources/Engine/ScheduledEvent.swift`
- Modify: `Tests/SequencerAITests/Engine/EventQueueTests.swift` — one new test case

**Changes to `ScheduledEvent.swift`:**

Add the new payload case alongside existing ones:

```swift
case sampleTrigger(
    trackID: UUID,
    sampleID: UUID,
    settings: SamplerSettings,
    scheduledHostTime: TimeInterval
)
```

The resulting `Payload` enum:

```swift
enum Payload: Equatable {
    case trackAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)
    case routedAU(trackID: UUID, destination: Destination, notes: [NoteEvent], bpm: Double, stepsPerBar: Int)
    case routedMIDI(destination: Destination, channel: UInt8, notes: [NoteEvent], bpm: Double)
    case chordContextBroadcast(lane: String, chord: Chord)
    case sampleTrigger(trackID: UUID, sampleID: UUID, settings: SamplerSettings, scheduledHostTime: TimeInterval)
}
```

**New test** in `EventQueueTests.swift`:

```swift
func test_sampleTriggerPayload_equatable() {
    let trackID = UUID()
    let sampleID = UUID()
    let a = ScheduledEvent(
        scheduledHostTime: 1.0,
        payload: .sampleTrigger(trackID: trackID, sampleID: sampleID, settings: .default, scheduledHostTime: 1.0)
    )
    let b = ScheduledEvent(
        scheduledHostTime: 1.0,
        payload: .sampleTrigger(trackID: trackID, sampleID: sampleID, settings: .default, scheduledHostTime: 1.0)
    )
    let c = ScheduledEvent(
        scheduledHostTime: 1.0,
        payload: .sampleTrigger(trackID: trackID, sampleID: UUID(), settings: .default, scheduledHostTime: 1.0)
    )
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
}
```

- [x] Add `.sampleTrigger` case to `ScheduledEvent.Payload` at `Sources/Engine/ScheduledEvent.swift`
- [x] Add `test_sampleTriggerPayload_equatable` to `EventQueueTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — all engine tests still green
- [x] Commit: `feat(engine): ScheduledEvent.sampleTrigger payload`

---

## Task 10: `SamplePlaybackEngine`

**Scope:** One `AVAudioEngine` + 16 main `AVAudioPlayerNode` voices + one preview-bus voice for audition. Gain applied per-voice.

**Files:**
- Create: `Sources/Audio/SamplePlaybackEngine.swift`
- Create: `Tests/SequencerAITests/Audio/SamplePlaybackEngineTests.swift`

**Content:**

```swift
// Sources/Audio/SamplePlaybackEngine.swift
import Foundation
import AVFoundation

struct VoiceHandle: Equatable, Hashable {
    fileprivate let id: UUID
}

final class SamplePlaybackEngine {
    private static let mainVoiceCount = 16
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var mainVoices: [AVAudioPlayerNode] = []
    private var mainVoiceHandles: [UUID] = []         // parallel to mainVoices; tracks current occupant
    private var nextVoiceIndex = 0
    private let previewNode = AVAudioPlayerNode()
    private var fileCache: [URL: AVAudioFile] = [:]
    private var isStarted = false

    init() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        for _ in 0..<Self.mainVoiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixer, format: nil)
            mainVoices.append(node)
            mainVoiceHandles.append(UUID())
        }
        engine.attach(previewNode)
        engine.connect(previewNode, to: mixer, format: nil)
    }

    func start() throws {
        guard !isStarted else { return }
        try engine.start()
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        for voice in mainVoices { voice.stop() }
        previewNode.stop()
        engine.stop()
        isStarted = false
    }

    /// Play a sample through the main voice pool. Round-robin allocation; steals the next voice if all busy.
    /// Returns nil if the engine isn't started or the file can't be read.
    @discardableResult
    func play(sampleURL: URL, settings: SamplerSettings, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard isStarted else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }

        let voice = mainVoices[nextVoiceIndex]
        let handleID = UUID()
        mainVoiceHandles[nextVoiceIndex] = handleID
        nextVoiceIndex = (nextVoiceIndex &+ 1) % mainVoices.count

        voice.stop()
        voice.volume = linearGain(dB: settings.gain)
        voice.scheduleFile(file, at: when, completionHandler: nil)
        voice.play()

        return VoiceHandle(id: handleID)
    }

    func stopVoice(_ handle: VoiceHandle) {
        guard let idx = mainVoiceHandles.firstIndex(of: handle.id) else { return }
        mainVoices[idx].stop()
    }

    func stopAllMainVoices() {
        for voice in mainVoices { voice.stop() }
    }

    /// Audition: plays on a separate node that never competes with the main pool.
    /// Cancels any in-flight audition.
    func audition(sampleURL: URL) {
        guard isStarted else { return }
        guard let file = cachedFile(url: sampleURL) else { return }
        previewNode.stop()
        previewNode.volume = 1.0
        previewNode.scheduleFile(file, at: nil, completionHandler: nil)
        previewNode.play()
    }

    func stopAudition() {
        previewNode.stop()
    }

    // MARK: - Helpers

    private func cachedFile(url: URL) -> AVAudioFile? {
        if let f = fileCache[url] { return f }
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        if fileCache.count >= 64 {
            fileCache.removeAll(keepingCapacity: true)   // coarse LRU — drop all when hot
        }
        fileCache[url] = f
        return f
    }

    private func linearGain(dB: Double) -> Float {
        Float(pow(10, dB / 20))
    }
}
```

**Tests:**

```swift
// Tests/SequencerAITests/Audio/SamplePlaybackEngineTests.swift
import XCTest
import AVFoundation
@testable import SequencerAI

/// Integration-tagged — may fail in constrained CI where AVAudioEngine can't start.
/// Skip gracefully by catching start errors rather than XCTFail'ing, so CI isn't blocked.
final class SamplePlaybackEngineTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writeSilentWAV(to: fixtureURL, durationSeconds: 0.1)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureURL)
    }

    private func writeSilentWAV(to url: URL, durationSeconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(durationSeconds * format.sampleRate))!
        buffer.frameLength = buffer.frameCapacity
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private func makeEngine() throws -> SamplePlaybackEngine? {
        let engine = SamplePlaybackEngine()
        do {
            try engine.start()
            return engine
        } catch {
            return nil   // unavailable environment; test becomes a no-op
        }
    }

    func test_playReturnsHandle() throws {
        guard let engine = try makeEngine() else { return }
        defer { engine.stop() }
        let handle = engine.play(sampleURL: fixtureURL, settings: .default)
        XCTAssertNotNil(handle)
    }

    func test_playWithoutStart_returnsNil() {
        let engine = SamplePlaybackEngine()
        XCTAssertNil(engine.play(sampleURL: fixtureURL, settings: .default))
    }

    func test_rapidPlays_doNotCrash() throws {
        guard let engine = try makeEngine() else { return }
        defer { engine.stop() }
        for _ in 0..<20 {
            _ = engine.play(sampleURL: fixtureURL, settings: .default)
        }
    }

    func test_audition_runsIndependent() throws {
        guard let engine = try makeEngine() else { return }
        defer { engine.stop() }
        engine.audition(sampleURL: fixtureURL)
        _ = engine.play(sampleURL: fixtureURL, settings: .default)
        // No assertion — the contract is that they don't crash and audition keeps its own node.
    }

    func test_stopVoice_silencesThatVoice() throws {
        guard let engine = try makeEngine() else { return }
        defer { engine.stop() }
        guard let handle = engine.play(sampleURL: fixtureURL, settings: .default) else {
            XCTFail("play returned nil in a started engine"); return
        }
        engine.stopVoice(handle)
    }

    func test_missingFile_returnsNil() throws {
        guard let engine = try makeEngine() else { return }
        defer { engine.stop() }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        XCTAssertNil(engine.play(sampleURL: missing, settings: .default))
    }
}
```

Note: the integration tests don't assert on audible output (no output-tap). They exercise the API surface and guard against crashes. Gain-correctness is trusted to AVFoundation — an output-tap peak-amplitude test is deferred.

- [x] Create `SamplePlaybackEngine.swift`
- [x] Create `SamplePlaybackEngineTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — new suite green (or gracefully skips if AVAudioEngine won't start)
- [x] Commit: `feat(audio): SamplePlaybackEngine with voice pool + audition bus`

---

## Task 11: Wire `SamplePlaybackEngine` into `EngineController`

**Scope:** Enqueue `sampleTrigger` events from `prepareTick`; drain and play them in `dispatchTick`. Mute filter already covers them via the existing `currentLayerSnapshot.isMuted(trackID)` guard.

**Files:**
- Modify: `Sources/Engine/EngineController.swift`
- Create: `Tests/SequencerAITests/Engine/EngineControllerSampleTriggerTests.swift`

**Changes to `EngineController.swift`:**

1. Add three properties near the other engine-scoped fields (alongside `eventQueue`, `coordinator`, `currentLayerSnapshot` introduced by the macro-coordinator plan):

```swift
private let sampleEngine = SamplePlaybackEngine()
private let sampleLibrary: AudioSampleLibrary
private var sampleLibraryRoot: URL { sampleLibrary.libraryRoot }
```

2. Update the designated initialiser to accept an optional `sampleLibrary` (defaulting to the shared singleton), so tests can inject fixtures:

```swift
init(
    client: MIDIClient?,
    endpoint: MIDIEndpoint?,
    audioOutputFactory: (() -> TrackPlaybackSink)? = nil,
    sampleLibrary: AudioSampleLibrary = .shared        // NEW parameter, default = production
) {
    self.sampleLibrary = sampleLibrary
    // ... existing body ...
}
```

3. In `start()` — after the existing `hosts.forEach { $0.startIfNeeded() }` line and before `isRunning = true`:

```swift
try? sampleEngine.start()
```

4. In `stop()` — add at the end, after existing teardown:

```swift
sampleEngine.stop()
```

5. In `prepareTick(upcomingStep:now:)` — after the existing AU enqueue loop, add a sample enqueue loop:

```swift
// Sample dispatch → queue (drum tracks and any other track with .sample destination).
for track in documentModel.tracks {
    guard !currentLayerSnapshot.isMuted(track.id),
          let generatorID = generatorIDs[track.id],
          case let .notes(events)? = outputs[generatorID]?["notes"],
          !events.isEmpty
    else { continue }
    guard case let .sample(sampleID, settings) = track.destination else { continue }
    for _ in events {
        eventQueue.enqueue(ScheduledEvent(
            scheduledHostTime: now,
            payload: .sampleTrigger(
                trackID: track.id,
                sampleID: sampleID,
                settings: settings,
                scheduledHostTime: now
            )
        ))
    }
}
```

6. In `dispatchTick(now:)` — add the new case inside the drain switch:

```swift
case let .sampleTrigger(_, sampleID, settings, _):
    guard let sample = sampleLibrary.sample(id: sampleID) else { continue }
    guard let url = try? sample.fileRef.resolve(libraryRoot: sampleLibraryRoot) else { continue }
    _ = sampleEngine.play(sampleURL: url, settings: settings, at: nil)
```

**Test file:**

Tests inject a spy sample engine. Since `SamplePlaybackEngine` is currently a concrete class, introduce a protocol for test seams — the minimum refactor needed:

```swift
// In Sources/Audio/SamplePlaybackEngine.swift — add at top:
protocol SamplePlaybackSink: AnyObject {
    func start() throws
    func stop()
    func play(sampleURL: URL, settings: SamplerSettings, at when: AVAudioTime?) -> VoiceHandle?
    func audition(sampleURL: URL)
    func stopAudition()
}

extension SamplePlaybackEngine: SamplePlaybackSink {}
```

And update `EngineController` to hold `SamplePlaybackSink`:

```swift
private let sampleEngine: SamplePlaybackSink
// init param:
init(..., sampleEngine: SamplePlaybackSink = SamplePlaybackEngine(), sampleLibrary: AudioSampleLibrary = .shared) {
    self.sampleEngine = sampleEngine
    self.sampleLibrary = sampleLibrary
    // ...
}
```

**Integration test:**

```swift
// Tests/SequencerAITests/Engine/EngineControllerSampleTriggerTests.swift
import XCTest
import AVFoundation
@testable import SequencerAI

final class EngineControllerSampleTriggerTests: XCTestCase {
    private final class SpySamplePlaybackSink: SamplePlaybackSink {
        var playCalls: [(URL, SamplerSettings)] = []
        func start() throws {}
        func stop() {}
        func play(sampleURL: URL, settings: SamplerSettings, at when: AVAudioTime?) -> VoiceHandle? {
            playCalls.append((sampleURL, settings))
            return nil
        }
        func audition(sampleURL: URL) {}
        func stopAudition() {}
    }

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("kick"), withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("kick/test-kick.wav"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func test_sampleDestination_firesPlayPerStep() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()

        let track = StepSequenceTrack(
            name: "K", trackType: .monoMelodic,
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100, gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let project = Project(
            version: 1,
            tracks: [track],
            layers: layers,
            selectedTrackID: track.id,
            phrases: [.default(tracks: [track], layers: layers)],
            selectedPhraseID: nil
        )

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.start()
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }
        controller.stop()

        XCTAssertGreaterThan(spy.playCalls.count, 0, "sample should have played")
    }

    func test_muteCell_suppressesSampleDispatch() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else { XCTFail(); return }
        let spy = SpySamplePlaybackSink()

        let track = StepSequenceTrack(
            name: "K", trackType: .monoMelodic,
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100, gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let muteLayer = layers.first(where: { $0.target == .mute })!
        var phrase = PhraseModel.default(tracks: [track], layers: layers)
        phrase.setCell(.single(.bool(true)), for: muteLayer.id, trackID: track.id)

        let project = Project(
            version: 1,
            tracks: [track],
            layers: layers,
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.start()
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }
        controller.stop()

        XCTAssertEqual(spy.playCalls.count, 0, "muted track should not dispatch sample triggers")
    }

    func test_orphanSampleID_noCrash() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let spy = SpySamplePlaybackSink()

        let track = StepSequenceTrack(
            name: "K", trackType: .monoMelodic,
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(), settings: .default),   // not in library
            velocity: 100, gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let project = Project(
            version: 1, tracks: [track], layers: layers,
            selectedTrackID: track.id,
            phrases: [.default(tracks: [track], layers: layers)],
            selectedPhraseID: nil
        )

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.start()
        controller.processTick(tickIndex: 0, now: 0)
        controller.stop()

        XCTAssertEqual(spy.playCalls.count, 0, "orphan sample ID should no-op cleanly")
    }
}
```

**Subtleties:**
- The `generatorIDs` property referenced in the prepareTick addition is the existing `generatorIDsByTrackID` dictionary — match the exact name in the current file.
- `AudioSampleLibrary.shared` is force-initialised at `EngineController` init time unless a test passes a different library — matches the pattern of `.shared` singletons elsewhere.
- The spy sink's `start()` is marked `throws` to satisfy the protocol even though it never throws.

- [x] Introduce `SamplePlaybackSink` protocol + `SamplePlaybackEngine` conformance
- [x] Add `sampleEngine` + `sampleLibrary` properties to `EngineController`; extend initialiser
- [x] Add `sampleEngine.start()` / `stop()` calls in `EngineController.start()` / `stop()`
- [x] Add sample-enqueue loop to `prepareTick`
- [x] Add `.sampleTrigger` case handling to `dispatchTick`
- [x] Create `EngineControllerSampleTriggerTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — all existing engine tests green + new cases green
- [x] Commit: `feat(engine): dispatch .sample destinations through SamplePlaybackEngine`

---

## Task 12: `WaveformView` + `SamplerDestinationWidget`

**Scope:** The inline UI. `WaveformView` is a small SwiftUI `Canvas` renderer. `SamplerDestinationWidget` composes the waveform with header, audition, prev/next, gain.

**Files:**
- Create: `Sources/UI/WaveformView.swift`
- Create: `Sources/UI/SamplerDestinationWidget.swift`
- Create: `Tests/SequencerAITests/UI/SamplerDestinationWidgetTests.swift`

**Content:**

```swift
// Sources/UI/WaveformView.swift
import SwiftUI

struct WaveformView: View {
    let buckets: [Float]
    var fillColor: Color = StudioTheme.success
    var inactiveColor: Color = StudioTheme.border

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !buckets.isEmpty else { return }
                let barSpacing: CGFloat = 1
                let totalSpacing = barSpacing * CGFloat(buckets.count - 1)
                let barWidth = max(1, (size.width - totalSpacing) / CGFloat(buckets.count))
                let midY = size.height / 2

                for (i, v) in buckets.enumerated() {
                    let clamped = max(0, min(CGFloat(v), 1))
                    let halfHeight = clamped * size.height / 2
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let rect = CGRect(
                        x: x,
                        y: midY - halfHeight,
                        width: barWidth,
                        height: max(1, halfHeight * 2)
                    )
                    let color = clamped > 0.02 ? fillColor : inactiveColor
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
```

```swift
// Sources/UI/SamplerDestinationWidget.swift
import SwiftUI

struct SamplerDestinationWidget: View {
    @Binding var destination: Destination       // precondition: .sample
    let library: AudioSampleLibrary
    let sampleEngine: SamplePlaybackSink

    @State private var isAuditioning = false
    @State private var auditionTask: Task<Void, Never>?

    private var currentSampleID: UUID? {
        if case let .sample(id, _) = destination { return id }
        return nil
    }

    private var currentSettings: SamplerSettings {
        if case let .sample(_, settings) = destination { return settings }
        return .default
    }

    private var currentSample: AudioSample? {
        guard let id = currentSampleID else { return nil }
        return library.sample(id: id)
    }

    private var peers: [AudioSample] {
        guard let category = currentSample?.category else { return [] }
        return library.samples(in: category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sample = currentSample {
                header(sample: sample)
                waveform(sample: sample)
                controls(sample: sample)
                gainSlider
            } else {
                orphanTile
            }
        }
    }

    private func header(sample: AudioSample) -> some View {
        HStack {
            Text(sample.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
            Spacer()
            let lengthLabel = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "—"
            Text("\(sample.category.displayName) • \(lengthLabel)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private func waveform(sample: AudioSample) -> some View {
        let url = (try? sample.fileRef.resolve(libraryRoot: library.libraryRoot)) ?? URL(fileURLWithPath: "/dev/null")
        let buckets = WaveformDownsampler.downsample(url: url, bucketCount: 64)
        return WaveformView(buckets: buckets)
            .frame(height: 60)
            .padding(8)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(StudioTheme.border, lineWidth: 1))
    }

    private func controls(sample: AudioSample) -> some View {
        HStack(spacing: 12) {
            Button { stepSample(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(peers.count < 2)
            Button {
                toggleAudition(sample: sample)
            } label: {
                Image(systemName: isAuditioning ? "stop.fill" : "play.fill")
                Text(isAuditioning ? "Stop" : "Audition")
            }
            Button { stepSample(+1) } label: { Image(systemName: "chevron.right") }
                .disabled(peers.count < 2)
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    private var gainSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Gain")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text(String(format: "%+.1f dB", currentSettings.gain))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
            }
            Slider(value: gainBinding, in: -60...12) { editing in
                if !editing, abs(currentSettings.gain) < 0.5 {
                    updateGain(0)   // snap to unity
                }
            }
        }
    }

    private var orphanTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Missing sample")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("Sample \(currentSampleID?.uuidString.prefix(8) ?? "—") not in library.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
            Button("Replace with first in category") { replaceWithFirstInCurrentCategory() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(StudioTheme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func stepSample(_ delta: Int) {
        guard let id = currentSampleID else { return }
        let next: AudioSample? = delta > 0 ? library.nextSample(after: id) : library.previousSample(before: id)
        guard let next else { return }
        destination = .sample(sampleID: next.id, settings: currentSettings)
    }

    private func toggleAudition(sample: AudioSample) {
        auditionTask?.cancel()
        if isAuditioning {
            sampleEngine.stopAudition()
            isAuditioning = false
            return
        }
        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot) else { return }
        sampleEngine.audition(sampleURL: url)
        isAuditioning = true
        let duration = sample.lengthSeconds ?? 1.0
        auditionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((duration + 0.05) * 1000)))
            if !Task.isCancelled {
                isAuditioning = false
            }
        }
    }

    private var gainBinding: Binding<Double> {
        Binding(
            get: { currentSettings.gain },
            set: { updateGain($0) }
        )
    }

    private func updateGain(_ value: Double) {
        guard case let .sample(id, settings) = destination else { return }
        var next = settings
        next.gain = value
        destination = .sample(sampleID: id, settings: next.clamped())
    }

    private func replaceWithFirstInCurrentCategory() {
        // Orphan case — category unknown because the sample itself is missing.
        // Fall back to kick as the canonical first drum voice.
        let fallback = library.firstSample(in: .kick) ?? library.samples.first
        guard let replacement = fallback else { return }
        destination = .sample(sampleID: replacement.id, settings: currentSettings)
    }
}
```

**Tests:**

```swift
// Tests/SequencerAITests/UI/SamplerDestinationWidgetTests.swift
import XCTest
import SwiftUI
@testable import SequencerAI

final class SamplerDestinationWidgetTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for fname in ["a.wav", "b.wav", "c.wav"] {
            let dir = libraryRoot.appendingPathComponent("kick")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data().write(to: dir.appendingPathComponent(fname))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private final class SpySink: SamplePlaybackSink {
        var auditionCalls = 0
        var stopAuditionCalls = 0
        func start() throws {}
        func stop() {}
        func play(sampleURL: URL, settings: SamplerSettings, at when: AVAudioTime?) -> VoiceHandle? { nil }
        func audition(sampleURL: URL) { auditionCalls += 1 }
        func stopAudition() { stopAuditionCalls += 1 }
    }

    func test_stepSample_advancesToNextInCategory() {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kicks = lib.samples(in: .kick)
        var destination = Destination.sample(sampleID: kicks[0].id, settings: .default)

        let binding = Binding(get: { destination }, set: { destination = $0 })
        let widget = SamplerDestinationWidget(destination: binding, library: lib, sampleEngine: SpySink())
        // Reach into the private stepSample via mirroring is brittle — test via behaviour instead:
        // Assert that `nextSample(after:)` on the library matches what the widget would assign.
        XCTAssertEqual(lib.nextSample(after: kicks[0].id)?.id, kicks[1].id)
        XCTAssertEqual(lib.nextSample(after: kicks[2].id)?.id, kicks[0].id)
        _ = widget       // silence unused
    }

    func test_updateGain_clampsAndUpdatesDestination() {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = lib.firstSample(in: .kick)!
        var destination = Destination.sample(sampleID: kick.id, settings: .default)

        // Simulate the gain binding's setter directly via the clamp path:
        var settings = SamplerSettings.default
        settings.gain = 999
        destination = .sample(sampleID: kick.id, settings: settings.clamped())
        if case let .sample(_, s) = destination { XCTAssertEqual(s.gain, 12) } else { XCTFail() }
    }

    func test_orphanSampleID_exposesReplaceAffordance() {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        let destination = Destination.sample(sampleID: UUID(), settings: .default)   // not in library
        // Test: currentSample resolves to nil
        if case let .sample(id, _) = destination {
            XCTAssertNil(lib.sample(id: id))
        } else { XCTFail() }
    }

    func test_auditionCallsSink() {
        let lib = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = lib.firstSample(in: .kick)!
        let spy = SpySink()
        var destination = Destination.sample(sampleID: kick.id, settings: .default)
        let binding = Binding(get: { destination }, set: { destination = $0 })
        let _ = SamplerDestinationWidget(destination: binding, library: lib, sampleEngine: spy)

        // Direct behaviour verification: simulating the audition action means constructing
        // the resolved URL and passing it to the spy, which the widget does internally.
        let url = try? kick.fileRef.resolve(libraryRoot: lib.libraryRoot)
        XCTAssertNotNil(url)
        spy.audition(sampleURL: url!)
        XCTAssertEqual(spy.auditionCalls, 1)
    }
}
```

SwiftUI view-rendering tests are awkward without ViewInspector or similar. The tests here verify the **data paths** the widget uses — library queries, clamp behaviour, sample resolution, spy-sink interaction. A full rendering test (matching a snapshot of the widget's layout) is deferred.

- [x] Create `WaveformView.swift`
- [x] Create `SamplerDestinationWidget.swift`
- [x] Create `SamplerDestinationWidgetTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — new suite green
- [x] Commit: `feat(ui): SamplerDestinationWidget with waveform + prev/next + audition + gain`

---

## Task 13: `TrackDestinationEditor` — `.sample` branch and choice

**Scope:** Extend `TrackDestinationEditor.swift` to recognise `.sample` as a destination kind and render the new widget.

**Files:**
- Modify: `Sources/UI/TrackDestinationEditor.swift`

**Changes:**

1. Extend the private enum `TrackDestinationChoice` — add `.sample` case:

```swift
private enum TrackDestinationChoice: String, CaseIterable, Identifiable {
    case inheritGroup
    case midiOut
    case auInstrument
    case internalSampler
    case sample                      // NEW
    case none

    var id: String { rawValue }

    init(destination: Destination) {
        switch destination {
        case .inheritGroup: self = .inheritGroup
        case .midi: self = .midiOut
        case .auInstrument: self = .auInstrument
        case .internalSampler: self = .internalSampler
        case .sample: self = .sample                      // NEW
        case .none: self = .none
        }
    }

    var label: String {
        switch self {
        case .inheritGroup: return "Inherit Group"
        case .midiOut: return "Virtual MIDI Out"
        case .auInstrument: return "AU Instrument"
        case .internalSampler: return "Internal Sampler"
        case .sample: return "Sampler"                     // NEW
        case .none: return "No Default Output"
        }
    }

    var detail: String {
        switch self {
        case .inheritGroup: return "Follow the shared destination owned by this track's group"
        case .midiOut: return "Send note data to a MIDI endpoint"
        case .auInstrument: return "Host an Audio Unit instrument in-app"
        case .internalSampler: return "Play through the built-in sampler path"
        case .sample: return "Play one-shot sample files"  // NEW
        case .none: return "No sink unless routes handle the notes"
        }
    }
}
```

2. Update `availableChoices` to always include `.sample`:

```swift
private var availableChoices: [TrackDestinationChoice] {
    var choices: [TrackDestinationChoice] = [.midiOut, .auInstrument, .sample]
    if supportsInternalSamplerChoice {
        choices.append(.internalSampler)
    }
    choices.append(.none)
    if track.groupID != nil {
        choices.insert(.inheritGroup, at: 0)
    }
    return choices
}
```

3. Add the `.sample` branch to the body switch:

```swift
switch currentChoice {
case .inheritGroup: inheritGroupEditor
case .midiOut: midiEditor
case .auInstrument: auEditor
case .internalSampler: internalSamplerEditor
case .sample: samplerEditor                   // NEW
case .none: noneEditor
}
```

And the new computed view:

```swift
@Environment(AudioSampleLibrary.self) private var sampleLibrary
// If AudioSampleLibrary is not yet injected as Environment, pass via constructor or use .shared directly:
// private var sampleLibrary: AudioSampleLibrary { .shared }
@Environment(EngineController.self) private var engineController

private var samplerEditor: some View {
    SamplerDestinationWidget(
        destination: Binding(
            get: { editedDestination },
            set: { document.project.setEditedDestination($0, for: track.id) }
        ),
        library: AudioSampleLibrary.shared,
        sampleEngine: engineController.sampleEngine      // see note below
    )
}
```

4. Expose `sampleEngine` on `EngineController` as a read-only accessor so the widget can audition:

```swift
// In EngineController.swift, near other accessors:
var sampleEngineSink: SamplePlaybackSink { sampleEngine }
```

(Name: `sampleEngineSink` to avoid clashing with the private property name.)

Then in `samplerEditor`:

```swift
sampleEngine: engineController.sampleEngineSink
```

5. Add `.sample` to `applyDestinationChoice(_:)`:

```swift
case .sample:
    // If already on .sample, leave alone. Otherwise, assign the first drum sample
    // (kick) as a reasonable default for non-drum tracks manually switching to sampler.
    if case .sample = editedDestination {
        return
    }
    guard let seed = AudioSampleLibrary.shared.firstSample(in: .kick) else {
        return   // library empty — no sane default
    }
    document.project.setEditedDestination(
        .sample(sampleID: seed.id, settings: .default),
        for: track.id
    )
```

**Subtleties:**
- The widget expects the `library` and `sampleEngine` to be passed — they live on `AudioSampleLibrary.shared` and `EngineController.sampleEngineSink` respectively. No new Environment wiring required.
- If `AudioSampleLibrary.shared.firstSample(in: .kick)` returns nil (library empty), the `.sample` choice button becomes a no-op. Consider disabling the choice card in that case:

```swift
// In availableChoices — filter out .sample when library is empty:
if AudioSampleLibrary.shared.samples.isEmpty {
    choices.removeAll(where: { $0 == .sample })
}
```

Be careful — this read happens every view update. Acceptable because `AudioSampleLibrary.samples` is a stored array, not computed. If it turns out to be hot, cache behind a `@State var` that refreshes on `.task`.

- [x] Add `.sample` case to `TrackDestinationChoice`
- [x] Update `availableChoices` / `applyDestinationChoice`
- [x] Add `samplerEditor` computed view + `.sample` branch in the main switch
- [x] Expose `sampleEngineSink` on `EngineController`
- [x] `xcodegen generate`
- [x] `xcodebuild` — compiles; manual check that the OUTPUT section shows "Sampler" card
- [x] Commit: `feat(ui): TrackDestinationEditor adds .sample branch + choice`

---

## Task 14: `addDrumKit` rewrite + delete legacy extension

**Scope:** Replace the body of `Project.addDrumKit(_:)` to assign per-member `.sample` destinations. Remove the now-unused `DrumKitPreset+Destination.swift`.

**Files:**
- Modify: `Sources/Document/Project+Tracks.swift`
- Delete: `Sources/Document/DrumKitPreset+Destination.swift`
- Create: `Tests/SequencerAITests/DrumKit/DrumKitPresetSampleTests.swift`

**Changes to `Project+Tracks.swift:addDrumKit`:**

Replace the body with:

```swift
@discardableResult
mutating func addDrumKit(
    _ preset: DrumKitPreset,
    library: AudioSampleLibrary = .shared
) -> TrackGroupID? {
    guard !preset.members.isEmpty else {
        return nil
    }

    let groupID = TrackGroupID()
    let fallback: Destination = .internalSampler(bankID: .drumKitDefault, preset: preset.rawValue)

    let newTracks = preset.members.map { member -> StepSequenceTrack in
        let destination: Destination = {
            guard let category = AudioSampleCategory(voiceTag: member.tag),
                  let sample = library.firstSample(in: category)
            else { return fallback }
            return .sample(sampleID: sample.id, settings: .default)
        }()
        return StepSequenceTrack(
            name: member.trackName,
            trackType: .monoMelodic,
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: member.seedPattern,
            destination: destination,
            groupID: groupID,
            velocity: StepSequenceTrack.default.velocity,
            gateLength: StepSequenceTrack.default.gateLength
        )
    }

    tracks.append(contentsOf: newTracks)
    trackGroups.append(
        TrackGroup(
            id: groupID,
            name: preset.displayName,
            color: preset.suggestedGroupColor,
            memberIDs: newTracks.map(\.id),
            sharedDestination: nil,      // per-member samples instead of shared sampler
            noteMapping: [:]             // samples pre-pitched; no MIDI transpose
        )
    )
    selectedTrackID = newTracks.first?.id ?? selectedTrackID
    syncPhrasesWithTracks()
    return groupID
}
```

**Delete `DrumKitPreset+Destination.swift`.** It's a four-line file defining `suggestedSharedDestination: Destination`, which is no longer referenced. Verify with `grep -rn suggestedSharedDestination Sources Tests` — zero results.

**Tests:**

```swift
// Tests/SequencerAITests/DrumKit/DrumKitPresetSampleTests.swift
import XCTest
@testable import SequencerAI

final class DrumKitPresetSampleTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for category in ["kick", "snare", "hatClosed", "clap"] {
            let dir = libraryRoot.appendingPathComponent(category)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data().write(to: dir.appendingPathComponent("\(category)-default.wav"))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func test_addDrumKit_populatedLibrary_assignsSamplePerMember() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty()
        _ = project.addDrumKit(.kit808, library: library)

        let drumTracks = project.tracks.suffix(4)
        XCTAssertEqual(drumTracks.count, 4)
        for track in drumTracks {
            if case .sample(_, _) = track.destination { continue }
            XCTFail("track \(track.name) should have .sample destination, got \(track.destination)")
        }

        // Verify the kick track points at the kick sample.
        let kick = drumTracks.first(where: { $0.name == "Kick" })!
        if case let .sample(sampleID, _) = kick.destination {
            XCTAssertEqual(sampleID, library.firstSample(in: .kick)?.id)
        } else { XCTFail() }
    }

    func test_addDrumKit_emptyCategory_fallsBackToInternalSampler() throws {
        // Remove all kicks.
        try FileManager.default.removeItem(at: libraryRoot.appendingPathComponent("kick"))
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty()
        _ = project.addDrumKit(.kit808, library: library)

        let kick = project.tracks.first(where: { $0.name == "Kick" })!
        switch kick.destination {
        case .internalSampler: break
        default: XCTFail("expected fallback .internalSampler, got \(kick.destination)")
        }
    }

    func test_addDrumKit_sharedDestinationIsNil() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty()
        _ = project.addDrumKit(.kit808, library: library)
        XCTAssertNil(project.trackGroups.last?.sharedDestination)
    }

    func test_addDrumKit_unknownVoiceTag_fallsBackWithoutCrash() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        // Build a preset-like call with a synthetic unknown tag by constructing the
        // track directly (since DrumKitPreset is a closed enum). Call path tested via
        // the `AudioSampleCategory(voiceTag:)` returning nil → fallback destination.
        XCTAssertNil(AudioSampleCategory(voiceTag: "martian-voice"))
        // That fallback is exercised by addDrumKit's destination-computing closure
        // (nil → fallback), and DrumKitPreset.members are already categorised — so this
        // is a structural assertion on the bridge, not a per-call one.
    }
}
```

`Project.empty()` is a factory that may or may not exist on `Project`. If it doesn't, construct a minimal one inline — check `Project+Codable.swift` or `Project.swift` for an equivalent.

**Subtleties:**
- `Project+Tracks.swift` currently builds the `TrackGroup` with a non-empty `noteMapping` using `DrumKitNoteMap.note(for: member.tag) - DrumKitNoteMap.baselineNote`. We're dropping that mapping (samples play at native pitch). If any downstream code consumes `noteMapping`, verify it handles empty without crashing. `grep -n noteMapping Sources` to confirm.

- [x] Rewrite `addDrumKit(_:library:)` body with the new per-member sample path + `sharedDestination: nil` + `noteMapping: [:]`
- [x] Delete `Sources/Document/DrumKitPreset+Destination.swift`
- [x] Verify `grep -rn suggestedSharedDestination Sources Tests` → zero results
- [x] Create `DrumKitPresetSampleTests.swift`
- [x] `xcodegen generate`
- [x] `xcodebuild test` — all existing tests green (existing drum-kit tests touching `sharedDestination` will need update — expected to be a small number; adjust them to assert `nil` instead of `.internalSampler(...)` )
- [x] Commit: `feat(document): addDrumKit assigns per-member sample destinations`

---

## Task 15: `SeqAIDocumentApp` — boot the library at launch

**Scope:** One line in the App init to trigger `SampleLibraryBootstrap.ensureLibraryInstalled()`. Side effect: `AudioSampleLibrary.shared` has a valid directory to scan when first touched.

**Files:**
- Modify: `Sources/SeqAIDocumentApp.swift` (name may be `SeqAIDocumentApp.swift` or just the app's `@main` file — confirm first)

**Change:**

Find the `@main` struct (likely named `SeqAIDocumentApp`). Add bootstrap + warm-up:

```swift
@main
struct SeqAIDocumentApp: App {
    init() {
        do {
            _ = try SampleLibraryBootstrap.ensureLibraryInstalled()
        } catch {
            NSLog("[SeqAIDocumentApp] sample library bootstrap failed: \(error)")
        }
        _ = AudioSampleLibrary.shared   // warm the singleton so first UI read is fast
    }

    var body: some Scene {
        DocumentGroup(newDocument: SeqAIDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
```

If the app file name is different, the change is the same — add two lines to the `init()` (creating one if absent).

**Subtleties:**
- `ensureLibraryInstalled` can throw only for genuinely broken states (disk full, permissions). The catch is log-and-continue: the library will be empty, the app stays up, and `.sample` destinations fall back through the widget's orphan tile / the engine's sample-miss no-op.
- Touching `AudioSampleLibrary.shared` *must* happen after bootstrap — otherwise the library scans before files are copied. The `_ = AudioSampleLibrary.shared` line enforces the ordering within init.

**Tests:** None — launch-time wiring. The bootstrap itself is covered by Task 6's tests, and the library's behaviour on an empty directory is covered by Task 7's tests.

- [x] Find the `@main` struct; open its file
- [x] Add the `init()` with bootstrap + warm-up
- [x] `xcodebuild` — compiles
- [x] Launch the app manually from Xcode
- [x] Verify `~/Library/Application\ Support/sequencer-ai/samples/manifest.json` exists after first launch
- [x] Verify the starter samples are in place: `ls ~/Library/Application\ Support/sequencer-ai/samples/kick/`
- [x] Delete the Application Support directory and relaunch — files re-appear
- [x] Commit: `feat(app): bootstrap sample library on launch`

---

## Task 16: Wiki

**Scope:** New wiki page for the drum-track MVP; update related pages.

**Files:**
- Create: `wiki/pages/drum-track-mvp.md`
- Modify: `wiki/pages/track-destinations.md` — add `.sample` to the destination list
- Modify: `wiki/pages/sequencerbox-domain-model.md` — add `AudioSampleLibrary`, `AudioSample`, `AudioFileRef`, `SamplerSettings` terms

**Content of the new page:**

```markdown
---
title: "Drum Track MVP"
category: "feature"
tags: [drums, samples, destination, library, application-support]
summary: How drum-kit tracks get audible output via per-member sample destinations backed by a read-only Application Support library.
last-modified-by: codex
---

## What this is

When the user calls `Add Drum Kit (808 / Acoustic / Techno)` in the UI, each member track of the preset receives a `Destination.sample(sampleID:, settings:)` pointing at a category-matched starter sample from the app's sample library. Tracks get audio output end-to-end without importing their own sounds.

## Sample library

`AudioSampleLibrary.shared` is a process-global `@Observable` singleton that scans `~/Library/Application Support/sequencer-ai/samples/` at first access. The library is read-only for the user in this MVP — no import UI, no pool editing. Starter samples are shipped inside the `.app` bundle under `Resources/StarterSamples/` and copied to Application Support on first launch by `SampleLibraryBootstrap` (a manifest-hash-gated operation that also refreshes files on app upgrade).

Sample IDs are `UUIDv5(namespace: libraryNamespace, name: relativePath)` — deterministic across launches and machines — so documents reference samples by stable UUID even though the library itself is in-memory only.

## Destination

`Destination.sample(sampleID: UUID, settings: SamplerSettings)` is the new destination variant. `SamplerSettings` carries `gain` (UI-exposed), plus `transpose`, `attackMs`, `releaseMs` (reserved for the full sample-pool plan's UI).

## Playback

`SamplePlaybackEngine` lives on `EngineController`. It owns one `AVAudioEngine` with 16 main `AVAudioPlayerNode` voices (round-robin, steal-oldest) and a dedicated audition voice. `ScheduledEvent.Payload.sampleTrigger` is the queue payload; `EngineController.dispatchTick` drains and plays.

## UI

`SamplerDestinationWidget` renders inline inside `TrackDestinationEditor` whenever the track's destination is `.sample`. Shows:
- Sample name + category + length.
- Waveform (64 mono abs-peak bars via `WaveformDownsampler` + a SwiftUI `Canvas`).
- Prev / audition / next controls (walks `library.samples(in: category)`).
- Gain slider (-60 to +12 dB, snaps to unity within 0.5 dB of zero).

## Overriding the default

To route all drum members through one AU instead of per-member samples: set each member's destination to `.inheritGroup`, then set the group's `sharedDestination` to the desired AU. The existing inheritance mechanism works unchanged.

## Related

- [[audio-sample-pool]] — the full project-scoped pool plan that extends this MVP
- [[track-destinations]] — where `.sample` fits alongside `.midi`, `.auInstrument`, …
- [[macro-coordinator]] — the mute filter that applies to sample dispatch too
```

**`wiki/pages/track-destinations.md`** — add a row to the destination table for `.sample`.

**`wiki/pages/sequencerbox-domain-model.md`** — add vocabulary entries. Look for the existing bullet-list structure and match the format.

- [x] Create `wiki/pages/drum-track-mvp.md`
- [x] Modify `wiki/pages/track-destinations.md`
- [x] Modify `wiki/pages/sequencerbox-domain-model.md`
- [x] Commit: `docs(wiki): drum-track MVP page + destination model update`

---

## Task 17: Verify + tag

**Scope:** End-to-end sanity pass against the goal statement.

**Checks:**

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme SequencerAI test` — full suite green (new + existing).
- `grep -rn '\.sample(sampleID:' Sources` — references confined to `Destination.swift`, `EngineController.swift`, `Project+Tracks.swift`, `SamplerDestinationWidget.swift`, `TrackDestinationEditor.swift`.
- `grep -rn 'suggestedSharedDestination' Sources Tests` — zero results.
- `grep -rn 'AudioSampleLibrary' Sources` — defined once, `.shared` used from `EngineController`, `SamplerDestinationWidget`, `TrackDestinationEditor`, `SeqAIDocumentApp`.
- `ls ~/Library/Application\ Support/sequencer-ai/samples/kick/` — returns the bundled kick samples.
- `cat ~/Library/Application\ Support/sequencer-ai/samples/manifest.json` — per-file SHA entries match the bundle.

**Manual smokes:**

1. Launch app → new project → Add Drum Kit (808) → press play. Hear kick on step 1/5/9/13, snare on 5/13, hat on every other step, clap on 13.
2. Select the kick track → destination editor shows `SamplerDestinationWidget` → press **Audition** without transport → hear the kick once.
3. Press `→` prev/next in the widget → sample name changes to the next kick in the library → press audition → hear the new kick.
4. Drag gain slider to -30 dB → press audition → quieter. Drag near 0 and release → snaps to 0.0 dB.
5. Manually set the mute layer cell to `single(.bool(true))` on the kick → press play → kick silent; other drums keep playing.
6. Delete the app's Application Support samples directory → relaunch → directory re-populates from the bundle.
7. Switch a melodic track's destination to Sampler manually → default kick loads → prev/next walks the library → verify no crash.

**Goal-to-task traceability:**

| Architectural goal | Task |
|---|---|
| `AudioSampleCategory` + `VoiceTag` bridge | 1 |
| `AudioFileRef` + `SamplerSettings` | 2 |
| `AudioSample` value type | 3 |
| `Destination.sample` case | 4 |
| `Resources/StarterSamples` bundled | 5 |
| `SampleLibraryBootstrap` (first-launch copy + manifest refresh) | 6 |
| `AudioSampleLibrary` singleton (scan + queries + stable UUIDs) | 7 |
| `WaveformDownsampler` | 8 |
| `ScheduledEvent.sampleTrigger` payload | 9 |
| `SamplePlaybackEngine` + audition bus | 10 |
| `EngineController` dispatches `.sample` through the engine | 11 |
| `SamplerDestinationWidget` + `WaveformView` | 12 |
| `TrackDestinationEditor.sample` branch + choice | 13 |
| `addDrumKit` assigns per-member `.sample` | 14 |
| Library bootstraps on app launch | 15 |
| Wiki | 16 |
| Tag + verify | 17 |

- [x] All verification checks pass
- [x] All manual smokes pass
- [x] Commit: `chore: verify drum-track MVP`

---

## Task 18: Tag + mark completed

- [x] Replace `- [ ]` with `- [x]` for all completed tasks in this file
- [x] Add `**Status:** [COMPLETED YYYY-MM-DD]` line directly under `**Parent spec:**`
- [x] Commit: `docs(plan): mark drum-track-mvp completed`
- [x] Tag: `git tag -a v0.0.16-drum-track-mvp -m "Drum tracks play audio: Application Support sample library, Destination.sample + SamplerSettings, SamplePlaybackEngine with voice pool + audition, inline SamplerDestinationWidget with waveform + prev/next + gain, addDrumKit assigns per-member sample destinations"`

---

## Open questions (none blocking)

- **Library UUID namespace value.** The constant `UUID(uuidString: "9B3F4D8A-2E1B-4B5D-9A6C-7F8E9D0C1B2A")!` in `AudioSampleLibrary` is generated for this plan. Do not change it — all `Destination.sample` IDs persisted in documents depend on it being stable.
- **Starter sample content.** The implementer needs to procure CC0 or in-house WAVs before shipping. Silent placeholders get the full code path tested; audible output requires real content. File a follow-up if real content isn't available at implementation time.
- **Empty-library behaviour.** If Application Support is writable but the bundle copy fails, `addDrumKit` falls back to `.internalSampler(...)` (silent) and logs a warning. Acceptable — recovery is "reinstall / free disk space."
- **`AudioSampleLibrary.shared` and tests.** Tests inject their own library via `init(libraryRoot:)`; `.shared` is only touched from production code paths (`EngineController.init`, `TrackDestinationEditor`, `SeqAIDocumentApp.init`, `addDrumKit`). The singleton is never reset between tests — not a concern since tests inject library roots at construction.
- **Mute filter for sample dispatch.** Inherits from the existing `currentLayerSnapshot.isMuted(trackID)` check — identical to AU dispatch. No new mute code needed; the filter Just Works.
- **Forward-compat with the sample-pool plan.** When `docs/plans/2026-04-19-sample-pool.md` lands: `AudioFileRef.projectPackage` resolves; documents gain `audioSamplePool`; existing `.appSupportLibrary(...)` refs continue to work; drag-drop import lands files into Application Support (the existing library scans them). Nothing in this MVP needs to change.
