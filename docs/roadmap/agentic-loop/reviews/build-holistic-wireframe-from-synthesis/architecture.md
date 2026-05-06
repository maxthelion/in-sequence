---
status: reviewed
verdict: needs-correction
reviewed: 2026-05-06T19:34:30+01:00
source_pass: docs/roadmap/agentic-loop/passes/build-holistic-wireframe-from-synthesis.md
scheduled_follow_up: docs/roadmap/agentic-loop/passes/correct-holistic-wireframe-commit-discard-evidence.md
---

# Architecture Review

## Verdict

The wireframe correctly stays probe-scoped and does not mutate Swift document,
playback, or routing contracts. The fixture also uses useful ownership labels.
Before it becomes the next production source-of-truth shape, the commit/discard
and capture ownership transitions need one more explicit pass.

## What Passed

- The HTML/JS host is disposable and isolated under
  `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/`.
- Fixture state distinguishes document-owned phrase rows, pattern slots, and
  clip history from runtime-session selection/overrides, runtime audio buffer
  state, and audio-graph routing.
- Stable IDs exist for tracks, phrases, clips, the shared buffer, slice cues,
  busses, and returns.
- The result avoids copying lane-probe SwiftUI `@State` into production.

## Findings

### P0 - The transient overlay transition is underspecified

`performanceOverride.owner` is `runtime-session`, while `keepTarget` says it
writes to active phrase cells and scene blend. That is directionally right, but
the fixture does not model the transition as a transaction from session overlay
to authored document/scene state. The UI then makes Keep and Discard identical
visual clears.

The correction should add explicit fixture fields for:

- runtime overlay source owner;
- keep destination owners and labels;
- discard restoration owners and labels;
- post-action state labels for committed versus discarded outcomes.

### P1 - Audio buffer capture needs a sharper owner boundary

`Capture Loop To Shared Buffer` targets `runtime-buffer then document reference`.
That is plausible, but production architecture needs to know what becomes
persisted metadata and what remains runtime audio memory. The correction should
make this a fixture invariant rather than only a label.

### P1 - Mixer route evidence should remain a summary, not a production graph

The route summary usefully carries the Lane C return-style send default, but it
is visual evidence only. The review should not authorize cherry-picking this
HTML route shape into the app's persisted `Route` or audio graph model without a
separate architecture note.

## Agent-Side Outcome

Schedule a correction pass. No user decision is needed: these are ownership and
evidence clarity issues that agents can infer from the context pack, wiki, and
wireframe requirements.
