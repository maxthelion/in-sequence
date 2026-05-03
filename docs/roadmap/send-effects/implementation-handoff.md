# Send Effects - Implementation Handoff

## Feature

- **ID:** 6
- **Title:** Send Effects
- **Status:** `inventory`
- **Stage:** `ready-for-build-queue`
- **Source directory:** `docs/roadmap/send-effects/`

---

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [plan.md](plan.md) | First build document to read. It sequences verification, authored send state, engine topology, mixer UI, and regression coverage. |
| [spec.md](spec.md) | Primary product contract. Use this whenever behavior, acceptance criteria, or non-goals are in doubt. |
| [architecture.md](architecture.md) | Guardrails around persistence, fan-out topology, central rebuild ownership, and shared mixer composition. |
| [architecture-review.md](architecture-review.md) | Accepted architecture verdict. Locks the settled send decisions and the single-delta-path requirement. |
| [existing-state.md](existing-state.md) | Current code reality: no send model, no send hosts, no send taps, and no send controls in the mixer. |
| [user-stories.md](user-stories.md) | User intent and acceptance signals for per-track sends, shared send-bus inserts, and automatic wet returns. |
| [ux-review.md](ux-review.md) | Accepted composite UX direction across the three prototypes. |
| [prototype-approval.md](prototype-approval.md) | User approval and the fixed v1 decisions for insert scope, return path, and mute behavior. |
| [prototypes/01-mixer-send-knobs.html](prototypes/01-mixer-send-knobs.html) | Reference for the per-track send controls in the shared mixer strip. |
| [prototypes/02-send-bus-insert-chain.html](prototypes/02-send-bus-insert-chain.html) | Reference for the send-bus detail and insert-chain editing surface. |
| [prototypes/03-signal-flow-overview.html](prototypes/03-signal-flow-overview.html) | Planning artifact only. Use it to reason about topology, not as a production-screen requirement. |
| [decisions.md](decisions.md) | Settled product decisions the build must not reopen. |
| [notes.md](notes.md) | Original feature framing and cross-links to Mixer Main Out and Mixer Busses. |

The implementation loop should consume this handoff first, then follow the
links above in the order shown unless a plan phase points somewhere more
specific.

---

## Goal

Add two fixed wet-return buses, `Send A` and `Send B`, to the shared mixer so
each track can dial independent send amounts, each send bus can host one global
insert chain, and the processed wet returns blend back into the main output
automatically. This is an additive extension of the current mixer and
audio-graph model, not a routing-system rewrite.

---

## Chosen Product Direction

The approved direction is a composite of the prototype set:

- use the per-track `A` / `B` send controls from
  `01-mixer-send-knobs.html` directly in the mixer strip;
- use the fixed send-bus detail and insert-chain editing treatment from
  `02-send-bus-insert-chain.html`;
- treat `03-signal-flow-overview.html` as a planning artifact only, not a
  shipped screen.

The settled v1 decisions are already made and must be preserved:

- `Send A` and `Send B` each own one global insert chain;
- send returns connect to `finalOutputMixer`;
- muted tracks contribute neither dry nor wet signal;
- send behavior is post-fader in v1;
- the user does not create, rename, or reroute send buses.

Do not reopen those product calls unless later user feedback explicitly
invalidates them.

---

## Guardrails The Implementer Must Preserve

1. `TrackMixSettings` remains the authoritative persisted home for per-track
   send values. `sendA` and `sendB` default to `0.0`, clamp to `0.0...1.0`,
   and load safely from legacy documents.
2. `Project` owns exactly two fixed send-bus authored states. Do not introduce
   user-created, user-renamable, or scene-scoped send buses in v1.
3. Per-track send edits must ride one canonical authored mutation path. Reuse
   the existing track-mix change contract instead of inventing a parallel
   send-only source of truth.
4. Graph ownership stays in the engine / graph layer. Views may author document
   state, but they must not mutate AVAudioEngine topology directly.
5. Track send level changes are parameter writes; send-bus insert edits are
   graph rebuild work under the same central coordinator already responsible
   for master-chain topology changes.
6. The send tap stays on the post-fader, post-mute path so muted tracks produce
   neither dry nor wet output and fader moves scale send contribution in v1.
7. Send returns reconnect to `finalOutputMixer`, bypassing master inserts. Do
   not reroute them through `preMasterMixer`.
8. Reuse or extract shared insert semantics and shared mixer surfaces instead of
   forking a third near-duplicate insert model or a send-only workspace shell.
9. Prototype 03 remains documentation only. Do not ship a separate signal-flow
   screen as part of this feature.

---

## Implementation Read Order

1. Read this handoff.
2. Read [plan.md](plan.md) and execute in phase order.
3. Use [spec.md](spec.md) as the product contract for behavior and acceptance
   criteria.
