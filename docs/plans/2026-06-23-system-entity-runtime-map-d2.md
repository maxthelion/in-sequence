# System Entity And Runtime Ownership Map Plan

**Status:** Completed 2026-06-23. Shipped D2 diagram sources, rendered SVG
artifacts, runtime ownership manifest, render/check scripts, ownership lint, and
wiki links. No production behavior changes in this slice.

**Context:** The current timing work showed that we need a better shared map of
which data structures are persisted document truth, which are UI/session state,
which are compiled playback buffers, and which are touched by the sequencer or
audio paths. The existing wiki page `wiki/pages/system-entity-diagrams.md` and
rendered `docs/diagrams/system-entity-model.svg` are a good start, but the
diagram source is not reproducible, not ownership-annotated, and not checked for
staleness.

**Goal:** Establish a lightweight, reproducible diagram and ownership-audit
workflow using D2 as the primary source format, with generated SVG artifacts and
repo checks that make runtime-boundary drift visible.

## Why D2

D2 is a good default for this job because the source is plain text, diffable,
and friendlier than hand-maintained SVG for entity and data-flow diagrams. It is
also better suited than Mermaid for larger system maps with repeated styling,
containers, legends, and edge labels.

Mermaid remains useful for small inline wiki sketches. The canonical diagrams
for system ownership should be D2 source files checked into the repo, rendered to
SVG for browsing.

## Questions The Maps Must Answer

- What entities exist in the persisted `.seqai` document?
- Which fields are identifiers, references, pools, or owned child objects?
- What authored state is compiled into `PlaybackSnapshot`, `PhrasePlaybackBuffer`,
  `TrackSourceProgram`, `ClipBuffer`, and related hot-path structures?
- Which code reads or mutates each structure: UI, session, snapshot compiler,
  sequencer tick, dispatch, audio graph, render/tap callbacks, persistence, or
  diagnostics?
- Which structures are allowed in realtime-adjacent paths?
- Which route/send/sample/slicer objects cross between document, runtime graph,
  cache, and UI?

## Proposed Files

```
docs/diagrams/
  README.md
  system-entity-model.svg
  runtime-ownership-map.svg
  playback-snapshot-path.svg
  audio-graph-routing-map.svg

docs/diagrams/src/
  system-entity-model.d2
  runtime-ownership-map.d2
  playback-snapshot-path.d2
  audio-graph-routing-map.d2
  styles.d2

docs/architecture/
  runtime-ownership-manifest.yml

scripts/diagrams/
  render-d2.sh
  check-d2-rendered.sh

scripts/diagnostics/
  runtime-ownership-lint.sh
```

`docs/diagrams/src/*.d2` are the editable source of truth. Generated SVGs are
reviewable artifacts, not hand-edited diagrams.

`runtime-ownership-manifest.yml` is a small structured index that labels major
types/files by owner, lifetime, and hot-path access. The first version should be
manual and intentionally compact; generated extraction can come later.

## Ownership Vocabulary

Every important node in the runtime maps should carry these labels, either in
the D2 text or in the manifest:

- `lifetime`: persisted, session, compiled-snapshot, runtime, cache, diagnostic
- `owner`: document, live-store, session, engine, audio, UI, app
- `read_by`: UI, session, compiler, tick, dispatch, audio-graph, render-callback,
  diagnostics, persistence
- `mutated_by`: UI, session, compiler, tick, dispatch, audio-graph, persistence
- `thread`: main, tick-clock, audio-engine-main, render/tap-callback, background
- `realtime_class`: safe-hot-read, realtime-adjacent, main-only, structural-edit,
  forbidden-hot-path

The labels should be boring and mechanical. The point is not a beautiful
diagram; the point is that a reviewer can see when a performance-time path is
about to touch the wrong owner.

## Initial Diagrams

### 1. Persisted Entity Model

Replace the current hand-rendered entity SVG with D2 source covering:

- `Project`
- tracks and track groups
- pattern banks and source refs
- clip, generator, and slice pools
- phrases, phrase layers, and phrase cells
- routes, mixer busses, send busses, master bus state
- sample/drum-kit/slicer references

This diagram answers: "what is saved, what owns what, and which IDs reference
other pools?"

### 2. Runtime Ownership Map

Create a cross-boundary map with bands:

- SwiftUI views
- `SequencerDocumentSession`
- `LiveSequencerStore`
- snapshot compiler
- `PlaybackSnapshot` and buffers
- `EngineController` tick/dispatch
- `SamplePlaybackEngine`, slicer playback, AU hosts, mixer/send graph
- `DevActivity` and timing probes

This diagram answers: "which side of the UI/runtime/audio boundary owns this
piece?"

### 3. Playback Snapshot Path

Convert the current wiki Mermaid playback path into D2 and annotate hot-path
reads:

```
LiveSequencerStoreState
  -> SequencerSnapshotCompiler
  -> PlaybackSnapshot
  -> PhrasePlaybackBuffer / TrackSourceProgram / ClipBuffer
  -> EngineController.prepareTick
  -> EventQueue
  -> dispatch sinks
```

This diagram answers: "what does the sequencer tick read, and what must it not
read?"

### 4. Audio Graph Routing Map

Create a focused map for the current failure class:

- sample asset cache
- prepared sample assets
- sample voice pools
- track mixer/filter nodes
- mixer busses
- send busses/effects
- master/final output mixers
- meter taps
- route/send mutation paths

This diagram answers: "what can disconnect a sample player or force graph
repair, and which UI actions can trigger that?"

## Render Tooling

`scripts/diagrams/render-d2.sh` should:

- fail with a clear install message if `d2` is not installed;
- render every `docs/diagrams/src/*.d2` file to `docs/diagrams/*.svg`;
- preserve stable output paths so wiki/docs links do not churn;
- avoid network access.

Example local install guidance should live in `docs/diagrams/README.md`, not in
random plan prose. The script should not install tools automatically.

`scripts/diagrams/check-d2-rendered.sh` should:

- render diagrams into a temporary directory;
- diff against checked-in SVGs;
- fail if source and rendered artifacts diverge;
- print the exact render command needed to refresh.

The first version may be advisory if `d2` is missing on CI. Once the project
standardizes the toolchain, CI should require it.

## Runtime Ownership Lint

The ownership lint should start simple and explicit. It is not a substitute for
review, but it should catch obvious drift.

Initial checks:

- Hot tick files must not import `SwiftUI` or `AppKit`.
- `Sources/Audio` render/tap callback code must not call document/session APIs.
- `EngineController.processTick`, `prepareTick`, and dispatch helpers must not
  read `Project` or call broad document export/apply paths.
- Sample/slicer trigger paths must not call file IO APIs except through prepared
  cache/warmup seams.
- Realtime-allow comments must include a named justification and a test/doc
  reference.
- Types listed as `main-only` in the ownership manifest must not be referenced
  from listed tick/render callback files.

This can begin as an `rg`-based script, then move to SwiftSyntax or SourceKitten
if the string checks become noisy.

## Plan Of Work

1. Create `docs/diagrams/README.md`.
   - Explain D2 as source, SVG as generated artifact, and when Mermaid is still
     acceptable.
   - Document local render and check commands.

2. Add D2 source for the existing entity model.
   - Port the current wiki Mermaid/entity content into
     `docs/diagrams/src/system-entity-model.d2`.
   - Keep the existing visual content but add ownership/lifetime labels.
   - Render `docs/diagrams/system-entity-model.svg`.

3. Add runtime ownership manifest.
   - Start with the known core types and files:
     `Project`, `LiveSequencerStoreState`, `SequencerDocumentSession`,
     `PlaybackSnapshot`, `PhrasePlaybackBuffer`, `TrackSourceProgram`,
     `ClipBuffer`, `EngineController`, `TickClock`, `EventQueue`,
     `SampleAssetCache`, `PreparedSampleAsset`, `SamplePlaybackEngine`,
     `MainAudioGraph`, meter publishers, mixer/send bus hosts.
   - Keep the first manifest small enough to review in one sitting.

4. Add `runtime-ownership-map.d2`.
   - Use bands for UI, session, live store, snapshot, tick/dispatch, audio graph,
     cache, and diagnostics.
   - Color by realtime class, not by feature area.

5. Add `playback-snapshot-path.d2`.
   - Convert the existing playback data path into a diagram with hot-read
     labels.
   - Mark forbidden back-edges such as tick -> document export or
     dispatch -> SwiftUI.

6. Add `audio-graph-routing-map.d2`.
   - Focus on sample/drum-kit/slicer routing, mixer busses, send effects, meter
     taps, and graph repair.
   - Explicitly mark route/send actions that are structural graph mutations
     versus performance-time scalar updates.

7. Add render/check scripts.
   - `render-d2.sh` renders all diagrams.
   - `check-d2-rendered.sh` verifies committed SVGs match D2 source.
   - Scripts should be deterministic and quiet when successful.

8. Add `runtime-ownership-lint.sh`.
   - Start with targeted `rg` checks aligned to the manifest.
   - Make output actionable: file, line, violated boundary, suggested owner.
   - Wire into local diagnostics, not mandatory CI, until false positives are
     under control.

9. Update wiki references.
   - Point `wiki/pages/system-entity-diagrams.md` at the D2 source files and SVG
     artifacts.
   - Link `wiki/pages/playback-data-path.md`,
     `wiki/pages/engine-architecture.md`, and
     `wiki/pages/architecture-guardrails.md` to the ownership map.

10. Use the maps on the current timing/audio work.
    - Annotate the sample cache / prepared playback / graph repair path.
    - Confirm the map makes the current failure obvious: per-trigger sample
      dispatch must not enqueue unbounded main-thread graph repair.

## Acceptance Criteria

- All canonical diagrams have checked-in D2 source and generated SVG output.
- `scripts/diagrams/check-d2-rendered.sh` fails when a D2 source change is not
  rendered.
- `runtime-ownership-manifest.yml` covers the current playback and sample/audio
  structures touched by timing work.
- `runtime-ownership-lint.sh` catches at least one seeded forbidden boundary in
  a fixture or documented dry-run case.
- Wiki pages link to the generated diagrams and explain which diagram answers
  which question.
- The audio-graph routing map identifies send-effect route mutation, prepared
  sample player pools, and graph repair as distinct nodes.
- The diagrams make it clear that hot tick/sample/slicer dispatch reads
  prepared runtime/cache data, not document/UI state.

## Verification Commands

Once D2 is installed:

```sh
scripts/diagrams/render-d2.sh
scripts/diagrams/check-d2-rendered.sh
scripts/diagnostics/runtime-ownership-lint.sh
```

For the current timing bug work, also run:

```sh
scripts/diagnostics/realtime-path-lint.sh
scripts/diagnostics/timing-probe-report.sh <captured unified log>
```

## Deliberately Deferred

- Fully automatic Swift type graph extraction. Manual D2 plus a small manifest
  gets us useful understanding faster.
- A custom in-app architecture viewer.
- CI hard-failure on missing D2 until the tool is available in the standard
  developer/agent environment.
- Replacing existing wiki Mermaid snippets that are small and readable.
