---
feature: send-effects
created: 2026-05-03
status: draft
based_on:
  - docs/roadmap/send-effects/user-stories.md
  - docs/roadmap/send-effects/existing-state.md
  - docs/roadmap/send-effects/ux-review.md
  - docs/roadmap/send-effects/prototype-approval.md
  - docs/roadmap/send-effects/decisions.md
  - docs/roadmap/send-effects/architecture.md
  - docs/roadmap/send-effects/architecture-review.md
  - docs/roadmap/send-effects/prototypes/01-mixer-send-knobs.html
  - docs/roadmap/send-effects/prototypes/02-send-bus-insert-chain.html
  - docs/roadmap/send-effects/prototypes/03-signal-flow-overview.html
---

# Send Effects - Specification

## Overview

Send Effects adds two fixed wet buses, `Send A` and `Send B`, to the shared
mixer lane. Each track gets independent send amounts for both buses. Each send
bus gets a global insert chain whose processed return is mixed back into the
main output automatically. The approved UX direction is a composite:

- per-track send controls from `01-mixer-send-knobs.html`
- send-bus insert editing from `02-send-bus-insert-chain.html`
- signal-flow rules from `03-signal-flow-overview.html` as planning guidance
  only, not as a shipped screen

This feature is additive. It does not redesign playback, document ownership, or
the existing master-bus architecture. It extends the current mixer and
audio-graph model with fixed send lanes that behave like ordinary shared effect
returns.

---

## 1. Product Direction

### 1.1 Fixed send lanes in the shared mixer surface

`Send A` and `Send B` are always present. The user does not create, rename, or
delete them in v1.

They live in the same shared mixer workspace targeted by Mixer Main Out and
Mixer Busses. Send Effects must extend that shared lane model rather than
creating a second bus workspace or a standalone send screen.

### 1.2 Per-track send controls stay on the track strip

Each track strip exposes two independent send controls:

- `Send A`
- `Send B`

Each control edits only that track's value for that bus. Adjusting one track's
send amount must never change any other track's send values.

The control may use a compact knob or similarly small continuous control, but
it must satisfy the approved UX properties:

- zero and non-zero states are visually distinguishable
- the edited bus and track are explicit while adjusting
- the control remains in the mixer lane instead of navigating away

### 1.3 Send-bus effect editing uses a bus-detail surface

Selecting `Send A` or `Send B` exposes an effect-chain editor for that bus.
That editor supports:

- add effect
- reorder effects
- bypass effect
- remove effect

The editor must show an explicit empty state when a bus has no inserts.

### 1.4 Auto-return is informational, not user-routable

The send return is automatic. The user does not choose a destination for
`Send A` or `Send B` in v1. The UI may label the behavior as returning to
master output automatically, but it does not expose a routing switch.

### 1.5 No production signal-flow screen

`03-signal-flow-overview.html` is a planning artifact only. It informs the spec
and implementation but does not define a new production workspace or user
screen.

---

## 2. Settled Decisions

The following decisions are fixed by `decisions.md`, `prototype-approval.md`,
and `architecture-review.md`.

### 2.1 Global send-bus inserts

Each send bus has one global insert chain in v1. Insert chains are not scene
scoped.

### 2.2 Return path goes to `finalOutputMixer`

The wet return from each send bus connects to `finalOutputMixer`, so send
returns bypass master-bus inserts.

This avoids re-processing reverb and delay tails through master compression,
limiting, or EQ and matches the approved product direction.

### 2.3 Muted tracks do not feed sends

In v1, muting a track removes both dry and wet contribution from that track.
The send tap therefore behaves as post-mute and post-fader.

### 2.4 Pre/post-fader routing is deferred

There is no per-send or per-track pre/post-fader toggle in this feature.
Post-fader send behavior is the only supported mode in v1.

---

## 3. Data Model And Persistence

### 3.1 Track send values live with track mix settings

Per-track send amounts are authored document state. The persisted track model
must store:

- `sendA: Double`
- `sendB: Double`

These values belong with the track's mix state and persist across save/reload.
They default to `0.0` when loading older documents.

Allowed range is `0.0...1.0`. Writes clamp to that range.

### 3.2 Project owns two fixed send-bus states

The document persists two send-bus states on `Project`:

- `sendBusA`
- `sendBusB`

Each bus owns:

- stable fixed identity
- fixed display name (`Send A` / `Send B`)
- one insert chain

The send buses are not user-extensible in v1.

### 3.3 Insert semantics must stay structurally shared

Send-bus inserts must use the same effect semantics as the master bus and mixer
busses: enabled/disabled state, ordering, AU/native effect identity, and any
persisted preset payload.

The implementation may rename or extract the existing master-bus insert type,
or it may adapt it behind a shared abstraction, but it must not create a third
divergent insert schema with different behavior for sends.

### 3.4 Transient runtime objects are not persisted

