# Adversarial Review: Incremental Snapshot Compilation

Reviewed branch: `codex/live-sequencer-store-v2`

Reviewed commit: `d8d3dab` (`perf(sequencer): incremental snapshot compilation on hot edits`)

Plan under review: [2026-04-24-incremental-snapshot-compilation.md](../plans/2026-04-24-incremental-snapshot-compilation.md)

Reviewer stance: deliberately adversarial. This review assumes the clip hot path can look good while adjacent mutation shapes still violate the plan.

## Verdict

The branch lands a real incremental path for simple clip, phrase, pattern-bank, and selected-phrase changes. The single-step clip edit path is plausibly improved.

It is not plan-complete. Selection batching still installs redundant snapshots in the phrase grid, `.track` invalidation can leave derived track programs and phrase buffers stale, composite batches default to full rebuilds, and the equivalence suite is much smaller than the guardrail matrix the plan demanded. The implementation should not be tagged as "incremental snapshot compilation complete" until these are remediated.

## Findings

### 1. [P1] Cell selection still installs a playback snapshot

Location: `Sources/App/SequencerDocumentSession+Mutations.swift:166-170`

`setSelectedPhraseAndTrackID` seeds every batch with `.selectedPhrase`, even when the phrase is already selected and only the track changes. `PhraseWorkspaceView.handleSingleTap` calls this before toggling a boolean cell, so a single tap can first install an identical playback snapshot and clear the event queue, then perform the real cell mutation and install another snapshot.

Why this matters:

- violates the plan's playback-inert selection guardrail
- keeps a hot UI gesture on the engine path
- clears prepared events for no audible state change

Expected remediation:

- classify the combined phrase/track selection from actual state changes, not from the API name
- selected-track-only remains playback-inert
- selected-phrase publishes only when the selected phrase actually changes
- phrase-grid boolean tap performs at most one snapshot install for the actual cell mutation

### 2. [P1] `.track` invalidation leaves derived buffers stale

Location: `Sources/Engine/SequencerSnapshotCompiler.swift:48-97`

The incremental compiler handles `.track(id)` by replacing only `tracks`, but `TrackSourceProgram` is derived from track macros/defaults and `PhrasePlaybackBuffer` is derived from those program macro bindings. The plan explicitly calls out track macro/destination changes as the tricky case requiring program and phrase-buffer rebuilds.

Why this matters:

- a generic `mutateTrack` can change macro bindings while the old `TrackSourceProgram` survives
- phrase buffers can retain the old macro-binding shape and defaults
- incremental compile can diverge from `compile(state:)`

Expected remediation:

- widen `.track(id)` to rebuild the affected `TrackSourceProgram`
- rebuild phrase buffers when track macro bindings or macro defaults can affect phrase macro resolution
- optionally split track invalidation into narrower descriptors if the code can reliably distinguish playback-inert metadata from program-shaped changes
- add oracle tests that fail on the stale-buffer case

### 3. [P2] Batch routing defaults most composite edits to full rebuild

Location: `Sources/App/SequencerDocumentSession+Mutations.swift:57-68`

`batch` defaults `initialChange` to `.full`, and the body receives raw `LiveSequencerStore`, so changes made inside most batches cannot accumulate narrow `SnapshotChange`s. Production paths like `setPatternSourceRef` call `batch(impact:)` without a narrow change, meaning pattern-slot edits use full snapshot rebuilds despite the plan specifying `.patternBank(trackID)` plus clip invalidation only when a clip is created.

Why this matters:

- many composite writer paths keep paying full compile cost
- tests can prove `batch` publishes once but not that it publishes narrowly
- the plan's "batch unions narrow invalidation sets" invariant is not implemented for raw-store batch bodies

Expected remediation:

- require an explicit `SnapshotChange` for `batch`, or add a mutation recorder API that can collect narrow changes from store calls
- update known composite paths to pass the narrowest safe change
- use `.full` only for structural or ambiguous mutations

### 4. [P2] Equivalence tests miss most promised mutation shapes

Location: `Tests/SequencerAITests/Engine/IncrementalCompileEquivalenceTests.swift:7-127`

The plan requires an oracle matrix across track, generator, layers, full fallback, bulk, fixtures, and reference reuse. The committed suite covers only clip, phrase, pattern-bank, and selected-phrase. That is why the stale `.track` case and broad batch fallback can survive while the branch still looks green.

Why this matters:

- the core correctness contract is "incremental equals full compile"
- missing mutation shapes are exactly where hidden dependencies live
- the performance optimization is only safe if the oracle matrix is broad enough

Expected remediation:

- add tests for track macro/default changes, generator changes, layer changes, bulk changes, full fallback, and playback-inert selection
- assert reference reuse where possible
- include at least one larger fixture so accidental full rebuilds and hidden dependencies are visible

## Residual Risk

Even after these fixes, the performance test should be treated as a regression signal rather than a proof of correctness. The correctness proof is the full-compile oracle matrix. The benchmark only proves that one hot gesture fits inside the budget on the reference project.

