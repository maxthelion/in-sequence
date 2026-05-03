---
feature: modifier-chain-placement
created: 2026-05-03
stories_covered: [1, 2, 3, 4, 5]
architecture_approved: true
architecture_review: architecture-review.md
selected_prototype: prototypes/modifier-chain-placement-slot-well.html
---

# Modifier Chain Placement — Spec

Sources: `user-stories.md`, `existing-state.md`, `ux-review.md` (accepted),
`prototype-approval.md` (approved), `architecture.md`, and
`architecture-review.md` (accepted).

---

## 1. Scope and Non-Goals

### In scope

- Replace the current source/modifier editing affordances in
  `TrackSourceEditorView` with a slot-well UI for the **selected pattern slot**
  only.
- Support three source-well states: clip occupied, generator occupied, and
  explicit empty source.
- Support three modifier-well states: modifier occupied, modifier empty, and
  modifier unavailable for track types that cannot host modifiers.
- Provide an in-context source picker that exposes the four source actions from
  [[story:2]] without navigating away from the track editor:
  - create new blank clip
  - select clip from pool
  - create new blank generator
  - select generator from pool
- Provide a matching modifier picker with modifier-specific options and empty
  states.
- Introduce or use slot-scoped document mutations so source/modifier changes act
  on one selected slot instead of the whole bank.
- Preserve the current engine contract: playback is still compiled from
  `TrackPatternSlot.sourceRef`.

### Explicitly out of scope

- Multiple modifier stages or a true modifier chain. This feature continues to
  expose the existing single post-source modifier slot only.
- Any "apply to all slots" source or modifier action.
- Cleanup of the broader track-source architecture beyond what is needed to
  support correct selected-slot editing.
- A general-purpose library workspace or full browser redesign.
- Changes to document serialization shape beyond using the already-supported
  `mode == .clip` and `clipID == nil` empty-source state.

---

## 2. Resolved Product Decisions

### 2.1 Remove reveals an explicit empty state

Removing the current source does **not** auto-open the picker.

After removing a clip or generator source, the source well stays in place and
renders an explicit empty state with a prominent `[+] Add Source` action. This
is the chosen behavior because it keeps the empty state legible, preserves the
progressive-disclosure requirement from `prototype-approval.md`, and makes
cancel behavior obvious: if the picker is opened and then cancelled, the slot
remains empty.

### 2.2 The picker groups by source type, not by one flat list of pool items

Opening the source picker reveals two grouped sections inside one contained
surface that remains within the current track view:

- **Generator**
  - `New Blank Generator`
  - `Select Generator From Pool`
- **Clip**
  - `New Blank Clip`
  - `Select Clip From Pool`

This satisfies [[story:2]]'s four distinct actions while keeping deeper pool
browsing on a second level. Only the high-level actions appear initially; pool
contents appear after the user chooses a pool action.

### 2.3 `New Blank Generator` is a fast-path default, not a generator-kind menu

The stories ask for a fast blank-generator path, not a new generator taxonomy
step. `New Blank Generator` therefore creates the default compatible source
generator for the track type:

- mono track -> `GeneratorKind.monoGenerator`
- poly track -> `GeneratorKind.polyGenerator`
- slice track -> `GeneratorKind.sliceGenerator`

If the project later introduces a need to choose among multiple blank generator
kinds at creation time, that becomes a separate roadmap item. `Select Generator
From Pool` remains the path for choosing other compatible generator kinds, such
as progression chords on poly tracks.

### 2.4 The modifier well follows the same shell, with modifier-specific rules

The modifier well uses the same visual pattern as the source well:

- occupied state with item summary + remove action
- empty state with an add action
- contained picker that stays inside the track editor

Its choices differ because modifiers are generator-only. The modifier picker
shows:

- `New Blank Modifier`
- `Select Modifier From Pool`

The implementation must filter modifier choices using
`GeneratorKind.supportsModifierStage`.

### 2.5 Unsupported modifier tracks use an explicit unavailable state

If a track type has **no** compatible modifier kinds at all, the modifier well
must not silently disappear and must not show a misleading enabled plus button.
Instead it renders an explicit unavailable empty state:

- label: `Modifier`
- state text: `Modifiers are unavailable for this track type`
- disabled primary affordance or informational badge, not a hidden control

For track types that do support modifiers but currently have zero compatible
pool entries, the well stays addable because `New Blank Modifier` remains a
valid action.

---

## 3. Data Model and Mutation Contract

### 3.1 Selected-slot truth only

Every source or modifier action in this feature targets the currently selected
`TrackPatternSlot` only. The slot well never rewrites every slot in the bank as
a side effect.

