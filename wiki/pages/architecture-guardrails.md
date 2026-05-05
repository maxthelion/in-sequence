---
title: "Architecture Guardrails"
category: "architecture"
tags: [architecture, guardrails, buffers, snapshots, document, runtime]
summary: Cross-cutting architecture decisions PM and implementation work should preserve.
last-modified-by: codex
---

This page records cross-cutting architecture choices that roadmap architecture passes should check before a feature becomes a spec.

It complements [[project-layout]], [[document-model]], [[engine-architecture]], and [[code-review-checklist]].

For product and runtime orientation, start with [[application-overview]], [[information-architecture-ux]], and [[playback-data-path]].

## Document Truth Versus Runtime State

The `.seqai` document is persisted user truth. It should contain authored musical state and references, not temporary UI/runtime state.

Runtime-only states should stay out of the document unless the user explicitly commits them. Examples:

- audition state;
- transient capture/history buffers;
- selected prototype or modal state;
- transport-derived state;
- cached playback snapshots.

If a feature has a "preview", "audition", "cue", or "pseudo" state, the architecture pass must say when, if ever, that state becomes persisted document data.

## Playback Snapshots And Buffers

Hot playback code should prefer compiled, typed runtime data over ad hoc traversal of the full document model.

Current examples:

- `PlaybackSnapshot` carries typed runtime fields and no longer embeds the whole `Project`.
- `ClipBuffer` stores clip steps and macro overrides in compact step-indexed arrays.
- `PhrasePlaybackBuffer` stores phrase state as arrays keyed by step.
- `SnapshotChange` records narrow invalidation domains so live mutations do not default to full rebuilds.

When a feature affects playback, the architecture pass should ask:

- does this belong in persisted document state, a compiled snapshot, or transient runtime state?
- can the hot path read a small buffer or lookup rather than walking the document?
- what narrow invalidation should update the compiled runtime state?
- what tests prove the runtime buffer matches the authored document truth?

The current canonical note-resolution path is documented in [[playback-data-path]].

## Array-Style Sequencer Data

Step sequencer data should normally be represented as predictable arrays or array-like buffers indexed by step, track, lane, or pattern slot.

This keeps playback deterministic and makes boundary cases testable: empty, one step, page boundaries, wraparound, and maximum length.

Avoid introducing feature-specific storage that fights this shape unless the architecture document explains why.

## Realtime And Future Audio Thread Rules

The current engine is timer-driven, but future audio-thread work should preserve realtime discipline:

- no allocation in render-thread code;
- no locks in render-thread code;
- UI-to-render communication via command/ring buffers;
- render-to-UI communication via buffers read from the UI/display side;
- explicit threading contracts for every runtime object.

These rules are listed in [[code-review-checklist]] and should inform architecture guardrails before implementation begins.

## Small Boundaries Over Broad Rewrites

Prefer small focused document deltas, snapshot invalidations, and runtime adapters over broad document rewrites.

Red flags for architecture review:

- a UI concept becoming document truth because it was convenient;
- a new feature requiring wholesale project export/import on every gesture;
- duplicated playback paths for "almost the same" behavior;
- view-local state becoming the source of playback truth;
- new global mutable state without an explicit owner.

## PM Architecture Pass

Every roadmap `architecture.md` should cite the relevant code and wiki sources it used. It should make the proposed course of action reviewable before spec:

- what state is persisted;
- what state is transient;
- what runtime buffers or snapshots are involved;
- what existing patterns are being followed;
- what architecture questions remain open.
