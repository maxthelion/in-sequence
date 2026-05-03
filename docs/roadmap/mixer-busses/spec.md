---
created: 2026-05-03
stories_covered: [1, 2, 3, 4, 5]
architecture_approved: true
architecture_review: architecture-review.md
prototype_approval: prototype-approval.md
---

# Mixer Busses — Spec

Sources: `user-stories.md`, `ux-review.md`, `prototype-approval.md`,
`decisions.md`, `architecture.md`, `architecture-review.md`, and
`existing-state.md`.

---

## 1. Scope and Non-Goals

This spec covers all five approved user stories for Mixer Busses:

- Story 1: create a new bus from the mixer
- Story 2: route a track's output to a bus or back to master
- Story 3: control each bus with fader, pan, mute, and solo
- Story 4: edit a bus insert chain
- Story 5: name and identify buses distinctly

### Explicitly out of scope

- Bus-to-bus routing or bus chaining
- Parallel track outputs or multi-destination routing
- Scene-scoped user-created bus inserts
- Arrangement-level or clip-level bus visualization
- New effect types or new AudioUnit hosting rules beyond bus-host reuse/extraction
- A second prototype-review loop unless later feedback invalidates the approved mixer lane

---

## 2. Product Direction

The approved direction is the three-zone mixer lane from
`prototype-approval.md`: track strips on the left, bus strips in the middle,
and master out on the right.

The key product decisions are fixed:

- solo is additive across tracks and busses
- user-created bus inserts are global in v1
- deleting a routed bus requires confirmation and reroutes affected tracks to master on confirm
- bus outputs are fixed to master in v1

This feature is a conservative DAW-style routing extension. It adds ordinary
mix busses without introducing scene variants or a second routing paradigm.

---

## 3. What Changes

### 3.1 Persisted document model

Add `buses: [MixerBus]` to `Project`.

Each `MixerBus` persists:

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Stable routing identity |
| `name` | `String` | User-visible, non-empty after normalisation |
| `color` | `String?` | Optional bus colour tag |
| `mix` | `BusMixSettings` | Level, pan, mute, solo |
| `inserts` | `[MixerBusInsert]` | Global bus insert chain |

Add `outputBusID: UUID?` to `StepSequenceTrack`.

- `nil` means route directly to master
- any bus UUID means route through that bus
- older documents decode with `buses == []` and `outputBusID == nil`

### 3.2 Solo-state model

Use one authoritative solo representation:

- add `isSoloed: Bool` to `TrackMixSettings`
- keep `MixerBus.mix.isSoloed` on `BusMixSettings`

Solo state is persisted as authored strip state. Effective mute because of other
active solos remains runtime-derived only.

This keeps document truth explicit while avoiding shadow solo-membership state.

### 3.3 Audio graph

The signal path becomes:

`track -> bus (optional) -> preMasterMixer -> master chain -> final output`

Tracks routed to master continue to connect directly to `preMasterMixer`.
User-created busses always output to `preMasterMixer`. No bus may route to
another bus in v1.

Each bus owns its own mixer node plus insert chain host. Bus creation, deletion,
rerouting, and insert-topology changes are engine stop/restart operations
coordinated through the existing graph owner.

### 3.4 Mixer UI

The mixer surface becomes one coordinated workspace shared with
`[[feature:mixer-main-out]]`.

From left to right:

1. horizontally scrollable track strips
2. fixed bus section
3. fixed master-out column

The bus section uses the approved darker section header and separator treatment
from the prototype so the three zones read immediately as a single signal-flow
surface.

---

## 4. Layout and Presentation

### 4.1 Standard width

At workspace widths `>= 820 pt`, show the full three-zone layout at once.

- track zone: flexible and horizontally scrollable
- bus zone: fixed-width section between tracks and master
- master zone: fixed-width column per `[[feature:mixer-main-out]]`

Bus strip anatomy, top to bottom:

