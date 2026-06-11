---
status: accepted
stage: implementation-plan
updated: 2026-06-04
source:
  - docs/roadmap/song-mode-phrase-looping/user-stories.md
  - docs/roadmap/song-mode-phrase-looping/existing-state.md
  - docs/roadmap/song-mode-phrase-looping/prototype-approval.md
  - docs/roadmap/song-mode-phrase-looping/architecture.md
  - docs/roadmap/song-mode-phrase-looping/spec.md
---

# Song Mode And Phrase Looping Plan

## Status

Accepted PM implementation plan for the approved free-play phrase-navigation
workflow. This plan does not authorize build-loop promotion by itself; the lane
still needs an accepted `implementation-handoff.md`.

## Scope

Build transport-level free-play phrase navigation:

- engine-owned current, queued, basis, and phrase-cycle state;
- transport current phrase display, queue display, and phrase dropdown;
- explicit `Queue` and `Now` actions;
- end-of-cycle queued phrase promotion;
- immediate phrase switch;
- stopped and invalid-state reconciliation;
- Tracks basis phrase resolution and edit targeting;
- required engine, UI, accessibility, and regression coverage.

Do not broaden this plan into scripted Song Mode, Audio Looping, MIDI work,
Track Perform work, persisted queue arrangement data, or a separate queue-cancel
control.

## Phase 0 - Build-Time Verification

Phase 0 is a short read-only pass to confirm the live code still matches the
accepted architecture assumptions before product code changes begin.

### 0-A. Confirm Engine Tick And Snapshot Seams

**Files to read.**

- `Sources/Engine/EngineController.swift`
- `Sources/Engine/PlaybackSnapshot.swift` or the current playback snapshot
  definition
- `Sources/Engine/SequencerSnapshotCompiler.swift` or the current snapshot
  compiler

**Tasks.**

1. Locate the current `prepareTick` phrase-selection path and confirm it still
   resolves playback from `playbackSnapshot.selectedPhraseID`.
2. Locate the implicit phrase-cycle boundary for the active phrase's step count.
3. Confirm no existing queue/current/basis state has already been added.
4. Confirm `PlaybackSnapshot` can remain unchanged for MVP because phrase
   buffers are already available by phrase ID.

**Acceptance signals.**

- The implementer can name the exact mutation point for queued promotion.
- The build has a written confirmation that no MVP `PlaybackSnapshot` queue
  field is needed.

### 0-B. Confirm UI Read Paths

**Files to read.**

- `Sources/UI/TransportBar.swift`
- `Sources/UI/TracksMatrixView.swift`
- `Sources/UI/LiveWorkspaceView.swift`
- `Sources/UI/PhraseWorkspaceView.swift`

**Tasks.**

1. Confirm the current top bar has no phrase indicator or queue dropdown.
2. Confirm Tracks basis selection still derives from
   `session.store.selectedPhraseID` in free mode.
3. Confirm the existing top-right `Basis Phrase` pill remains the canonical
   MVP basis surface.
4. Identify any duplicated phrase-index derivation that should not become the
   source of truth for this free-play workflow.

**Acceptance signals.**

- The implementer knows the transport insertion point.
- The implementer knows which Tracks basis read path must prefer engine state.

## Phase 1 - Engine Phrase Navigation State

Phase 1 creates the runtime state and action surface. No transport dropdown UI
should ship before these state transitions are testable.

### 1-A. Add Engine-Owned Live State

**What it is.** Add live performance state to `EngineController`:

- `private(set) var currentPhraseID: UUID?`
- `private(set) var queuedPhraseID: UUID?`
- `private(set) var basisPhraseID: UUID?`
- a phrase-cycle offset such as `phraseCycleStartTick`

Use the app's existing observable/publication pattern so SwiftUI reads stable
main-thread state while the tick path has a clock-safe mutation point.

**Required behavior.**

1. On playback start, initialize current phrase from selected phrase when no
   valid current phrase exists.
2. Set basis to current phrase unless a valid queue already defines the basis.
3. Reset phrase-local cycle position so the first prepared step is local step
   zero.
4. Keep queue/current/basis out of the saved document model.

