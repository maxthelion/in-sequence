# Track Macro Parameters: AU Macro Picker, Built-in Device Macros, Per-Step Macro Layers

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`
**Status:** Not started. Tag `v0.0.NN-track-macro-parameters` at completion.

## Summary

Each track can expose a small set of **macro parameters** that modulate its destination. Macros are the single abstraction that unifies internal-device parameters (sample start, sample length, sample gain) and third-party AU parameters (cutoff, resonance, anything the user picks from the parameter tree).

Once assigned, a track's macros:

- appear as **phrase layers** so they can be set per-track-per-step (single / bars / steps / curve) in Phrase view
- appear in **Live view** as live-editable knobs
- appear as a new **macro lane** inside clips for per-step overrides, layered over the phrase-layer value (clip macro = "local override," phrase layer = "arrangement modulation")
- are applied by the engine every prepared step via `MacroCoordinator` → a new `LayerSnapshot.macroValues` field → a new sink in the audio layer that writes to `AUParameter.value` (AU) or device-native setters (internal devices)

For AU destinations, macro selection is a user act: click a "Macros…" button on the destination panel, pick up to N parameters from the AU's `parameterTree`. The modal ranks likely candidates (cutoff, resonance, drive, attack, decay, release, filter, tone, pitch, env, lfo, rate, depth) at the top using case-insensitive substring matching, with the full tree browsable below.

For **internal devices**, macros are defined in code — the sampler auto-exposes `sampleStart`, `sampleLength`, and `sampleGain`. A separate plan (`2026-04-22-sampler-filter.md`) adds a built-in filter and extends `BuiltinMacroKind` with filter macros on top of this foundation.

This plan ships the AU and internal-macro shape in one slice, because the data model, coordinator path, and UI surfaces are shared.

## Scope: in

- New `TrackMacroDescriptor` + `TrackMacroBinding` document types
- `Destination.internalSampler` and `Destination.sample` auto-populate three built-in macros (`sampleStart`, `sampleLength`, `sampleGain`) on creation
- `Destination.auInstrument` can attach any subset of the AU's `parameterTree` parameters as macros via a modal picker
- `PhraseLayerTarget.macroParam(bindingID: UUID)` so macros flow through the existing coordinator / snapshot / phrase-cell editors untouched in shape
- `ClipContent.noteGrid` gains a parallel `macroLanes: [MacroLane]` field that overrides the phrase-layer value at the step boundary
- Live view shows a row of knobs for each track's macros
- Name-match ranking for "likely candidate" AU parameters

## Scope: out (deliberately deferred)

- Audio-rate automation / sample-accurate AU parameter ramps. V1 writes parameter values **once per prepared step** via `AUParameterAutomationEvent` with `.value` type, reusing the existing prepare-phase dispatch path. Per-step granularity only.
- Macro-to-macro routing, macro math, or LFO/envelope macros. Macros are scalars in `[min, max]` with a single source per step.
- MIDI learn, MIDI CC binding, or host-side CC→macro mapping. Plugins that translate CC internally still work; host-level CC binding is a separate plan.
- Factory preset "macro map" definitions for popular AUs. V1 is always user-picked (candidate ranking helps them choose).
- Persistence migration for existing documents. Old docs decode with `bindings: []` and `macroLanes: [:]`; no shim.
- Poly-voice independent filters. The sampler filter is one instance per track, shared by all voices on that track.

## Dependencies

- `MacroCoordinator` + `LayerSnapshot` already exist (`Sources/Engine/MacroCoordinator.swift`, `Sources/Engine/LayerSnapshot.swift`)
- Phrase-layer editors already handle scalar + indexed layers (`Sources/UI/PhraseCellEditors/`)
- AU hosting already captures `AVAudioUnit` per track (`Sources/Audio/AUAudioUnitFactory.swift`, `TrackPlaybackSink`)
- `Destination.auInstrument` already carries `AudioComponentID` and `stateBlob` (`Sources/Document/Destination.swift:30`)

## File Structure (post-plan)

```
Sources/Document/
  TrackMacroDescriptor.swift         NEW — what a macro is (id, name, range, source)
  TrackMacroBinding.swift            NEW — a specific binding on a specific track
  SamplerSettings.swift              MODIFIED — add sampleStartNorm, sampleLengthNorm (0..1)
  ClipContent.swift                  MODIFIED — .noteGrid gains macroLanes: [UUID: MacroLane]
  PhraseModel.swift                  MODIFIED — PhraseLayerTarget.macroParam(UUID) case + default layer synthesis
  Project+Tracks.swift               MODIFIED — helpers to list/add/remove macros on a track

