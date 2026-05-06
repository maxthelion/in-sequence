# Track Performance Overlay Build Plan

> For agentic workers: this is a production build plan. Implement it task by
> task and keep probe branches read-only. Port only the narrow pure model/test
> concepts named here; do not copy probe UI panels or broad project-file churn.

**Status:** Proposed.

**Source pass:** `docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md`

## Goal

Add a transient track-performance overlay that lets a user audition fill,
note-repeat intent, and step-order intent across one or more tracks without
mutating authored project state. The overlay must make live consequences
visible, then let the user explicitly Keep those consequences into authored
phrase/scene state or Discard back to authored playback.

The production shape follows the accepted Happy Accident Workbench default:
performance changes may be runtime-only only when the UI shows what is
transient, what Keep will write, and what Discard will restore.

## Inputs And Current Ownership

- `Project` and `LiveSequencerStoreState` own authored track, layer, phrase,
  source, route, and master-bus state.
- `SequencerSnapshotCompiler` compiles authored state into
  `PlaybackSnapshot`; the hot tick path reads this snapshot, not `Project`.
- `PlaybackSnapshot.resolvedStep(...)` resolves authored pattern slot, mute,
  fill, and macro values for one track at one phrase step.
- `EngineController.prepareTick(...)` reads `currentPlaybackSnapshot`, computes
  `stepInPhrase`, builds a `LayerSnapshot`, calls
  `EngineController.resolvedStepNotes(...)`, and queues prepared notes.
- `LiveWorkspaceView` and `TracksMatrixView` currently write real phrase cells
  through `SequencerDocumentSession.setPhraseCell(...)`.
- `EngineController` already owns an engine/runtime pattern for transient
  master-bus performance state via `masterBusPerformanceOverlay`, with Keep
  performed by `SequencerDocumentSession.saveMasterScenePerformanceOverrides`.
- Probe artifact `3a1d15d:Sources/Engine/TrackPerformanceOverrideLayer.swift`
  is a usable pure value seed. Its UI and `TracksMatrixView` changes are not
  production artifacts.

## Non-Goals

- No broad probe branch cherry-pick.
- No probe-local SwiftUI `@State` model as production ownership.
- No persistent runtime-only overlay field in `Project`.
- No 1/32 or 1/64 sub-step note-repeat scheduling in this P0 slice.
- No new scene or mixer schema beyond writing through existing master-bus
  scene/crossfader APIs when the existing master-bus overlay is active.
- No final Track Perform redesign beyond the minimum visible overlay controls
  and transaction targets.

## Runtime Ownership

Use split ownership:

- `EngineController` owns the runtime `trackPerformanceOverlay` because the
  tick path needs to read it next to `currentPlaybackSnapshot` under the same
  state lock.
- `SequencerDocumentSession` owns the user command API because it can coordinate
  authored phrase writes, scene/mixer Keep, Discard, snapshot publication, and
  eventual document flush.
- UI surfaces call session commands. They may read engine overlay state for
  display, following the existing master-bus perform pattern, but they must not
  mutate probe-local overlay state.

Suggested engine state:

```swift
struct TrackPerformanceOverlay: Equatable, Sendable {
    var trackOverrides: [UUID: TrackPerformanceOverride]
}

struct TrackPerformanceOverride: Equatable, Sendable {
    var fill: Bool?
    var repeatIntent: TrackRepeatIntent?
    var stepOrderIntent: TrackStepOrderIntent?
}

enum TrackRepeatIntent: Equatable, Sendable {
    case stepLocked(capturedStepIndex: Int)
}

enum TrackStepOrderIntent: String, CaseIterable, Equatable, Sendable {
    case forward
    case reverse
    case pingPong
}
```

`forward` is the inactive step-order value and should be compacted out of the
runtime overlay. If the probe model is ported directly, normalize its
`NoteRepeatInterval` cases so only the step-grid behavior is active in P0.
`thirtySecond` and `sixtyFourth` remain deferred until a sub-step scheduler
exists.

## Authored Destinations For Keep

Keep must write to explicit authored destinations and clear the overlay after
the write succeeds.

Track destinations:

- Fill writes the existing `fill-flag` phrase layer for the target tracks in
  the active performance phrase.
- Repeat writes a new authored phrase layer for repeat intent. P0 should add a
  built-in indexed phrase layer such as `repeat-intent` with values:
  `0 = off`, `1 = step-locked repeat`. Do not expose or persist 1/32 or 1/64
  values in P0.
- Step order writes a new authored phrase layer for step-order intent. P0
  should add a built-in indexed phrase layer such as `step-order` with values:
  `0 = forward`, `1 = reverse`, `2 = pingPong`.
- Keep writes `.single(...)` cells for the target tracks unless the UI has
  explicitly selected a narrower bar/step authoring mode. The first P0 UI should
  show this target as "active phrase cells".

Phrase selection:

