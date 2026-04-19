# Track Destinations (Voices) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give tracks a proper destination model (MIDI out or AUv3 instrument, per-track and uniquely instanced), with AU UI opening in a dedicated window so the user can edit plugin params live. Plus a cross-project "recent voices" history so a voice tuned in Project A shows up as a recall option when starting a new track in Project B. Verified by: an MIDI-destined mono track plays to the chosen endpoint; an AU-destined track opens the plugin's native UI in a window; closing the window persists state; reopening the document re-loads state; creating a voice in one project surfaces it in the voice-picker of a second project.

**Architecture:** Destinations are **per-track and inline** — not a shared pool. Each track's `Voicing` holds a `Destination` value type per voice tag (`"default"` for mono/poly/slice; `"kick"`/`"snare"`/… for drums). `Destination` is a tagged union: `.midi(port, channel, noteOffset)` or `.auInstrument(audioComponentID, stateBlob)`. AU state blobs travel via `NSKeyedArchiver`-encoded `AUAudioUnit.fullState` wrapped in the document JSON as base64. AU editor windows are owned by an `@MainActor AUWindowHost` keyed on the track+tag; windows are created lazily via `AUAudioUnit.requestViewController(...)` and torn down on close, at which point the host captures the unit's `fullState` and writes it back into the document. Recent-voices history is a JSON file at `~/Library/Application Support/sequencer-ai/voices/history.json`, written to on track-create / voice-edit-commit / window-close, read by a `RecentVoicesStore` that the voice-picker UI queries. Drums retain the per-tag voicing map as already specced, but this plan focuses on the mono/poly/slice "default" tag — drum per-tag voicing works through the same types (drum plan integration is trivial once this lands).

**Tech Stack:** Swift 5.9+, AVFoundation (AVAudioEngine, AVAudioUnit), AudioToolbox (AUAudioUnit), CoreMIDI (existing `MIDIClient`), AppKit (NSWindow, NSViewController), Foundation (NSKeyedArchiver, FileManager), XCTest.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — §"Vocabulary" (Voicing), §"Scoping" (track project-scoped), §"UX surfaces" (Track view's destination editor). AU out-of-process hosting + state-via-`fullState` captured in §Platform open-question "AUv3 hosting".

**Environment note:** Xcode 16 at `/Applications/Xcode.app`. `xcode-select` points at CommandLineTools. All `xcodebuild` invocations in this plan prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. AUv3 extension discovery + hosting requires the app's sandbox entitlements file to allow audio-component hosting (already set up per Plan 0's `SequencerAI.entitlements`; verify before Task 4).

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.5-track-destinations` at TBD.

**Deliberately deferred:**

- **Drum per-tag voicing UI.** The data types support N tags per drum track; the UI to edit per-tag destinations lands with a drum-focused plan. This plan ensures the types are ready.
- **Internal sampler voice kind.** `Destination` is extensible; a future `.internalSampler` variant arrives with the slice / audio-engine plan.
- **FX chains / per-track insert effects.** Audio-side plan.
- **Voice preset import/export via `.seqai-voice` files.** `RecentVoicesStore` gives informal cross-project reuse; explicit bundle-format exports come later.
- **AUv2 support.** AUv3 only for this plan. Out-of-process AUv3 matches the user's [[phat]] project's `.loadOutOfProcess` pattern.

---

## File Structure

```
Sources/
  Document/
    Destination.swift                  # NEW — enum .midi | .auInstrument
    Voicing.swift                      # NEW — per-tag Destination map (extracted from PhraseModel.swift)
    SeqAIDocumentModel.swift           # MODIFIED — Track.voicing: Voicing; legacy migration
  Audio/
    AUAudioUnitFactory.swift           # NEW — wraps AVAudioUnit instantiation + fullState codec
    AUWindowHost.swift                 # NEW — @MainActor, manages NSWindow per (trackID, tag)
    AudioInstrumentHost.swift          # MODIFIED — drive AUs from VoicePreset state blobs
    FullStateCoder.swift               # NEW — NSKeyedArchiver ↔ Data helper
  Platform/
    RecentVoicesStore.swift            # NEW — ~/Library/.../voices/history.json read/write
  UI/
    TrackDestinationEditor.swift       # NEW — source/destination split's right half
    VoicePickerView.swift              # NEW — recent + new + edit flow
    DetailView.swift                   # MODIFIED — host the destination editor on the right
