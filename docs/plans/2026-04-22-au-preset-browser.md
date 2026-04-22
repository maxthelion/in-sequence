# AU Preset Browser: Browse and Load Factory + User Presets

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`
**Status:** [COMPLETED 2026-04-22]. Tag `v0.0.4-au-preset-browser`.

## Summary

When a track's destination is a third-party AU (`Destination.auInstrument`), the user can click a "Presets…" button, see the AU's factory presets and (on AUv3) its user presets, and load one with a tap. Loading sets `auAudioUnit.currentPreset` and immediately re-captures the plugin's state into our existing `stateBlob`, so the preset choice persists with the document like any other parameter change.

This is intentionally a **browse + load** feature. We do not implement host-managed user presets (saving our own preset library outside the plugin's container) in v1 — that's a follow-up. Users who want to save tweaks can rely on the plugin's own "save preset" UI if it has one, or just save the project.

## Scope: in

- A "Presets…" button on AU destinations in `TrackDestinationEditor`
- A modal sheet listing factory presets and (AUv3) user presets, grouped
- Tap to load; visual indicator for the currently-loaded preset
- On load: set `currentPreset`, capture `fullState`, update `Destination.auInstrument.stateBlob`
- Handle the AU-is-missing / AU-is-loading case gracefully (empty state, not crash)

## Scope: out (deliberately deferred)

- Host-managed user preset library (saving our own preset files outside the plugin). That becomes a separate plan with decisions about storage location, naming, import/export, and cross-machine portability.
- Preset search beyond a simple in-sheet text filter.
- Preset categories / tags. Just two flat lists (factory, user) in v1.
- AUv2 user-preset emulation (AUv2 has no `userPresets` API; we show an empty user list for AUv2 plugins).
- Preset preview / audition without fully committing. Tap = commit.
- Bulk preset operations (rename, delete, reorder) — these require the host-managed library path.

## Dependencies

- AU hosting and `stateBlob` capture already exist (`Sources/Audio/AUAudioUnitFactory.swift`, `AudioInstrumentHost`).
- `TrackDestinationEditor.swift` is where the button slots in.
- No dependency on the macros plan. This plan can ship in either order relative to macros/filter.

## File Structure (post-plan)

```
Sources/Audio/
  AudioInstrumentHost.swift           MODIFIED — expose presetReadout(for:) + loadPreset(_:for:)

Sources/UI/TrackDestination/
  PresetBrowserSheet.swift            NEW — modal with Factory + User sections and search
  AUPresetRowView.swift               NEW — single row: name, "★ loaded" indicator

Sources/UI/
  TrackDestinationEditor.swift        MODIFIED — "Presets…" button on AU rows, opens sheet

Tests/SequencerAITests/
  Audio/
    AudioInstrumentHostPresetsTests.swift    NEW — fake AU, readout and load call paths
  UI/
    PresetBrowserSheetViewModelTests.swift   NEW — sheet's filter / selection logic is pure
```

No document-model types change. Presets are not persisted by us — only the resulting `stateBlob` is, and that's already in `Destination.auInstrument`.

## Task 1 — `AudioInstrumentHost` preset surface

**Goal:** Expose two operations: enumerate presets, and load one.

**Files:** `Sources/Audio/AudioInstrumentHost.swift`

### 1a — Readout type

```swift
struct AUPresetDescriptor: Equatable, Hashable, Sendable, Identifiable {
    let id: String                // "factory:\(number)" or "user:\(name)"; stable across loads
    let name: String
    let number: Int               // -1 for user presets
    let kind: Kind

    enum Kind: Sendable { case factory, user }
}
```

The `id` is a host-side synthesis (not the plugin's). Factory preset numbers are the authoritative identifier inside a given AU; user presets are named and the name is the key. We synthesize a single string id so the UI can use `Identifiable` without branching.

### 1b — Readout method

```swift
func presetReadout(for trackID: UUID) -> (factory: [AUPresetDescriptor], user: [AUPresetDescriptor])?
```

Returns `nil` if there's no live AU for this track (e.g. still loading, or destination isn't AU). Otherwise:

- Map `auAudioUnit.factoryPresets ?? []` to `.factory` descriptors.
- Map `auAudioUnit.userPresets` to `.user` descriptors (AUv3 only; on AUv2 the array will be empty and that's fine).

Readout is synchronous and cheap — `factoryPresets` is a property, no I/O. Do not cache; presets are read each time the sheet opens so user-preset changes made in another app surface on reopen.

### 1c — Load method

```swift
func loadPreset(_ descriptor: AUPresetDescriptor, for trackID: UUID) throws -> Data?
```

- Find the matching `AUAudioUnitPreset` by re-reading `factoryPresets` / `userPresets` (don't hold the preset object across UI sessions — its backing can become stale).
- Set `auAudioUnit.currentPreset = preset`.
- Call the existing `AUAudioUnitFactory.captureState(_:)` helper (or the equivalent path — audit `AUAudioUnitFactory.swift:78`) to encode the fresh `fullState` into a `Data` blob.
- Return the blob. The caller (UI → document command) writes it into `Destination.auInstrument.stateBlob`.

Errors: if the descriptor's id doesn't match any live preset (plugin was updated and preset N no longer exists), throw a `PresetNotFound` error. The UI shows a toast and closes the sheet.

**Tests:** `AudioInstrumentHostPresetsTests` with a fake `AUAudioUnit`-shaped protocol:
- Readout returns the expected factory and user lists.
- `loadPreset(.factory, number: 3)` sets `currentPreset` to the matching preset and returns a non-nil blob (the fake's `fullState` encoder runs).
- Loading a vanished preset throws `PresetNotFound`.
- Readout for a track with no AU returns `nil`.

## Task 2 — `PresetBrowserSheet` UI

**Goal:** A modal sheet with two sections and a text filter. Tapping a row commits the load.

**Files:** `Sources/UI/TrackDestination/PresetBrowserSheet.swift`, `AUPresetRowView.swift`

### 2a — Sheet shape

- Header: AU name (e.g. "Pigments" from `Destination.auInstrument.componentID.displayKey`) + a Close button.
- Search field filtering both sections, case-insensitive substring on name.
- `Section("Factory")` listing factory presets, empty-state text "No factory presets" if the AU exposes none.
- `Section("User")` listing user presets, empty-state text "No user presets" (this will show for most AUv2 plugins — that's correct, not a bug).
- Each row: name, and a filled star on the currently-loaded preset. Determine "currently-loaded" by comparing `auAudioUnit.currentPreset?.name` + `.number`.

### 2b — View model

Extract a pure `PresetBrowserSheetViewModel`:

```swift
final class PresetBrowserSheetViewModel: ObservableObject {
    @Published private(set) var factory: [AUPresetDescriptor] = []
    @Published private(set) var user: [AUPresetDescriptor] = []
    @Published var filter: String = ""
    @Published private(set) var loadedID: String? = nil

