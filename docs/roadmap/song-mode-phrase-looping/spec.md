---
status: accepted
stage: implementation-spec
updated: 2026-06-04
source:
  - docs/roadmap/song-mode-phrase-looping/user-stories.md
  - docs/roadmap/song-mode-phrase-looping/existing-state.md
  - docs/roadmap/song-mode-phrase-looping/open-questions.md
  - docs/roadmap/song-mode-phrase-looping/prototype-approval.md
  - docs/roadmap/song-mode-phrase-looping/architecture.md
  - docs/roadmap/song-mode-phrase-looping/ux-review.md
---

# Song Mode And Phrase Looping Spec

## Goal

Add free-play phrase navigation for live performance so a performer can see the
currently playing phrase, queue the next phrase for the next musical cycle,
switch immediately when needed, and edit against the phrase that is current or
cued.

This feature is scoped to the approved free-play workflow. It does not build a
scripted linear song arrangement.

## Product Basis

The accepted design basis is:

- `prototypes/01-transport-phrase-indicator.html` for transport current phrase,
  queue, end-of-cycle promotion, and immediate switch behavior;
- `prototypes/02-tracks-basis-phrase-tracking.html` for Tracks UI basis-phrase
  tracking;
- `architecture.md` for state ownership and engine transition boundaries.

The semantic state vocabulary from the prototypes carries into the build:

- current or active phrase state uses the existing active blue treatment;
- queued or preview phrase state uses the existing warning/amber treatment;
- immediate-switch affordances use the existing destructive/red treatment.

Implementation should map these to the app's native color tokens where they
exist rather than hardcoding prototype hex values.

## V1 Scope

Build the following free-play phrase-navigation behavior:

- transport shows the currently playing phrase while playback is active;
- transport exposes a phrase dropdown for queueing or immediate switching;
- queueing a phrase keeps the current phrase playing until its cycle ends;
- queueing replaces any previous queued phrase;
- the queued phrase remains visible after the dropdown closes;
- the tick engine promotes the queued phrase at the current phrase cycle
  boundary;
- immediate switch jumps to the target phrase immediately and clears any queue;
- Tracks UI basis phrase follows the queued phrase immediately, then follows the
  current phrase after promotion or immediate switch;
- edits made while the Tracks UI is showing a queued basis phrase write directly
  to that queued phrase.

## Non-Goals

- Do not implement a scripted Song Mode arrangement model.
- Do not change the saved project selection merely because a phrase is queued.
- Do not add queue/current/basis state to `PlaybackSnapshot` for MVP.
- Do not add a dedicated queue-cancel button for MVP.
- Do not add a transient preview or staging buffer for queued-basis edits.
- Do not redesign the existing Tracks UI basis panel.
- Do not extend this behavior to the existing `.song` auto-cycle display logic
  unless needed to avoid regressions.

## Runtime State

`EngineController` owns the live phrase-navigation state described in
`architecture.md`:

- `currentPhraseID`: phrase currently used by the tick engine for playback;
- `queuedPhraseID`: phrase selected to begin on the next current-phrase cycle;
- `basisPhraseID`: phrase the Tracks UI should display and edit;
- a phrase cycle offset such as `phraseCycleStartTick`.

These values are runtime performance state. Queueing must not mutate
`Project.selectedPhraseID` or `LiveSequencerStoreState.selectedPhraseID`.

Views may read observable engine state, but free-play phrase identity must not
be re-derived independently in each view from the global transport tick.

## Transport Behavior

### Playing State

While playback is running and a valid current phrase exists, the transport bar
shows:

- a compact "Now" label with the current phrase name;
- a cycle-progress indicator for the current phrase;
- a queue control that opens the phrase dropdown;
- queued phrase state when one exists.

Cycle progress is per bar for MVP. Per-step progress is a later refinement.

### Stopped State

When playback is stopped:

- the current phrase display uses the stopped/empty treatment, for example
  "none" or the existing equivalent empty label;
