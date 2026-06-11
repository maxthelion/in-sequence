---
status: accepted
accepted: 2026-06-04
source:
  - docs/roadmap/song-mode-phrase-looping/user-stories.md
  - docs/roadmap/song-mode-phrase-looping/existing-state.md
  - docs/roadmap/song-mode-phrase-looping/open-questions.md
  - docs/roadmap/song-mode-phrase-looping/prototype-approval.md
---

# Song Mode And Phrase Looping Architecture

## Scope

This feature adds free-play phrase navigation for live performance. It covers:

- a transport-level current phrase indicator;
- a queue for the next phrase;
- end-of-cycle promotion of the queued phrase;
- immediate phrase switching from the phrase dropdown;
- Tracks UI basis-phrase tracking for the current or queued phrase.

It does not build a scripted linear song arrangement. The existing `.song`
transport mode remains an adjacent, underbuilt auto-cycle behavior. This
architecture treats the approved stories as free-play behavior over the current
phrase-looping engine.

## Product Basis

The accepted basis is the pair of approved prototypes:

- `prototypes/01-transport-phrase-indicator.html` defines the transport
  current/queue/immediate-switch workflow.
- `prototypes/02-tracks-basis-phrase-tracking.html` defines the basis-phrase
  tracking rule: queuing a phrase immediately makes it the Tracks UI basis
  phrase, and switching confirms that phrase as current.

The existing Tracks UI `Basis Phrase` pill is the canonical MVP surface for
basis state. The spec may add the prototype's inline basis cue if layout allows,
but implementation must at least update the existing pill and edit target.

## State Ownership

`EngineController` owns live phrase-navigation state because the state is
performance runtime, not saved arrangement data:

- `currentPhraseID`: phrase currently used by the tick engine for playback.
- `queuedPhraseID`: phrase selected to begin on the next current-phrase cycle.
- `basisPhraseID`: phrase the Tracks UI should display and edit.
- `phraseCycleStartTick` or equivalent runtime offset: the tick index that makes
  the active phrase's local step start at zero after start, immediate switch, or
  queued promotion.

These values are observable as `private(set)` engine state for SwiftUI. The
clock path must keep a clock-safe copy or mutation point so `prepareTick` can
select the correct phrase without racing main-thread UI writes. UI publication
continues to use the existing `publishToMain` pattern.

`Project.selectedPhraseID` and `LiveSequencerStoreState.selectedPhraseID`
remain document/editor selection. They are not the queue and are not the source
of truth for free-play current phrase once playback is running. On engine
startup, document apply, or snapshot install, the engine should reconcile live
phrase-navigation state against the available phrase IDs and fall back to
`selectedPhraseID` if the current/basis/queued IDs no longer exist.

## Playback Snapshot Boundary

Do not add queue state to `PlaybackSnapshot` for MVP. The snapshot already
contains `phraseBuffersByID`, which gives the engine all phrase buffers needed
to switch playback by phrase ID. Queue/current/basis state is live transport
state and does not need to participate in document snapshot compilation.

`prepareTick` should resolve the playback phrase from live `currentPhraseID`
first, falling back to `playbackSnapshot.selectedPhraseID` only when live state
is unset or invalid. It then computes phrase-local step from the current phrase's
cycle offset:

```text
localStep = (upcomingStep - phraseCycleStartTick) % currentPhrase.stepCount
```

This avoids using the global transport tick modulo directly, which would make
immediate switches jump into the middle of the new phrase instead of starting
the new cycle cleanly.

## State Transitions

### Start

When playback starts, initialize `currentPhraseID` from the selected phrase if
no valid current phrase exists. Set `basisPhraseID` to the current phrase unless
a valid queue already defines the basis. Set the phrase cycle offset so the
first prepared step is local step zero.

### Queue Phrase

Queueing a phrase in free-play mode:

- sets `queuedPhraseID` to the selected target;
- sets `basisPhraseID` to the queued target immediately;
- does not interrupt the current phrase;
- does not mutate `Project.selectedPhraseID`;
- replaces any previously queued phrase.

No standalone queue-clear/cancel control is required for MVP. A queued phrase
can be replaced by choosing another queued target or cleared by an immediate
switch.

### End-Of-Cycle Promotion

The tick engine owns the musical boundary. When the final local step of the
current phrase completes and `queuedPhraseID` is valid, the engine promotes it:

- `currentPhraseID = queuedPhraseID`;
- `queuedPhraseID = nil`;
- `basisPhraseID = currentPhraseID`;
- the phrase cycle offset resets so the promoted phrase begins at local step
  zero on the next tick.