Tests/
  SequencerAITests/
    Document/
      DestinationTests.swift
      VoicingTests.swift
      SeqAIDocumentModelTests.swift    # MODIFIED — legacy migration assertions
    Audio/
      FullStateCoderTests.swift
      AUAudioUnitFactoryTests.swift    # mock-based where we can; integration-tagged where we can't
      AUWindowHostTests.swift          # lifecycle with a stub unit
    Platform/
      RecentVoicesStoreTests.swift
```

`project.yml` gains the `Audio/` and `Platform/` file additions and the new `Tests/` subdirectories.

---

## Task 1: `Destination` enum

**Scope:** The tagged union. Pure data; Codable; no audio-engine wiring yet.

**Files:**
- Create: `Sources/Document/Destination.swift`
- Create: `Tests/SequencerAITests/Document/DestinationTests.swift`

**Type:**

```swift
public enum Destination: Codable, Equatable, Sendable {
    case midi(port: MIDIEndpointName?, channel: UInt8, noteOffset: Int)
    case auInstrument(componentID: AudioComponentID, stateBlob: Data?)
    case none   // unassigned — track plays but no output target

    public var kindLabel: String { ... }   // "MIDI" / "AU Instrument" / "—"
}

public struct MIDIEndpointName: Codable, Equatable, Hashable, Sendable {
    public let displayName: String        // resolvable back to endpoint by name at load time
    public let isVirtual: Bool
}

public struct AudioComponentID: Codable, Equatable, Hashable, Sendable {
    public let type: String               // FourCharCode as 4-byte string, e.g. "aumu"
    public let subtype: String            // 4-byte
    public let manufacturer: String       // 4-byte
    public let version: UInt32

    public var displayKey: String { "\(manufacturer).\(type).\(subtype)" }
}
```

**Tests:**

1. Round-trip Codable for each variant (including `.none` and an AU with `stateBlob: Data(repeating: 0xAB, count: 64)`).
2. `Destination.none.kindLabel == "—"`.
3. `AudioComponentID.displayKey` format: `"XfnZ.aumu.Sero"` shape.
4. `MIDIEndpointName` equals another with the same displayName + isVirtual.
5. Channel value is the raw byte (0..15 for MIDI 1.0); the type doesn't validate — caller responsibility (covered by settings.json precondition when dispatching).

- [ ] Tests for the 5 cases
- [ ] Implement
- [ ] `xcodebuild test` green
- [ ] Commit: `feat(document): Destination enum (MIDI / AU / none)`

---

## Task 2: `Voicing` struct

**Scope:** The per-tag Destination map. Extract the type from `PhraseModel.swift` (where codex stubbed `voicing`-adjacent types); give it a proper home. For mono/poly/slice the "default" tag is used; drum tracks add per-tag entries later.

**Files:**
- Create: `Sources/Document/Voicing.swift`
- Create: `Tests/SequencerAITests/Document/VoicingTests.swift`

**Type:**

```swift
public struct Voicing: Codable, Equatable, Sendable {
    public static let defaultTag: VoiceTag = "default"

    public var destinations: [VoiceTag: Destination]

    public init(destinations: [VoiceTag: Destination] = [:]) {
        self.destinations = destinations
    }

    public static func single(_ destination: Destination) -> Voicing {
        Voicing(destinations: [defaultTag: destination])
    }

    public var defaultDestination: Destination {
        destinations[Self.defaultTag] ?? .none
    }

    public mutating func setDefault(_ destination: Destination) {
        destinations[Self.defaultTag] = destination
    }

