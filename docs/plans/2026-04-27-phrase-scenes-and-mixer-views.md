# Phrase Scenes and Mixer Views

**Parent context:** `docs/plans/2026-04-25-master-bus-scenes.md`, `wiki/pages/octatrack-reference.md`, and the current `PhraseWorkspaceView` / `PhraseModel` shape.
**Status:** Not started. Tag `v0.0.NN-phrase-scenes-mixer-views` at completion.

## Summary

Extend phrase editing from one track/layer matrix into three phrase views:

1. **Tracks** — the existing phrase matrix: phrases down the rows, tracks across the columns, one selected layer at a time (`pattern`, `mute`, macros, fill, etc.).
2. **Scenes** — phrase-level master scene assignment: choose master scene A, master scene B, and the crossfader position for each phrase.
3. **Mixer** — phrase-level mix automation across output busses: volume, pan, mute, solo, and related bus controls.

The important product decision: keep **base track mix values** and **phrase mixer automation** separate.

`StepSequenceTrack.mix` remains the track's default/current base mix. Phrase mixer cells are optional arrangement overlays that resolve on top of those defaults while a phrase plays. This avoids a destructive workflow where editing a phrase's breakdown or transition mix permanently changes the track's normal mix everywhere else.

## Current Shape

Already implemented:

- `PhraseModel` stores per-track, per-layer cells.
- Built-in phrase layers include `pattern`, `mute`, and `volume`.
- `StepSequenceTrack.mix` stores base `level`, `pan`, and `isMuted`.
- `MasterBusState` stores scenes, active scene, `MasterBusABSelection`, and `crossfader`.
- `MasterBusPerformanceOverlayState` can override master scene macro values and crossfader at runtime.
- `MixerWorkspaceView` / `ScenesWorkspaceView` exist as top-level workspace areas.

Missing:

- Phrase-level scene A/B selection.
- Phrase-level crossfader value.
- A phrase Scenes view.
- A phrase Mixer view that edits mix automation as phrase data rather than track defaults.
- A bus model for phrase mixer lanes that covers tracks, groups, master, and future bus-like endpoints consistently.

## Goals

- Make master scene A/B and crossfader part of phrase authoring.
- Let each phrase recall a different scene pair and fader position.
- Add a phrase view selector with `Tracks`, `Scenes`, and `Mixer`.
- Keep the existing Tracks phrase matrix intact.
- Let the Mixer phrase view list every relevant bus and edit phrase-scoped mix overlays.
- Preserve track defaults as defaults; phrase mixer cells should inherit from those defaults unless explicitly overridden.
- Make resolution order explicit and testable.

## Non-Goals

- No per-step crossfader automation in the first slice. Scene A/B and crossfader are phrase-level values.
- No full arranger/song mode.
- No new audio routing graph unless the current bus inventory cannot express the UI.
- No per-track insert chains.
- No destructive migration that converts existing track mix into phrase cells.

## Product Decision: Defaults vs Phrase Mixer Automation

Keep them separate.

### Why separate them?

- **Defaults remain stable.** A track's normal gain/pan/mute belongs to the track and should not change just because one phrase has a breakdown mix.
- **Phrases become reusable arrangements.** The same track can be loud in a drop phrase and quiet in a bridge phrase without copying the track or mutating global state.
- **Inheritance is clear.** Empty phrase mixer cells mean "use the current/base bus value."
- **Live performance has a clean stack.** Base mix → phrase overlay → live/performance overlay.
- **Undo and review are safer.** A phrase edit has phrase-level blast radius, not project-wide mix side effects.

### Where this can get confusing

`mute` and `volume` already exist in two nearby concepts:

- track mix mute/volume: output-level base defaults;
- phrase `mute` / `volume` layers: arrangement-time cells.

This plan should make the semantics explicit:

- Existing phrase `mute` keeps its current **source mute** meaning unless a later product decision changes it.
- Phrase Mixer `mute` should be **bus/output mute** for the selected phrase.
- Track `mix.isMuted` remains the default output mute.
- Phrase Mixer `volume` should be a bus/output level overlay, not a macro row masquerading as volume.

If the UI needs to avoid duplicate labels, use copy like `Source Mute` in the Tracks view and `Bus Mute` or simply `Mute` in the Mixer view with contextual headers.

## Desired Model

Add phrase-level scene assignment:

```swift
struct PhraseSceneState: Codable, Equatable, Sendable {
    var sceneAID: UUID?
    var sceneBID: UUID?
    var crossfader: Double? // nil = inherit current master AB selection
}
```

Add optional phrase-level mixer overlays:

```swift
enum PhraseMixBusID: Codable, Equatable, Hashable, Sendable {
    case track(UUID)
    case group(UUID)
    case master
}

struct PhraseMixOverlay: Codable, Equatable, Sendable {
    var busID: PhraseMixBusID
    var level: Double?  // nil = inherit base bus level
    var pan: Double?    // nil = inherit base bus pan, where supported
    var mute: Bool?     // nil = inherit base bus mute
    var solo: Bool?     // nil = no phrase solo override
}
```

Extend `PhraseModel`:

```swift
struct PhraseModel {
    var sceneState: PhraseSceneState?
    var mixOverlays: [PhraseMixOverlay]
}
```

Open implementation choice:

- Store `sceneState` / `mixOverlays` as explicit phrase fields, or
- Generalize phrase cell addressing beyond `(trackID, layerID)` so phrase-global and bus-scoped cells use the same editing machinery.

Recommendation for first implementation: use explicit phrase fields for scene state and mix overlays. The current phrase cell matrix is track/layer-shaped; forcing scene A/B and busses through fake track IDs would make the model clever in the bad way.

## Resolution Order

At playback / preview time:

1. Start from persisted base state:
   - `StepSequenceTrack.mix`
   - group/default bus state if/when groups gain bus mix fields
   - `MasterBusState.abSelection`
2. Apply selected phrase scene state:
   - if `sceneAID` / `sceneBID` are present, set the master AB pair for that phrase;
   - if `crossfader` is present, set crossfader for that phrase.
3. Apply phrase mix overlays:
   - track bus overlays to per-track audio/MIDI-output mix as appropriate;
   - group bus overlays when group busses exist;
   - master overlay to master output level/mute if supported.
4. Apply live/performance overlays last.

`nil` means inherit. Explicit values override only for the phrase.

## UI Shape

### Phrase view selector

Add a segmented/tabs control in `PhraseWorkspaceView`:

- `Tracks`
- `Scenes`
- `Mixer`

The existing matrix becomes the `Tracks` tab.

### Scenes tab

Rows: phrases.

Columns / controls:

- Phrase name / length
- Scene A picker
- Scene B picker
- Crossfader slider or compact horizontal fader
- Clear / inherit button for scene state

Behavior:

- Selecting scene A/B stores scene IDs, not indexes.
- If a stored scene ID is deleted, normalize to an existing scene or inherit.
- Crossfader stores `0...1`; display as A/B percentage or centered fader.
- Optionally show the active phrase's scene pair in the transport/top bar later.

### Mixer tab

Rows: busses.

Columns / controls:

- Bus name
- Volume
- Pan, where supported
- Mute
- Solo
- Inherit / clear override state

Suggested initial bus list:

- all tracks as track busses;
- track groups as group busses if there is runtime support, otherwise show after group bus support lands;
- master bus.

Phrase selection remains visible: the Mixer tab edits the selected phrase's overlays. If editing multiple phrases at once is desired later, add copy/paste or multi-select after the basic shape works.

## Task 1 — Model phrase scene state

**Goal:** Add phrase-level scene A/B and crossfader storage.

- [ ] Add `PhraseSceneState`.
- [ ] Add `sceneState: PhraseSceneState?` to `PhraseModel`.
- [ ] Decode old phrases with `sceneState = nil`.
- [ ] Normalize deleted scene IDs during project/master-bus normalization.
- [ ] Add tests for round-trip, legacy decode, scene deletion, and crossfader clamping.

Acceptance:

- Existing documents decode without phrase scene assignments.
- Scene IDs are stable across scene reordering.
- Deleted scene references are repaired or inherited deterministically.

## Task 2 — Apply phrase scene state to runtime

**Goal:** When a phrase becomes active, master scene A/B and crossfader reflect that phrase's scene state.

- [ ] Extend snapshot or phrase playback metadata with phrase scene state.
- [ ] Route phrase scene changes to `MasterBusHost` / `MasterBusPerformanceOverlayState` without rebuilding note playback unnecessarily.
- [ ] Avoid reapplying the same AB selection every tick; apply on phrase boundary or when phrase scene state changes.
- [ ] Add tests for phrase transition applying scene A/B and crossfader.

Acceptance:

- Phrase A can use scene pair 1/2 at crossfader 0.0.
- Phrase B can use scene pair 2/3 at crossfader 0.75.
- Transport crossing from Phrase A to Phrase B updates the master bus once at the phrase boundary.

## Task 3 — Add the Phrase Scenes view

**Goal:** Let users edit scene A, scene B, and crossfader for phrases.