Promotion should be atomic from the UI's perspective: the transport current
phrase, queue indicator, Tracks UI basis phrase, and audible phrase must update
as one coherent transition.

### Immediate Switch

Immediate switch from the dropdown:

- sets `currentPhraseID` to the target phrase immediately;
- clears `queuedPhraseID`;
- sets `basisPhraseID` to the target phrase;
- resets the phrase cycle offset so playback jumps to local step zero;
- invalidates any already-prepared next tick if needed so the next audible tick
  uses the new phrase.

This is also the MVP path for clearing an in-flight queue without adding a
separate cancel affordance.

### Queued-Basis Editing

When a queued phrase becomes the Tracks UI basis, edits made in Tracks land
immediately in that queued phrase. There is no transient preview buffer or
staging layer in MVP.

This is an explicit product default, not an accidental implementation detail.
If a performer queues Phrase C, edits Phrase C, and later replaces the queue,
the Phrase C edits remain. The spec must make this behavior visible enough to
avoid data surprise, but architecture does not introduce staging because the
approved stories require the grid to become the real edit target for the queued
phrase.

## View Integration

`TransportBar` should read the engine's phrase-navigation state and phrase names
from the document session/store. It should render:

- current phrase from `currentPhraseID`;
- queued phrase from `queuedPhraseID`;
- disabled or empty state when no valid current phrase can be resolved;
- a phrase dropdown with separate queue and immediate-switch actions.

`TracksMatrixView` and `LiveWorkspaceView` should resolve editing/basis phrase
from `engineController.basisPhraseID` in free-play navigation when valid, then
fall back to `session.store.selectedPhraseID`. This replaces the current
view-side dependence on `.song` auto-cycle derivation for the free-play story.

`PhraseWorkspaceView` may continue showing phrase matrix playback position, but
duplicated phrase-index derivation should not become the source of truth for
free-play current phrase. Shared phrase-playhead helpers may be reused for
display math, while live current/queued/basis identity remains on the engine.

## Testing Requirements

The builder spec/plan should include coverage for:

- engine current phrase initializes from selected phrase on start;
- queueing sets `queuedPhraseID` and `basisPhraseID` without changing audible
  current phrase;
- queued phrase promotes exactly at the current phrase cycle boundary;
- immediate switch clears the queue and starts the target phrase at local step
  zero;
- queue replacement uses the latest queued target;
- invalid queued/current/basis IDs reconcile when phrases are removed or a new
  snapshot/document is applied;
- Tracks UI basis resolution prefers queued/current basis state and sends edits
  to that phrase;
- no `PlaybackSnapshot` queue field is required for the switch path.

## Decisions Made

| ID | Decision |
|----|----------|
| A1 | `currentPhraseID`, `queuedPhraseID`, `basisPhraseID`, and phrase cycle offset are live `EngineController` state. |
| A2 | Queue/current/basis are not persisted document arrangement data and do not mutate `Project.selectedPhraseID` merely by queueing. |
| A3 | Phrase-boundary promotion is emitted by the tick engine at the current phrase's local cycle boundary. |
| A4 | `PlaybackSnapshot` should not carry queued phrase state for MVP; `prepareTick` chooses the live current phrase from existing `phraseBuffersByID`. |
| A5 | Free-play views should consume engine phrase-navigation state instead of duplicating `.song` auto-cycle derivation. |
| A6 | This feature is scoped to free-play phrase navigation and does not implement scripted Song Mode arrangement. |
| A7 | No standalone queue-clear/cancel control is required for MVP. Re-queueing replaces the queue; immediate switch clears it. |
| A8 | Edits made while a queued phrase is the Tracks UI basis land immediately in that phrase. No transient preview buffer is introduced. |

## Left For Spec

- Whether the dropdown dismisses after `Now` and on outside tap.
- Exact disabled/stopped-state copy and affordance for the queue button.
- Cycle progress granularity and visual treatment.
- Long phrase-name truncation in the crowded transport bar.
- Narrow transport layout behavior.
- Whether to add an inline basis cue in addition to the existing `Basis Phrase`
  pill.
- Grid resize/scroll behavior when the basis phrase changes to a phrase with a
  different bar count.
- Exact accessibility labels, focus order, and keyboard behavior for the phrase
  dropdown.

## Readiness

This accepted architecture closes the architecture artifact gap only. The lane
is still not builder-ready until accepted `spec.md`, `plan.md`, and
`implementation-handoff.md` exist.
