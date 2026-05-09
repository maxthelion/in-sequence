---
feature: mixer-main-out
created: 2026-05-03
---

# Mixer Main Out Plan

## Status

Historical PM build plan, reconciled after the accepted 2026-05-09
product-owner correction. The implementation has since landed; use
`spec.md`, `implementation-handoff.md`, and `decisions.md` as the current
product contract.

---

## Overview

Mixer Main Out adds a fixed master-output surface to the mixer workspace using
the already-approved Variant A lane from `prototype-approval.md` and the locked
product decisions in `decisions.md`.

The implementation stays deliberately narrow:

1. add one persisted global `masterOutputGain` field to `MasterBusState`
2. apply that gain on `finalOutputMixer.outputVolume`
3. add a transient master-meter publisher with a post-fader tap and manual clip
   clear
4. extract the existing Scene Perform crossfader into a shared view and embed a
   new master column in the mixer workspace
5. expose `MasterBusState.masterInserts` as the post-blend Master Out insert
   chain

No new effect types, no scene-specific master fader, and no Scene A/B insert
editing from Master Out are in scope.

---

## Phase 0 — Pre-Build Verification

Phase 0 is read-only. Its job is to confirm that the current code still matches
the seams assumed by the spec before any edits start.

### 0-A. Confirm the master-gain and tap seam

**What it is.** Verify that `finalOutputMixer` remains the correct shared point
for both audible master gain and metering.

**Files to read.**