    public func destination(for tag: VoiceTag) -> Destination {
        destinations[tag] ?? .none
    }
}
```

**Tests:**

1. `Voicing.single(.midi(...)).defaultDestination == .midi(...)`.
2. `Voicing(destinations: ["kick": ..., "snare": ...]).destination(for: "cowbell") == .none`.
3. Round-trip Codable (both shapes).
4. Mutating `setDefault` replaces the default tag's destination.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): Voicing per-tag Destination map`

---

## Task 3: Migrate `StepSequenceTrack` to use `Voicing`

**Scope:** Codex's current `StepSequenceTrack` has `output: TrackOutputDestination` (enum) and `audioInstrument: AudioInstrumentChoice` separately. Collapse into `var voicing: Voicing`. Legacy decoder migrates old documents.

**Files:**
- Modify: `Sources/Document/SeqAIDocumentModel.swift` — change `StepSequenceTrack` fields and update its Codable
- Modify: `Sources/Engine/EngineController.swift` — read from `track.voicing.defaultDestination` instead of `track.output` + `track.audioInstrument`
- Modify: `Sources/UI/DetailView.swift` — read/write through the new field
- Modify: `Tests/SequencerAITests/SeqAIDocumentTests.swift` — assertion updates

**Migration mapping (legacy decode):**