1. output label (`-> Master`)
2. insert chain section
3. fader
4. pan control
5. mute / solo row
6. bus name

The bus section header includes `Busses` and an `Add Bus` button. A trailing
`+ Add Bus` tile also appears at the end of the bus strip row.

### 4.2 Narrow width

At workspace widths `< 820 pt`, keep master-out compact behavior defined by
`[[feature:mixer-main-out]]` and allow the track-plus-bus lane to scroll
horizontally as one combined strip area.

The bus zone does not collapse into a separate modal in v1. It stays in the
same scroll lane so routing context remains visible beside tracks.

### 4.3 Insert-section height

Bus strips use a fixed insert-section height aligned across the whole bus row.

- show up to three insert rows without expanding strip height
- if more than three inserts exist, the section becomes internally scrollable
- empty rows render as dashed affordances when no insert occupies the slot

This preserves a stable row height while still allowing longer chains.

### 4.4 Global versus scene-scoped copy

Because bus inserts are global while master inserts are scene-scoped, the UI
must state that difference directly:

- bus section label: `Inserts`
- master section label: `Inserts (Scene: <name>)`

Scene selection must not change the visible bus insert chain.

---

## 5. Behaviour

### 5.1 Story 1 — Create a new bus

Either `Add Bus` affordance creates a new bus immediately in the bus row.

Creation behavior:

- append the bus to the ordered bus list
- default name: `Bus N`, where `N` is the next visible ordinal
- default mix: unity level, centered pan, unmuted, unsoloed
- default inserts: empty
- default output: master

After creation, the new bus name enters inline edit mode automatically so the
user can rename it without a second discovery step. If the user commits an
empty name, normalise back to the default generated name.

The new bus appears in every track output selector as soon as the graph
rebuild completes.

### 5.2 Story 2 — Route a track's output to a bus

Each track strip exposes an output selector listing:

- `Master`
- every current bus name in display order

Selecting a destination updates document state first, then performs the engine
rewire.

During rerouting:

- the originating track selector is disabled
- the control label reads `Applying...`
- no second routing change may start from that track

On completion, the selector returns to its normal label. No modal or separate
toast is required in v1.

If a bus is renamed, every track output selector updates to the new label
everywhere that bus is referenced.

### 5.3 Story 3 — Bus fader, pan, mute, and solo

Each bus strip exposes:

- a continuous level fader
- a pan control
- `Mute`
- `Solo`

Bus level, pan, mute, and solo are persisted with the session.

Solo behaviour is additive across tracks and busses:

- when no strips are soloed, mute buttons alone determine audible state
- when one or more strips are soloed, every unsoloed strip becomes effectively muted
- a track routed to a soloed bus remains audible through that bus even if the
  track itself is not soloed
- direct-to-master tracks follow the same additive solo rule as bus-routed tracks

The mixer shows a single `SOLO ACTIVE` banner while any solo exists. The banner
provides `Clear Solo`, which clears every track and bus `isSoloed` flag.

Visual dimming of effectively muted strips is derived from runtime solo output,
not persisted state.

### 5.4 Story 4 — Bus inserts

Each bus has one global insert chain used in all scenes.

The bus insert section supports:

- add insert
- bypass / enable insert
- reorder insert
- remove insert

Bypassing an insert must not imply deleting it. Reordering and add/remove remain
topology-changing actions and therefore go through the graph rebuild path.

The bus feature must reuse or extract the current insert-list interaction model
instead of leaving a duplicated divergent insert editor.

### 5.5 Story 5 — Naming and identification

Bus names are editable inline from the strip label.

Rename rules:

- enter rename on bus creation and on explicit rename gesture
- `Enter` commits
- `Escape` cancels
- blur commits the current value
- whitespace-only names normalise to the generated default name

Bus colour is optional metadata in v1. If present, it is shown as a compact
accent on the strip and may also appear in the routing selector row, but colour
must not be the only identifying cue.

### 5.6 Delete bus