- `Sources/Audio/MainAudioGraph.swift`
- `Sources/Audio/MasterBusHost.swift`
- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Audio/MasterBusHostTests.swift`

**Checks.**

1. Confirm `finalOutputMixer` still sits after A/B branch blending and before
   hardware output.
2. Confirm a global master gain can be applied there without fighting existing
   crossfade writes.
3. Confirm where tap install/remove belongs relative to graph rebuilds and
   engine restart.

**Acceptance signals.**

- The implementer can name the single authoritative post-fader meter point.
- The tap lifecycle is tied to a concrete rebuild path before coding starts.

### 0-B. Confirm the reuse seams for inserts and crossfader UI

**What it is.** Validate which parts of Scenes Perform can be lifted into the
master mixer column instead of reimplemented.

**Files to read.**

- `Sources/UI/Mixer/MixerWorkspaceView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`
- `Sources/Document/MasterBus.swift`

**Checks.**

1. Confirm the existing crossfader widget still writes through
   `setLiveMasterCrossfader(_:)`.
2. Confirm the master-bus model exposes a `MasterBusState.masterInserts`
   mutation surface for post-blend Master Out inserts.
3. Confirm the Master Out insert label and actions stay bound to the post-blend
   chain rather than Scene A/B insert lists.

**Acceptance signals.**

- The implementer knows which crossfader view code will be extracted versus
  reused.
- The insert section can mutate `MasterBusState.masterInserts` without exposing
  Scene A/B insert editing.

### 0-C. Confirm the existing test landing zones

**What it is.** Identify where the new coverage belongs before feature code is
added.

**Files to read.**

- `Tests/SequencerAITests/Audio/MasterBusHostTests.swift`
- `Tests/SequencerAITests/Document/MasterBusStateTests.swift`
- `Tests/SequencerAITests/App/SequencerDocumentSessionMasterBusTests.swift`
- any existing mixer or scene-perform UI tests

**Checks.**

1. Confirm document round-trip coverage already exists for `Project.masterBus`.
2. Confirm session-level tests already cover master-bus mutations and can absorb
   master gain writes.
3. Confirm whether mixer UI coverage needs a new focused test file.

**Acceptance signals.**

- The implementer can name exact files for document, engine, session, and UI
  regression coverage.

---

## Phase 1 — Persisted Master Gain

Phase 1 introduces the only new authored document state for this feature: a
global post-blend master output gain.

### 1-A. Add `masterOutputGain` to `MasterBusState`

**What it is.** Extend the persisted master-bus model with one global gain
field.

**Required behavior.**

1. Add `masterOutputGain: Double` to `MasterBusState`.
2. Default new documents to `1.0`.
3. Decode legacy documents that omit the field as `1.0`.
4. Keep `MasterBusScene.outputGain` out of scope for this feature.

**Guardrails.**

- Do not repurpose scene output gain as the global master fader.
- Clamp or normalize consistently with the spec's `0...2` range.

**Acceptance signals.**

- Old documents open without data loss.
- New documents round-trip the authored master output gain.

### 1-B. Add session and document mutation paths

**What it is.** Give the UI one explicit way to author the global master gain.

**Files likely to change.**

- `Sources/Document/MasterBus.swift`
- `Sources/App/SequencerDocumentSession+Mutations.swift`
- any helper exposing `Project.masterBus` writes

**Required behavior.**

1. Add a focused mutation for setting the global master output gain.
2. Route it through the same document/session ownership path used by existing
   insert and scene mutations.
3. Keep authored document gain separate from live crossfader override state.

**Acceptance signals.**

- The mixer fader has one canonical document mutation entry point.
- Session tests can verify the document write without touching audio code.

### 1-C. Apply gain on the audio graph

**What it is.** Make the new field audible.

**Files likely to change.**

- `Sources/Audio/MainAudioGraph.swift`
- `Sources/Audio/MasterBusHost.swift`
- `Sources/Engine/EngineController.swift`

**Required behavior.**

1. Apply `masterOutputGain` on `finalOutputMixer.outputVolume`.
2. Preserve the existing A/B crossfade math and branch gain behavior.
3. Ensure graph writes still flow through the existing `performOnMain`
   discipline.

**Acceptance signals.**

- Master gain changes are audible at the final output only.
- Metering can later tap the same post-fader signal without architectural drift.

---

## Phase 2 — Transient Master Metering

Phase 2 adds the first runtime-only subsystem in this feature: a real-time-safe
meter publisher for the master output.

### 2-A. Add a transient master-meter owner

**What it is.** Introduce a `MasterMeterPublisher`-style type that owns tap
state, published levels, and the clip latch.

**Required behavior.**

1. Hold left/right peak values and peak-hold markers.
2. Hold a latched clip flag.
3. Expose a `clearClip()` action for the UI.
4. Keep all of this state out of the document model.

**Guardrails.**

- No `@Observable` writes from the audio callback thread.
- No persistence of clip state or meter readings.

**Acceptance signals.**

- Meter state is available to SwiftUI without leaking into `Project`.
- The clip latch can be cleared independently of playback state.

### 2-B. Install a post-fader tap and publish safely

**What it is.** Add the tap and thread-safe publication path.

**Files likely to change.**

- `Sources/Audio/MainAudioGraph.swift`
- `Sources/Audio/MasterBusHost.swift`
- `Sources/Engine/EngineController.swift`

**Required behavior.**

1. Install the tap on `finalOutputMixer`.
2. Remove and reinstall it across engine rebuilds and graph restarts.
3. Compute channel peaks in dBFS-compatible form.
4. Bridge those values to main-thread-observable state via a thread-safe
   buffer, atomic, or equivalent narrow transport.

**Acceptance signals.**

- The meter reflects the same signal path that the master fader controls.
- Engine rebuilds do not leak duplicate taps or stale meter state.

### 2-C. Define deterministic meter display rules

**What it is.** Lock down the spec-facing display data the UI will consume.

**Required behavior.**

1. Surface left/right live peak levels.
2. Surface peak-hold markers with a short visual hold.
3. Surface a clip latch when either channel exceeds `0 dBFS`.
4. Surface whether `CLR` should be visible.

**Acceptance signals.**

- The UI can render a stable meter without recomputing audio values locally.

---

## Phase 3 — Master Column UI

Phase 3 adds the actual mixer-facing surface, but it should stay a presentation
extension of the current master-bus path rather than a new subsystem.

### 3-A. Extract a shared crossfader view

**What it is.** Lift the existing Scene Perform crossfader into a reusable
component.

**Files likely to change.**

- `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`
- a new shared view file under `Sources/UI/Mixer/` or `Sources/UI/`
- `Sources/UI/Mixer/MixerWorkspaceView.swift`

**Required behavior.**

1. Both Scene Perform and Mixer Main Out render the same live crossfader state.
2. The shared view still writes through `engineController.setLiveMasterCrossfader(_:)`.
3. The mixer variant omits Reset / Save Blend / Save to Scene affordances.

**Acceptance signals.**

- Dragging either crossfader updates the other immediately.
- No second local crossfader state is introduced.

### 3-B. Add the fixed master-out column and compact overlay

**What it is.** Build the approved Variant A layout in the mixer workspace.

**Files likely to change.**

- `Sources/UI/Mixer/MixerWorkspaceView.swift`
- new focused master-column subviews under `Sources/UI/Mixer/`

**Required behavior.**

1. At `>= 540 pt`, render a fixed-width right-side master column.
2. At `< 540 pt`, collapse to the compact strip plus temporary overlay.
3. Preserve the existing track-strip scroll behavior.
4. Keep section order: crossfader, inserts, fader, meter.

**Acceptance signals.**

- The master-out surface is visually distinct and always reachable.
- Narrow-width behavior does not hide the master path entirely.

### 3-C. Expose post-blend Master Out inserts

**What it is.** Show the post-blend Master Out insert chain inside the master
column.

**Required behavior.**

1. Bind the visible insert chain to `MasterBusState.masterInserts`.
2. Keep the chain stable as the Scene A/B crossfader moves.
3. Support add, bypass, reorder, and remove mutations for the post-blend chain.
4. Show empty placeholder rows when the master chain has fewer than two
   inserts.

**Acceptance signals.**

- Insert editing in the master column mutates `MasterBusState.masterInserts`.
- The label communicates final-output ownership, for example `Final chain` /
  `After Scene A/B mix`.
- Master Out does not expose Scene A/B insert editing affordances.

### 3-D. Add the master fader and meter presentation

**What it is.** Render the final control stack for stories 1 and 3.

**Required behavior.**

1. Show the global master fader with the approved DAW-style markings.
2. Render a dual vertical L/R meter with color zones and peak-hold markers.
3. Show `CLIP` only when latched and `CLR` only when actionable.
4. Keep the fader and meter readable at the approved fixed column width.

**Acceptance signals.**

- The master column carries the whole approved control story without requiring
  the user to switch to Scene Perform.

---

## Phase 4 — Tests and Verification

Phase 4 proves the implementation stayed within the approved model and runtime
boundaries.

### 4-A. Document and session regression coverage

**Add or extend tests for:**

1. legacy decode default of `masterOutputGain == 1.0`
2. codable round-trip preserving authored gain
3. session mutation writing the global gain only

**Acceptance signals.**

- Old documents open cleanly.
- New documents persist the field and no unrelated master-bus state regresses.

### 4-B. Audio/runtime regression coverage

**Add or extend tests for:**

1. applying master gain on the final output path
2. post-blend `MasterBusState.masterInserts` mutation and graph routing
3. clip latch set/clear behavior
4. tap lifecycle surviving graph rebuilds without duplicate install

**Acceptance signals.**

- The meter and fader share the same audible node.
- Rebuilds do not leave orphaned taps or stale published values.

### 4-C. UI verification

**Add or extend tests for:**

1. fixed master column rendering in mixer workspace
2. compact-strip collapse rule below `540 pt`
3. shared crossfader state between Scene Perform and Mixer Main Out

**Manual smoke checks before landing.**

1. move the master fader and confirm audible level change without changing
   track-strip fader positions
2. drag the crossfader in either surface and confirm mirrored UI state
3. trigger the clip latch, then clear it manually
4. edit inserts from the mixer column and confirm they affect the post-blend
   Master Out chain, not Scene A/B insert chains

**Acceptance signals.**

- The UI satisfies all four stories from `spec.md`.
- `xcodebuild test` is green after the feature lands.

---

## Non-Goals and Watchouts

- Do not expose Scene A/B insert editing from Master Out.
- Do not revive `MasterBusScene.outputGain` as a v1 shortcut.
- Do not persist meter values or clip latch state.
- Do not give the mixer master column extra Scene Perform actions that the spec
  explicitly excluded.
- Do not split ownership of crossfader state between mixer and scene views.

---

## Ready for Implementation Handoff

After this plan is accepted, the next PM-loop action should be
`write-implementation-handoff`.
