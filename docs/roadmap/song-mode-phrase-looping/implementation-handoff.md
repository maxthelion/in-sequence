---
status: accepted
stage: implementation-handoff
updated: 2026-06-04
source:
  - docs/roadmap/song-mode-phrase-looping/prototype-approval.md
  - docs/roadmap/song-mode-phrase-looping/architecture.md
  - docs/roadmap/song-mode-phrase-looping/spec.md
  - docs/roadmap/song-mode-phrase-looping/plan.md
---

# Song Mode And Phrase Looping Implementation Handoff

## Builder Contract

Implement the accepted free-play phrase-navigation workflow only:

- transport current phrase display;
- phrase dropdown with separate `Queue` and `Now` actions;
- queued phrase visibility after dropdown dismissal;
- queued phrase promotion at the current phrase cycle boundary;
- immediate phrase switching;
- stopped and invalid-state reconciliation;
- Tracks basis-phrase tracking and edit targeting;
- accessibility and verification required by the accepted spec and plan.

This handoff does not authorize a scripted Song Mode arrangement, Audio Looping
work, MIDI hardware acceptance, Track Perform follow-up, persisted queue
arrangement data, a dedicated queue-cancel control, or transient queued-edit
buffers.

## Accepted Product Basis

Use the accepted artifacts in this directory as the implementation authority:

- `prototype-approval.md`: both prototypes are accepted and complementary.
- `architecture.md`: live phrase-navigation state belongs to `EngineController`;
  queue/current/basis state is runtime performance state, not document
  arrangement data.
- `spec.md`: accepted UX, edge-state, accessibility, and acceptance behavior.
- `plan.md`: accepted implementation sequence and verification coverage.

The build should preserve the README intent: performers can turn a loop into
arrangement material while keeping live edits coordinated with the phrase they
are hearing or preparing.

## Build-Time Read First

Before product code changes, do the Phase 0 verification from `plan.md` and
record the findings in build-loop evidence:

- confirm `prepareTick` still resolves playback from
  `playbackSnapshot.selectedPhraseID` or the current equivalent;
- identify the active phrase-cycle boundary and the mutation point for queued
  promotion;
- confirm no existing queue/current/basis state has already been added;
- confirm `PlaybackSnapshot` can stay free of MVP queue/current/basis fields;
- confirm `TransportBar` still has no phrase indicator/dropdown;
- confirm the Tracks basis read path and the existing top-right `Basis Phrase`
  pill that must remain the canonical MVP surface.

If current code materially disagrees with those assumptions, stop and write
build-loop evidence before broadening the implementation.

## Engine State And Actions

Add narrow live performance state to `EngineController`:

- `currentPhraseID`: phrase currently used by the tick engine;
- `queuedPhraseID`: phrase selected to begin on the next current-phrase cycle;
- `basisPhraseID`: phrase the Tracks UI should display and edit;
- a phrase-cycle offset such as `phraseCycleStartTick`.

Use existing engine publication and clock-safety patterns. SwiftUI may observe
stable main-thread state, but tick selection and cycle-boundary promotion must
not race UI mutations.

Required engine actions:

- queue a valid phrase for the next cycle;
- switch to a valid phrase immediately;
- reconcile current, queued, and basis IDs against available phrases;
- clear queue state on stop.

Queueing must set `queuedPhraseID` and `basisPhraseID`, replace any prior
queue, leave `currentPhraseID` and audible playback unchanged, and avoid
mutating `Project.selectedPhraseID` or `LiveSequencerStoreState.selectedPhraseID`.

Immediate switch must set `currentPhraseID`, clear `queuedPhraseID`, set
`basisPhraseID`, reset phrase-local cycle position to zero, and invalidate or
replace already-prepared work if needed so the next audible tick uses the target
phrase.

## Tick Boundary Promotion

The tick engine owns the musical boundary. Resolve playback from valid
`currentPhraseID` first, falling back to the snapshot selected phrase only when
live state is unset or invalid.

Compute phrase-local step from the active phrase-cycle offset:

```text
localStep = (upcomingStep - phraseCycleStartTick) % currentPhrase.stepCount
```

When the final local step of the current phrase completes and the queued phrase
is valid, promote atomically:

- `currentPhraseID = queuedPhraseID`;
- `queuedPhraseID = nil`;
- `basisPhraseID = currentPhraseID`;
- reset phrase-cycle offset so the promoted phrase begins at local step zero.

If the queued phrase is invalid at the boundary, clear the queue and keep the
current valid phrase playing. The transport current phrase, queue indicator,
Tracks basis phrase, and audible phrase must update as one coherent transition.

## Stopped And Invalid-State Reconciliation

Reconcile live phrase-navigation state on playback start, document apply,
snapshot install, phrase deletion, and state reload:

- invalid current phrase falls back to selected phrase, then first available
  phrase if the existing UI already uses that fallback;
- invalid queued phrase is cleared;
- invalid basis phrase falls back to current phrase while playing and selected
  phrase while stopped;
- no-phrase state uses existing empty-state behavior without crashing.