4. Use [architecture.md](architecture.md) and
   [architecture-review.md](architecture-review.md) as hard guardrails for
   persistence, delta ownership, graph rebuild coordination, and mixer-surface
   reuse.
5. Read [existing-state.md](existing-state.md) before touching document,
   graph, engine, or mixer code.

Do not reopen the settled product decisions in [decisions.md](decisions.md) or
[prototype-approval.md](prototype-approval.md). If current code reality
conflicts with them, capture that as an implementation finding and stay within
the documented guardrails.

---

## Build Sequence

Follow the plan's phases in order:

1. **Phase 0 - verification**
   Confirm the document landing zones, graph-owner seams, and mixer / insert
   reuse seams before editing code.
2. **Phase 1 - authored send state**
   Add persisted per-track send amounts, fixed authored send-bus state, and the
   focused session / delta mutations needed to own them cleanly.
3. **Phase 2 - engine-owned send topology**
   Install the fixed send infrastructure, apply send amounts as lightweight
   parameter changes, and route send-bus insert edits through the central graph
   rebuild coordinator.
4. **Phase 3 - mixer UI**
   Extend the track strip with send controls, add fixed send-bus detail
   surfaces, and keep the entire feature inside the shared mixer information
   architecture.
5. **Phase 4 - regression coverage and verification**
   Add the document, mutation, graph, engine, and focused UI coverage called
   out in the plan, then finish with the limited manual smoke checks that the
   current harness cannot prove end to end.

---

## Files And Modules Expected To Change

| Area | Expected work |
|---|---|
| `Sources/Document/TrackMixSettings.swift`, `StepSequenceTrack.swift`, `Project.swift`, and `Project+Codable.swift` | Add persisted send values and fixed send-bus state with legacy-safe decode defaults |
| `Sources/Document/ProjectDelta.swift` plus the session mutation surface | Keep one canonical change path for track-send updates and express send-bus insert edits cleanly |
| `Sources/Audio/MainAudioGraph.swift`, `AudioInstrumentHost.swift`, `SamplePlaybackEngine.swift`, and new or extracted send-host support | Install track fan-out, fixed send-bus hosts, and wet-return routing |
| `Sources/Audio/MasterBusHost.swift` and `Sources/Engine/EngineController.swift` | Coordinate send-bus rebuilds with the existing master-chain restart discipline and any meter-tap lifecycle |
| `Sources/UI/MixerView.swift`, `Sources/UI/Mixer/MixerWorkspaceView.swift`, and extracted shared insert-editor surfaces | Add per-track send controls and send-bus detail editing without duplicating the mixer shell |
| `Tests/SequencerAITests/**` across document, audio, engine, and focused UI coverage | Prove migration defaults, track fan-out, targeted send updates, send-bus rebuild isolation, and the core mixer states |

No `docs/specs/**`, `docs/plans/**`, wiki pages, or unrelated roadmap items
belong in this build.

---

## Acceptance Focus

The implementation is ready to ship to review only when these outcomes are
observable:

- Every track strip exposes independent `Send A` and `Send B` controls whose
  zero and non-zero states are easy to scan.
- Editing one track's send amount changes only that track's wet contribution and
  persists across save / reload.
- `Send A` and `Send B` each expose one editable insert chain with explicit
  empty states and no duplicate editor surface.
- Wet returns are audible in the main mix through `finalOutputMixer` without
  requiring extra routing choices from the user.
- Muted tracks contribute neither dry nor wet signal.
- Send-bus insert edits rebuild only the affected wet-return chain and stay
  under the central graph-owner discipline.

See [spec.md](spec.md) Section 6 for the full acceptance criteria and
[plan.md](plan.md) for the exact verification and test sequence.

---

## Non-Goals And Deferred Follow-Ups

- No user-created or user-renamable send buses.
- No pre/post-fader toggle in v1.
- No alternate wet-return destination or manual return routing.
- No scene-scoped send-bus inserts.
- No second mixer shell, send-only workspace, or production signal-flow screen.
- No forked insert-effect schema for send buses if the existing semantics can be
  shared or extracted.

---

## Open Questions

There are no user-blocking product questions left for this item.

The remaining checks are implementation findings already called out in
[plan.md](plan.md):

- confirm the exact codable landing zones for `sendA`, `sendB`, and the fixed
  send-bus state;
- confirm whether the existing insert model should be generalized now or
  wrapped behind a narrow send-bus adapter first;
- confirm the lightest extraction path for shared insert-editor and mixer-strip
  surfaces;
- confirm the most practical test files to extend for document, engine, and UI
  coverage.

These are implementation checks, not reasons to relitigate the PM direction.