The following are runtime-only and must never be saved in the document:

- per-track send gain nodes
- send summing mixers
- send return mixers
- send-bus host objects
- editor selection state or picker visibility state

---

## 4. Runtime And Ownership Contract

### 4.1 Track-level fan-out is the required topology

Each track's post-fader output fans out to:

- the existing dry destination (`preMasterMixer`)
- the `Send A` gain node
- the `Send B` gain node

This fan-out occurs at the track level, not after tracks are already summed.

### 4.2 Send infrastructure is always installed for the session

`Send A` and `Send B` are fixed lanes, so the engine installs their runtime
infrastructure for the session as part of graph setup rather than creating or
destroying send wiring when a user turns a knob from zero to non-zero.

Tracks with zero send values still have send-path nodes available; they simply
contribute silence because the send gain is zero.

### 4.3 Send amount changes are parameter changes, not graph rewires

Changing `sendA` or `sendB` on a track must update runtime gain only. It must
not stop or rebuild the engine graph.

### 4.4 Send insert-chain changes use the central graph coordinator

Changing a send bus insert chain may require graph rebuild work. That rebuild
must be coordinated through the same central owner that already handles
master-bus graph restart concerns.

Send-bus code must not stop and restart the engine in isolation.

### 4.5 No UI-only playback truth

The mixer UI reads authored send values from the document model and writes
through the document/session mutation path. It must not maintain an independent
send-level source of truth that can drift from persisted state.

---

## 5. Mutation Contract

### 5.1 One canonical path for track send changes

This feature reuses the track-mix mutation path rather than introducing a
second overlapping delta channel.

The canonical authored state is widened track mix data, and engine propagation
must continue to flow through the existing track-mix change contract. The send
feature must not add a separate `trackSendChanged` path that duplicates
ownership of the same values.

### 5.2 Track send writes

When the user edits a send amount:

1. the session clamps and persists `sendA` / `sendB`
2. the project emits the normal track-mix change for that track
3. the engine applies the new send gains for that track only

No other track's send state changes as a side effect.

### 5.3 Send-bus insert writes

When the user edits a send-bus chain:

1. the session persists the new insert-chain state for `Send A` or `Send B`
2. the project emits the bus change through the bus-host mutation path
3. the engine rebuilds the affected send-bus chain through the central graph
   coordinator

Editing `Send A` must not touch `Send B`, and vice versa.

---

## 6. UI Contract

### 6.1 Track-strip send controls

The track strip must show two continuous controls labeled clearly for `A` and
`B`. The UI must make these states obvious:

- zero send
- non-zero send
- current numeric or percentage value while editing
- which track and which send are being edited

The approved prototype uses compact knobs plus an in-place popover slider.
Implementation may adapt the exact control so long as the information and
interaction contract remains intact.

### 6.2 Fixed send-bus presence

The mixer surface must always show `Send A` and `Send B` as fixed bus lanes or
selectors. They are not conditional on whether any track currently routes to
them.

### 6.3 Insert-chain editor behavior

For each send bus, the effect editor must support:

- explicit empty state with add affordance
- visible ordered list when inserts exist
- bypass state that is visible at a glance
- remove affordance per insert
- reorder affordance that matches the project's broader bus-insert editing
  pattern

If AU plugin browsing is not yet shared with the master/bus editor path, the
send feature may use the same placeholder or staged effect-picking mechanism as
the broader mixer work. It must not invent a send-specific effect taxonomy.

### 6.4 Return-path communication

The UI should communicate that send output returns automatically to the main
mix, but it must not imply that the user can redirect it somewhere else in v1.

### 6.5 Cohesion with the shared mixer lane

Send Effects must not fork visual patterns away from Mixer Main Out or Mixer
Busses. Send-specific UI should feel like a fixed specialization of the same
lane system, not a separate tool.

---

## 7. Acceptance Criteria

The feature is correct when all of the following are true:

1. Every track can store independent `Send A` and `Send B` values.
2. Changing one track's send value does not affect any other track.
3. Send values persist across save/reload and older documents load with both
   sends at zero.
4. With a non-zero send amount and an audible effect on that send bus, the wet
   return is audible in the main output.
5. Muting a track removes both its dry and wet contribution.
6. `Send A` and `Send B` each expose a global insert chain with add, bypass,
   remove, and reorder behavior.
7. Editing `Send A` never changes `Send B`, and vice versa.
8. Send returns route to `finalOutputMixer`, not back through master inserts.
9. The mixer UI keeps send editing inside the shared mixer workflow; no
   standalone send-routing screen is introduced.

---

## 8. Non-Goals

- User-created or user-renamed send buses
- More than two fixed send buses
- Pre-fader send mode or pre/post toggles
- User-routable send returns
- A dedicated signal-flow screen in production UI
- A second send-specific insert model that diverges from master/bus semantics

