---
feature: step-order
created: 2026-06-06
status: accepted-builder-facing
sources:
  - docs/roadmap/step-order/open-questions.md
  - docs/roadmap/step-order/notes.md
  - docs/roadmap/step-order/user-stories.md
  - docs/roadmap/step-order/existing-state.md
  - docs/roadmap/step-order/ux-review.md
  - docs/roadmap/step-order/prototypes/step-order-wireframe.html
---

# Step Order Accepted Architecture

This is accepted PM architecture for the next Step Order spec pass. It fixes
the builder-facing direction for v1 scope, map ownership, playback insertion,
toggle timing, persistence, UI obligations, and tests. It does not make the
lane ready for build promotion; spec, plan, and implementation handoff remain
downstream.

## V1 Shape

Step Order v1 is a phrase-scoped playback override:

1. A producer creates or edits a named 16-step map.
2. The map is assigned to the current phrase.
3. The performer enables the phrase's Step Order toggle.
4. At the next phrase boundary, playback resolves each output step through the
   map before reading the source step.
5. Disabling the toggle returns playback to sequential source-step resolution
   at the next phrase boundary.

The underlying clip, generator, pattern, and phrase-cell data is never rewritten
by Step Order playback. The map changes how existing material is read.

Accepted v1 defaults:

- maps are fixed-length 16-entry arrays;
- map values are source step indexes in `0...15`;
- maps live in a top-level named project pool;
- each phrase can assign at most one map;
- a phrase-level enabled flag controls whether the assigned map is active;
- per-track, project-wide, layer-level, variable-length, and stacked
  transformations are deferred.

## Product Basis

The accepted UX basis is `prototypes/step-order-wireframe.html`, with the
reviewed gaps resolved as follows:

- keep the two-row output-step/source-step editor;
- keep named persistent maps and the map list/picker;
- add an assignment path from the map picker and active-map control to the
  current phrase;
- show `Phrase` as the fixed v1 scope;
- hide or mark project, layer, and phrase/track scope as future rather than
  adjustable controls;
- show a concrete pending toggle state between request and phrase-boundary
  application;
- label identity maps as pass-through/no remap.

## Document Model

The document should gain a stable top-level map pool and phrase assignment
state. Local naming can follow project conventions, but the durable shape is:

```swift
struct StepOrderMap: Codable, Equatable, Identifiable, Sendable {
    var id: StepOrderMapID
    var name: String
    var values: [UInt8] // exactly 16, each value 0...15
}

struct StepOrderAssignment: Codable, Equatable, Sendable {
    var mapID: StepOrderMapID
    var isEnabled: Bool
}
```

`Project` or its document-root equivalent owns the map pool. `PhraseModel` owns
the optional `StepOrderAssignment` for that phrase.

Existing projects decode with an empty map pool and no phrase assignments.
Invalid saved maps should decode conservatively: missing maps disable their
assignments, wrong-length arrays are rejected or migrated to identity only if
the spec explicitly accepts that behavior, and out-of-range values are not
allowed into the compiled playback snapshot.

Changing a map, assigning a map, or changing the saved enabled state is normal
document editing and may mark the project dirty. Runtime pending toggle state
is not persisted.

## Snapshot Compilation

The compiler should resolve phrase assignments into engine-safe playback data
before the tick path runs.

Accepted compiled shape:

- `PhrasePlaybackBuffer` carries `stepOrderMap: [UInt8]?` or an equivalent
  immutable 16-entry value.
- `nil` means sequential playback.
- non-`nil` means the phrase has a valid assigned map and Step Order is enabled.

Compilation must not leave map-ID lookup, document traversal, or SwiftUI state
access on the tick path. Incremental snapshot compilation should invalidate the
affected phrase buffer when:

- the assigned map ID changes;
- the phrase enabled state changes;
- the assigned map's values change;
- the assigned map is deleted or becomes invalid.

If the implementation chooses to store compiled data on
`TrackPhrasePlaybackBuffer` instead, it must still preserve the accepted v1
semantics: phrase-level assignment, same active map for all playable tracks in
that phrase, and no per-track opt-in/out control in v1.

## Playback Resolution

Step Order applies after the output `stepInPhrase` is known and before the
source step is read for note/source playback. The accepted insertion area is
the `PlaybackSnapshot.resolvedStep` path identified in `existing-state.md` and
the accepted wireframe.

Conceptually:

```text
outputStep = stepInPhrase
sourceStep = phrase.stepOrderMap?[outputStep] ?? outputStep
resolvedStep = read source and pattern data at sourceStep
```

The output step remains the clock position. The source step is the step used to
read pattern/source material. This distinction keeps the feature
non-destructive and prevents the map from being treated as authored clip data.

For v1, phrase layer timing such as mute, fill, and macro lanes should remain
anchored to the output step unless the later spec intentionally expands Step
Order to remap those layers too. That keeps Step Order focused on source-step
playback and avoids surprising changes to performance automation.

## Toggle Timing And Pending State

Toggling Step Order during playback is deferred to the next phrase boundary.
Toggling while stopped can update the saved phrase enabled state immediately,
but the UI should still show the phrase's effective enabled value clearly.

Accepted runtime contract:

- UI command requests `enabled` or `disabled` for a phrase;
- engine/session stores a pending request when playback is running;
- current playback continues with the effective state until the phrase boundary;
- at the boundary, the pending state becomes effective;
- UI clears the pending badge when the engine/session publishes applied state.

The pending state is runtime-only. It should include the phrase ID, requested
enabled value, and enough effective/applied state for SwiftUI to render:

- Off;
- On;
- Pending On;
- Pending Off.

Do not require SwiftUI to infer pending state by polling `PlaybackSnapshot`
contents or comparing arrays. The spec can choose the exact command and
publication API, but the state transition must be observable and testable.

## UI Integration

The spec should build from the accepted prototype while closing its gaps:

- editor: two-row select-output then choose-source interaction, auto-advance,
  and visible wrap/end behavior;
- map picker: create, rename, edit, delete when unused, and show usage count;
- assignment: assign a selected named map to the current phrase;
- active-map control: open the picker or switch assigned maps from the editor;
- scope: fixed phrase-level label for v1;
- toggle: visible On/Off/Pending state with phrase-boundary language;
- identity state: label identity maps as pass-through/no remap;
- validation: 16 cells, values 0...15, no hidden modulo for invalid data.

The v1 UI should not expose editable per-track toggles. If future UX exposes
Phrase/Track scope, it needs a separate design and architecture update.

## Testing Requirements

The builder spec/plan should include coverage for:

- creating a named 16-step map and assigning it to a phrase;
- saving and loading the map pool and phrase assignment;
- rejecting or safely handling wrong-length and out-of-range map data;
- compiling an enabled assignment to a non-`nil` snapshot map;
- compiling disabled or missing assignments to sequential playback;
- playback resolving `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]` to the expected
  source steps without mutating clip data;
- disabling Step Order restoring sequential playback;
- toggling during playback entering pending state and applying at the next
  phrase boundary;
- toggling while stopped updating effective state without a pending boundary;
- map edits invalidating affected phrase buffers;
- deleting an assigned map being blocked or clearing assignment through an
  explicit accepted flow;
- phrase-layer timing remaining anchored to output steps for v1.

## Decisions Made

| ID | Decision |
|----|----------|
| A1 | V1 assignment scope is phrase-only: one assigned map per phrase, applied to all playable tracks in that phrase. |
| A2 | Maps live in a top-level named project pool; phrases store map ID plus enabled state. |
| A3 | Playback applies the map in the compiled snapshot/source-resolution path and does not mutate clips, generators, patterns, or phrase cells. |
| A4 | Toggle changes during playback apply at the next phrase boundary and publish explicit pending/applied UI state. |
| A5 | V1 maps are exactly 16 entries with values in `0...15`; variable-length maps are deferred. |
| A6 | Per-track, project-wide, layer-level, and stacked transformations are out of v1. |
| A7 | Phrase layer automation remains output-step based in v1 unless the spec explicitly changes that boundary. |

## Left For Spec

- Exact Swift model names and migration/defaulting behavior.
- Exact command names for assigning maps and arming enable/disable.
- How map deletion behaves when the map is assigned.
- The visual design of the pending toggle badge/pill.
- The editor's end-of-map wrap indicator.
- Empty/identity copy and disabled states.
- Keyboard, focus, and accessibility behavior for the map grid and picker.
- Whether non-16-step phrases are disabled, blocked from assignment, or handled
  through an explicit unavailable state.

## Readiness

This accepted architecture closes the architecture artifact gap only. Step
Order remains not builder-ready until accepted `spec.md`, `plan.md`, and
`implementation-handoff.md` exist.

