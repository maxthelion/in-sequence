---
feature: modifier-chain-placement
created: 2026-05-03
---

# Modifier Chain Placement Plan

## Status

PM plan — implementation handoff still required. No production code has been
written.

---

## Overview

Modifier Chain Placement is a selected-slot source-editor refactor. It keeps the
existing `SourceRef` document shape and engine playback contract, but replaces
the current bank-level source-switching UI with slot-well controls that operate
on the currently selected pattern slot only.

The build should be split into three phases:

1. **Phase 0** verifies live-code assumptions before editing.
2. **Phase 1** adds the slot-scoped document mutations and regression tests.
3. **Phase 2** replaces the current `TrackSourceEditorView` flows with the
   approved source/modifier slot wells and contained pickers.

No persistence migration is expected. No engine architecture change is expected.
The plan assumes `SourceRef` remains canonical and that an empty source
continues to be represented as `.clip` with `clipID == nil`.

---

## Phase 0 — Pre-Build Verification

Phase 0 is read-only. Its purpose is to confirm the spec's assumptions against
the current codebase so the implementer does not discover a hidden dependency
mid-build.

### 0-A. Confirm the current editor seams

**What it is.** Verify the exact structure of
`Sources/UI/TrackSource/TrackSourceEditorView.swift` before refactoring it.

**Files to read.**

- `Sources/UI/TrackSource/TrackSourceEditorView.swift`
- `Sources/UI/TrackSource/TrackPatternSlotPalette.swift`
- `Sources/UI/TrackSource/GeneratorAttachmentControl.swift`

**Checks.**

1. Confirm `sourceTab`, `modifiersTab`, and the private
   `GeneratorSelectionSheet` are still the current source/modifier entry points.
2. Confirm whether `TrackSourceEditorView` already has a natural extraction seam
   for slot-well subviews or whether the new views should be introduced as new
   files under `Sources/UI/TrackSource/`.
3. Confirm how the pattern-slot palette currently communicates source type and
   bypass state so the new source/modifier badges do not duplicate or fight the
   existing slot affordances.

**Acceptance signals.**

- The implementer can name the concrete call sites that will be removed or
  replaced.
- The implementer knows whether to refactor in place or extract focused subviews
  first.

### 0-B. Confirm current source mutation side effects

**What it is.** Validate the behavior of the current document helpers so the new
slot-scoped flow does not accidentally reuse bank-wide mutation paths.

**Files to read.**

- `Sources/Document/Project+TrackSources.swift`
- Any tests covering `attachNewGenerator`, `removeAttachedGenerator`,
  `switchAttachedGenerator`, `setPatternSourceRef`, `setPatternClipID`, and
  modifier writes

**Checks.**

1. Confirm `attachNewGenerator`, `removeAttachedGenerator`, and
   `switchAttachedGenerator` still rewrite every slot in the bank.
2. Confirm `ensureClipForCurrentPattern(trackID:)` auto-creates a blank clip and
   therefore cannot be the remove-source path for the new empty-source state.
3. Confirm where `attachedGeneratorID` still matters so compatibility writes can
   be contained without silently fanning source changes across sibling slots.

**Acceptance signals.**

- The implementer can state which helpers remain legacy-only and which new
  helpers are required for the slot-well UI.
- Any remaining `attachedGeneratorID` dependency is identified before coding
  starts.

### 0-C. Confirm existing picker and test coverage gaps

**What it is.** Verify what already exists for clip/generator selection and what
test harnesses are available.

**Files to read.**

- `Sources/UI/TrackSource/**`
- `Tests/**` covering `Project+TrackSources`, `TrackSourceEditorView`, or source
  editing flows

**Checks.**

1. Confirm there is still no clip-pool picker in the current UI.
2. Confirm whether the existing generator sheet can be adapted or whether the
   new source/modifier picker structure should replace it entirely.
3. Confirm the test files that should absorb new slot-scoped source and modifier
   regression coverage.

**Acceptance signals.**

- The implementer knows whether picker work starts from adaptation or
  replacement.
