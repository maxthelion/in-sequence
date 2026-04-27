---
title: "Track Macros"
category: "architecture"
tags: [macros, au, sampler, clip, snapshot, engine, document]
summary: Per-track macro system — slot model, document types, clip-level per-step overrides, and the precedence rule the snapshot compiler enforces.
last-modified-by: codex
---

## Overview

Every track exposes up to 8 macro slots (M1–M8). A slot is either empty or bound to one parameter. Slot positions are stable: adding or removing a binding never shifts the position of surviving slots, so the muscle-memory layout of the knob row is preserved.

Two destination kinds populate macros differently:

- **AU instrument destinations** — user assigns AU parameters one at a time via `SingleMacroSlotPickerSheet`. Each slot maps to one `AUParameterDescriptor`.
- **Sampler (`.sample` / `.internalSampler`) destinations** — 8 built-in macros are installed automatically on kind transition: `sampleStart`, `sampleLength`, `sampleGain`, plus the five filter macros (`samplerFilterCutoff`, `samplerFilterReso`, `samplerFilterDrive`, `samplerFilterType`, `samplerFilterPoles`).

On a kind transition, `setEditedDestination` routes through `Project.setDestinationWithMacros`, which calls `syncBuiltinMacros`. Sampler built-ins are installed; AU parameter bindings are dropped when transitioning away from `.auInstrument`. The cascade purges phrase layers and clip macro lanes for every removed binding.

## Document types

### `TrackMacroDescriptor` (`Sources/Document/TrackMacroDescriptor.swift`)

Describes a single controllable parameter. Fields: `id`, `displayName`, `minValue`, `maxValue`, `defaultValue`, `valueType`, `source`.

`source` is either:

- `.builtin(BuiltinMacroKind)` — a named built-in for samplers
- `.auParameter(address: UInt64, identifier: String)` — an AU parameter addressed by the tree's 64-bit address, with the keyPath identifier as a fallback

Built-in descriptor IDs are deterministic: `TrackMacroDescriptor.builtinID(trackID:kind:)` derives a UUID from a SHA-like hash of `"<trackID>-<kind.rawValue>"` so the ID survives document round-trips.

### `TrackMacroBinding` (`Sources/Document/TrackMacroDescriptor.swift`)

A binding wraps a `TrackMacroDescriptor` with a `slotIndex: Int` (clamped 0–7). Bindings live on `StepSequenceTrack.macros: [TrackMacroBinding]`.

Codable behaviour: `slotIndex` is encoded as a keyed field; legacy documents that lack the key decode to `0` and are normalised to sequential indices by `StepSequenceTrack` on load.

### `MacroLane` (`Sources/Document/ClipContent.swift`)

A per-step override array. `values: [Double?]` is parallel to the clip's step count; a `nil` at index N means "no override at this step." `MacroLane.synced(stepCount:)` pads or truncates the array when the clip length changes.

### `ClipPoolEntry.macroLanes` (`Sources/Document/PhraseModel.swift`)

`ClipPoolEntry` carries `macroLanes: [UUID: MacroLane]` keyed by binding descriptor ID. A missing key means no lane exists for that binding. Legacy documents without the field decode as `[:]` — no migration required.

`ClipPoolEntry.synced(with:stepCount:)` drops lanes for removed bindings and resizes survivors. `ClipPoolEntry.removingMacroLane(id:)` removes a single lane (used by the cascade on binding removal).

## Slot model invariants

- The row always renders M1–M8 (8 slots). An unbound slot shows a dashed ring with a `+` icon.
- `addAUMacro(descriptor:to:slotIndex:)` on `Project+TrackMacros.swift` returns `Bool` — `false` when the requested slot is occupied, the 8-slot cap is reached, or the AU parameter address duplicates an existing binding.
- `removeMacro(id:from:)` cascades: it drops the matching phrase layer and removes the binding's lane from every clip in the pool.
- `syncMacroLayers()` re-derives the full phrase-layer list from the current track bindings.

## Session API

`SequencerDocumentSession+Mutations.swift` owns two typed methods for slot management:

- `session.assignAUMacroToSlot(_ descriptor:, to trackID:, slotIndex:) -> Bool` — assigns one AU parameter to a slot. Returns `false` if the slot is occupied or the cap is reached. Runs a full batch: updates tracks, layers, phrases.
- `session.removeAUMacroSlot(bindingID:, trackID:)` — removes a binding and calls `writeBackChangedClips` so clip macro lane cascades reach the live store.

Both methods call `project.syncMacroLayers()` and write back tracks, layers, and phrases in a single `.snapshotOnly` batch.

`session.setEditedDestination(_:for:)` routes through `Project.setDestinationWithMacros` and also calls `writeBackChangedClips` — this ensures kind transitions always cascade correctly in production.

The `writeBackChangedClips` helper (private on `LiveSequencerStore`) compares each clip in the project export to the live clip pool and writes back any that differ.

## Per-step clip macro lanes

A clip's `macroLanes` dictionary is authored from `ClipContentPreview`. The UI shows a slot strip (M1, M2, …) above the trigger/velocity/probability mode picker.

- Tapping a **bound** slot switches the cell grid to edit that macro's lane.
- Tapping an **unbound** slot opens `SingleMacroSlotPickerSheet` to pick one AU parameter.

Lane edits write back via `session.ensureClipAndMutate` setting `entry.macroLanes`.

## Snapshot compiler and precedence

`SequencerSnapshotCompiler` resolves the macro value for each step in this order:

1. **Clip-step override** — if `clip.macroLanes[bindingID]?.values[stepIndex]` is non-`nil`, that value wins.
2. **Phrase-layer default** — the phrase layer's resolved value for that track and binding.
3. **Descriptor default** — `TrackMacroDescriptor.defaultValue`.

The compiler determines macro binding order by the clip's **owning track ID** (looked up from `clipOwnerByID`), not by `trackType`. This ensures two tracks of the same type each see their own bindings rather than non-deterministically resolving the wrong track's macros.

`ClipBuffer` carries `macroBindingOrder: [UUID]` and `macroOverrideValues: [[Double?]]` — the pre-resolved per-step per-binding override table produced at compile time.

## Related pages

- [[track-destinations]] — the destination card UI, `PresetStepper`, and the AU macro slot knob row
- [[document-model]] — wider `.seqai` persistence model
- [[engine-architecture]] — tick lifecycle and snapshot compilation
- [[project-layout]] — canonical source layout for `Document/`, `Engine/`, and `UI/`