- the queue control is disabled;
- `queuedPhraseID` is cleared;
- Tracks UI basis resolves back to the selected phrase if no valid live basis
  remains.

The disabled queue control must have an accessibility label or help string that
explains that phrase queueing is available during playback.

### Phrase Dropdown

The dropdown lists all valid phrases using their existing phrase names. Each
row exposes two explicit actions:

- `Queue`: queue this phrase for the next phrase cycle;
- `Now`: switch to this phrase immediately.

The current phrase row is visually marked as current. The queued phrase row is
visually marked as queued. If the same phrase is current and queued is not set,
only the current state is shown.

Selecting `Queue`:

- sets `queuedPhraseID` to the target phrase;
- replaces any previous queue;
- sets `basisPhraseID` to the target phrase immediately;
- leaves `currentPhraseID` and audible playback unchanged;
- dismisses the dropdown.

Selecting `Now`:

- sets `currentPhraseID` to the target phrase immediately;
- clears `queuedPhraseID`;
- sets `basisPhraseID` to the target phrase;
- resets phrase-local cycle position so playback starts the target at local
  step zero;
- dismisses the dropdown.

Tapping outside the dropdown or pressing Escape dismisses it without changing
phrase state.

### Queue Visibility And Long Names

When no phrase is queued, the queue control can use compact copy such as
`Queue`.

When a phrase is queued, the queue control should show the queued phrase name
where space allows, for example `Next: Phrase C`. Long phrase names are
truncated in the control with a stable trailing ellipsis and exposed in full via
accessibility value or tooltip/help text. The dropdown row itself should prefer
showing the full phrase name, truncating only when the row cannot fit.

On narrow or crowded transport layouts, preserve this priority order:

1. play/stop and transport safety controls;
2. current phrase identity;
3. queued phrase presence;
4. full queued phrase name;
5. secondary copy such as "at end of cycle".

If the full queued name cannot fit, show a compact queued-state indicator plus
truncated name. Do not allow transport controls or labels to overlap.

## End-Of-Cycle Promotion

The tick engine owns the musical boundary. When the current phrase completes
its local cycle and `queuedPhraseID` is valid, promotion happens atomically:

- `currentPhraseID` becomes the queued phrase;
- `queuedPhraseID` is cleared;
- `basisPhraseID` becomes the new current phrase;
- the phrase cycle offset resets so the promoted phrase begins at local step
  zero on the next tick;
- transport current phrase, queue indicator, Tracks basis phrase, and audible
  phrase update coherently.

If the queued phrase is no longer valid at the boundary, clear the queue and
continue the current valid phrase.

## Immediate Switch

Immediate switch is the MVP escape hatch for an in-flight queue. It must:

- take effect on the next audible tick possible;
- clear any queued phrase;
- start the target phrase at local step zero;
- update transport and Tracks basis state together.

If the engine has already prepared a next tick using the old phrase, the switch
path must invalidate or replace that pending work so the next audible tick uses
the immediate target.

## Tracks Basis Phrase

The existing top-right `Basis Phrase` pill is the canonical MVP basis surface.
This feature must update that pill and the edit target. A new inline basis cue
inside the grid is not required for MVP.

Basis resolution in free-play navigation is:

1. valid `EngineController.basisPhraseID`;
2. selected phrase from the document/session store;
3. first available phrase as an empty-state fallback, if the existing UI already
   uses that behavior.

Queueing a phrase sets the basis phrase immediately. This means the performer
can edit the queued phrase before it becomes audible. Those edits write directly
to the queued phrase and remain even if the queue is later replaced or cleared
by an immediate switch. This is accepted MVP behavior.

When basis changes to a phrase with a different bar or step count, the Tracks
grid rerenders to the target phrase's actual size. Preserve vertical track
position where possible. Reset horizontal step/bar scroll to the beginning of
the new basis phrase unless the existing grid already has a stronger local
scroll preservation rule. No same-length phrase constraint is allowed for the
feature.

## Reconciliation And Invalid IDs

On playback start, document apply, snapshot install, phrase deletion, or any
state reload:

- invalid `currentPhraseID` falls back to selected phrase, then first available
  phrase if needed;
- invalid `queuedPhraseID` is cleared;
- invalid `basisPhraseID` falls back to current phrase while playing, then
  selected phrase while stopped;
- if no phrase exists, transport and Tracks UI use the existing empty-state
  behavior without crashing.

## Accessibility And Keyboard

The phrase navigation control must be operable without pointer-only behavior:

- the phrase dropdown opens from keyboard focus using Space or Return;
- Escape closes the dropdown without changing phrase state;
- each row's `Queue` and `Now` actions are separately focusable;
- focus order is current transport phrase control, dropdown rows in phrase
  order, each row's `Queue` action, then each row's `Now` action;
- accessible labels include current phrase, queued phrase if any, and action
  consequence, for example "Queue Phrase C for next cycle" and "Switch to
  Phrase C now";
- queued and current state must not be communicated by color alone.

## Acceptance Criteria

- While playback is running in free-play mode, the transport bar shows the
  phrase currently used by the engine.
- The phrase dropdown lists all phrases and exposes separate Queue and Now
  actions per phrase.
- Queueing a phrase does not interrupt the current phrase.
- Queueing a new phrase replaces the prior queued phrase.
- Queued phrase state remains visible after the dropdown closes.
- At the current phrase cycle boundary, the queued phrase becomes current and
  the queue clears.
- Immediate switch clears the queue and starts the target phrase at local step
  zero.
- Tracks UI basis phrase updates immediately on queue, immediate switch, and
  end-of-cycle promotion.
- Tracks edits made while a queued phrase is the basis write to that queued
  phrase.
- Stopping playback clears queue state and disables queueing until playback
  resumes.
- Long phrase names truncate without overlapping neighboring transport controls
  and remain available to accessibility/help surfaces.
- Current, queued, and immediate-switch states are visually distinct and
  accessible without relying only on color.
- No MVP `PlaybackSnapshot` queue field is introduced.

## Testing Requirements

The implementation plan must include coverage for:

- engine current phrase initializes from selected phrase on start;
- stopped transport disables queueing and clears queued state;
- queueing sets `queuedPhraseID` and `basisPhraseID` without changing audible
  current phrase;
- queue replacement uses the latest queued target;
- queued phrase promotes at the current phrase cycle boundary;
- immediate switch clears the queue and starts the target at local step zero;
- invalid current, queued, and basis IDs reconcile safely;
- Tracks basis resolution prefers engine basis state in free-play navigation;
- Tracks edits target the queued basis phrase immediately after queueing;
- phrase-grid rendering handles a basis phrase with a different bar count;
- transport truncation and dropdown labels remain non-overlapping in a crowded
  layout;
- dropdown dismissal works for Queue, Now, outside tap, and Escape;
- no queue/current/basis state is added to `PlaybackSnapshot` for MVP.

## Decisions Made

| ID | Decision |
|----|----------|
| S1 | Queue cancellation in MVP is replacement or immediate-switch clear; there is no standalone cancel control. |
| S2 | `Now` and `Queue` both dismiss the dropdown after a successful action. |
| S3 | Outside tap and Escape dismiss the dropdown without changing phrase state. |
| S4 | Cycle progress is per bar for MVP. |
| S5 | Long phrase names truncate in transport controls and are exposed in full through accessibility/help surfaces. |
| S6 | Queueing while stopped is disabled; stopping clears queued state. |
| S7 | The existing top-right `Basis Phrase` pill is the canonical MVP basis surface. |
| S8 | Queued-basis edits land immediately in the queued phrase and are not staged. |
| S9 | Basis changes may resize the grid to the target phrase's actual bar count; MVP does not require same-length phrases. |
| S10 | Free-play phrase navigation does not add queued phrase state to `PlaybackSnapshot`. |

## Readiness

This accepted spec closes the specification artifact gap for this PM lane. The
lane still needs an accepted `plan.md` and `implementation-handoff.md` before it
is ready for build-loop promotion.