Sources/Audio/
  AudioInstrumentHost.swift          MODIFIED — expose parameterTree lookup to UI + macro write path
  TrackMacroApplier.swift            NEW — applies macro values to AU / sampler on prepare
  SamplePlaybackEngine.swift         MODIFIED — setVoiceParam entry points for sampleStart/Length/Gain

Sources/Engine/
  LayerSnapshot.swift                MODIFIED — add macroValues: [UUID: [UUID: Double]] (track → binding → value)
  MacroCoordinator.swift             MODIFIED — read macroParam layers, write into snapshot.macroValues
  EngineController.swift             MODIFIED — dispatch snapshot.macroValues to TrackMacroApplier

Sources/UI/
  TrackDestination/
    MacroPickerSheet.swift           NEW — modal: browses AU parameterTree, ranks candidates, multi-selects
    MacroPickerCandidateRanker.swift NEW — pure name-match ranker (testable in isolation)
  TrackDestinationEditor.swift       MODIFIED — "Macros…" button on AU / sampler rows
  LiveWorkspaceView.swift            MODIFIED — macro knob row per track
  PhraseWorkspaceView.swift          MODIFIED — macroParam layers listed alongside built-ins
  Track/ClipMacroLaneEditor.swift    NEW — per-step override lane in the clip editor

Tests/SequencerAITests/
  Document/
    TrackMacroDescriptorTests.swift               NEW
    ClipContentMacroLaneTests.swift               NEW
  Engine/
    MacroCoordinatorMacroParamTests.swift         NEW
    TrackMacroApplierTests.swift                  NEW
  UI/
    MacroPickerCandidateRankerTests.swift         NEW
```

## Task 1 — `TrackMacroDescriptor` + `TrackMacroBinding`

**Goal:** One document type describes "what a macro is on this track," regardless of destination kind.

**Files:** `Sources/Document/TrackMacroDescriptor.swift`, `TrackMacroBinding.swift`

```swift
enum TrackMacroSource: Codable, Equatable, Hashable, Sendable {
    // Built-in device macro. The applier knows how to dispatch these by kind.
    case builtin(BuiltinMacroKind)

    // AU parameter, addressed by stable identifier from AUParameterTree.
    // `address` is the 64-bit parameter address captured at selection time;
    // `identifier` is the plugin's keyPath, stored as a fallback for host
    // reconnection when addresses shift across plugin versions.
    case auParameter(address: UInt64, identifier: String)
}

enum BuiltinMacroKind: String, Codable, CaseIterable, Sendable {
    // Sampler / sample destination
    case sampleStart          // 0..1 normalized position in source buffer
    case sampleLength         // 0..1 normalized length from start
    case sampleGain           // dB, -60..+12
    // The sampler-filter plan (2026-04-22-sampler-filter.md) adds five more
    // cases on top of these three. Don't preemptively add them here —
    // this enum evolves additively and each plan owns its kinds.
}

struct TrackMacroDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: UUID                 // stable across renames
    var displayName: String
    var minValue: Double
    var maxValue: Double
    var defaultValue: Double
    var valueType: PhraseLayerValueType   // reuse existing enum: .scalar / .boolean / .patternIndex
    var source: TrackMacroSource
}