**Acceptance signals.**

- Starting playback exposes a valid current phrase when phrases exist.
- Queue/current/basis state does not mutate `Project.selectedPhraseID` merely
  by starting or queueing.

### 1-B. Add Queue And Immediate-Switch Actions

**What it is.** Add narrow engine actions for the transport dropdown:

- queue target phrase for the next current-phrase cycle;
- switch to target phrase immediately.

**Required behavior.**

1. Queueing a valid phrase sets `queuedPhraseID` and `basisPhraseID`.
2. Queueing does not change `currentPhraseID` or interrupt audible playback.
3. Queueing a second phrase replaces the previous queue.
4. Immediate switch sets current phrase, clears queue, sets basis phrase, and
   resets phrase-local cycle position to zero.
5. Immediate switch invalidates or replaces already-prepared next-tick work if
   needed so the next audible tick uses the target phrase.
6. Invalid target IDs are ignored or reconciled without crashing, following the
   local error-handling style.

**Acceptance signals.**

- Queue and Now can be called independently of the dropdown view.
- Immediate switch is the MVP path for clearing an in-flight queue.

### 1-C. Promote Queued Phrase At Cycle Boundary

**What it is.** Move queued phrase promotion into the tick engine at the active
phrase's musical boundary.

**Required behavior.**

1. Resolve playback phrase from valid `currentPhraseID`, falling back to
   snapshot selected phrase only when live state is unset or invalid.
2. Compute local step from the phrase-cycle offset rather than global transport
   tick modulo:

   ```text
   localStep = (upcomingStep - phraseCycleStartTick) % currentPhrase.stepCount
   ```

3. When the final local step of the current phrase completes and the queued
   phrase is valid, promote it atomically: `currentPhraseID = queuedPhraseID`,
   `queuedPhraseID = nil`, `basisPhraseID = currentPhraseID`, and reset cycle
   offset.
4. If the queued phrase is invalid at the boundary, clear the queue and keep
   the current valid phrase playing.

**Acceptance signals.**

- The promoted phrase starts at local step zero.
- Transport state, Tracks basis state, and audible phrase update coherently at
  the boundary.

## Phase 2 - Reconciliation And Stopped State

Phase 2 makes the runtime state robust across normal document and transport
changes before the views depend on it.

### 2-A. Reconcile Invalid IDs

**Trigger points.**

- playback start;
- document apply;
- snapshot install;
- phrase deletion;
- state reload.

**Required behavior.**

1. Invalid current phrase falls back to selected phrase, then first available
   phrase if the existing app uses that fallback.
2. Invalid queued phrase is cleared.
3. Invalid basis phrase falls back to current phrase while playing and selected
   phrase while stopped.
4. No-phrase state uses existing empty-state behavior without crashing.

**Acceptance signals.**

- Removing the queued phrase clears the queue without affecting a valid current
  phrase.
- Removing the current phrase resolves to a safe fallback.

### 2-B. Stop Clears Queue

**Required behavior.**

1. Stopping playback clears `queuedPhraseID`.
2. Queueing is unavailable while stopped.
3. Tracks basis resolves back to selected phrase while stopped when no valid
   live basis remains.

**Acceptance signals.**

- A stopped transport cannot accumulate a hidden queued phrase.
- Restarting playback initializes from selected or reconciled current phrase.

## Phase 3 - Transport Phrase Navigation UI

Phase 3 wires the accepted transport prototype into the native transport bar
using app-native controls and tokens.

### 3-A. Current Phrase Display

**File.** `Sources/UI/TransportBar.swift`

**Required behavior.**

1. Show the phrase currently used by the engine while playback is running.
2. Show stopped or empty treatment when no valid current phrase can be resolved.
3. Include per-bar cycle progress for MVP.
4. Use active/current visual treatment from native tokens corresponding to the
   accepted blue prototype state.

**Acceptance signals.**

- The transport phrase label never derives independently from view-side
  `.song` auto-cycle logic.
- Current phrase copy and cycle progress do not overlap existing transport
  controls.

### 3-B. Phrase Dropdown With Queue And Now

**Required behavior.**

