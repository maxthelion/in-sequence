# Clip History Architecture Guardrails

## Invariants

1. **Document truth is never changed by audition.** The pseudo-clip that plays during history review is a transient runtime object. It must not touch the document's pattern-slot array or any persisted model until the user explicitly commits a save action.

2. **The rolling capture buffer is append-only and monotonically ordered.** Steps are captured in playback order. Reads into the buffer always specify a length and produce a deterministic slice. No UI action may reorder, delete, or mutate captured history.

3. **Slot identity is stable during the modal session.** Pattern slot indices observed when the modal opens remain the authoritative save targets for the full duration of the modal. If a slot is occupied at open time, overwrite must be explicit; the modal must not silently reassign or auto-pick a different slot mid-session.

4. **Capture captures post-modifier output.** The rolling buffer records the resolved note events that actually played, not pre-modifier generator output. This matches the user intent ("capture what I heard") and aligns with the existing `capturedClipContent` engine API. The spec must state this explicitly so the distinction does not become a runtime surprise.

5. **Buffer size must cover the target history window.** A 16-bar window at 16th-note resolution requires 256 steps minimum. The current default of 64 steps is insufficient and must be raised before this feature is buildable. This is a required engine-side change, not a UI change.

## Lightweight Data and Runtime Shape

### Rolling capture buffer (engine layer, already exists)

The buffer is a private ring-buffer of captured steps inside `EngineController`. It lives in memory only. Its maximum size (step count) must be configurable or at minimum raised to accommodate the target history window.

Ownership: `EngineController` owns the buffer. The buffer is not part of the document model.

Lifetime: the buffer is live from the start of engine playback and is cleared on transport stop or document load. It is not restored from disk.

### Pseudo-clip state (new transient runtime object)

When the history modal is open, the engine needs a way to play a specific slice of the capture buffer as if it were a real clip, without writing that slice to the document.

Shape (conceptual):

```
PseudoClipState
  sourceTrackID: TrackID
  startStep: Int          // offset into capture buffer
  lengthSteps: Int        // currently selected clip length
  noteGrid: ClipContent   // materialized from buffer slice on demand
```

Ownership: the modal view-model or a lightweight session object scoped to the modal's lifetime. It must not be stored on the document or any long-lived controller.

Lifetime: created when the modal opens, discarded when the modal closes (cancel or save). On save, the `noteGrid` is written to a pattern slot via the existing `saveRollingCapture` API.

Thread/actor boundary: `noteGrid` materialization reads from the capture buffer, which is owned by the engine. This read must be dispatched safely, following the same thread contract as the existing `capturedClipContent(trackID:lengthSteps:)` call.

### Playback during audition

The engine needs to know whether to drive a track from its live generator chain or from the pseudo-clip `noteGrid`. This should be a lightweight runtime flag on the engine, not a document change.

Conceptual flag: `auditionPseudoClip: PseudoClipState?` on the engine or a relevant controller. When non-nil for a given track, the engine plays the pseudo-clip's note-grid instead of running the generator.

This flag is cleared when the modal closes. It must never propagate to the document.

## Persistence Boundaries

| What | Persisted? | When |
|------|-----------|------|
| Rolling capture buffer | No | Memory only; cleared on transport stop |
| Pseudo-clip state | No | Modal session only; discarded on close |
| Pattern slot assignment | Yes | Only on explicit user save action |
| New clip content | Yes | Created in the document at save time via existing `saveRollingCapture` API |

The save action is the only moment anything crosses from transient to persisted. Audition, length changes, and region selection are all pre-persistence operations.

Migration concerns: none from persisting new document types. The feature creates standard clips in existing pattern slots. No new document schema is needed.

## Risks and Unknowns

1. **Buffer size change is a required precondition.** Raising the capture buffer from 64 to 256+ steps may have performance or memory implications that are not yet assessed. The spec must treat this as a prerequisite engineering task, not an incidental detail.

2. **Pseudo-clip audition and live generator run on the same track.** The engine needs a clean, tested way to suppress the generator and substitute the pseudo-clip for a given track during audition. If this requires broad changes to the playback dispatch path, the cost could exceed the UX surface area. The implementation must verify that this can be done as a thin runtime override rather than a new code path.

3. **Materialization on a scrub boundary.** If the user is changing the history window start position (scrubbing), the pseudo-clip's `noteGrid` must rematerialize efficiently. If rematerialization is expensive, the UI will need to debounce or defer. This is an unknown until the buffer read cost is measured.

4. **Empty and partial history states.** The modal may open when the buffer contains fewer steps than the requested window (transport just started, or history was cleared). The engine returns no `ClipContent` in this case. The modal must handle this explicitly; it is not safe to assume the buffer is always full.

5. **Overwrite semantics are unresolved.** User story 6 requires that overwrite of an occupied slot is explicit. The current `saveRollingCapture` API does not enforce this. Whether the modal shows a confirmation prompt or prevents saving over occupied slots needs a product decision before spec. This is a blocker for the save-flow spec.

6. **Modifier chain inclusion scope.** The existing-state report notes that capture stores resolved note events after the modifier chain. This should be confirmed against the actual `capturedClipContent` implementation before the spec states it as a fact.

## Non-Goals (Architectural Level)

- Persisting the rolling capture buffer to disk. Clip history is a live-session convenience, not a project artifact.
- Exposing history from tracks that do not have an active generator. The feature is generator-track scoped.
- Capturing parameter automation, pitch-bend, or non-note events in the first pass.
- Creating a new document model type for "virtual clips" that would require schema migration.
- Surfacing clip history outside the generator-view entry point in the first version.
- Any changes to how the document stores or identifies pattern slots.

## Architecture Questions That Must Be Answered Before Spec

1. Can the engine expose a stable, thread-safe way to set and clear a per-track pseudo-clip audition override without touching the document? What is the minimal interface?
2. What is the performance cost of materializing a 256-step note-grid from the capture buffer on demand?
3. Is the overwrite-occupied-slot policy a confirmation prompt, a lock that requires explicit unlock, or silent overwrite? (Product decision, not implementation.)
4. Should the modal show the history region selector as a scrollable or paginated view of all 16 bars, or as a fixed window the user positions? (UX detail that affects the pseudo-clip start-step selection model.)