struct TrackMacroBinding: Codable, Equatable, Hashable, Sendable {
    let descriptor: TrackMacroDescriptor
    // Macro bindings live on the track so a single UUID stably identifies
    // "track X's cutoff macro" for phrase-layer targets and clip lanes.
}
```

**Not in scope here:** the actual application of values. That's Task 5.

**Tests:**
- Round-trip a `TrackMacroDescriptor` through JSON for both `.builtin` and `.auParameter` cases.
- Two descriptors with the same id are equal; differing only in display name are not.
- `BuiltinMacroKind.allCases` round-trips.

## Task 2 — Track storage for macros + built-in auto-population

**Goal:** A track carries `macros: [TrackMacroBinding]`. When a destination is assigned, built-in macros are auto-populated; user-added AU macros are appended.

**Files:** `Sources/Document/Project+Tracks.swift`, `StepSequenceTrack` (wherever the struct lives — likely `Sources/Document/StepSequenceTrack.swift`; read it first, then extend).

- Add `var macros: [TrackMacroBinding]` to `StepSequenceTrack`.
- Add `Project.setDestination(_:for:)` side-effect: when destination transitions to `.sample` or `.internalSampler`, ensure the three built-in sampler macros (`sampleStart`, `sampleLength`, `sampleGain`) exist (append missing, never duplicate). When destination transitions to `.auInstrument`, wipe sampler built-ins but leave `.auParameter` bindings alone. The sampler-filter plan extends this list to eight on top of the same mechanism.
- Add `Project.addAUMacro(descriptor:to:)`, `removeMacro(id:from:)` helpers.

**Why this wiring shape:** a sampler track gets useful macros the moment it's created — zero configuration. Switching to an AU clears only built-ins so the user doesn't see dangling "sampleStart" knobs on a Pigments track; AU macros persist across destination swaps within the same AU kind (reconnection handled in Task 6e).

**Tests:** `ProjectTrackMacroTests.swift`:
- Setting `.internalSampler` populates the three built-in sampler macros with stable ids (stable id = deterministic hash of `(trackID, builtinKind.rawValue)` — document this in the helper).
- Setting `.auInstrument` removes `.builtin(...)` bindings and keeps `.auParameter(...)` bindings.
- Adding the same AU macro twice is a no-op.
- Removing a macro also removes any phrase-layer cells and clip macro-lane entries that referenced it (cascade — implemented here, tested here).

## Task 3 — `ClipContent.noteGrid` gains `macroLanes`

**Goal:** A clip can carry per-step overrides for any of its track's macros. Override semantics: if the lane has a value at step N, that value wins; otherwise the phrase-layer value wins; otherwise the descriptor default wins.

**Files:** `Sources/Document/ClipContent.swift`, `Tests/.../ClipContentMacroLaneTests.swift`

```swift
struct MacroLane: Codable, Equatable, Sendable {
    // Parallel to `steps.count` in the enclosing .noteGrid.
    // `nil` at index N means "no override, defer to phrase layer / default."
    var values: [Double?]
}