1. The dropdown lists all valid phrases by existing phrase name.
2. Each row exposes separate `Queue` and `Now` actions.
3. Current and queued rows are visibly marked.
4. `Queue` dismisses the dropdown after successfully queueing.
5. `Now` dismisses the dropdown after successfully switching.
6. Outside tap and Escape dismiss without changing phrase state.
7. Queue controls are disabled while stopped, with accessibility help that
   explains queueing is available during playback.

**Acceptance signals.**

- Queueing leaves audible playback unchanged and keeps queued phrase state
  visible after the dropdown closes.
- Immediate switch clears the queue and updates current phrase display on the
  next observable update.

### 3-C. Long-Name And Crowded Layout Handling

**Required behavior.**

1. Long current and queued names truncate with stable trailing ellipsis.
2. Full names remain available through accessibility value, tooltip, or help
   surface following local app convention.
3. Preserve layout priority in this order: play/stop and transport safety
   controls, current phrase identity, queued phrase presence, full queued
   phrase name, secondary copy.
4. Use current/queued/action state labels or icons so color is not the only
   carrier of meaning.

**Acceptance signals.**

- Crowded transport layouts remain non-overlapping.
- Queued state is understandable without relying on amber color alone.

## Phase 4 - Tracks Basis And Edit Targeting

Phase 4 connects the Tracks UI to engine-owned basis state while preserving the
existing `Basis Phrase` surface.

### 4-A. Prefer Engine Basis State

**Files likely to change.**

- `Sources/UI/TracksMatrixView.swift`
- `Sources/UI/LiveWorkspaceView.swift`

**Required behavior.**

1. Resolve free-play editing basis from valid `engineController.basisPhraseID`.
2. Fall back to `session.store.selectedPhraseID`.
3. Preserve any existing first-phrase empty fallback if the current UI already
   uses one.
4. Update the existing top-right `Basis Phrase` pill to show the resolved
   basis phrase.

**Acceptance signals.**

- Queueing a phrase immediately changes the Tracks basis phrase.
- Promotion and immediate switch confirm the active phrase as basis.

### 4-B. Route Edits To The Basis Phrase

**Required behavior.**

1. Edits made while queued phrase is basis write directly to that queued phrase.
2. Replacing the queue or immediate-switch clearing it does not undo edits
   already made to the previously queued phrase.
3. The feature does not introduce transient preview buffers or staged edits.

**Acceptance signals.**

- A test or focused manual verification proves queued-basis edits land on the
  queued phrase ID, not the audible current phrase.

### 4-C. Handle Basis Phrase Size Changes

**Required behavior.**

1. The Tracks grid rerenders to the target phrase's actual bar or step count.
2. Preserve vertical track position where possible.
3. Reset horizontal step/bar scroll to the beginning unless existing grid
   behavior has a stronger local rule.
4. Do not impose a same-length phrase constraint.

**Acceptance signals.**

- Queueing or switching to a phrase with a different bar count renders the
  correct grid size without stale cells or layout breakage.

## Phase 5 - Tests, Accessibility, And Regression Pass

Phase 5 closes the implementation with focused coverage and a native UI review.

### 5-A. Engine Tests

Add or extend engine tests for:

- current phrase initializes from selected phrase on start;
- stopped transport disables queueing and clears queued state;
- queueing sets queued and basis IDs without changing current phrase;
- queue replacement uses the latest queued target;
- queued phrase promotes at the current phrase cycle boundary;
- immediate switch clears queue and starts target phrase at local step zero;
- invalid current, queued, and basis IDs reconcile safely;
- no queue/current/basis state is added to `PlaybackSnapshot` for MVP.

### 5-B. Tracks And Session Tests

Add focused coverage for:

- Tracks basis resolution preferring valid engine basis state;
- queued-basis edits targeting the queued phrase immediately after queueing;
- basis phrase changes rendering a different bar count correctly enough to
  prevent stale edit targeting.

### 5-C. Transport UI And Accessibility Checks

Verify:

- dropdown opens from keyboard focus using Space or Return;
- Escape closes without changing state;
- each row's `Queue` and `Now` actions are separately focusable;
- focus order is current transport phrase control, dropdown rows in phrase
  order, each row's `Queue`, then each row's `Now`;