- In Free transport mode, Keep targets `session.store.selectedPhraseID`.
- In Song transport mode while running, Keep targets the phrase that
  `LiveWorkspaceView` currently treats as the editing phrase: the playing
  phrase derived from transport position.
- If no playing phrase can be resolved, fall back to selected phrase and show
  that fallback in the Keep target label.

Scene/mixer destinations in scope:

- If `masterBusPerformanceOverlay` has scene macro overrides, Keep writes them
  to the owning `MasterBusScene` using the existing session master-scene save
  path, then clears those scene macro overrides.
- If `masterBusPerformanceOverlay.crossfaderOverride` is active and a
  `MasterBusABSelection` exists, Keep writes the crossfader into the authored
  master-bus A/B selection using the existing master-bus mutation path, then
  clears the live crossfader override.
- Track-level Keep must not invent mixer-route writes.

## Discard Restore Owner

`SequencerDocumentSession.discardPerformanceOverlay()` is the restore
coordinator.

Discard behavior:

- Clear `EngineController.trackPerformanceOverlay`.
- Clear `EngineController.masterBusPerformanceOverlay`.
- Invalidate prepared tick output so already-prepared notes cannot leak after
  Discard.
- Re-publish or re-read the current authored snapshot only if needed for UI
  display consistency. Do not rewrite phrase cells, scene cells, mixer state, or
  `Project`.

The authored restore sources are:

- phrase cells and defaults in `LiveSequencerStore`;
- compiled phrase buffers in the next `PlaybackSnapshot`;
- existing `MasterBusState` in `LiveSequencerStore`;
- existing mixer/routing state in `LiveSequencerStore` and `EngineController`'s
  applied document model.

## Command API

Add session-facing commands:

```swift
@MainActor
extension SequencerDocumentSession {
    func setTrackPerformanceFill(_ enabled: Bool?, trackIDs: [UUID])
    func setTrackPerformanceRepeat(_ intent: TrackRepeatIntent?, trackIDs: [UUID])
    func setTrackPerformanceStepOrder(_ intent: TrackStepOrderIntent?, trackIDs: [UUID])
    func clearTrackPerformance(trackIDs: [UUID])
    func clearAllTrackPerformance()
    func keepPerformanceOverlay()
    func discardPerformanceOverlay()
}
```

Add engine-facing commands:

```swift
extension EngineController {
    func setTrackPerformanceFill(_ enabled: Bool?, trackIDs: [UUID])
    func setTrackPerformanceRepeat(_ intent: TrackRepeatIntent?, trackIDs: [UUID])
    func setTrackPerformanceStepOrder(_ intent: TrackStepOrderIntent?, trackIDs: [UUID])
    func clearTrackPerformance(trackIDs: [UUID])
    func clearTrackPerformanceOverlay()
    var hasTrackPerformanceOverlay: Bool { get }
    func trackPerformanceState(for trackID: UUID) -> TrackPerformanceOverride
}
```

Every engine command must normalize stale track IDs against the current
snapshot, compact inactive entries, clear `eventQueue`, and set
`preparedTickIndex = nil`. Overlay command changes must not call
`apply(documentModel:)` or install a new `PlaybackSnapshot`.

## Tick-Path Read Point And Precedence

The read point is inside `EngineController.prepareTick(...)`, in the same
state-lock read that currently captures `currentPlaybackSnapshot`.

Resolution order for one track:

1. Compute the authored phrase step from the selected phrase buffer.
2. Call `PlaybackSnapshot.resolvedStep(...)` for the authored base.
3. Resolve authored repeat and step-order phrase-layer values into the base
   playback step once those layers exist.
4. Apply `trackPerformanceOverlay` above that base:
   - fill override wins over authored fill;
   - step-order override wins over authored step order;
   - active note repeat wins over step order for the source step;
   - mute, pattern slot, phrase macro values, clip-step macro overrides, and
     routing remain authored unless a later plan explicitly adds overlays for
     them.
5. Pass the effective fill and effective source step into source-note
   resolution.

Do not store the overlay inside `PlaybackSnapshot`. The snapshot remains the
authored playback base. The overlay is read after snapshot resolution and before
`GeneratedSourceEvaluator.resolveClipStep(...)`.

`PlaybackSnapshot.layerSnapshot(...)` either needs an overlay-aware companion or
`prepareTick(...)` needs to patch the fill portion of `currentLayerSnapshot`
after reading the overlay. Macro application must continue to use authored
macro values.

## Note Repeat P0 Semantics

P0 note repeat is step-grid repeat only:

- engaging repeat captures the effective source step for each target track on
  the next prepared tick;
- while active, that captured source step is used once per sequencer step;
- releasing or clearing repeat removes the capture and playback rejoins the
  current phrase step;
- repeat applies only when the selected slot resolves to a clip source;
- generator-source repeat is a no-op in P0 unless a later implementation proves
  a safe generator capture contract.