- [ ] Add phrase view selector to `PhraseWorkspaceView`.
- [ ] Keep current matrix as `Tracks`.
- [ ] Add `PhraseScenesView`.
- [ ] Add scene A/B pickers sourced from `session.store.masterBus.scenes`.
- [ ] Add crossfader control.
- [ ] Add clear/inherit actions.

Acceptance:

- User can set scene A/B and crossfader for each phrase.
- UI survives scene deletion/reorder.
- UI does not confuse active master scene editing with phrase scene assignment.

## Task 4 — Model phrase mixer overlays

**Goal:** Add phrase-scoped bus mix overlays without mutating track defaults.

- [ ] Add `PhraseMixBusID`.
- [ ] Add `PhraseMixOverlay`.
- [ ] Add `[PhraseMixOverlay]` to `PhraseModel`.
- [ ] Define supported bus inventory for v1: tracks + master, groups only if runtime support exists.
- [ ] Add round-trip and legacy decode tests.
- [ ] Add resolution tests proving nil inherits defaults and explicit values override.

Acceptance:

- Existing track `mix` remains unchanged when phrase mixer overlays are edited.
- Phrase overlays round-trip through document save/load.
- Missing/deleted bus references normalize cleanly.

## Task 5 — Apply phrase mixer overlays to runtime

**Goal:** Make phrase mix overlays audible and scoped.

- [ ] Compile phrase mixer overlays into playback/runtime state.
- [ ] Apply track bus level/pan/mute through scoped runtime mix updates.
- [ ] Define solo semantics for phrase overlays.
- [ ] Ensure phrase overlays do not force full playback snapshot rebuilds when a scoped runtime update is enough.
- [ ] Add tests for track level, pan, mute, and solo resolution.

Acceptance:

- Phrase-specific volume/pan/mute changes are audible.
- Leaving a value unset inherits `StepSequenceTrack.mix`.
- Returning to a phrase with no overlay returns to base track mix.

## Task 6 — Add the Phrase Mixer view

**Goal:** Provide the third phrase view for bus-level phrase automation.

- [ ] Add `PhraseMixerView`.
- [ ] List track busses and master bus.
- [ ] Add volume, pan, mute, and solo controls.
- [ ] Show inherited values distinctly from explicit overrides.
- [ ] Add per-control clear/inherit actions.
- [ ] Consider a "write current defaults into this phrase" command after the base UI works.

Acceptance:

- User can edit the selected phrase's mix overlays without changing `StepSequenceTrack.mix`.
- Explicit and inherited states are visually distinct.
- Controls use existing mixer styling where possible.

## Task 7 — Documentation and terminology cleanup

**Goal:** Make the distinction between source/track/default mix and phrase mixer overlays understandable.

- [ ] Update `wiki/pages/phrase-workspace.md` or create it if missing.
- [ ] Update `wiki/pages/macro-coordinator.md` if mute semantics need clarification.
- [ ] Update `wiki/pages/master-bus-scenes.md` / `track-destinations.md` with phrase scene assignment flow if those pages exist.
- [ ] Add glossary text for:
  - track default mix;
  - source mute;
  - bus/output mute;
  - phrase mix overlay;
  - master scene assignment.

Acceptance:

- A new contributor can tell whether a control edits a track default, phrase overlay, live overlay, or master scene.

## Open Questions

- Should phrase mixer solo be persisted as a phrase overlay, or should solo remain runtime-only?
- Should group busses be included in v1 if group audio busses are not fully modeled yet?
- Should crossfader be phrase-level only in v1, or should it immediately support bars/steps/curve modes like normal phrase cells?
- Should existing phrase `volume` layer be renamed or deprecated once Phrase Mixer volume exists?
- Should the Scenes view also allow editing scene macro values per phrase, or only A/B assignment and crossfader?

## Test Plan

- Document:
  - phrase scene state round-trip;
  - phrase mixer overlay round-trip;
  - legacy phrase decode defaults;
  - deleted scene/bus reference normalization.
- Runtime:
  - phrase boundary applies scene A/B and crossfader;
  - phrase mixer overlays resolve over track defaults;
  - scoped runtime updates happen without unnecessary full snapshot rebuilds.
- UI:
  - phrase view selector switches Tracks / Scenes / Mixer;
  - Scenes view edits phrase state;
  - Mixer view edits phrase overlays, not track defaults.
- Manual smoke:
  - create two master scenes;
  - set Phrase A to Scene A/B at crossfader left;
  - set Phrase B to Scene A/B at crossfader right;
  - play across phrase boundary and hear master bus change;
  - lower one track in Phrase B's Mixer view and confirm Phrase A remains unchanged.

