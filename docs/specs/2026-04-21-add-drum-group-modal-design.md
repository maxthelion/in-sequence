# Add Drum Group Modal

**Date:** 2026-04-21
**Status:** Design — not yet implemented
**Relates to:** `docs/specs/2026-04-21-single-destination-ui-design.md` (supplies `AddDestinationSheet`), `docs/specs/2026-04-20-drum-track-mvp-design.md`, `wiki/pages/track-destinations.md`

## Goal

Replace the `Menu("Add Drum Kit")` dropdown on the Tracks page with an `Add Drum Group` button that opens a dedicated modal for creating a drum group. The modal lets the user:

1. Choose between a **Blank** group (user-editable starter rows: kick, snare, hat, clap) and a **Templated** group (one of `DrumKitPreset.allCases`).
2. Preview the tracks the group will contain.
3. For templated groups, toggle whether seed step-patterns are prepopulated into the new clips.
4. Optionally configure a **shared destination** on the group and select — per member — which tracks route to it (`.inheritGroup`) versus keeping their per-voice default destination.

**Verified by:** On the Tracks page, pressing `Add Drum Group` opens a sheet titled "Add Drum Group". With the default selection (`Blank`), the sheet shows four editable rows (Kick, Snare, Hat, Clap). Switching the segmented control to `Templated` reveals a preset picker defaulting to `808 Kit` and replaces the rows with a read-only list (Kick, Snare, Hat, Clap) plus a `Prepopulate step patterns` toggle (default on). Toggling `Add shared destination` on reveals a summary row with a `Pick…` button; tapping `Pick…` presents `AddDestinationSheet` reused from the single-destination-ui plan. After committing a destination, per-row `Routes to shared` checkboxes appear in the tracks table, default all-checked. Pressing `Create Group` closes the modal, opens the Track workspace, and leaves the project with (a) the expected set of drum tracks owned by the new group, (b) their clip-pool entries seeded or empty per the toggle, (c) `sharedDestination` set on the group, (d) each member's `destination` either `.inheritGroup` (checked rows) or the today's per-voice default (unchecked rows). Pressing `Cancel` closes the modal with no project mutation. The old `Menu("Add Drum Kit")` control is gone from the Tracks action bar.

## Non-goals

- Editing an existing drum group through this modal. Create-only surface.
- Reordering members inside the modal, editing seed patterns inline, or editing MIDI notes per row. Users configure those afterwards on the individual track page.
- Changing `Destination`, `ClipPoolEntry`, or `TrackGroup` on the wire. All additions are additive at call sites only; existing documents decode unchanged.
- Introducing a new `TrackType` or new `DrumKitPreset` cases. Presets come from `DrumKitPreset.allCases` as today.
- Data migration. `addDrumKit(_:library:)` keeps its signature and call-site compatibility so code outside this plan does not need to change.
- Keyboard shortcuts, undo granularity beyond SwiftUI's document-based default, slice-track drum kits (modal creates `.monoMelodic` tracks only, matching today's behavior).
- Changing how `DrumKitNoteMap` resolves MIDI notes for drum voices at engine time.

## Principle

The existing `Menu("Add Drum Kit")` commits a group in one click — the user cannot inspect what they are about to get, cannot choose to skip seeded patterns, and cannot configure shared routing at creation time. The resulting group always has `sharedDestination = nil`, forcing the user to reopen the group afterwards to set routing. The modal makes the implicit choices explicit at the point where the user already has them in mind.

Making the same flow work for a user-defined "blank" starter set (kick / snare / hat / clap) is the smallest generalisation of today's preset-only path and matches the mental model the user already has: "I want a group of drum tracks, these names, optionally sharing a destination."

The data model already encodes everything needed. `TrackGroup` has `sharedDestination`. `Destination` has `.inheritGroup`. `ClipPoolEntry` has `.stepSequence(stepPattern:pitches:)` which accepts an all-false pattern for empty clips. No new types are required for storage; only one new value type describes the in-flight plan.

## Architecture

Two new files, one rewritten function, one UI wiring change, one sheet sub-component.