- The implementer has named the exact test files to extend or the new focused
  test files to add.

---

## Phase 1 — Slot-Scoped Document Mutations

Phase 1 introduces the data-layer support the new UI needs. The UI should not
compose `SourceRef` writes ad hoc inside SwiftUI closures when the document
layer can express the operation directly.

### 1-A. Add explicit selected-slot source helpers

**What it is.** Introduce slot-scoped source operations in
`Sources/Document/Project+TrackSources.swift` so the UI can express the spec's
actions directly.

**Required behaviors.**

1. Remove a clip source by setting the selected slot to explicit empty clip
   state (`mode == .clip`, `clipID == nil`) without auto-creating a
   replacement clip.
2. Create a blank clip for one selected slot only when the user explicitly
   chooses `New Blank Clip`.
3. Assign an existing compatible clip to one selected slot only.
4. Create a blank generator of the default compatible kind for the current
   track type and assign it to one selected slot only.
5. Assign an existing compatible generator to one selected slot only.

**Guardrails.**

- Preserve `modifierGeneratorID` and `modifierBypassed` when removing or
  swapping the source unless the action explicitly targets the modifier.
- Do not call bank-wide helpers for the slot-well flow.
- Do not create a clip as a side effect of removing a generator or adding a
  modifier.

**Acceptance signals.**

- Every source action can be performed against an explicit `trackID` and
  `slotIndex`.
- No selected-slot source operation rewrites sibling slots in the same bank.

### 1-B. Add slot-scoped modifier attachment helpers as needed

**What it is.** Keep modifier changes symmetrical with source changes without
inventing source material.

**Required behaviors.**

1. `New Blank Modifier` creates one compatible modifier generator and attaches
   it to the selected slot only.
2. `Select Modifier From Pool` assigns an existing compatible modifier to the
   selected slot only.
3. `Remove Modifier` clears `modifierGeneratorID` and resets bypass to `false`
   on the selected slot only.
4. Modifier changes on an empty source slot leave the source empty.

If the existing `setPatternModifierGeneratorID` and
`setPatternModifierBypassed` helpers already satisfy these rules, Phase 1-B may
be a verification-plus-call-site task instead of a larger document rewrite.

**Acceptance signals.**

- Modifier attach/remove/bypass behavior is explicit and selected-slot-only.
- The modifier path never calls `ensureClipForCurrentPattern(trackID:)`.

### 1-C. Add document-layer regression tests

**What it is.** Lock the slot-scoped rules down before the view refactor lands.

**Tests to add.**

1. Removing a clip source leaves the selected slot in `.clip` mode with
   `clipID == nil` and does not change sibling slots.
2. Creating a blank generator updates only the selected slot and does not fan
   out through legacy bank helpers.
3. Selecting a clip or generator from pool updates only the selected slot.
4. Adding or removing a modifier does not create a clip implicitly.
5. Removing a modifier clears bypass state back to `false`.

**Acceptance signals.**

- The new tests fail on any bank-wide fan-out regression.
- The new tests prove that explicit empty source state is stable and persisted
  through normal `SourceRef` writes.

---

## Phase 2 — Source/Modifier Slot-Well UI

Phase 2 replaces the current source/modifier interaction surface inside
`TrackSourceEditorView` while staying within `Sources/UI/TrackSource/`.

### 2-A. Extract the slot-well surface from `TrackSourceEditorView`

**What it is.** Refactor the current view into smaller pieces before wiring the
new flow.

**Expected structure.**

- Persistent two-tab state surface: `Source` and `Modifier`
- Focused source well subview
- Focused modifier well subview
- Contained picker views for source and modifier choices

New focused files under `Sources/UI/TrackSource/` are preferred over growing
`TrackSourceEditorView.swift` further.

**Acceptance signals.**

- The top-level editor remains readable.
- Source well, modifier well, and picker logic each have a clear ownership
  boundary.

### 2-B. Implement source-well occupied and empty states

**What it is.** Replace the current "Switch To Generator Source" flow with the
approved slot-well interaction model.

**Required behaviors.**

