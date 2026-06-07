---
feature: step-order
created: 2026-06-06
status: architecture-accepted
sources:
  - README.md
  - docs/roadmap/step-order/notes.md
  - docs/roadmap/step-order/user-stories.md
  - docs/roadmap/step-order/existing-state.md
  - docs/roadmap/step-order/ux-review.md
  - docs/roadmap/step-order/prototypes/step-order-wireframe.html
---

# Step Order Open Questions

Step Order is a non-destructive playback-resolution override. It remaps the
output phrase step to a source step through a selectable 16-step lookup so a
performer can repeat, reorder, or skip existing material without editing the
clip or generator data that produced it.

This file records the product and architecture questions carried forward from
the accepted UX review and current-state inventory. The paired architecture
artifact accepts conservative v1 defaults, so no product-owner lock is required
for the next spec pass.

## Summary

- Architecture-answerable gaps accepted: 5
- Product defaults accepted: 4
- Product-owner lock needed now: no
- Ready for build-loop promotion: no

The accepted UX evidence and architecture are enough for `spec.md`. The lane is
not implementation-ready until spec, plan, and handoff artifacts define the
UI, persistence, compiler, engine, and regression-test details.

## Architecture-Answerable Gaps

### A1 - Assignment Scope

**Accepted architecture decision for spec.**

V1 assigns one active step-order map to a phrase. When enabled, that phrase's
playback resolves source steps through the map for every playable track in the
phrase.

Track-level opt-in/out is deferred. The existing-state report found that
phrase+track enablement is feasible, but the accepted UX review also found the
per-track toggle affordance incomplete. A phrase-only v1 keeps assignment
visible and avoids implementing an underspecified track-toggle workflow.

Project-level and layer-level scopes remain future options. The v1 UI should
show `Phrase` as the active scope and avoid presenting project/layer/track
scope controls as adjustable production controls.

### A2 - Map Pool Ownership

**Accepted architecture decision for spec.**

Step-order maps live in a top-level named project pool, not as anonymous
phrase-local arrays.

Accepted direction:

- each map has a stable ID, name, and exactly 16 source-step values;
- phrases store an assignment to a map ID plus enabled/disabled state;
- deleting a map that is assigned to any phrase is blocked or requires an
  explicit reassignment flow;
- project save/load round-trips the pool and phrase assignments.

Reason:

The raw intent asks for a selectable modification, the user stories ask for
named saveable maps that can be recalled, and the accepted UX review endorses a
named persistent pool model. Phrase-local anonymous storage would make reuse
and map picking harder than the approved workflow requires.

### A3 - Playback Boundary

**Accepted architecture decision for spec.**

The map is applied at playback resolution, after the sequential phrase step is
known and before the source step is read. It must not mutate clip steps,
generated source definitions, pattern cells, or phrase layer authoring data.

The accepted insertion point is the compiled playback snapshot path, around
`PlaybackSnapshot.resolvedStep`, where the engine currently normalizes
`stepInPhrase` before reading the active pattern/source step. The compiler
should pre-resolve assigned map IDs into engine-safe arrays; the tick path must
not consult SwiftUI state or the live document model.

### A4 - Pending Toggle Propagation

**Accepted architecture decision for spec.**

Live enable/disable changes apply at the next phrase boundary. The UI should
show a concrete pending state immediately after the performer requests the
change and clear that pending state when the engine confirms the boundary
application.

Accepted direction:

- UI sends a command to arm enable/disable for the current phrase;
- engine/session state records the pending requested value and phrase ID;
- boundary application installs the new enabled state into the playback path;
- UI observes an explicit pending/applied state rather than inferring it from
  map contents alone.

The exact event API can be local to the implementation, but the spec must make
the pending affordance testable.

### A5 - Fixed 16-Step Limit

**Accepted architecture decision for spec.**

V1 maps are exactly 16 entries, and each value is a source step in `0...15`.
Variable-length maps are deferred.

The spec should encode this in validation, persistence, the editor grid, and
engine compilation. If a phrase is not compatible with 16-step playback in v1,
the UI should prevent assignment or the compiler should treat the assignment as
inactive with a visible unavailable state. Do not silently modulo arbitrary
phrase lengths into a 16-step map as the first implementation.

## Product Defaults Accepted

### Q1 - Map Assignment Flow

**Accepted v1 default.**

Assignment is available from the map picker/list and from the active-map
control in the editor. A user can choose a named map and assign it to the
current phrase without leaving the Step Order workflow.

Reason:

The UX review identified missing assignment as the largest story gap. Keeping
assignment inside the Step Order map workflow is the smallest route that makes
the map recall story complete without requiring a broader Phrase Workspace
redesign.

### Q2 - Scope Surface

**Accepted v1 default.**

Show `Phrase` as the fixed v1 scope. Do not expose adjustable Project, Layer,
or Phrase/Track tabs as active controls until those scopes have accepted UX and
architecture.

The UI may label the scope as phrase-level so the performer understands the
blast radius. It should not imply per-track control exists in v1.

### Q3 - Identity And Empty Maps

**Accepted v1 default.**

New maps may start as the identity sequence `[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]`.
The editor should label identity maps as pass-through or no remap so the user
can distinguish an enabled identity map from an intentional variation.

There is no separate empty map state in v1. Reset to identity is sufficient.

### Q4 - Toggle Persistence

**Accepted v1 default.**

The assigned map and enabled state are persisted phrase settings. Live pending
state is runtime-only and is not persisted.

Reason:

The user stories require recalling maps across sessions. Persisting assignment
and enabled state gives saved projects deterministic playback while keeping
boundary-pending performance state out of the document.

## Deferred

- Per-track step-order enablement or assignment.
- Project-wide step-order maps that apply across all phrases automatically.
- Layer-level step-order automation and stacked map transformations.
- Variable-length maps.
- Map transforms that add notes instead of only remapping source indexes.
- Sharing UI/data structures with Note Repeat.

## Product-Owner Attention

No product-owner question is required for the next spec pass.

The accepted architecture resolves assignment scope as phrase-only v1 and map
ownership as a top-level named project pool. If later PM work wants per-track
enablement or project-wide scope in v1, that should be a new product decision
and likely a UX rework, not an implementation assumption.