enum ClipContent: Codable, Equatable, Sendable {
    case noteGrid(
        lengthSteps: Int,
        steps: [ClipStep],
        macroLanes: [UUID: MacroLane]     // binding.descriptor.id -> lane
    )
    case sliceTriggers(stepPattern: [Bool], sliceIndexes: [Int])
}
```

- Keep `sliceTriggers` unchanged in this plan — slice clips don't get per-step macros in v1.
- Add a `synced(with macros: [TrackMacroBinding], stepCount: Int)` method that drops lanes for removed macros and resizes `values` to match the clip's step count.
- Codable: legacy docs without `macroLanes` decode as empty; no migration.

**Why a dict keyed by descriptor id, not an ordered list:** macros can be reordered in UI without invalidating clip data, and sparse lanes (only cutoff has overrides, nothing else has a lane) don't pay storage cost.

**Tests:**
- Round-trip a clip with two macro lanes.
- Legacy clip JSON (no `macroLanes` key) decodes with empty lanes.
- `synced` drops lanes whose descriptor id isn't in the track's current bindings.
- `synced` pads or truncates lane values to match step count.

## Task 4 — Phrase layer target + coordinator extension

**Goal:** A per-track macro binding appears as a `PhraseLayerDefinition` in the phrase model, so the existing cell editor (single / bars / steps / curve) edits it with no per-editor changes.

**Files:** `Sources/Document/PhraseModel.swift`, `Sources/Engine/MacroCoordinator.swift`, `Sources/Engine/LayerSnapshot.swift`

### 4a — Target case

```swift
enum PhraseLayerTarget: Codable, Equatable, Sendable {
    case patternIndex
    case mute
    case macroRow(String)
    case blockParam(String, String)
    case voiceRouteOverride(String)
    case macroParam(trackID: UUID, bindingID: UUID)   // NEW
}
```

Do **not** collapse this into the existing `.macroRow(String)`. `.macroRow` is a global intensity-like knob keyed by name; `.macroParam` is track-scoped and binding-scoped.

### 4b — Default layer synthesis

`PhraseLayerDefinition.defaultSet(for tracks:)` currently returns a hard-coded list (see `PhraseModel.swift:222`). Extend it to append, after the fixed builtins, one layer per `(track, binding)` pair with:

- `id = "macro-\(trackID)-\(bindingID)"`
- `name = binding.descriptor.displayName`
- `valueType = binding.descriptor.valueType`
- `minValue / maxValue / defaults[trackID]` from the descriptor
- `target = .macroParam(trackID:bindingID:)`

`PhraseModel.synced(with:layers:)` already drops cells for unknown layers and creates `inheritDefault` cells for new ones. Verify this handles the new layer ids without change.

### 4c — Snapshot extension

```swift
struct LayerSnapshot: Equatable, Sendable {
    let mute: [UUID: Bool]
    let fillEnabled: [UUID: Bool]
    let macroValues: [UUID: [UUID: Double]]   // track -> binding -> resolved value
    ...
}
```

`MacroCoordinator.snapshot(...)` walks `.macroParam` layers, resolves the cell value at `stepInPhrase`, and writes it into `macroValues`. Cell-value type must match descriptor `valueType` — if a boolean cell shows up for a scalar descriptor, coerce (bool → 0/1) rather than skip; log an assertion in debug.

**Tests:** `MacroCoordinatorMacroParamTests.swift`:
- Given one track with one scalar macro, a phrase cell of `.single(.scalar(0.7))` yields `snapshot.macroValues[trackID][bindingID] == 0.7` for every step.
- `.steps([0.0, 0.5, 1.0, 0.5])` yields the right value per step index modulo step count.
- `.curve(...)` interpolates (reuse existing `phrase.resolvedValue` path — no new interpolation logic).
- Removing the binding from the track → cell is no longer read → snapshot contains no entry for that binding.

## Task 5 — Clip macro lane override + `TrackMacroApplier`

**Goal:** Engine prepare-phase combines phrase-layer snapshot + clip macro lane and writes the resolved value into the destination.

**Files:** `Sources/Audio/TrackMacroApplier.swift`, `Sources/Engine/EngineController.swift`

### 5a — Override resolution

For each track on each prepared step:

1. Start with `descriptor.defaultValue`.
2. If `snapshot.macroValues[track][binding]` exists, use it.
3. If the currently-playing clip is `.noteGrid` and its `macroLanes[binding.descriptor.id]?.values[stepInClip]` is non-nil, that value wins.

Step 3 runs in the coordinator, not the applier, so the applier sees one resolved `[UUID: [UUID: Double]]` per step.

### 5b — `TrackMacroApplier`

```swift
final class TrackMacroApplier {
    // Injected: the sampler playback engine and the AU host registry.
    // The switch on TrackMacroSource.builtin is extensible — the
    // sampler-filter plan adds a branch for .samplerFilter* kinds
    // without changing this class's public shape.
    func apply(_ values: [UUID: [UUID: Double]], tracks: [StepSequenceTrack])
}
```

Per binding:

- `.builtin(.sampleStart | .sampleLength | .sampleGain)` → `SamplePlaybackEngine.setVoiceParam(trackID:, kind:, value:)`. Value is applied to newly-started voices on subsequent steps — do not retroactively seek already-playing voices (adds click noise; v1 is discrete per-step anyway).
- `.auParameter(address:identifier:)` → look up `AUParameter` via `auAudioUnit.parameterTree?.parameter(withAddress: address)`, fall back to `parameterTree?.value(forKeyPath: identifier)`, write with `setValue(_:originator:)` using a per-applier token so observer callbacks don't bounce back. If both lookups fail, log once per binding id and skip.

**Do not** re-read the parameter tree every prepared step. Cache `(trackID, bindingID) -> AUParameter` on first successful lookup; invalidate on destination swap.

**Tests:** `TrackMacroApplierTests.swift` with a fake `AUParameter`-like protocol:
- Scalar binding writes the exact value on each prepared step.
- Unknown AU param address logs once, not per-step.
- Destination swap clears the cache.
- Bool descriptor written as 0.0 / 1.0 on the underlying parameter.

## Task 6 — AU `parameterTree` access + macro picker modal

**Goal:** From the destination editor, the user can see every parameter exposed by the loaded AU, see a "Likely candidates" shortlist, and multi-select which to expose as macros.

**Files:**
- `Sources/UI/TrackDestination/MacroPickerSheet.swift`
- `Sources/UI/TrackDestination/MacroPickerCandidateRanker.swift`
- `Sources/Audio/AudioInstrumentHost.swift` (extend to expose parameter metadata)
- `Sources/UI/TrackDestinationEditor.swift` (add "Macros…" button)

### 6a — Parameter readout

Add to `AudioInstrumentHost` a method `parameterReadout(for trackID: UUID) -> [AUParameterDescriptor]?` returning a flat, pre-sorted list of:

```swift
struct AUParameterDescriptor: Equatable, Hashable, Sendable {
    let address: UInt64
    let identifier: String
    let displayName: String
    let minValue: Double
    let maxValue: Double
    let defaultValue: Double
    let unit: String?          // rendered via AudioUnitParameterUnit → human string
    let group: [String]        // ancestor group displayNames, outer-first
    let isWritable: Bool
}
```

Flatten `auAudioUnit.parameterTree?.allParameters`. Skip non-writable parameters. Readout is called on main thread — cache per trackID until destination changes.

### 6b — Candidate ranker (pure, testable)

```swift
enum MacroPickerCandidateRanker {
    static let candidateKeywords: [String] = [
        "cutoff", "resonance", "filter", "drive", "tone",
        "attack", "decay", "sustain", "release", "env",
        "lfo", "rate", "depth", "amount",
        "pitch", "detune", "fine",
        "reverb", "delay", "chorus", "wet", "dry", "mix",
        "macro"
    ]