1. Occupied clip source shows clip identity plus change/remove actions.
2. Occupied generator source shows generator identity plus change/remove
   actions.
3. Empty source shows an `Empty` badge, explanatory copy, and a prominent
   `[+] Add Source` action.
4. No inline clip editor is shown when the source is empty.

**Acceptance signals.**

- Removing a source leaves the user in an explicit empty slot state.
- The current "Switch To Generator Source" copy path is gone.

### 2-C. Implement the contained source picker

**What it is.** Build the grouped source picker required by the spec.

**Required behaviors.**

1. First level groups actions by source type:
   - `New Blank Generator`
   - `Select Generator From Pool`
   - `New Blank Clip`
   - `Select Clip From Pool`
2. `New Blank Generator` is the visually primary action.
3. Pool browsing is second-level disclosure inside the same track-view context,
   not a workspace switch.
4. Cancel leaves the slot in its prior state.
5. Empty pool branches show explicit recovery text rather than a blank list.

**Acceptance signals.**

- The fastest clip-to-generator path is remove -> add source -> new blank
  generator.
- The user never leaves the track editor to browse compatible clips or
  generators.

### 2-D. Implement the modifier well and unsupported-state behavior

**What it is.** Make modifier editing use the same shell while respecting
modifier-specific compatibility rules.

**Required behaviors.**

1. Supported empty modifier state shows `Empty` plus `[+] Add Modifier`.
2. Occupied modifier state shows modifier identity, bypass state, change, and
   remove actions.
3. Unsupported track types show an explicit unavailable state instead of hiding
   the well.
4. Modifier pool branches filter through
   `compatibleModifierGenerators(for:)` / `supportsModifierStage`.

**Acceptance signals.**

- Source and modifier wells read as one coherent interaction family.
- Unsupported modifier tracks are understandable at a glance.

### 2-E. Add UI-focused regression coverage

**What it is.** Cover the highest-risk interaction rules with focused tests at
the lightest practical level the project supports.

**Minimum coverage.**

1. Source tab badge reflects clip, generator, and empty states.
2. Modifier tab badge reflects modifier-present, bypassed, and empty states.
3. Removing a source exposes the empty-state add action.
4. Cancelling a picker from an empty slot leaves the slot empty.
5. A modifier action on an empty source slot does not reveal a fake clip-backed
   editing state.

If the project does not currently support reliable SwiftUI interaction tests for
these flows, capture the gap explicitly and rely on the new document tests plus
manual smoke verification in the implementation handoff.

---

## Build Gate Before Handoff

Before the feature is marked ready for implementation handoff, the build team
should confirm:

- [ ] Selected-slot source actions do not mutate sibling slots.
- [ ] Explicit empty source state is visible and stable.
- [ ] `New Blank Generator` is the primary recovery path from an empty source.
- [ ] Clip and generator pool branches stay in-context and show explicit empty
      states.
- [ ] Modifier add/remove/bypass stays slot-scoped and never creates a clip
      implicitly.
- [ ] Unsupported modifier tracks show an explicit unavailable state.
- [ ] No production code outside the document and `TrackSource` UI layers was
      touched unless Phase 0 proved it was required.

---

## Files and Modules Expected To Change

| File / area | Why |
|---|---|
| `Sources/Document/Project+TrackSources.swift` | Add or narrow slot-scoped source/mutation helpers |
| `Sources/UI/TrackSource/TrackSourceEditorView.swift` | Replace current source/modifier flow with slot-well structure |
| `Sources/UI/TrackSource/` new focused subviews | Source well, modifier well, picker views |
| `Tests/**` covering track-source document mutations | Slot-scoped source/modifier regression tests |
| `Tests/**` covering track-source UI state, if available | Badge / empty-state / picker-cancel coverage |

No engine-layer rewrite is expected. No persistence-schema change is expected.
No `docs/specs/**`, `docs/plans/**`, or wiki edits are part of this build plan.

---

## Expected Next PM Step

After this plan is accepted, the next PM-loop action should be
`write-implementation-handoff` for `docs/roadmap/modifier-chain-placement/`.