- Old `output == .midiOut` → `Destination.midi(port: MIDIEndpointName(displayName: "Virtual Out", isVirtual: true), channel: 0, noteOffset: 0)`
- Old `output == .auInstrument` with a populated `audioInstrument` → `Destination.auInstrument(componentID: ..., stateBlob: nil)` (old saves didn't persist fullState)
- Missing fields → `Destination.none`

Encoder-side: write `voicing` as the new structure; drop the legacy fields.

**Tests:**

1. An old-format JSON (with `output` + `audioInstrument` fields) decodes into a track whose `voicing.defaultDestination` reflects the old selection.
2. A new-format document round-trips through encode → decode unchanged.
3. Existing document tests (`test_document_roundtrip`, etc.) keep passing against the new field names (test fixtures updated).
4. `EngineController` receives `Voicing` values and routes MIDI correctly (existing engine integration tests stay green).

- [ ] Update the type
- [ ] Update EngineController
- [ ] Update DetailView reads
- [ ] Legacy-migration unit test
- [ ] Full suite green
- [ ] Commit: `refactor(document): Track.voicing replaces output + audioInstrument; legacy migration`

---

## Task 4: `FullStateCoder` — AU state ↔ `Data`

**Scope:** `AUAudioUnit.fullState: [String: Any]?` isn't Codable. Wrap it via `NSKeyedArchiver` with secure coding, return `Data` suitable for `Destination.auInstrument.stateBlob`.

**Files:**
- Create: `Sources/Audio/FullStateCoder.swift`
- Create: `Tests/SequencerAITests/Audio/FullStateCoderTests.swift`

**API:**

```swift
public enum FullStateCoder {
    public static func encode(_ fullState: [String: Any]?) throws -> Data?
    public static func decode(_ data: Data?) throws -> [String: Any]?

    public enum CoderError: Swift.Error, Equatable {
        case archiveFailed, unarchiveFailed, unexpectedType
    }
}
```

Internals: `NSKeyedArchiver(requiringSecureCoding: true)` for encode; `NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, ...])` for decode. Whitelist of expected top-level classes covers dictionary, array, string, number, data — enough for AU fullState payloads.

**Tests:**

1. Encode `nil` → returns `nil`.
2. Encode `["foo": "bar", "count": 7, "blob": Data(repeating: 0xFE, count: 16)]` → non-nil Data.
3. Decode that Data returns an equivalent dict (string-matched, number-matched, data-bytes-matched).
4. Decode garbage Data → throws `unarchiveFailed`.
5. Decode valid-archive-of-wrong-type (e.g. a plain `NSNumber`) → throws `unexpectedType`.
6. Round-trip nested dicts (simulated AU payload: `["pluginData": Data(...), "isMuted": true, "preset": "Lead 3"]`).

- [ ] Tests
- [ ] Implement with NSKeyedArchiver wrapper
- [ ] Green
- [ ] Commit: `feat(audio): FullStateCoder for AU state blob serialization`

---

## Task 5: `AUAudioUnitFactory` — instantiation + state apply/capture

**Scope:** Centralised AU instantiation. Given a `Destination.auInstrument`, returns an `AVAudioUnit` whose `auAudioUnit` is loaded with the stored state. Also captures state on demand.

**Files:**
- Create: `Sources/Audio/AUAudioUnitFactory.swift`
- Create: `Tests/SequencerAITests/Audio/AUAudioUnitFactoryTests.swift` (integration-tagged; skips if AVFoundation isn't available in the test environment)

**API:**

```swift
public final class AUAudioUnitFactory {
    public enum FactoryError: Swift.Error {
        case componentNotFound(AudioComponentID)
        case instantiationFailed(OSStatus)
    }

    public static func instantiate(
        _ componentID: AudioComponentID,
        stateBlob: Data?,
        completion: @escaping (Result<AVAudioUnit, FactoryError>) -> Void
    )

    /// Captures the unit's current fullState (via FullStateCoder) as a new Data.
    public static func captureState(_ unit: AVAudioUnit) throws -> Data?
}
```

Uses `AVAudioUnit.instantiate(with:options: .loadOutOfProcess, completionHandler:)`. On success, decodes `stateBlob` via `FullStateCoder` and applies to `unit.auAudioUnit.fullState`.

**Tests (integration-tagged):**

1. Instantiation with an unknown `AudioComponentID` → `componentNotFound`.
2. Round-trip: instantiate system-bundled `DLSMusicDevice` (AU's Apple DLS synth, available on every macOS install), set a parameter, `captureState`, instantiate a second copy with that blob, verify parameter matches. Skip with `XCTSkip` if `DLSMusicDevice` isn't found.
3. State blob persists across factory calls (use tempDir to write Data, re-read, re-instantiate).

- [ ] Tests
- [ ] Implement factory
- [ ] Green (skips acceptable for CI paths missing the DLS synth)
- [ ] Commit: `feat(audio): AUAudioUnitFactory with state apply/capture`

---

## Task 6: `AudioInstrumentHost` driven by `Destination`

**Scope:** Codex's `AudioInstrumentHost` currently takes an `AudioInstrumentChoice`. Adapt to accept a `Destination.auInstrument` value (same underlying component, different wrapper). Preserve the codex work's startup-crash guards (`6ccccd0`, `98c4bf0`).

**Files:**
- Modify: `Sources/Audio/AudioInstrumentHost.swift`
- Modify: `Tests/SequencerAITests/Engine/AudioInstrumentHostTests.swift`

**Behaviour:**

- `host.attach(destination:)` loads the AU via the factory; if `stateBlob` is non-nil, applies on instantiation completion.
- `host.detach()` captures the current state → returns the new blob (caller writes it back to the document's Voicing).
- `host.currentUnit` — accessible AVAudioUnit for `AUWindowHost` to request a view controller.

**Tests (extend the existing ones):**

1. Attach → currentUnit is non-nil after completion.
2. Attach → detach → returned state Data is non-nil and decodes via FullStateCoder.
3. Attach with an invalid componentID → logs + `currentUnit == nil`; does not crash.
4. Attach twice without detach → detaches the previous unit cleanly.

- [ ] Update AudioInstrumentHost
- [ ] Extend tests
- [ ] Green
- [ ] Commit: `refactor(audio): AudioInstrumentHost takes Destination.auInstrument`

---

## Task 7: `AUWindowHost` — lifecycle of AU editor windows

**Scope:** Manages one NSWindow per (trackID, voiceTag). Opens via `requestViewController`; persists state on close.

**Files:**
- Create: `Sources/Audio/AUWindowHost.swift`
- Create: `Tests/SequencerAITests/Audio/AUWindowHostTests.swift`

**API:**

```swift
@MainActor
public final class AUWindowHost: NSObject {
    public typealias StateWriteback = (TrackID, VoiceTag, Data?) -> Void

    public init(stateWriteback: @escaping StateWriteback)

    public func open(for trackID: TrackID, tag: VoiceTag, unit: AVAudioUnit, title: String)
    public func close(for trackID: TrackID, tag: VoiceTag)
    public func isOpen(for trackID: TrackID, tag: VoiceTag) -> Bool
}

extension AUWindowHost: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification)
}
```

Implementation:

- On `open`: if a window already exists for the key, `makeKeyAndOrderFront(nil)` and return.
- Otherwise: `unit.auAudioUnit.requestViewController { vc in ... }` → wrap in NSWindow → set size to vc.preferredContentSize (with sensible fallback: 600×400) → show.
- On `windowWillClose`: look up the AUAudioUnit, call `FullStateCoder.encode(unit.auAudioUnit.fullState)`, fire `stateWriteback(trackID, tag, data)`, remove the window from the registry.
- Deinit closes all windows and writes back state for each.

**Tests:**

- Most of this is NSWindow / AU-runtime integration, hard to unit-test. Focus on the registry behaviour:

1. `open(_:tag:unit:)` registers a window; `isOpen` returns true.
2. Second `open` with the same key does NOT create a second window (registry size stays 1).
3. `close(_:tag:)` removes from the registry and calls the writeback callback exactly once.
4. Window delegate path: simulate a `windowWillClose` notification; verify writeback fires.

Use a stub `AVAudioUnit`-adjacent object for tests (extract an internal protocol `AUViewHosting` if needed).

- [ ] Tests (4 cases against the registry, with stubs)
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(audio): AUWindowHost for per-track AU editor windows`

---

## Task 8: `RecentVoicesStore` — cross-project voice history

**Scope:** Persists a list of recently-used voices to `~/Library/Application Support/sequencer-ai/voices/history.json`. Append-on-use, read-on-voice-picker-open. Cross-project by virtue of being at user-library scope.

**Files:**
- Create: `Sources/Platform/RecentVoicesStore.swift`
- Create: `Tests/SequencerAITests/Platform/RecentVoicesStoreTests.swift`

**Type:**

```swift
public struct RecentVoice: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String                    // user-supplied or "untitled" → renameable in picker
    public var destination: Destination
    public var firstSeen: Date                 // when first added to history
    public var lastUsed: Date                  // updated on every recall
    public var projectOrigin: String?          // last known document title for context
}

public final class RecentVoicesStore {
    public static let shared = RecentVoicesStore(
        historyURL: URL.userAppSupport
            .appendingPathComponent("sequencer-ai/voices/history.json")
    )

    public init(historyURL: URL)

    public func load() -> [RecentVoice]       // newest first; empty [] if file missing
    public func record(_ voice: RecentVoice)  // append or update (by id); bump lastUsed
    public func touch(id: UUID)               // bump lastUsed without other changes
    public func rename(id: UUID, to name: String)
    public func prune(maxEntries: Int = 64)   // keep newest N; call opportunistically
}
```

File format: JSON array of `RecentVoice`; pretty-printed for user-inspectability; atomic write (write tempfile then `mv`).

**Tests:**

1. `load()` on an empty filesystem returns `[]`; doesn't crash.
2. `record(v1); load()` returns `[v1]`.
3. `record(v1); record(v2)` where v2 has a later `lastUsed` → `load()` returns `[v2, v1]` (newest first).
4. `record(v1); record(v1')` where v1' has same id → stored as one entry with merged fields (lastUsed = max).
5. `prune(maxEntries: 2)` on a store with 5 entries retains newest 2.
6. `rename` updates the persisted name; file content reflects change.
7. Directory creation: if `~/Library/Application Support/sequencer-ai/voices/` doesn't exist, `record` creates it.

Use a per-test temp dir for the `historyURL`, not `.shared`, to keep tests isolated from the real user dir.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(platform): RecentVoicesStore (cross-project voice history)`

---

## Task 9: `TrackDestinationEditor` view + `VoicePickerView`

**Scope:** The right-hand half of Track view. Shows current destination + controls to change it. "Pick voice" opens a modal/sheet picker showing: recent voices, "blank MIDI", "blank AU" options. For AU destinations, an "Edit" button opens the AU window via `AUWindowHost`.

**Files:**
- Create: `Sources/UI/TrackDestinationEditor.swift`
- Create: `Sources/UI/VoicePickerView.swift`
- Modify: `Sources/UI/DetailView.swift` — host the editor on the right of the detail split

**Behaviour:**

- Current destination renders as a pill: `"🎹 Serum 1 (AU)"` or `"🔌 IAC Bus 1 · ch 1 (MIDI)"` or `"— (no destination)"`.
- Tapping the pill opens the voice picker.
- VoicePicker has three tabs: **Recent** (from `RecentVoicesStore`), **New MIDI** (endpoint dropdown + channel), **New AU** (component-type filter + list sourced from `AudioComponentDescription` enumeration).
- Picking a voice updates `track.voicing.setDefault(destination)` on the document and `store.record(...)` on the history store.
- For `.auInstrument` destinations: an "Edit" button in the editor sends the track's current AU through `AUWindowHost.open`. Writeback from the host updates `track.voicing`.

**Tests:**

- This is SwiftUI view code; snapshot tests (Plan 2b `qa-infrastructure`) cover the render. For behaviour:

1. Selecting a MIDI destination from the picker writes to `track.voicing` and records in the store (test uses injected `RecentVoicesStore` pointed at tempDir).
2. Selecting a recent voice from the Recent tab writes the full destination to the track.
3. Clicking Edit on an AU destination calls `AUWindowHost.open` with the correct trackID / tag / unit (spy on the host).
4. If no AU is attached yet (unit not yet loaded), the Edit button is disabled with a tooltip.

Use `@MainActor` view-model tests where possible; SwiftUI rendering via `NSHostingView` for state-inspection.

- [ ] Tests
- [ ] Implement TrackDestinationEditor + VoicePicker
- [ ] Integrate into DetailView
- [ ] Green
- [ ] Commit: `feat(ui): TrackDestinationEditor + VoicePickerView with recent-voices recall`

---

## Task 10: Wire everything end-to-end

**Scope:** `EngineController` observes `track.voicing` changes and drives AU attachment / detachment through `AudioInstrumentHost`. UI's "Edit" button dispatches through `AUWindowHost`. Closed windows write state back via a callback that updates the document.

**Files:**
- Modify: `Sources/Engine/EngineController.swift` — observe voicing
- Modify: `Sources/App/SequencerAIApp.swift` — instantiate `AUWindowHost` with the writeback closure
- Modify: `Sources/UI/DetailView.swift` — the Edit button sends a command up through the environment

**Behaviour:**

- Opening a document: for each track with `.auInstrument` destination, EngineController asks AudioInstrumentHost to attach. The AU loads with its stored state. No window pops up — the user explicitly clicks Edit to open.
- User edits in the AU window: parameter automation flows live.
- User closes the AU window: AUWindowHost captures state via FullStateCoder, the writeback closure updates `document.model.tracks[i].voicing.destinations["default"] = .auInstrument(..., stateBlob: newBlob)`.
- Switching voicing to `.midi`: AudioInstrumentHost detaches AU; any open window for that track closes and writes state back.
- Save document: new stateBlob persists.
- Reopen: AU re-attaches with saved state; Edit button works; round-trip identical.

**Tests:**

- Integration-tagged test: load a document with a known AU destination and a pre-captured state blob; verify `AudioInstrumentHost.currentUnit?.auAudioUnit.fullState` matches after attachment.
- Spy-based test: simulate a window close; verify `document.model.tracks[0].voicing.destinations["default"]` acquires a non-nil stateBlob.
- Manual smoke: hit Play on an AU-destined track, hear output in a DAW / routed through macOS audio; note in commit message.

- [ ] Wire EngineController
- [ ] Wire app-level AUWindowHost instantiation
- [ ] Integration test
- [ ] Manual smoke test
- [ ] Green
- [ ] Commit: `feat(engine): wire Destination through EngineController + AUWindowHost`

---

## Task 11: Wiki update

**Scope:** Add `wiki/pages/track-destinations.md` describing the Destination / Voicing / AUWindowHost / RecentVoicesStore model. Update `wiki/pages/project-layout.md` for the new files.

**Files:**
- Create: `wiki/pages/track-destinations.md`
- Modify: `wiki/pages/project-layout.md`

- [ ] Wiki page covers: Destination tagged union (per-track, not shared); AU UI open flow (requestViewController → NSWindow → writeback on close); RecentVoicesStore user-library path; migration from codex's audioInstrument + output
- [ ] project-layout.md gains the `Audio/` and `Platform/` module rows
- [ ] Commit: `docs(wiki): track-destinations page + project-layout update`

---

## Task 12: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for completed steps
- [ ] Add a `Status:` line after `Parent spec` in this file's header, following the placeholder-token pattern used in other plans
- [ ] Commit: `docs(plan): mark track-destinations completed`
- [ ] Tag: `git tag -a v0.0.5-track-destinations -m "Track destinations complete: Destination enum; per-track AU hosting with window UI; RecentVoicesStore; migration from codex audioInstrument+output fields"`

---

## Goal-to-task traceability (self-review)

| Goal / architectural claim | Task |
|---|---|
| `Destination` enum (MIDI / AU / none) | Task 1 |
| `Voicing` per-tag map | Task 2 |
| Legacy migration from codex's `output` + `audioInstrument` | Task 3 |
| AU state ↔ Data codec via NSKeyedArchiver | Task 4 |
| AU instantiation factory with state apply/capture | Task 5 |
| `AudioInstrumentHost` adapter | Task 6 |
| AU editor window lifecycle | Task 7 |
| Cross-project voice history at `~/Library/.../voices/history.json` | Task 8 |
| Voice picker UI + track destination editor | Task 9 |
| End-to-end wiring (attach on load, write state on close, round-trip save) | Task 10 |
| Wiki | Task 11 |
| Tag | Task 12 |

## Open questions resolved for this plan

- **Shared vs per-track AU instances:** per-track. Two tracks using "the same" voice each get their own AVAudioUnit instance; state divergence is expected. Cross-project sharing happens via the RecentVoicesStore recall (copies the destination config into a new track).
- **Voice preset IDs:** per-track `Voicing` holds `Destination` inline. `RecentVoicesStore` entries have UUIDs but those aren't referenced from the document — they're just keys in the user-library history. When the user picks a recent voice, the destination is COPIED into the track's voicing (with a fresh AU instance loaded from the same componentID + stateBlob).
- **What populates RecentVoicesStore?** Track-create with a non-`.none` destination, user-initiated "Save this voice" action, and AU-window-close (if the destination's been edited since last-seen). Passive tracking would bloat the history.
- **AUv3 vs AUv2:** v3 only. `AVAudioUnit.instantiate(with:options: .loadOutOfProcess, ...)` covers the v3 case; v2 plugins are rarer and can be added later if demand exists.
- **Entitlements:** app sandbox requires `com.apple.security.temporary-exception.audio-unit-host` (already present per Plan 0). No user-prompted elevation for AU hosting.
- **`ProjectOrigin` in RecentVoice:** populated from the document's title at the time of record. Privacy: document titles are user-chosen and don't leak content, but the history file is readable by anything running as the user — if that becomes a concern, we can anonymise later.
- **Picker filter by track type:** for mono/poly/slice only "instrument" AU type-IDs show; drum tracks would show drum-kit AU types. For this plan (melodic-focused), the filter is `type == "aumu"` (AU Music Device). Drums later.
