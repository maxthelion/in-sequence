# Incremental Snapshot Compilation Remediation

> **Remediates:** [2026-04-24-incremental-snapshot-compilation.md](./2026-04-24-incremental-snapshot-compilation.md)
>
> **Driven by:** [2026-04-25-adversarial-review-incremental-snapshot-compilation.md](../reviews/2026-04-25-adversarial-review-incremental-snapshot-compilation.md)

## Summary

The first incremental snapshot compilation slice improved the simple clip-edit path but left four plan-level gaps:

- selected-track-only phrase-grid taps can still install redundant snapshots because `setSelectedPhraseAndTrackID` always seeds `.selectedPhrase`
- `.track(id)` invalidation replaces only `tracks`, leaving derived track programs and phrase buffers stale for macro-shaped track edits
- composite batch writers default to `.full`, so many paths still rebuild the whole snapshot
- the oracle test matrix covers too few mutation shapes to prove incremental correctness

This remediation plan completes the original guardrails without changing the broader live-store architecture.

## Guardrails

- Correctness beats narrowness. Any mutation shape that cannot be classified precisely falls back to `.full`.
- Playback-inert selection changes must not call `engineController.apply(playbackSnapshot:)` and must not clear the event queue.
- Every non-inert `SnapshotChange` used in production has at least one full-compile oracle test.
- `.track(id)` must be either safe for all generic track mutations or replaced by narrower change descriptors with explicit caller routing.
- Composite batch paths must name their invalidation. Silent `.full` defaults are allowed only for explicitly structural operations.
- `StepGridTapLatencyTests` remains a performance gate, but the oracle matrix is the correctness gate.

## Phase 1: Fix Selection Inertness

**Goal:** selecting a track in the already-selected phrase is store-only; selecting a different phrase updates snapshot metadata once.

Implementation:

- Change `setSelectedPhraseAndTrackID(phraseID:trackID:)` so it computes whether the phrase and track IDs actually changed before dispatching.
- Avoid `batch(changed: .selectedPhrase)` for combined selection. Either perform the two store writes and dispatch the computed change, or add a small helper that builds a `SnapshotChange` from before/after selection values.
- Keep `setSelectedTrackID` playback-inert.
- Keep `setSelectedPhraseID` as `.selectedPhrase` only when the selected phrase actually changes.

Tests:

- `PlaybackInertSelectionTests`
  - selected-track-only change does not call `apply(playbackSnapshot:)`
  - selected-track-only change does not clear `eventQueue`
  - combined selection with unchanged phrase and changed track is playback-inert
  - combined selection with changed phrase installs exactly one snapshot
- Phrase-grid tap regression:
  - boolean cell tap in the currently selected phrase installs one snapshot for the phrase-cell mutation, not one for selection plus one for the cell

Acceptance:

- Existing selection UI still updates selected track and phrase.
- No redundant playback snapshot install occurs for selected-track-only phrase-grid taps.

## Phase 2: Make Track Invalidation Correct

**Goal:** incremental `.track` output equals a full compile for every track edit the current API can express.

Implementation option A, conservative:

- Keep `SnapshotChange.track(id)`.
- Rebuild the affected `TrackSourceProgram` for every `.track(id)`.
- Rebuild every phrase buffer for `.track(id)` because phrase buffers derive macro-binding order and defaults from track programs.
- Preserve clip buffers, generator pool, clip pool, and unaffected scalar metadata.

Implementation option B, narrower:

- Split `SnapshotChange.track(id)` into explicit variants, for example:
  - `.trackMetadata(id)` for name and other playback-inert UI metadata
  - `.trackPlayback(id)` for pitches, velocity, gate, destination/filter fields carried on `tracks`
  - `.trackMacroShape(id)` for macro binding/default changes, which rebuilds program plus phrase buffers
- Update every caller to choose a precise variant.

Recommendation:

- Start with option A. It is wider but correct, small, and still much cheaper than a full snapshot rebuild on the reference project.
- Add option B only after tests show `.track` is a real hot-path cost.

Tests:

- `IncrementalCompileEquivalenceTests`
  - track name change equals full compile
  - track velocity/gate/pitches change equals full compile
  - track macro binding add/remove equals full compile
  - track macro default change equals full compile