    static func rank(_ params: [AUParameterDescriptor]) -> (candidates: [AUParameterDescriptor], rest: [AUParameterDescriptor])
}
```

Case-insensitive substring match on `displayName` and any element of `group`. A match on `displayName` ranks above a match on a group name; `cutoff` before `filter cutoff` before `filter`. Stable tie-break by `displayName`.

**Tests:** `MacroPickerCandidateRankerTests.swift` — given a canned fixture of ~40 descriptors (including real Pigments-style names), exact expected ordering of candidates, and `candidates + rest` equals the input set.

### 6c — Modal

`MacroPickerSheet` shows:

- Top section "Likely candidates" — ranked candidates, each with checkbox, name, group path, and a faint min/max/unit line.
- Collapsible "All parameters" section — everything else, alphabetical, same row shape.
- A search box filtering both sections.
- A counter "N of up to 8 selected" (enforce a cap — see Task 9).
- Already-bound parameters render as checked by default (so reopening the sheet shows current state).

Confirm button commits the diff — add newly checked, remove newly unchecked. Cancel discards.

**Internal-device destinations** use a different button path: when destination is `.internalSampler` or `.sample`, the "Macros" button opens a **read-only list** of built-ins (users can't remove them — the whole point is one-click consistency). No picker sheet for internal devices in v1.

### 6d — Destination editor button

In `TrackDestinationEditor.swift`, add a "Macros…" button visible only when destination is `.auInstrument`, `.internalSampler`, or `.sample`. MIDI / none destinations do not show it.

### 6e — Reconnection across document load

On document load, for each `.auParameter(address:identifier:)` binding, resolve the live `AUParameter` by `address` first, by `identifier` second. If neither resolves, keep the binding in the doc (don't silently delete — the plugin may be missing a version), mark it disabled in UI, and skip it in the applier. This is important: users will open docs on machines where the AU isn't installed, and we must not destroy their work.

**Tests:** the disabled-binding path is tested in `TrackMacroApplierTests` (Task 5).

## Task 7 — Live view macro row

**Goal:** In Live view, each track shows a horizontal row of knobs — one per macro binding. Dragging a knob writes the descriptor's current value to the phrase-layer default (`.single(newValue)` in `inheritDefault` context; otherwise the behavior is "live override" — next step the phrase cell wins again).

**Files:** `Sources/UI/LiveWorkspaceView.swift`

Decision to lock in during implementation: **"live knob drag sets the phrase layer default, doesn't overwrite step cells."** Reason: Live view is for arrangement-level play; Phrase view is where per-step edits live. A Live drag shouldn't clobber step automation the user set up in Phrase view. If this feels wrong during implementation, flag it and we reassess — don't silently change the model.

Knob visuals: reuse `ThrottledMixControl.swift` — matches existing mixer-fader ergonomics.

Tests: this is a SwiftUI view; no snapshot tests exist in this repo today. Document the decision in the view's file header and ship without unit tests for the visual layer. Add one ViewModel-level test that `applyLiveValue(_:binding:)` writes to `layer.defaults[trackID]` and not to any cell.

## Task 8 — Phrase view integration + clip macro lane editor

**Goal:** Macro-param layers are listed alongside mute/pattern/volume in Phrase view with zero special-cased rendering. Clip editor gains a macro lane view for per-step overrides.

**Files:** `Sources/UI/PhraseWorkspaceView.swift`, `Sources/UI/Track/ClipMacroLaneEditor.swift`

### 8a — Phrase view

Because `PhraseLayerDefinition` is the same shape for a built-in and a `.macroParam`, the existing row rendering should work. Audit:

- Layer list section order: built-ins first, then per-track macros grouped by track.
- Layer defaults sync when a binding is added/removed (call `project.layers = PhraseLayerDefinition.defaultSet(for: tracks)` at the right seam).
- Scalar-layer editor respects descriptor min/max — it already does via `layer.scalarRange`.

### 8b — Clip macro lane editor

In the clip editor inside `TrackSourceEditorView.swift`'s clip branch (or wherever `ClipContent.noteGrid` is edited — confirm path before starting), add a collapsible "Macros" section with one lane per track binding. Each lane is a horizontal strip of `values.count` cells; tapping a cell opens a scalar scrubber that sets `values[i] = Double`; long-press clears to `nil`. A cleared cell shows the phrase-layer-resolved value in pale text (so the user sees what the default is).

This lane is per-clip. A track with five clips has five independent lane sets.

## Task 9 — Limits and guards

**Goal:** Don't let the macro system blow up.

- Cap per-track bindings at **8**. The modal disables further checkboxes and shows a "8 of 8 selected" message. Rationale: keeps the Live view knob row sane on narrow screens and caps per-step dispatch cost.
- Binding ids are UUIDs, stable across document loads. Never regenerate.
- When removing a macro, cascade to phrase-layer cells (drop the layer) and clip macro lanes (drop the lane dict entry). Covered in Task 2's tests.
- AU parameter writes are batched per-step: one `setValue` per parameter per step, not per prepared sample. Audio thread never touches `parameterTree`.

## Test Plan (whole-plan)

- Document / model: all round-trips, all cascade rules.
- Engine: coordinator produces `macroValues`, applier dispatches to fakes, no per-step allocations in a tight loop.
- UI: candidate ranker is fully unit-tested; view integration is exercised manually (documented below).
- Manual smoke:
  1. Create a sampler track. Confirm three sampler macros (sampleStart, sampleLength, sampleGain) appear in Phrase view with descriptor-correct defaults.
  2. Set "sampleGain" to `.steps([0, -6, 0, -12])` and hear per-step amplitude variation.
  3. In the clip, override step 1 of the sampleGain lane to 0 dB. Confirm step 1 is at full level while other steps duck.
  4. Create an AU track with Pigments (or any third-party AU). Click "Macros…". Verify "Cutoff" and "Resonance" appear near the top of candidates. Select three. Confirm three new layers + three new knobs appear.
  5. Automate Pigments cutoff via `.curve(...)`. Hear the sweep.
  6. Save document. Reopen. Verify bindings restore and still write to the live AU.
  7. Remove the Pigments AU (simulate by editing the component ID to a non-installed one). Reopen. Verify bindings show as disabled in the picker but are not deleted.

## Assumptions and open questions

- **Assumption:** AU parameter writes once per prepared step is enough fidelity for macros. If not — if we need audio-rate ramps — we add a ramping sink in the engine later; the doc model doesn't change.
- **Open question:** should the Live view knob drag write to the phrase layer default (current decision) or create a temporary override that decays after N steps? V1 goes with the simpler "write default" behavior and we revisit if it feels wrong in use.
- **Open question:** should we ship factory "macro map" JSON files for popular AUs (Pigments, Diva, Serum)? Deferred — user-picked with candidate ranking is the v1 answer.

## Traceability

| Requirement                                                        | Task |
|--------------------------------------------------------------------|------|
| Click a button on an AU destination to pick macro params           | 6c, 6d |
| Modal shows likely candidates (cutoff, resonance, etc.)            | 6b, 6c |
| Macros editable in Live view                                       | 7 |
| Macros editable in Phrase view                                     | 4, 8a |
| Per-step macro overrides inside a clip (a "layer" in the clip)     | 3, 5a, 8b |
| Internal sampler auto-exposes standard macros                      | 2, 1 |
| Sample start / length / gain available as sampler macros           | 1 (BuiltinMacroKind), 5b |
| Macros are writable per prepared step without audio-thread churn   | 5b, 9 |
| Document persistence survives missing plugins without data loss    | 6e |