Each bus exposes a delete affordance in strip-level actions.

Delete behavior:

- if no tracks route to the bus, delete immediately
- if any tracks route to the bus, show a confirmation prompt
- the prompt lists each affected track by current name
- confirmation copy states that affected tracks will be rerouted to `Master`
- confirm performs reroute-to-master and bus deletion in one coordinated mutation
- cancel leaves routing and the bus unchanged

There is no alternate "choose another bus" flow in v1.

---

## 6. Data and Ownership

### 6.1 Persisted

Persisted authored state:

| Field | Owner | Meaning |
|---|---|---|
| `buses` | `Project` | Ordered user-created mixer busses |
| `buses[].name` | `MixerBus` | Display label used in strip and routing selectors |
| `buses[].color` | `MixerBus` | Optional visual tag |
| `buses[].mix` | `MixerBus` | Bus level, pan, mute, solo |
| `buses[].inserts` | `MixerBus` | Global bus insert chain |
| `tracks[].outputBusID` | `StepSequenceTrack` | Output routing target |
| `tracks[].mix.isSoloed` | `TrackMixSettings` | Authored track solo state |

### 6.2 Transient

Runtime-only state:

| Value | Owner |
|---|---|
| live bus-node map | graph / engine owner |
| per-track rerouting-in-progress flags | mixer runtime owner |
| effective mute state from solo logic | engine controller |
| strip dimming caused by solo | derived UI state |
| rename field focus / presentation state | local UI state |

Effective mute and rewiring indicators must never be persisted into the
document model.

### 6.3 Mutation ownership

All authored changes write through document/session mutations first. Direct view
mutation of graph nodes is not allowed.

The engine / graph owner is responsible for:

- creating and destroying bus hosts
- rewiring tracks to bus or master destinations
- rebuilding bus insert topology
- deriving effective mute from persisted mute + solo state

---

## 7. Implementation Constraints

### 7.1 Graph discipline

- add bus
- delete bus
- reroute track output
- add or remove bus inserts
- reorder bus inserts

All five are coordinated graph-topology mutations and must use the existing
stop / reconnect / restart discipline.

Bus level, pan, mute, and bypass-only changes are parameter updates and should
not trigger a full graph rebuild.

### 7.2 Backward compatibility

The implementation must preserve old `.seqai` documents:

- missing `Project.buses` decodes as `[]`
- missing `StepSequenceTrack.outputBusID` decodes as `nil`
- missing `TrackMixSettings.isSoloed` decodes as `false`

Round-trip coverage is required for both legacy and newly authored documents.

### 7.3 Shared surface and shared insert UI

This feature must not fork the mixer shell from `[[feature:mixer-main-out]]`.
The shared three-zone surface and strip anatomy should be composed once.

Likewise, bus insert editing must come from a shared or extracted insert-list
path rather than a second bespoke editor implementation.

---

## 8. Acceptance Criteria

- Adding a bus inserts a new strip in the bus section and auto-focuses its name field.
- Every track routing selector lists `Master` plus all current bus names.
- Changing a track route shows the approved temporary `Applying...` disabled state.
- Bus fader, pan, mute, and solo affect the audible grouped signal in real time.
- Solo is additive across tracks and busses, with one visible global `SOLO ACTIVE` state.
- A bus insert chain applies to all scenes and does not change with scene selection.
- Renaming a bus updates the strip label and every routing selector reference.
- Deleting a routed bus requires confirmation and reroutes listed tracks to master on confirm.
- Older documents without bus data or solo flags still decode to a valid master-routed state.

---

## 9. Ready-For-Plan Notes

The implementation plan should preserve the following sequencing constraints:

1. establish document-model and codable migration support first
2. add graph-owned bus hosts and routing mutation paths next
3. extract or share insert-list UI rather than duplicating it
4. compose the shared three-zone mixer surface with `[[feature:mixer-main-out]]`
5. finish with solo-state derivation, delete confirmation, and regression coverage