- Reuse assertions:
  - `.track(id)` reuses unrelated clip buffers
  - `.track(id)` reuses generator pool data

Acceptance:

- No stale `TrackSourceProgram` or `PhrasePlaybackBuffer` survives a track macro-shaped edit.
- All `.track` oracle cases pass.

## Phase 3: Make Batch Invalidation Explicit

**Goal:** composite mutations publish one snapshot with the narrowest safe invalidation.

Implementation:

- Remove the silent `.full` default from `batch`, or rename it to make broad invalidation obvious, such as `batchFullRebuild`.
- Add an explicit `changed:` argument at every `batch` call site.
- Route known composite writers:
  - `setPatternSourceRef` existing clip switch: `.patternBank(trackID)`
  - `setPatternSourceRef` with newly created clip: `.full` unless clip-pool structural insertion gets a safe narrow descriptor
  - `setEditedDestination` and MIDI destination edits: `.full` through `.fullEngineApply`
  - `applyMacroDiff`: `.full` until macro/layer/phrase invalidation is decomposed safely
  - `writeStateBlob`: `.track(runtimeTrackID)` or wider if group destination updates affect multiple tracks
  - `ensureClipAndMutate`: `.full` when it can create a clip; `.clip(id)` plus `.patternBank(trackID)` when the clip already exists
- Add comments only where the invalidation is intentionally wider than the written fields.

Tests:

- `SessionPublishUsesIncrementalPathTests`
  - `mutateClip` publishes `.clip`
  - `mutatePhrase` publishes `.phrase`
  - `mutatePatternBank` publishes `.patternBank`
  - `setPatternSourceRef` existing clip does not full rebuild
  - structural batch still full rebuilds
- `SessionBatchHelperTests`
  - batches still publish exactly once
  - batch with explicit `.selectedTrack` and no playback changes does not publish

Acceptance:

- No production `batch(impact:)` call relies on an implicit `.full`.
- Composite hot paths are narrow where the dependency shape is known.

## Phase 4: Complete the Oracle Matrix

**Goal:** the tests prove that incremental compile is a semantics-preserving optimization, not just a fast path for one gesture.

Add or expand:

- `IncrementalCompileEquivalenceTests`
  - clip content edit
  - phrase cell edit
  - pattern-bank slot edit
  - generator param edit
  - track metadata/playback/macro edit
  - selected phrase edit
  - layers edit
  - bulk clip + phrase + pattern-bank edit
  - full fallback for structural changes
- `ReferenceReuseTests`
  - unaffected clip buffers reuse/equal previous values
  - unaffected phrase buffers reuse/equal previous values
  - unaffected track programs reuse/equal previous values
- `FullRebuildFallbackTests`
  - ambiguous structural changes call the full path
- `LayersChangeRebuildsAllPhraseBuffersTests`
  - layers rebuild phrase buffers and reuse clip buffers / track programs

Fixtures:

- one minimal single-track project
- one multi-track, multi-phrase reference project
- one macro-heavy project with AU macro bindings and clip macro overrides

Acceptance:

- Every `SnapshotChange` field has at least one oracle test.
- The test names describe the mutation shape and the expected rebuild/reuse boundary.

## Phase 5: Re-run Performance and Document the Boundary

**Goal:** keep the original performance win while making the wider invalidation choices explicit.

Verification:

- Run `StepGridTapLatencyTests`.
- Run the full `IncrementalCompileEquivalenceTests` suite.
- Run session routing tests that spy on snapshot/full compile call counts.
- If `.track(id)` conservative invalidation exceeds the one-frame budget in real UI gestures, write a follow-up plan for narrower track-change descriptors.

Documentation:

- Update [2026-04-24-incremental-snapshot-compilation.md](./2026-04-24-incremental-snapshot-compilation.md) or the wiki with the final invalidation table.
- Record which mutation shapes intentionally fall back to full rebuild.

## Done Criteria

- The four adversarial findings are fixed or explicitly narrowed with tests.
- No selected-track-only gesture installs a playback snapshot.
- `.track` incremental compile matches full compile for macro-shaped changes.
- Composite batches no longer hide broad rebuilds behind a default argument.
- The oracle matrix covers all production `SnapshotChange` shapes.
- `xcodebuild test` passes.

