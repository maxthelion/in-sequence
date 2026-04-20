# Drum Track MVP Design — Sample-Backed Destinations

**Date:** 2026-04-20
**Status:** Design — not yet implemented
**Relates to:** `docs/plans/2026-04-19-sample-pool.md` (full sample-pool plan; this design is a forward-compatible subset), `docs/specs/2026-04-18-north-star-design.md` §"Drum tracks as groups"

## Goal

Give drum tracks audible output without shipping the full sample-pool subsystem. When a user calls `addDrumKit(_:)`, each member track gets its own sample-backed destination playing a category-appropriate starter sample (kick → kick sample, snare → snare sample, …). The starter samples live in a read-only library under `~/Library/Application Support/sequencer-ai/samples/`, populated from the app bundle on first launch. The destination editor exposes the sample inline — waveform, name, audition, gain, and prev/next category walk — without a browser, without drag-drop import, and without touching the document format.

**Verified by:** Creating a new project, calling `Add Drum Kit (808)`, hearing the kick/snare/hat/clap play when transport runs, auditioning each independently in the destination editor, walking prev/next within a category to swap the kick sound, and adjusting gain per member — all without opening any import/browser UI.

## Non-goals

- Drag-and-drop sample import.
- A sample browser or picker sheet.
- User-authored pool editing (add/remove/recategorise).
- Sample-accurate scheduling (`scheduledHostTime` is populated but not honoured by the sample dispatch path — consistent with the existing AU path).
- Transpose, attack, and release UI. The struct carries them for forward compatibility; the widget binds only `gain`.
- Package-document migration (the full sample-pool plan's Task 4). MVP keeps the current flat JSON `.seqai` format.
- Document-persisted pool. The library is in-memory, rebuilt on each launch from the on-disk scan.
- `AudioFileRef.globalLibrary(id:)` — not needed because Application Support *is* the global library in MVP.

## Architecture

Three layers:

### 1. Read-only sample library (global)

`~/Library/Application Support/sequencer-ai/samples/<category>/*.wav` populated on first launch from `Resources/StarterSamples/` in the app bundle. A launch-time `SampleLibraryBootstrap` performs the copy, gated by a manifest SHA so app upgrades refresh stale files without touching hypothetical future user additions. An `@Observable` `AudioSampleLibrary` singleton scans the directory and exposes category queries.

Sample IDs are `UUIDv5(namespace: libraryNamespace, name: relativePath)` — deterministic across launches and machines, so documents reference samples by stable UUID even though the library itself is not persisted.

### 2. Document-side reference

`Destination.sample(sampleID: UUID, settings: SamplerSettings)` is added to the existing `Destination` enum. Tracks store the sample ID only; resolution goes through `AudioSampleLibrary.sample(id:)` → `AudioFileRef.appSupportLibrary(relativePath:)` → URL. `AudioFileRef` declares a second case `.projectPackage(filename:)` reserved for the future sample-pool plan — decodes successfully, throws `ResolveError.unsupportedScope` on resolve. `AudioSample` is not `Codable` — it's a library-only value type.

### 3. Playback path

A new `SamplePlaybackEngine` owns one `AVAudioEngine` with a 16-voice `AVAudioPlayerNode` pool (round-robin, steal-oldest) plus a dedicated preview-bus voice for audition that never competes with main-pool allocation. `ScheduledEvent.Payload` gains a `.sampleTrigger(trackID, sampleID, settings, scheduledHostTime)` case. `EngineController.prepareTick` enqueues one `sampleTrigger` per firing step on `.sample` tracks; `dispatchTick` resolves the URL via the library and calls `sampleEngine.play(sampleURL:settings:at:)`.

## Data model

Five new types, all `Sources/Document/` unless noted. Shapes match the full sample-pool plan so the future plan's types are additive, not replacements.

```swift
// Sources/Document/AudioSampleCategory.swift
enum AudioSampleCategory: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case kick, snare, sidestick, clap
    case hatClosed, hatOpen, hatPedal
    case tomLow, tomMid, tomHi
    case ride, crash, cowbell, tambourine, shaker
    case percussion
    case unknown

    var displayName: String { … }
    var isDrumVoice: Bool { … }            // true for kick…shaker
    init?(voiceTag: VoiceTag)              // bridge from DrumKitPreset.Member.tag
}
```

MVP omits the full plan's `.oneShotSynth`, `.oneShotVocal`, `.loop` cases — unused today, additive later.

```swift
// Sources/Document/AudioFileRef.swift
enum AudioFileRef: Codable, Equatable, Hashable, Sendable {
    case appSupportLibrary(relativePath: String)   // "kick/tr808.wav"
    case projectPackage(filename: String)          // declared; resolver throws in MVP

    enum ResolveError: Error, Equatable {
        case missing, unsupportedScope, noLibraryRoot
    }

    func resolve(libraryRoot: URL, packageRoot: URL?) throws -> URL
}
```

```swift
// Sources/Document/AudioSample.swift
struct AudioSample: Equatable, Identifiable, Hashable, Sendable {
    let id: UUID                        // UUIDv5 from relativePath; stable across launches
    let name: String                    // derived from filename sans extension
    let fileRef: AudioFileRef
    let category: AudioSampleCategory
    let lengthSeconds: Double?
}
```

Deliberately **not** `Codable`. The library is in-memory; documents persist only the `UUID` inside `Destination.sample`.

```swift
// Sources/Document/SamplerSettings.swift
struct SamplerSettings: Codable, Equatable, Hashable, Sendable {
    var gain: Double = 0              // dB, clamped [-60, +12];  UI-exposed
    var transpose: Int = 0            // semitones, clamped [-48, +48];  reserved
    var attackMs: Double = 0          // [0, 2000];  reserved
    var releaseMs: Double = 0         // [0, 5000];  reserved

    static let `default` = SamplerSettings()
    func clamped() -> SamplerSettings
}
```

Full-plan shape on disk; MVP UI binds only `gain`. The other three serialise as defaults so documents written today decode cleanly once the full plan wires them.

```swift
// Sources/Document/Destination.swift — new case on existing enum
enum Destination {
    case sample(sampleID: UUID, settings: SamplerSettings)
    // existing: .midi, .auInstrument, .internalSampler, .inheritGroup, .none
}
```

`Destination.Kind.sample`, `summary`, `kindLabel`, `withoutTransientState` all updated. Existing documents decode unchanged — the new case is only emitted by new destinations.

```swift
// Sources/Audio/AudioSampleLibrary.swift
@Observable final class AudioSampleLibrary {
    static let shared: AudioSampleLibrary           // uses SampleLibraryBootstrap.applicationSupportSamplesURL
    private(set) var samples: [AudioSample]

    init(libraryRoot: URL)                          // test-injectable

    func samples(in category: AudioSampleCategory) -> [AudioSample]
    func sample(id: UUID) -> AudioSample?
    func firstSample(in category: AudioSampleCategory) -> AudioSample?
    func nextSample(after id: UUID) -> AudioSample?         // within category, wraps
    func previousSample(before id: UUID) -> AudioSample?    // within category, wraps
    func reload()                                            // dev affordance; no UI trigger
}
```

## Bundled library + Application Support

### Repo structure

```
Resources/StarterSamples/
├── manifest.json              # generated: per-file SHA256 + app version stamp
├── kick/
│   ├── kick-tr808.wav
│   ├── kick-acoustic.wav
│   └── kick-punch.wav
├── snare/ (≥ 3 files)
├── hatClosed/ (≥ 3)
├── hatOpen/ (≥ 2)
├── clap/ (≥ 2)
├── ride/ (≥ 1)
├── crash/ (≥ 1)
├── tomLow/ (≥ 1)
├── tomMid/ (≥ 1)
├── tomHi/ (≥ 1)
└── percussion/ (≥ 2)
```

Budget: ~36 WAVs, each short (≤ 1 s) mono; bundle under 5 MB. Categories with zero starters keep an empty directory so the scanner finds the expected tree. `project.yml` adds `bundledResources: Resources/StarterSamples/**`.

### Bootstrap

`Sources/Audio/SampleLibraryBootstrap.swift`:

```swift
enum SampleLibraryBootstrap {
    static let applicationSupportSamplesURL: URL     // ~/Library/Application Support/sequencer-ai/samples/
    static let bundledSamplesURL: URL                // <app-bundle>/Resources/StarterSamples/

    /// Idempotent. Copies bundled starters into Application Support if:
    ///   (a) the Application Support samples directory is missing, or
    ///   (b) the bundled manifest.json hash differs from the installed manifest.json.
    /// App-update case (b) refreshes files whose per-file hash changed; user-added files
    /// (a future-plan concern) are never touched.
    @discardableResult
    static func ensureLibraryInstalled() throws -> URL
}
```

Called once from `SeqAIDocumentApp.init()` before `AudioSampleLibrary.shared` is first touched.

### Scanner

`AudioSampleLibrary.init(libraryRoot:)` walks the tree:

- Top-level directory name → `AudioSampleCategory.rawValue`. Unknown names emit `.unknown`-category entries and a warning log.
- For each `.wav` / `.aif` / `.aiff` / `.caf`, compose `relativePath = "<category>/<filename>"`, derive `sampleID`, open via `AVAudioFile` for length, emit an `AudioSample`.
- Samples sorted within category by `name` for stable prev/next ordering.

## Playback

### Engine

`Sources/Audio/SamplePlaybackEngine.swift`:

```swift
final class SamplePlaybackEngine {
    init()
    func start() throws                           // idempotent
    func stop()                                   // idempotent

    func play(sampleURL: URL, settings: SamplerSettings, at when: AVAudioTime? = nil) -> VoiceHandle?
    func stopVoice(_ handle: VoiceHandle)
    func stopAllMainVoices()

    func audition(sampleURL: URL)                 // preview bus; cancels previous audition
    func stopAudition()
}
```

One `AVAudioEngine`, one `AVAudioMixerNode` → output, 16 main `AVAudioPlayerNode`s (round-robin, steal-oldest), one dedicated `previewNode` for audition (never eligible for steal).

`SamplerSettings.gain` applied per-voice as `AVAudioPlayerNode.volume = pow(10, gain / 20)`. Transpose/attack/release pass through unused in MVP; documented inline as `// Plan: sample-pool-phase-2 wires transpose via varispeed, envelope via AVAudioUnitSampler.`.

### `AVAudioFile` cache

LRU keyed by URL, capacity 64, scoped inside `SamplePlaybackEngine`. File reads are cheap but not free at drum-grid rates; the cache absorbs the repeated-trigger cost. Invalidation is implicit — URLs are stable for the library's lifetime.

### Dispatch integration

```swift
// Sources/Engine/ScheduledEvent.swift — new payload case
enum Payload {
    case trackAU(…)
    case routedAU(…)
    case routedMIDI(…)
    case chordContextBroadcast(…)
    case sampleTrigger(trackID: UUID, sampleID: UUID, settings: SamplerSettings, scheduledHostTime: TimeInterval)
}
```

`EngineController.prepareTick` — for each track whose `effectiveDestination` is `.sample(sampleID, settings)` and whose coordinator-filtered firing output is non-empty, enqueue one `sampleTrigger` per note onset. Drum tracks are single-pitch-per-step (one event per firing step). Mute filter from `MacroCoordinator.snapshot(…).isMuted(trackID)` applies identically to the AU path.

`EngineController.dispatchTick` — new case in the drain switch:

```swift
case let .sampleTrigger(_, sampleID, settings, _):
    guard let sample = sampleLibrary.sample(id: sampleID),
          let url = try? sample.fileRef.resolve(libraryRoot: libraryRoot, packageRoot: nil)
    else { continue }
    _ = sampleEngine.play(sampleURL: url, settings: settings, at: nil)
```

`scheduledHostTime` is ignored, consistent with the existing AU path (both lift to real scheduling in the timing-modulations plan). The `followup-2026-04-20-macro-coordinator-review.md` item about ignoring `now` in `dispatchTick` covers both paths together.

### Engine lifecycle

`EngineController.init` constructs `SamplePlaybackEngine`. `EngineController.start()` calls `sampleEngine.start()`; `stop()` calls `sampleEngine.stop()`. The engine is not torn down between start/stop cycles — restart is cheap.

### Audition

`SamplerDestinationWidget` calls `sampleEngine.audition(sampleURL:)` when the play button is tapped. Runs independent of transport — plays whether the clock is running or not. Tapping mid-audition restarts from the top; auditioning a different sample cancels the previous audition.

## UI: `SamplerDestinationWidget`

`Sources/UI/SamplerDestinationWidget.swift`. Rendered inline in `TrackDestinationEditor` when the destination is `.sample`. Fits within the existing destination pane (~380pt wide).

### Layout

```
┌─────────────────────────────────────────────┐
│  kick-tr808        (Kick · 0.42s)           │   header: name + category · length
│  ┌───────────────────────────────────────┐  │
│  │ ▁▂▄▆▇█▇▆▅▄▃▂▁▁                        │  │   waveform: 64 mono abs-peak bars
│  └───────────────────────────────────────┘  │
│  [◀]  [▶ audition]  [▶]   Gain: ─────●──   │   prev · audition · next · gain slider
└─────────────────────────────────────────────┘
```

### Behaviour

- **Header:** `AudioSample.name`, `category.displayName`, `lengthSeconds` formatted (`"0.42s"`, `"1.3s"`).
- **Waveform:** `WaveformDownsampler.downsample(url:bucketCount: 64)` → `[Float]` in `[0, 1]`. Rendered via SwiftUI `Canvas` as vertical bars centred on the zero line; filled colour `StudioTheme.success`.
- **`[◀]` / `[▶]`:** call `library.previousSample(before: currentID)` / `nextSample(after: currentID)`, update `destination.sample.sampleID` via binding. Disabled if category has one sample.
- **`[▶ audition]`:** calls `sampleEngine.audition(sampleURL:)`. Label toggles to `[■ stop]` while playing (timer-based reset after `lengthSeconds`); tapping again restarts.
- **Gain slider:** `Slider(value: $gain, in: -60...+12)` bound to `destination.sample.settings.gain`. Label: `"\(gain, specifier: "%+.1f") dB"`. Snaps to `0` within `0.5 dB` for quick unity reset.
- **Orphan sample (library miss):** widget renders a `StudioPlaceholderTile` with a `[Replace…]` button that assigns `library.firstSample(in: currentCategory)` — rough recovery, acceptable until the full plan's browser lands.

### Waveform downsampler

```swift
enum WaveformDownsampler {
    /// Reads the URL via AVAudioFile, computes peak absolute magnitude per bucket (mono sum).
    /// Output length == bucketCount; values in [0, 1]. Cached by URL.
    static func downsample(url: URL, bucketCount: Int = 64) -> [Float]
}
```

Cache: `NSCache<NSURL, NSArray>`, bucketed values stored as `NSNumber`. Small (~256 B per sample); 50-sample library ≈ 12 KB. No mtime invalidation — the MVP library is read-only.

### `TrackDestinationChoice` wiring

New `.sample` case: `label: "Sampler"`, `detail: "Play one-shot sample files"`. Placement in `availableChoices`: always available; prominent selection for drum-group members (default); user can pick it manually on any track (e.g. a melodic one-shot).

## Drum-kit default flow

### `addDrumKit(_:)` rewrite

```swift
mutating func addDrumKit(_ preset: DrumKitPreset) -> TrackGroupID? {
    guard !preset.members.isEmpty else { return nil }
    let library = AudioSampleLibrary.shared
    let groupID = TrackGroupID()

    let newTracks = preset.members.map { member in
        let category = AudioSampleCategory(voiceTag: member.tag) ?? .unknown
        let destination: Destination =
            library.firstSample(in: category).map {
                .sample(sampleID: $0.id, settings: .default)
            } ?? .internalSampler(bankID: .drumKitDefault, preset: preset.rawValue)
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
            sharedDestination: nil,             // was preset.suggestedSharedDestination
            noteMapping: [:]                    // samples play at native pitch
        )
    )
    selectedTrackID = newTracks.first?.id ?? selectedTrackID
    syncPhrasesWithTracks()
    return groupID
}
```

### Override to shared destination

The existing `.inheritGroup` path still works. A user who wants all drums to go through one AU picks **Inherit Group** on each member in `TrackDestinationEditor`, then sets the group's `sharedDestination` to an AU via the group editor. No new UI — the override flow is mechanically available via the existing destination-choice buttons.

### Removed file

`Sources/Document/DrumKitPreset+Destination.swift` (`suggestedSharedDestination`) is deleted — no remaining callers after the rewrite. Grep confirms.

### Fallback semantics

For a member whose `VoiceTag` does not map to any `AudioSampleCategory` (e.g. an exotic custom tag), or whose category has zero library entries, destination falls back to `.internalSampler(bankID: .drumKitDefault, preset: preset.rawValue)` — preserves the current silent-placeholder behaviour.

## File structure

### New

```
Sources/
  Audio/
    SampleLibraryBootstrap.swift
    AudioSampleLibrary.swift
    SamplePlaybackEngine.swift
    WaveformDownsampler.swift
  Document/
    AudioSampleCategory.swift
    AudioSample.swift
    AudioFileRef.swift
    SamplerSettings.swift
  UI/
    SamplerDestinationWidget.swift
    WaveformView.swift

Resources/
  StarterSamples/
    manifest.json
    kick/, snare/, hatClosed/, hatOpen/, hatPedal/, clap/, ride/, crash/,
    tomLow/, tomMid/, tomHi/, percussion/

Tests/SequencerAITests/
  Document/
    AudioSampleCategoryTests.swift
    AudioFileRefTests.swift
    SamplerSettingsTests.swift
    DestinationSampleTests.swift
  Audio/
    SampleLibraryBootstrapTests.swift
    AudioSampleLibraryTests.swift
    WaveformDownsamplerTests.swift
    SamplePlaybackEngineTests.swift       # integration-tagged
  Engine/
    EngineControllerSampleTriggerTests.swift
  DrumKit/
    DrumKitPresetSampleTests.swift
  UI/
    SamplerDestinationWidgetTests.swift
```

### Modified

```
Sources/Document/Destination.swift                # add .sample case + Kind/summary/etc.
Sources/Document/Project+Tracks.swift             # addDrumKit → per-member .sample
Sources/Engine/ScheduledEvent.swift               # add .sampleTrigger payload
Sources/Engine/EngineController.swift             # hold SamplePlaybackEngine + library root;
                                                  # prepareTick enqueues sampleTrigger;
                                                  # dispatchTick handles sampleTrigger
Sources/UI/TrackDestinationEditor.swift           # .sample branch + choice
SeqAIDocumentApp.swift                            # SampleLibraryBootstrap.ensureLibraryInstalled() in init
project.yml                                       # bundledResources: Resources/StarterSamples/**
```

### Deleted

```
Sources/Document/DrumKitPreset+Destination.swift  # suggestedSharedDestination unused after rewrite
```

## Testing strategy

**Document types.** Pure round-trip + equality + clamp coverage, no I/O.

- `AudioSampleCategoryTests` — `isDrumVoice` table; `init(voiceTag:)` for each known tag plus an unknown.
- `AudioFileRefTests` — codable round-trip for both cases; `resolve(libraryRoot:packageRoot:)` returns URL on hit, throws `.missing` on miss, throws `.unsupportedScope` for `.projectPackage`.
- `SamplerSettingsTests` — clamp bounds; round-trip; defaults.
- `DestinationSampleTests` — `.sample` round-trips; equality compares both ID and settings; Kind mapping.

**Library.** Fixture-directory tests under `tempDir`.

- `SampleLibraryBootstrapTests` — fresh-install copy path; no-op when manifest matches; refresh when manifest changes; user-added files in Application Support preserved across refresh (forward-compat).
- `AudioSampleLibraryTests` — fixture dir with 3 kicks + 1 snare → known `AudioSample` count; UUIDv5 stability across two scans; `nextSample(after:)` / `previousSample(before:)` wrap.

**Audio / playback.**

- `WaveformDownsamplerTests` — fixture WAV with known envelope shape → monotonic non-negative bucket output; cache hit on second call.
- `SamplePlaybackEngineTests` (integration-tagged; may skip in CI sandbox) — play fixture WAV returns handle; rapid 20× plays steal-oldest without crash; audition runs independent of main voices; stopAudition silences audition only; gain setting affects output level (peak amplitude read via output tap).

**Engine integration.**

- `EngineControllerSampleTriggerTests` — inject spy `SamplePlaybackEngine`; drive `processTick` with a `.sample` destination + known generator output; assert `spy.playCalls.count == expectedFirings`; mute cell set to `true` → `spy.playCalls.count == 0`.

**Drum kit.**

- `DrumKitPresetSampleTests` — `addDrumKit(.kit808)` with populated library → each member's destination is `.sample(firstSampleOfCategory.id, .default)`; library stripped of kicks → kick member falls back to `.internalSampler(…)`; `trackGroups.last!.sharedDestination == nil`; unknown `VoiceTag` → fallback, no crash.

**UI.**

- `SamplerDestinationWidgetTests` — renders sample name + category + length from injected library; next-button updates destination's sampleID; wrap on last → first; gain binding updates settings; orphan sample ID → placeholder tile with `[Replace…]` that assigns `firstSample(in:)`.

## Forward-compatibility notes

When the full sample-pool plan (`docs/plans/2026-04-19-sample-pool.md`) lands:

- `AudioFileRef.projectPackage(filename:)` lights up; existing `.appSupportLibrary(…)` refs continue to resolve. Tracks pointing at library samples migrate untouched.
- `AudioSampleLibrary` evolves into the `AudioSamplePool` concept, or sits alongside it as the "global" pool. Either path is additive — destinations still reference by UUID.
- `SamplerSettings.transpose` / `attackMs` / `releaseMs` lights up in the UI; MVP documents decode cleanly because the fields were already in the struct.
- Drag-drop import lands new files into `~/Library/Application Support/sequencer-ai/samples/` (or into a project package's `Samples/` directory, depending on scope). The scanner picks them up on next reload.
- Sample-accurate scheduling via `ScheduledEvent.scheduledHostTime` applies to both AU and sample paths together when the timing-modulations plan lands.

No breaking changes forecast from any of these.

## Open questions (none blocking)

- **Library namespace UUID.** Pick a fixed UUID constant at implementation time; document it in `AudioSampleLibrary.swift` so future refactors don't regenerate and invalidate IDs.
- **Starter sample licensing.** The ~36 WAVs need to be royalty-free or in-house-made. Not blocking — any CC0 drum pack works; can swap later without touching code (filename stability → UUID stability).
- **Empty-library behaviour on first run.** If the Application Support directory is writable but the bundle copy fails (disk full, permissions), `addDrumKit` falls back to `.internalSampler` (silent) and logs a warning. User sees tracks created, no audio; acceptable because the failure mode is rare and recoverable by reinstalling / freeing space.
- **Engine lifecycle ordering.** `AudioSampleLibrary.shared` is touched before `SamplePlaybackEngine.init` runs — fine, they're independent. `SeqAIDocumentApp.init()` order: `SampleLibraryBootstrap.ensureLibraryInstalled()` → `AudioSampleLibrary.shared` warm-up → `EngineController.init` (which holds `SamplePlaybackEngine`). Document this in `SeqAIDocumentApp.swift` comments.