This applies to:

- removing a clip source
- removing a generator source
- creating a blank clip
- choosing a clip from pool
- creating a blank generator
- choosing a generator from pool
- adding, changing, bypassing, or removing a modifier

### 3.2 `SourceRef` remains canonical

The UI is a view over `TrackPatternSlot.sourceRef`. It must not introduce a
second source-of-truth object for:

- source mode
- source clip ID
- source generator ID
- modifier generator ID
- modifier bypass state

The source and modifier wells may hold transient presentation state, but every
musical edit is expressed back into `SourceRef`.

### 3.3 Empty source representation

An empty source slot uses the existing persisted shape:

- `mode == .clip`
- `clipID == nil`

The remove-source action must not auto-create a replacement clip. The slot is
deliberately empty until the user chooses a new source path.

### 3.4 Modifier attachment does not create source material

Adding or changing a modifier must not create a clip or generator source
implicitly. A slot may therefore be:

- empty source + no modifier
- empty source + modifier attached
- clip source + optional modifier
- generator source + optional modifier

If the source is empty, playback remains silent; the modifier is simply waiting
for source material to exist later.

### 3.5 Required mutation semantics

The implementation must provide slot-scoped operations with the following
behavior, whether by introducing new helpers or narrowing existing ones:

| Operation | Required behavior |
|---|---|
| Remove source | For clip mode: set selected slot to explicit empty clip state. For generator mode: clear generator source for the selected slot only; do not fan out to sibling slots. Preserve modifier state. |
| New blank clip | Create one new compatible clip pool entry, assign it to the selected slot, and close the picker. |
| Select clip from pool | Assign an existing compatible clip to the selected slot and close the picker. |
| New blank generator | Create one new compatible generator pool entry of the default kind for the track type, assign it to the selected slot, and close the picker. |
| Select generator from pool | Assign an existing compatible generator to the selected slot and close the picker. |
| New blank modifier | Create one new compatible modifier generator pool entry and attach it to the selected slot only. |
| Select modifier from pool | Assign an existing compatible modifier generator to the selected slot only. |
| Remove modifier | Clear `modifierGeneratorID` on the selected slot and reset `modifierBypassed` to false. |
| Toggle bypass | Flip `modifierBypassed` on the selected slot only. |

### 3.6 Legacy bank-level helpers are not the slot-well implementation path

The slot-well feature must not rely on `attachNewGenerator`,
`removeAttachedGenerator`, or `switchAttachedGenerator` for selected-slot
editing. Those helpers rewrite every slot in a bank and do not match the
approved responsibility boundary.

If implementation must still touch `attachedGeneratorID` for compatibility with
legacy paths, that write is a compatibility detail only. It must not cause
other slots to change and must not become the UI's source of truth.

---

## 4. UI Behavior

### 4.1 Persistent slot tabs

The track editor keeps a persistent two-tab surface:

- `Source`
- `Modifier`

Both tabs remain visible at all times and each tab shows a compact state badge
without requiring the user to open it:

- source badge: `Clip`, `Gen`, or `Empty`
- modifier badge: `Mod`, `Byp`, or `Empty`

The tab bar is a state summary, not just a navigation control.

### 4.2 Source well states

#### Occupied clip source

The source well shows:

- a `Clip` badge
- clip name
- compact clip metadata if available (for example bars or type)
- primary change action
- remove action

The current "Switch To Generator Source" button is removed.

#### Occupied generator source

The source well shows:

- a `Gen` badge
- generator name
- generator kind label
- primary change action
- remove action

#### Empty source

The source well shows:

- an `Empty` badge
- short explanatory text such as `No source selected`
- a prominent `[+] Add Source` action

No inline clip editor is shown when the source is empty.

### 4.3 Source picker flow

Selecting `[+] Add Source` or the source well's change action opens a contained
picker within the same track view. It may be an inline expansion, popover, or
sheet, but it must not navigate to a different workspace.

The first level of the picker shows two grouped sections in this order:

1. **Generator**
   - `New Blank Generator` (primary visual emphasis)
   - `Select Generator From Pool`
2. **Clip**
   - `New Blank Clip`
   - `Select Clip From Pool`

Behavior rules:

- Choosing either `New Blank ...` action performs the creation immediately,
  updates the selected slot, and closes the picker.
- Choosing either `Select ... From Pool` action expands or presents a second
  level containing compatible entries only.
- Selecting a pool entry updates the selected slot and closes the picker.
- Cancelling the picker leaves the slot in its prior state. If the slot was
  empty before opening, it stays empty after cancel.