    var filteredFactory: [AUPresetDescriptor] { /* filter by name */ }
    var filteredUser: [AUPresetDescriptor] { /* filter by name */ }

    func reload(trackID: UUID)                         // calls host.presetReadout
    func load(_ descriptor: AUPresetDescriptor)        // calls host.loadPreset, writes stateBlob
}
```

The view model is what tests target — SwiftUI view itself remains untested per repo convention.

### 2c — Commit path

When `load(_:)` succeeds:

- Update `Destination.auInstrument.stateBlob` via the existing document-command path (same path `AUAudioUnitFactory.captureState` results already feed through — audit `TrackPlaybackSink.captureStateBlob()` and its caller to find the seam).
- Update `loadedID` so the star jumps to the newly-loaded preset.
- Do **not** auto-close the sheet. The user may want to A/B several presets; they close when done.

### 2d — Live-AU-not-ready case

If `host.presetReadout(for:)` returns `nil` when the sheet opens, show a centered "Loading plugin…" placeholder. Poll once per 500 ms (up to 5 s) to refresh, then fall back to "Presets unavailable." This handles the async `AVAudioUnit.instantiate` gap where the button is tappable before the AU finishes loading.

**Tests:** `PresetBrowserSheetViewModelTests`:
- Filter "analog" includes "Analog Keys" and "Mega Analog," excludes "Digital Bells."
- `load(...)` on success updates `loadedID` to the descriptor's id.
- `load(...)` throwing `PresetNotFound` leaves `loadedID` unchanged.
- Empty factory + empty user after reload shows both arrays as empty (not nil).

## Task 3 — `TrackDestinationEditor` button

**Goal:** A "Presets…" button appears on AU destinations. It opens `PresetBrowserSheet` scoped to the track.

**Files:** `Sources/UI/TrackDestinationEditor.swift`

- Show the button when `destination.kind == .auInstrument`.
- Hide it for all other kinds. (If the macros plan also adds a "Macros…" button here, the two sit next to each other.)
- Tap presents `PresetBrowserSheet(trackID: track.id)`.

Not a testable seam on its own. Verified manually.

## Test Plan (whole-plan)

- **Unit**: host readout + load, view model filter + commit behavior.
- **Manual smoke**:
  1. Add an AU track with Pigments. Click "Presets…". Confirm factory presets appear.
  2. Tap a preset. Hear the plugin's sound change. Star indicator moves to the selected preset.
  3. Save the project, quit, relaunch, reopen. Confirm the preset-modified sound is still there (proves `stateBlob` was captured and restored).
  4. Open the sheet again. Confirm the star still points to the loaded preset.
  5. Load a different preset, close the sheet without A/B testing. Doc reflects the second preset.
  6. On AUv2 plugin (e.g. old DX7 clone): confirm factory list populates and user list shows "No user presets."
  7. On an AU that has no factory presets at all (rare): confirm "No factory presets" placeholder instead of blank section.
  8. Click "Presets…" immediately after attaching a fresh AU (race the async instantiation): confirm the "Loading plugin…" placeholder appears and resolves within a second or two.

## Assumptions

- `AUAudioUnitPreset` is the only preset type we care about. AUv2 plugins that expose presets only through `ClassInfo` / non-standard mechanisms are out of scope; in practice the vast majority expose factory presets through `AUAudioUnit.factoryPresets` via the AUv2→v3 bridge.
- Setting `currentPreset` and then capturing `fullState` is the right order. Some plugins are lazy about applying a preset until the audio callback runs. If this turns out to be a real problem in manual smoke, add a small delay (~50 ms) between the two operations and document it — don't preemptively engineer around a hypothetical.
- User presets surfaced via `auAudioUnit.userPresets` are safe to enumerate and set. We do not add / delete / rename user presets in this plan; the AU manages its own user storage.

## Traceability

| Requirement                                                  | Task |
|--------------------------------------------------------------|------|
| Browse AU presets from the host                              | 1b, 2a |
| Load a preset on tap                                         | 1c, 2c |
| Preset choice persists with the document                     | 1c (stateBlob capture), 2c (stateBlob write) |
| Works on both factory and user presets (AUv3)                | 1b |
| Graceful empty state on AUv2 user presets                    | 2a (empty-state text) |
| Doesn't crash when AU still loading                          | 2d |