Stopping playback clears `queuedPhraseID`, disables queueing, and lets Tracks
basis resolve back to selected phrase when no valid live basis remains.

## Transport UI

Wire the accepted transport prototype into `TransportBar` using native app
controls and tokens.

Required behavior:

- while playing with a valid current phrase, show compact current phrase
  identity and per-bar cycle progress;
- when stopped or empty, show the existing stopped/empty treatment;
- expose a phrase dropdown listing all valid phrases by existing names;
- each phrase row has separately focusable `Queue` and `Now` actions;
- current and queued rows are visibly marked without relying only on color;
- `Queue` and `Now` dismiss the dropdown after successful action;
- outside tap and Escape dismiss without changing phrase state;
- queue controls are disabled while stopped with accessibility help explaining
  queueing is available during playback.

Queued phrase state remains visible after the dropdown closes. Long current and
queued names must truncate with a stable trailing ellipsis, avoid overlapping
neighboring transport controls, and expose full names through the app's
accessibility/help convention.

Preserve crowded-layout priority:

1. play/stop and transport safety controls;
2. current phrase identity;
3. queued phrase presence;
4. full queued phrase name;
5. secondary copy such as "at end of cycle".

## Tracks Basis And Edit Targeting

The existing top-right `Basis Phrase` pill is the canonical MVP basis surface.
Do not require a new inline grid basis cue.

In free-play navigation, Tracks basis resolution is:

1. valid `EngineController.basisPhraseID`;
2. selected phrase from the document/session store;
3. first available phrase only if the existing UI already uses that fallback.

Queueing a phrase immediately changes the Tracks basis phrase. Edits made while
the queued phrase is the basis write directly to that queued phrase. Replacing
the queue or clearing it through `Now` does not undo those edits.

When basis changes to a phrase with a different bar or step count, rerender the
grid to the target phrase's real size, preserve vertical track position where
possible, and reset horizontal step/bar scroll to the beginning unless existing
grid behavior has a stronger local rule.

## Likely Product Code Touch Points

Confirm exact paths during Phase 0. Expected areas are:

| Area | Likely files | Build reason |
| --- | --- | --- |
| Engine runtime state | `Sources/Engine/EngineController.swift` | Own live current, queued, basis, cycle offset, queue actions, immediate switch, promotion, stopped reconciliation |
| Snapshot boundary | `Sources/Engine/PlaybackSnapshot.swift`, `Sources/Engine/SequencerSnapshotCompiler.swift` or current equivalents | Confirm no MVP queue/current/basis field is added; change only for compile compatibility if the code shape requires it |
| Transport UI | `Sources/UI/TransportBar.swift` | Current phrase display, queue control, dropdown, `Queue`/`Now`, accessibility |
| Tracks basis | `Sources/UI/TracksMatrixView.swift`, `Sources/UI/LiveWorkspaceView.swift` | Prefer valid engine basis for free-play editing and update basis pill/edit target |
| Phrase display helpers | `Sources/UI/PhraseWorkspaceView.swift` or a shared helper if needed | Avoid duplicated view-side phrase identity becoming free-play source of truth |
| Engine tests | `Tests/SequencerAITests/Engine/*` | Runtime transition, boundary, reconciliation, and snapshot-boundary coverage |
| UI/session tests | `Tests/SequencerAITests/*` | Tracks basis targeting and transport/dropdown behavior where supported |

Product code changes outside these areas need written build-loop evidence.

## Required Verification

Engine and model coverage must prove:

- current phrase initializes from selected phrase on start;
- queueing sets queued and basis IDs without changing current phrase;
- queue replacement uses the latest queued target;
- queued phrase promotes exactly at the current phrase cycle boundary;
- immediate switch clears queue and starts target phrase at local step zero;
- stopping playback disables queueing and clears queued state;
- invalid current, queued, and basis IDs reconcile safely;
- no MVP queue/current/basis field is added to `PlaybackSnapshot`.

Tracks and session coverage must prove:

- Tracks basis prefers valid engine basis state in free-play navigation;
- queued-basis edits target the queued phrase immediately after queueing;
- switching to a different-length basis phrase rerenders without stale edit
  targeting or layout breakage.

Transport UI and accessibility verification must prove:

- dropdown opens from keyboard focus using Space or Return;
- Escape closes without changing phrase state;
- each row's `Queue` and `Now` actions are separately focusable;
- focus order follows current transport phrase control, phrase rows in order,
  `Queue`, then `Now`;
- accessible labels include current phrase, queued phrase if any, and action
  consequence;
- current, queued, and immediate-switch states are not communicated by color
  alone;
- long phrase labels truncate without overlap and expose full names through
  accessibility/help surfaces;
- dropdown dismissal works for `Queue`, `Now`, outside tap, and Escape.

Manual or screenshot evidence should cover crowded transport layout and Tracks
basis changes, because the product risk is user-facing coordination during live
performance.

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

## Promotion Note

This accepted handoff closes the PM implementation-handoff gap. It does not
create or promote a build loop. Promotion, if appropriate, remains a later
coordinator decision.