### 4.4 Source picker empty states

Pool branches must never fail by omission. If the user opens a pool branch and
there are no compatible entries:

- the branch shows explicit empty-state text
- the empty state explains why the list is empty
- the sibling `New Blank ...` action remains visible or recoverable without
  closing the picker

Examples:

- `Select Clip From Pool` with no compatible clips:
  `No compatible clips in this project yet. Create a blank clip or return.`
- `Select Generator From Pool` with no compatible generators:
  `No compatible generators in this project yet. Create a blank generator or return.`

### 4.5 Modifier well states

#### Occupied modifier

The modifier well shows:

- a `Mod` badge
- modifier generator name
- modifier kind label
- bypass pill or toggle
- primary change action
- remove action

If bypass is enabled, the badge may read `Byp` or the pill may indicate the
state; in either case the bypass state must be visible at a glance.

#### Empty modifier on supported track types

The modifier well shows:

- an `Empty` badge
- short explanatory text
- a prominent `[+] Add Modifier` action

#### Modifier unavailable for this track type

The modifier well shows the unavailable state described in Section 2.5 instead
of hiding the well entirely.

### 4.6 Modifier picker flow

On supported track types, `[+] Add Modifier` or the change action opens a
contained picker that stays within the track editor.

First level:

1. `New Blank Modifier`
2. `Select Modifier From Pool`

Behavior rules:

- `New Blank Modifier` creates the default compatible modifier generator for the
  track type and attaches it to the selected slot only.
- `Select Modifier From Pool` reveals only compatible pool entries where
  `supportsModifierStage == true`.
- Choosing a modifier does not change the current source selection.
- Cancelling the picker leaves the modifier state unchanged.

### 4.7 Empty modifier-pool behavior

If the track type supports modifiers but the project currently has no compatible
modifier pool entries, `Select Modifier From Pool` opens an explicit empty
state rather than a blank list.

`New Blank Modifier` remains available in that case.

---

## 5. Visual and Interaction Requirements

### 5.1 Progressive disclosure

The default track editor view must show only:

- the current source summary
- the current modifier summary
- the primary add/change/remove actions

It must not show full clip lists, generator lists, or modifier lists until the
user opens the relevant picker branch.

### 5.2 Tap budget

The fastest clip-to-generator swap path for [[story:5]] is:

1. remove current clip source
2. tap `[+] Add Source`
3. tap `New Blank Generator`

This is the intended maximum for the most common path: **three interactions**
within the same track view.

If the user chooses an existing generator from pool instead, the pool-selection
step may add one more interaction inside the picker, but no screen navigation is
allowed.

### 5.3 Source and modifier legibility

Without entering a nested browser, the user must be able to tell:

- whether the selected slot currently uses a clip, generator, or no source
- whether a modifier exists
- whether the modifier is bypassed

The approved slot-well direction is specifically meant to solve this
at-a-glance problem; the implementation must preserve it.

---

## 6. Acceptance Criteria

### Story 1 — Remove clip source and replace with generator

- A clip-backed selected slot shows a remove action in the source well.
- Removing the clip changes only the selected slot and leaves the source well in
  an explicit empty state.
- The empty state exposes `[+] Add Source`.
- The user can create a blank generator from that state without leaving the
  track view.

### Story 2 — Four source actions in-context

- The source picker exposes all four high-level actions from [[story:2]] inside
  one contained UI surface.
- Pool browsing is a second-level disclosure inside that surface, not a
  workspace switch.
- Each pool branch has an explicit empty state when no compatible entries
  exist.

### Story 3 — At-a-glance source/modifier clarity

- The `Source` and `Modifier` tabs are both always visible.
- Each tab shows a current-state badge even when not selected.
- The user can distinguish clip source, generator source, empty source, modifier
  present, modifier bypassed, and modifier empty without opening a separate
  browser.

### Story 4 — Symmetrical modifier interaction model

- On supported track types, the modifier well uses the same occupied/empty shell
  as the source well.
- An empty supported modifier well exposes `[+] Add Modifier`.
- An occupied modifier well exposes change, bypass, and remove actions.
- Modifier changes affect only the selected slot and do not create source
  material implicitly.

### Story 5 — Fastest swap path stays in-budget

- Replacing a clip with a new blank generator takes no more than three
  interactions in the selected-slot UI.
- The swap path never requires leaving the track editor.
- `New Blank Generator` is the visually primary action in the source picker.

---

## 7. Open Questions

None.

The architecture review already resolved the product-level questions required to
write this spec. Any remaining uncertainty is implementation detail for the
later plan, not a blocker on the feature definition.