### 1. `DrumGroupPlan` — in-flight description of the group to build

`Sources/Document/DrumGroupPlan.swift`, new file. A pure value type that describes what `addDrumGroup(plan:)` should materialise. Not Codable; never persisted.

```swift
struct DrumGroupPlan: Equatable {
    struct Member: Equatable {
        var tag: VoiceTag
        var trackName: String
        var seedPattern: [Bool]         // 16 bools; all-false for blank
        var routesToShared: Bool        // honored only when plan.sharedDestination != nil
    }
    var name: String                    // e.g. "808 Kit" or "Drum Group"
    var color: String                   // matches TrackGroup.color hex
    var members: [Member]
    var prepopulateClips: Bool          // if false, clip content is all-false stepSequence
    var sharedDestination: Destination? // nil → no shared destination; members use per-voice defaults
}
```

A `DrumGroupPlan.blankDefault` static factory returns the `kick / snare / hat-closed / clap` starter set with empty seed patterns, `prepopulateClips = false` (no clips to prepopulate in Blank), `sharedDestination = nil`, `name = "Drum Group"`, `color = "#8AA"` (matching today's `TrackGroup` default), all `routesToShared = true` (harmless until a destination is set).

A `DrumGroupPlan.templated(from: DrumKitPreset)` static factory reads the preset's `members`, sets `prepopulateClips = true` by default, inherits `name` and `color` from the preset, and sets `routesToShared = true` on each member.

### 2. `Project.addDrumGroup(plan:library:)` — generalised creation function

`Sources/Document/Project+DrumGroups.swift`, new file. This is today's `addDrumKit` lifted to take an explicit `DrumGroupPlan`. Pseudocode (actual Swift lives in the implementation plan):

```
1. Return nil if plan.members is empty.
2. Allocate groupID = UUID().
3. For each member in plan.members:
   a. Compute destination:
      - If plan.sharedDestination != nil && member.routesToShared → .inheritGroup
      - Else → defaultForTag(member.tag, library:), which performs the existing
        AudioSampleCategory(voiceTag:)→library.firstSample(in:) lookup and falls back
        to .internalSampler(bankID: .drumKitDefault, preset: plan.name).
   b. Build a StepSequenceTrack with trackType .monoMelodic, name = member.trackName,
      pitches [DrumKitNoteMap.baselineNote], stepPattern =
         plan.prepopulateClips ? member.seedPattern : Array(repeating: false, count: 16),
      destination above, groupID above.
   c. Build a ClipPoolEntry with .stepSequence(stepPattern: <same as track>,
      pitches: [DrumKitNoteMap.baselineNote]).
   d. Append the track's TrackPatternBank.default(for:initialClipID:).
4. Append tracks / clip pool entries / pattern banks / the new TrackGroup with
   sharedDestination: plan.sharedDestination to the project.
5. Set selectedTrackID to newTracks.first?.id and call syncPhrasesWithTracks().
6. Return the groupID.
```

A private helper `Project.defaultDestination(forVoiceTag:library:)` encapsulates today's inline destination-from-voice-tag logic so both `addDrumGroup` and the existing `addDrumKit` shim use the same resolver.

### 3. `Project.addDrumKit(_:library:)` becomes a shim

Rewritten to compose a `DrumGroupPlan.templated(from:)` and call `addDrumGroup(plan:library:)`. Same signature, same return type, same observable behavior (drum-kit members get per-voice destinations, `sharedDestination = nil`, seed patterns prepopulated). Preserved so existing callers and tests require no changes.

### 4. `AddDrumGroupSheet` — the modal

`Sources/UI/DrumGroup/AddDrumGroupSheet.swift`, new file.

**Signature:**

```swift
struct AddDrumGroupSheet: View {
    let auInstruments: [AudioInstrumentChoice]
    let onCreate: (DrumGroupPlan) -> Void
    let onCancel: () -> Void
}
```

The sheet owns the `DrumGroupPlan` as `@State` and mutates it locally. It reads no `document` or `Project` directly — the caller (`TracksMatrixView`) owns the commit by calling `document.project.addDrumGroup(plan:)` inside `onCreate`.

**Layout** (single ScrollView, `minWidth: 640`, `minHeight: 560`):

- **Header:** "Add Drum Group" title + subtitle.
- **Template segmented control:** `[Blank | Templated]`.
  - When `Templated`, a preset `Picker` appears to the right bound to a local `@State var selectedPreset: DrumKitPreset = .kit808`. Changing the preset replaces `plan.members`, `plan.name`, and `plan.color` (prepopulate toggle and shared-destination state are preserved across switches).
  - Switching back to Blank restores the blank defaults.
- **Tracks table** (a `StudioPanel` titled "Tracks"):
  - One row per `plan.members` entry, listing the track name.
  - **Blank mode:** each row has an editable `TextField` for name and a `[–]` remove button. Footer has `+ Add track` which appends a row with a default tag (`"kick"`), a placeholder name (`Track <n>`), and an empty seed pattern.
  - **Templated mode:** rows are read-only text.
  - **Per-row `Routes to shared` checkbox:** appears in each row only when `plan.sharedDestination != nil`. Default all-checked (because `DrumGroupPlan.Member.routesToShared` defaults to `true`).
- **Options panel** (a `StudioPanel` titled "Options"):
  - Templated-only toggle: `Prepopulate step patterns` bound to `plan.prepopulateClips`.
  - Toggle: `Add shared destination`.
    - Off → `plan.sharedDestination = nil`; per-row checkboxes hidden.
    - On → immediately presents the nested `AddDestinationSheet` to force a pick:
      - If the nested sheet commits a `Destination`, it is stored in `plan.sharedDestination` and the toggle stays on. Per-row checkboxes become visible, default all-checked. A summary row (using `DestinationSummary` from the single-destination-ui plan) appears alongside a `Pick…` button to re-pick.
      - If the nested sheet is cancelled, the toggle flips back off and `plan.sharedDestination` remains `nil`. No checkboxes appear.
    - Toggling `Add shared destination` off clears `plan.sharedDestination` back to `nil`.
    - Tapping `Pick…` after a destination is set re-presents the nested sheet; commit replaces the destination, cancel leaves the current value alone.
- **Footer:** `Cancel` and `Create Group` buttons. `Create Group` is disabled when `plan.members.isEmpty`.

Pressing `Create Group` calls `onCreate(plan)` and dismisses. `Cancel` calls `onCancel` and dismisses.

### 5. `TracksMatrixView` wiring

Replace the `Menu("Add Drum Kit") { … }` block at `Sources/UI/TracksMatrixView.swift:90–97` with:

```swift
Button("Add Drum Group") { isPresentingAddDrumGroup = true }
    .buttonStyle(.bordered)
```

Add `@State private var isPresentingAddDrumGroup = false` and a `.sheet(isPresented: $isPresentingAddDrumGroup)` presenting `AddDrumGroupSheet`. Inside its `onCreate`:

```swift
_ = document.project.addDrumGroup(plan: plan)
isPresentingAddDrumGroup = false
onOpenTrack()
```

`onCancel` just flips `isPresentingAddDrumGroup = false`.

## Data flow

1. `TracksMatrixView` renders the action bar with the new `Add Drum Group` button.
2. User taps the button → `.sheet(isPresented:)` presents `AddDrumGroupSheet`.
3. Sheet opens with `DrumGroupPlan.blankDefault` as initial state.
4. User interacts with form controls, which mutate the sheet's `@State plan: DrumGroupPlan` in-place.
5. If the user taps `Pick…` to choose a shared destination, the sheet presents a nested `AddDestinationSheet` with `isInGroup: false` (the group itself doesn't inherit) and the ambient `engineController.availableAudioInstruments`. Commit updates `plan.sharedDestination`; cancel is a no-op.
6. User taps `Create Group` → sheet calls `onCreate(plan)` → caller invokes `document.project.addDrumGroup(plan: plan)` which mutates the project as described above.
7. SwiftUI re-renders `TracksMatrixView`; the new group and its member tracks appear in the matrix. The caller also calls `onOpenTrack()` to navigate to the Track workspace for the first new member (matches today's post-`addDrumKit` behavior).

No observable state, engine-apply cycle, or threading model changes. `EngineController.apply(documentModel:)` observes the mutation on its next tick via the existing `@Binding`-driven re-render.

## Error handling

- **Empty Blank track list:** `Create Group` disabled; can't commit an empty group.
- **Duplicate track names in Blank:** allowed. Track IDs are UUIDs; name collisions are cosmetic and already possible today.
- **Shared destination picker cancelled on first open** (user flipped the toggle on but cancelled): the toggle flips back off; `plan.sharedDestination` stays `nil`; no checkboxes appear. The outer modal remains open.
- **Shared destination picker cancelled on re-pick** (user tapped `Pick…` while a destination was already set, then cancelled): `plan.sharedDestination` stays at its current value; nested sheet dismisses.
- **User picks a shared destination, then toggles `Add shared destination` off:** `plan.sharedDestination` is set back to `nil`. Checkboxes disappear. Re-enabling the toggle re-opens the nested sheet — a fresh commit is required to avoid a stale destination surviving a deliberate off/on cycle.
- **Library empty when computing per-voice defaults for unchecked rows:** the existing `.internalSampler(bankID: .drumKitDefault, preset: plan.name)` fallback applies. No new handling needed.
- **User selects Templated, picks `808 Kit`, switches back to Blank:** sheet state resets `plan.members` / `plan.name` / `plan.color` to the blank defaults; the `prepopulateClips` and shared-destination state are preserved (they remain meaningful in both modes).
- **`single-destination-ui` plan not yet landed:** this plan blocks on it for `AddDestinationSheet` and `DestinationSummary`. Stated in the Scope section; plan sequencing enforced by `Depends on`.

## Testing

### Unit tests (Document layer)

`Tests/SequencerAITests/Document/ProjectAddDrumGroupTests.swift` — new file, pure value-level:

- `addDrumGroup(plan: .blankDefault)` → project has 4 new tracks named `Kick`, `Snare`, `Hat`, `Clap`; one new group with `sharedDestination == nil`; each track has a per-voice destination (`.sample` if library has the category, else `.internalSampler` fallback); each track has a clip pool entry; all clip step patterns are all-false.
- `addDrumGroup(plan: .templated(from: .kit808))` → same 4 members as today's `addDrumKit(.kit808)`; seeded patterns match `DrumKitPreset.kit808.members`; group `sharedDestination == nil`.
- Same as above but with `plan.prepopulateClips = false` → tracks have all-false seed patterns; clips have all-false step patterns; other fields unchanged.
- Same as above but with `plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)` and every member `routesToShared = true` → every new track's destination is `.inheritGroup`; group `sharedDestination` matches the plan.
- Mixed routing: half of members have `routesToShared = true`, half `false`, with a shared destination set → checked members get `.inheritGroup`; unchecked members get a per-voice default; group `sharedDestination` matches the plan.
- `addDrumGroup(plan: …)` where `members.isEmpty` → returns `nil`; project unchanged.

`Tests/SequencerAITests/Document/ProjectAddDrumKitShimTests.swift` — new file, regression:

- `addDrumKit(.kit808)` (and each other case of `DrumKitPreset.allCases`) still produces the same tracks / clips / group shape as before, proving the shim preserves behavior.

`Tests/SequencerAITests/Document/DrumGroupPlanFactoryTests.swift` — new file:

- `.blankDefault.members` has the expected tag / name / empty-pattern shape.
- `.templated(from: .kit808)` mirrors `DrumKitPreset.kit808.members` and carries `prepopulateClips = true`, `sharedDestination = nil`.

### UI (manual smoke)

No automated UI harness today. Verify manually:

1. Open a fresh project → Tracks action bar shows `Add Mono`, `Add Poly`, `Add Slice`, `Add Drum Group`. No `Menu`.
2. Tap `Add Drum Group`. Modal opens, segmented control set to `Blank`, four editable rows (`kick`, `snare`, `hat-closed`, `clap`), `Add shared destination` off, `Create Group` enabled.
3. Rename a row, remove a row, tap `+ Add track`. The tracks table updates.
4. Tap `Cancel`. Modal closes; project unchanged.
5. Reopen; switch to `Templated`, preset `808 Kit`. Rows become read-only: `Kick, Snare, Hat, Clap`. `Prepopulate step patterns` toggle visible and on.
6. Toggle `Add shared destination` on. A destination summary row and `Pick…` button appear. Per-row `Routes to shared` checkboxes appear, all checked.
7. Tap `Pick…`. The nested `AddDestinationSheet` presents with no `Inherit Group` option (`isInGroup: false`). Pick `Virtual MIDI Out`. Nested sheet closes; summary row updates to show `MIDI · SequencerAI Out · ch 1`.
8. Uncheck `Routes to shared` on two of the four rows.
9. Tap `Create Group`. Modal closes. Tracks matrix shows a new `808 Kit` group with `Kick, Snare, Hat, Clap` members. Inspect per-track destinations: two are `.inheritGroup`, two are their per-voice defaults. Group's `sharedDestination` is `.midi(…)`.
10. Open Track workspace for a `Kick` with `routesToShared = true`: its Output panel (post-single-destination-ui) shows `Inherit Group` summary. For an unchecked one: shows `Sampler` or `Internal Sampler` summary.

### Visual regression guard

Before/after screenshots of the Tracks action bar and matrix. The only expected delta in the action bar is `Add Drum Kit` Menu → `Add Drum Group` Button. The first-created group under the old flow and the default-blank group under the new flow should look structurally identical (four tracks, color, default destinations) — confirmed by manual comparison.

## Scope

Single plan, ~6 new or modified files:

- `Sources/Document/DrumGroupPlan.swift` — new
- `Sources/Document/Project+DrumGroups.swift` — new (contains `addDrumGroup(plan:library:)` and `defaultDestination(forVoiceTag:library:)` helper)
- `Sources/Document/Project+Tracks.swift` — modified: `addDrumKit(_:library:)` rewritten to compose a plan and call `addDrumGroup`
- `Sources/UI/DrumGroup/AddDrumGroupSheet.swift` — new
- `Sources/UI/TracksMatrixView.swift` — modified: button + sheet wiring
- Tests — three new files under `Tests/SequencerAITests/Document/` plus no new UI tests

No spec decomposition needed.

## Decisions taken

- **Blank defaults are `kick, snare, hat-closed, clap`.** Matches the user's intent ("kick, snare, hihat etc.") and the common denominator of the existing presets.
- **Blank mode's rows are fully editable (rename, remove, `+ Add track`).** Templated-mode rows are read-only preview.
- **Shared destination is picked inline via the existing `AddDestinationSheet`** from the single-destination-ui plan. No duplicate widget.
- **Per-row `Routes to shared` defaults to checked.** When the user sets a shared destination, the most probable intent is "all members route to it". Users can opt individual members out, which falls back to the per-voice default (today's `addDrumKit` behavior).
- **No shared destination chosen → every member gets today's per-voice default.** Matches current `addDrumKit(…)` behavior exactly.
- **`addDrumKit` preserved as a shim** that composes a `DrumGroupPlan.templated(from:)` and calls `addDrumGroup(plan:)`. Keeps the signature and observable behavior for any caller outside this plan.
- **`prepopulateClips` applies to templated groups only.** Blank groups always produce empty clips; the toggle is hidden in Blank mode (toggling would have no effect).
- **No validation of track name uniqueness.** UUIDs carry identity; name collisions are cosmetic and already possible.
- **Nested sheet (not inline destination editor).** Matches the single-destination-ui UX; keeps the modal body under control.
- **Slice drum kits remain unsupported.** Today's `addDrumKit` creates only `.monoMelodic` tracks and this plan does not change that.
- **No keyboard shortcuts.** Not in scope.
