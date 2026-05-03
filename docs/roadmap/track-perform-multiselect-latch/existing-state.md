# Track Perform Multi-Select And Latch - Existing State

## Summary

The codebase already has one useful primitive for this roadmap item: authored
phrase edits can fan out to multiple explicit track IDs. What it does **not**
have is a performer-owned selection set or a track-level runtime overlay for
momentary versus latched controls.

Today the closest "Track Perform" surfaces still edit phrase data directly:

1. `TracksMatrixView` perform mode toggles the current layer on one track at a time.
2. `LiveWorkspaceView` can fan the same phrase edit out to a predefined
   track group, but not to an arbitrary user-picked edit set.

That means the current app has partial infrastructure for linked writes, but no
actual multi-select workflow and no latch model for Fill, Note Repeat, or other
binary performance controls.

---

## 1. Selection Model Today

### What exists

The persistent document model stores a single `selectedTrackID`
(`[[code:Sources/Document/Project.swift:19]]`). The live store mirrors that as
`storeSelectedTrackID` / `selectedTrack`
(`[[code:Sources/Engine/LiveSequencerStore.swift:112]]`,
`[[code:Sources/Engine/LiveSequencerStore+Accessors.swift:23]]`).

The main track matrix also treats selection as singular. `TracksMatrixView`
reads one `selectedTrackID`, highlights a card when `track.id == selectedTrackID`,
and updates selection with `session.setSelectedTrackID(track.id)`
(`[[code:Sources/UI/TracksMatrixView.swift:128]]`,
`[[code:Sources/UI/TracksMatrixView.swift:363]]`,
`[[code:Sources/UI/TracksMatrixView.swift:366]]`).

### Gap vs. [[story:1]] and [[story:3]]

There is no persistent or session-local concept of "selected tracks" as a set.
The existing state supports exactly one focused track, not an additive
multi-select edit set with clear inclusion / exclusion affordances.

---

## 2. Multi-Track Editing Primitive Already Exists, But Only As Fan-Out

### What exists

The phrase mutation API already supports broadcasting one authored value to many
tracks: `SequencerDocumentSession.setPhraseCell(...)` accepts `trackIDs: [UUID]`
and writes the same phrase cell to every supplied track
(`[[code:Sources/App/SequencerDocumentSession+Mutations.swift:465]]`).

That fan-out behavior is also covered at the model level:
`test_set_phrase_cell_can_fan_out_to_multiple_tracks`
(`[[code:Tests/SequencerAITests/SeqAIDocumentTests.swift:185]]`).

`LiveWorkspaceView` uses that exact mechanism for grouped edits. When the UI is
collapsed to a track group, the scope carries `members.map(\.id)` and
`performPrimaryAction(on:)` writes the selected layer change to every member
track in the scope
(`[[code:Sources/UI/LiveWorkspaceView.swift:105]]`,
`[[code:Sources/UI/LiveWorkspaceView.swift:246]]`,
`[[code:Sources/UI/LiveWorkspaceView.swift:253]]`).

### Gap vs. [[story:1]] and [[story:2]]

This is not performer-driven multi-select. The app can fan out an authored edit
to a list of tracks, but today that list comes from an existing `TrackGroup`,
not from a temporary selection the user builds on the Track Perform surface.

So the current primitive is "broadcast to known IDs," not "select arbitrary
tracks, keep the set visible, then link edits through that set."

---

## 3. Current Perform Surfaces Still Mutate Phrase Data

### Tracks matrix perform mode

`TracksMatrixView` enters perform mode with a UI toggle, but tapping a track
card still routes to `performPrimaryAction(trackID:)`, which cycles the current
layer value and calls `session.setPhraseCell(...)` with exactly one `trackID`
(`[[code:Sources/UI/TracksMatrixView.swift:311]]`,
`[[code:Sources/UI/TracksMatrixView.swift:367]]`,
`[[code:Sources/UI/TracksMatrixView.swift:386]]`,
`[[code:Sources/UI/TracksMatrixView.swift:396]]`).

### Live workspace

`LiveWorkspaceView` is also a phrase/layer editing surface. Each scope button
routes to `performPrimaryAction(on:)`, and that path likewise ends in
`session.setPhraseCell(...)`
(`[[code:Sources/UI/LiveWorkspaceView.swift:123]]`,
`[[code:Sources/UI/LiveWorkspaceView.swift:246]]`,
`[[code:Sources/UI/LiveWorkspaceView.swift:253]]`).

### Consequence

The current "perform" behavior is still authored-state mutation, not a
runtime-only shadow state. That matters for this item because [[story:4]],
[[story:5]], and [[story:6]] describe live behavior that should respond to
pointer-down / pointer-up and latch mode, not just persist a new phrase value.

---

## 4. Runtime Overlay Infrastructure Exists Only For Scenes

### What exists

The only concrete performance overlay in engine code today is the master-bus
scene overlay: `EngineController` owns `masterBusPerformanceOverlay`
(`[[code:Sources/Engine/EngineController.swift:113]]`), and
`ScenesWorkspaceView+Perform` drives scene crossfader / macro overrides against
that runtime-only state rather than mutating phrase cells
(`[[code:Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:29]]`).

For track-perform behavior, no equivalent overlay exists. There is no
track-level performance state for selected tracks, Fill overrides, Note Repeat,
or latch mode in the store or engine.

The only concrete design for that layer is still in plan form:
`docs/plans/2026-04-25-live-perform-note-repeat-step-order.md` proposes a
`PerformanceOverlayState` with `fillTrackIDs`, note-repeat captures, and
step-order state, but none of that exists in production code yet
(`[[code:docs/plans/2026-04-25-live-perform-note-repeat-step-order.md:20]]`,
`[[code:docs/plans/2026-04-25-live-perform-note-repeat-step-order.md:35]]`,
`[[code:docs/plans/2026-04-25-live-perform-note-repeat-step-order.md:139]]`).