- accessible labels include current phrase, queued phrase if any, and action
  consequence;
- queued/current/immediate states are not conveyed by color alone;
- long labels truncate without overlap and expose full names through an
  accessibility/help surface;
- dropdown dismissal works for `Queue`, `Now`, outside tap, and Escape.

## Files And Modules Likely Touched

| Area | Files | Reason |
|---|---|---|
| Engine runtime state | `Sources/Engine/EngineController.swift` | Own current, queued, basis, cycle offset, queue actions, immediate switch, boundary promotion, stopped reconciliation |
| Playback snapshot boundary | `Sources/Engine/PlaybackSnapshot.swift`, `Sources/Engine/SequencerSnapshotCompiler.swift` or current equivalents | Confirm no MVP queue field is added; update only if the current code structure requires compile compatibility |
| Transport UI | `Sources/UI/TransportBar.swift` | Current phrase display, queue control, dropdown, Now action, accessibility labels |
| Tracks basis | `Sources/UI/TracksMatrixView.swift`, `Sources/UI/LiveWorkspaceView.swift` | Prefer engine basis phrase for free-play editing and basis pill |
| Phrase display helpers | `Sources/UI/PhraseWorkspaceView.swift` or shared helper if needed | Avoid duplicated view-side phrase identity becoming free-play source of truth |
| Engine tests | `Tests/SequencerAITests/Engine/*` | Runtime transition, boundary, reconciliation, snapshot-boundary coverage |
| UI/session tests | `Tests/SequencerAITests/*` | Tracks basis targeting, transport dropdown behavior where supported |

The exact file list should be confirmed during Phase 0. Product code changes
outside these areas need a written build-time reason.

## Acceptance Checklist

- [ ] Transport shows the engine-owned current phrase while playback is running.
- [ ] Queue dropdown lists all phrases with separate `Queue` and `Now` actions.
- [ ] Queueing does not interrupt the current phrase.
- [ ] Queueing a new phrase replaces the previous queue.
- [ ] Queued phrase remains visible after the dropdown closes.
- [ ] Queued phrase promotes at the current phrase cycle boundary and starts at
      local step zero.
- [ ] Immediate switch clears queue and starts the target at local step zero.
- [ ] Stopping playback clears queue state and disables queueing.
- [ ] Invalid current, queued, and basis IDs reconcile without crashes.
- [ ] Tracks basis phrase updates on queue, immediate switch, and promotion.
- [ ] Tracks edits made against queued basis write to the queued phrase.
- [ ] Different-length basis phrases rerender the Tracks grid correctly.
- [ ] Long phrase names truncate without overlapping neighboring transport
      controls and remain available to accessibility/help surfaces.
- [ ] Current, queued, and immediate-switch states are accessible without
      relying only on color.
- [ ] No MVP queue/current/basis field is added to `PlaybackSnapshot`.

## Risks And Mitigations

| Risk | Mitigation |
|---|---|
| Clock-path state races between SwiftUI actions and `prepareTick` | Keep mutations at the existing engine-safe boundary and publish observable state through the existing main-thread pattern. |
| Immediate switch still plays one tick of the old phrase | Explicitly invalidate or replace already-prepared work when switching now. |
| View-side phrase-index derivation conflicts with engine-owned current phrase | Make `EngineController` the source of truth for free-play current/queued/basis identity and limit old derivation to adjacent `.song` display needs. |
| Queued-basis editing surprises users | Keep queued state visible in transport and basis pill; tests must prove edits land on the real queued phrase. |
| Different phrase lengths break the Tracks grid | Include a dedicated basis-size test/manual check and reset horizontal scroll on basis change unless existing grid rules are stronger. |
| Transport crowding causes overlap | Treat truncation, layout priority, and accessibility full-name exposure as required acceptance work, not polish. |

## Promotion Readiness

This plan closes the build-plan artifact gap only. The lane remains not ready
for build-loop promotion until accepted `implementation-handoff.md` exists and
packages this plan into the final builder-facing contract.