Sub-step intervals are explicitly deferred. The UI must not promise 1/32 or
1/64 playback, and tests must assert that unsupported sub-step intents are not
scheduled as multiple events inside one tick.

## UI Surface Requirements

Minimum P0 surface:

- Track Perform controls in the existing Live or Tracks perform surface for
  selected target tracks: Fill, Repeat, Order, Clear.
- A visible transient-state badge per affected track that distinguishes
  authored phrase state from overlay state.
- A persistent transaction strip when any performance overlay is active:
  - Keep target: active phrase cells, plus scene A/B state when active;
  - Discard target: authored phrase, scene, mixer, and overlay restore point.
- Keep and Discard must produce distinct acknowledgements or visible state
  changes in the UI.
- Controls must still show what is currently sounding: selected track set,
  active phrase, current step, fill/repeat/order overlay labels, and scene
  overlay state if present.

Do not copy `TrackPerformanceOverrideProbePanel`. Use existing production
surfaces and design tokens.

## Implementation Tasks

- [ ] Port a narrow pure `TrackPerformanceOverlay` value model and focused
  tests from `3a1d15d`, renaming away from probe-specific assumptions.
- [ ] Add authored repeat/order phrase-layer definitions and snapshot fields for
  resolved repeat/order intent.
- [ ] Add engine-owned `trackPerformanceOverlay`, normalization, clear, read
  accessors, and prepared-tick invalidation.
- [ ] Add overlay-aware step resolution in `EngineController.resolvedStepNotes`
  without storing overlay data in `PlaybackSnapshot`.
- [ ] Add session command APIs for fill, repeat, order, clear, Keep, and
  Discard.
- [ ] Wire Keep writes for fill, repeat, order, scene macro overrides, and live
  crossfader override.
- [ ] Wire Discard to clear track and master-bus overlays without mutating
  authored state.
- [ ] Add minimal Track Perform UI controls, overlay badges, Keep target label,
  and Discard target label.
- [ ] Add the production tests below.
- [ ] Run `xcodebuild test` with the repo's standard Xcode environment.

## Test Plan

Pure model tests:

- fill override applies to multiple tracks and preserves authored fallback;
- note repeat source-step capture wins over step-order source remapping;
- step-order remaps playhead steps and clearing restores sequential playback;
- clearing one track compacts inactive state and does not affect other tracks;
- clearing all removes the overlay.

Session authority tests:

- applying fill, repeat, or step-order overlay leaves `Project`,
  `LiveSequencerStore.exportToProject()`, and document bindings unchanged until
  Keep;
- applying overlay does not call `apply(documentModel:)` and does not replace
  `PlaybackSnapshot`;
- Keep writes the expected phrase cells for fill, repeat, and step order, then
  clears the track overlay;
- Keep writes active master-bus scene macro and A/B crossfader overrides when
  present, then clears the master-bus overlay;
- Discard clears track and master-bus overlays and leaves authored phrase,
  scene, mixer, and document state unchanged.

Playback tests:

- fill overlay changes clip fill-lane selection above authored
  `PlaybackSnapshot.resolvedStep(...)`;
- authored fill remains effective after Discard;
- reverse and ping-pong step-order intents resolve source steps without
  changing phrase step, mute, pattern slot, or macro values;
- note repeat captures the effective source step and keeps using it while the
  phrase step advances;
- changing or clearing an overlay invalidates already-prepared tick output so
  stale notes do not play on the next tick.

Sub-step limitation tests:

- P0 repeat emits at most one prepared note batch per normal sequencer step;
- 1/32 and 1/64 intents are either not constructible through the production
  command API or return an explicit unsupported/deferred result;
- no UI test or label promises sub-step repeat until a sub-step scheduler plan
  lands.

UI tests:

- Fill, Repeat, Order, Clear, Keep, and Discard controls call session commands,
  not direct phrase-cell mutations from the view;
- overlay badges show active transient state per affected track;
- Keep target label names active phrase cells and scene A/B state when active;
- Discard target label names authored phrase/scene/mixer restore;
- after Keep or Discard, the transaction strip disappears only after the
  relevant overlays are clear.

## Risks And Guardrails

- Prepared tick output can already be queued before a user action. Every overlay
  setter and clearer must clear `eventQueue` and reset `preparedTickIndex`.
- Adding repeat/order phrase layers is an additive document change. Decode
  defaults must preserve older documents.
- Do not fork the tick path around `PlaybackSnapshot`. Add a small
  overlay-aware resolution helper instead.
- Do not use hard-coded 16-step step-order maps as final policy. Step-order
  resolution must respect the resolved clip length or phrase buffer length.
- Keep must be all-or-clear: if any authored write fails to resolve a target
  layer or phrase, leave the overlay active and surface a testable failure
  state rather than silently discarding.

## Follow-Up After This Plan

Run an agent-side UX/IA, architecture, and testing review of this build plan
before Swift implementation. If the review passes, the next build pass should
start with the pure model and tests, then integrate engine/session ownership
before UI.