### Gap vs. [[story:4]], [[story:5]], and [[story:6]]

Momentary versus latched behavior needs runtime ownership. A phrase-cell write
cannot express "engage on pointer down, release on pointer up" without
persisting the edit into authored state. The app needs a track-level live state
layer comparable to the scene overlay before latch semantics can be consistent
across binary controls.

---

## 5. Pointer / Gesture Support Is Tap-Based Only

### What exists

Both current perform surfaces are button-driven:

- `TracksMatrixView` wraps each card in a single tap action
  (`[[code:Sources/UI/TracksMatrixView.swift:355]]`,
  `[[code:Sources/UI/TracksMatrixView.swift:365]]`).
- `LiveWorkspaceView` likewise wraps each scope in a `Button`
  (`[[code:Sources/UI/LiveWorkspaceView.swift:123]]`,
  `[[code:Sources/UI/LiveWorkspaceView.swift:125]]`).

There is no pointer-down / pointer-up handler, no gesture state object, and no
visible latch mode control on either surface.

### Gap vs. [[story:4]] and [[story:5]]

Momentary behavior depends on press lifecycle, not just tap. The UI currently
has no interaction primitive that can say "engage immediately on mouse-down,
then auto-release on mouse-up." A latch model therefore needs both new runtime
state and new gesture handling.

---

## 6. Fill And Note Repeat Are Still Separate Gaps

### Fill

The UX architecture page explicitly says Live / Track Perform should own
performance gestures such as fill, note repeat, latch, and multi-select
(`[[code:wiki/pages/information-architecture-ux.md:77]]`), but the current fill
behavior is still phrase-authored rather than a live per-track control. The
existing-state report for `[[feature:track-fill-toggle]]` already documents that
gap.

### Note Repeat

`[[feature:note-repeat]]` is even further behind: its existing-state report says
there is no note-repeat toggle, no repeat state, and no sub-step scheduling
primitive. The only detailed behavior definition is still the proposed plan in
`docs/plans/2026-04-25-live-perform-note-repeat-step-order.md`.

### Consequence for this item

This roadmap item is partly a unification problem. It is not only "add
multi-select"; it also needs a shared live interaction model that future Fill
and Note Repeat controls can opt into without each feature inventing its own
runtime state and gesture rules.

---

## 7. Model Gaps Vs. UX / Workflow Gaps

### Model / engine gaps

- No multi-track selection set in `Project` or `LiveSequencerStore`.
- No track-level performance overlay state comparable to
  `masterBusPerformanceOverlay`.
- No latch-mode flag or momentary press lifecycle API.
- No track-perform cleanup rules for resetting live selection / latch state on
  track change, phrase change, or view exit.

### UX / workflow gaps

- No clear affordance for adding or removing tracks from an edit set.
- No visible "these tracks will all be changed" state on the current perform UI.
- No dedicated binary control row for Fill / Repeat style actions.
- No way to tell whether a control is operating in momentary or latched mode.

The existing phrase fan-out helper solves only the last mile of "apply one
value to many IDs." It does not solve the user workflow around assembling,
displaying, and safely using that set.

---

## 8. Relevant Tests And Missing Coverage

### Relevant tests

- `test_set_phrase_cell_can_fan_out_to_multiple_tracks` proves the document
  model can already write one phrase-cell value to multiple explicit track IDs
  (`[[code:Tests/SequencerAITests/SeqAIDocumentTests.swift:185]]`).

### Missing coverage

- No tests for arbitrary multi-select state on a perform surface.
- No tests for linked edits affecting only the selected temporary edit set.
- No tests for pointer-down / pointer-up momentary behavior.
- No tests for track-level latch mode shared across multiple binary controls.
- No tests for resetting live selection / latch state on context changes.

---

## 9. Divergence Summary

| Story | Existing state | Gap |
|---|---|---|
| [[story:1]] Select an edit set of tracks | Single `selectedTrackID`; groups can broadcast edits | Need arbitrary temporary multi-select with visible membership |
| [[story:2]] Apply one cell change to every selected track | `setPhraseCell(... trackIDs:)` already fans out authored edits | Need the perform UI to feed that primitive from a user-built selection set |
| [[story:3]] Understand edit scope before committing | No selected-set visualization beyond single selected track or predefined groups | Need explicit selection affordance and clear linked-edit feedback |
| [[story:4]] Momentary behavior for binary controls | Perform surfaces are tap-driven phrase edits | Need pointer-down / pointer-up runtime behavior |
| [[story:5]] Latched behavior for binary controls | No track-level live overlay or latch mode | Need runtime state that persists outside a press but outside authored phrase data |
| [[story:6]] Shared latch model across controls | Fill and Note Repeat are separate unfinished features | Need one common live-perform interaction model, not per-feature drift |

## 10. Build-Relevant Conclusion

The smallest coherent implementation direction is:

- add a performer-owned selection set outside `selectedTrackID`;
- reuse the existing multi-track phrase fan-out primitive for linked edits where
  authored mutation is intended; and
- introduce a separate track-level runtime overlay layer for binary live
  controls so momentary and latched behavior do not mutate phrase data.

Without those two layers staying distinct, the feature risks collapsing into one
of two wrong shapes:

- a purely persistent phrase editor with no real performance behavior; or
- ad hoc runtime toggles that cannot share one latch contract across Fill,
  Note Repeat, and future binary controls.
