# Modifier Chain Placement - Implementation Handoff

## Feature

- **ID:** 9
- **Title:** Modifier Chain Placement
- **Status:** `inventory`
- **Stage:** `ready-for-build-queue`
- **Source directory:** `docs/roadmap/modifier-chain-placement/`

---

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [plan.md](plan.md) | First build document to read. It sequences the work into verification, document-layer changes, UI refactor, and tests. |
| [spec.md](spec.md) | Primary product contract. Use this when there is any ambiguity about behavior, acceptance criteria, or non-goals. |
| [architecture.md](architecture.md) | Slot-scoped data and UI guardrails. Read before touching source or modifier mutation paths. |
| [architecture-review.md](architecture-review.md) | Accepted review of the architecture pass. Highlights risks around empty-source behavior, modifier semantics, and picker structure. |
| [existing-state.md](existing-state.md) | Current code reality: bank-level helpers, missing remove-clip mutation, generator-only picker, and current test gaps. |
| [user-stories.md](user-stories.md) | User intent and acceptance signals behind the feature. |
| [ux-review.md](ux-review.md) | Accepted UX direction for the slot-well model. |
| [prototype-approval.md](prototype-approval.md) | User approval and the progressive-disclosure note that the final implementation must preserve. |
| [prototypes/modifier-chain-placement-slot-well.html](prototypes/modifier-chain-placement-slot-well.html) | Selected prototype for layout and interaction reference. |
| [notes.md](notes.md) | Original user language and the raw product concern that triggered the roadmap item. |

The implementation loop should consume this handoff first, then follow the
links above in the order shown unless a plan phase points somewhere more
specific.

---

## Goal

Refactor `TrackSourceEditorView` so the selected pattern slot exposes source and
modifier editing through two persistent slot-well tabs instead of the current
"Switch To Generator Source" flow and generator-only sheet. The slot wells must
make the selected slot's state legible at a glance, allow explicit empty-source
state, keep the common clip-to-generator swap fast, and keep all source and
modifier edits scoped to the selected slot only.

---

## Chosen Product Direction

The accepted direction keeps `Source` and `Modifier` as persistent tabs with
state badges, but turns each tab body into a compact well that summarizes the
current slot content and exposes the relevant actions. Removing a source leaves
the slot in an explicit empty state rather than auto-opening a picker or
creating a replacement clip. From that empty state, `[+] Add Source` opens a
contained picker inside the track editor with progressive disclosure: the first
level shows grouped Generator and Clip actions, with `New Blank Generator` as
the visually primary fast path, while pool browsing expands only when the user
asks for it. The modifier well uses the same shell and in-context picker model,
with modifier-specific compatibility rules and an explicit unavailable state on
track types that cannot host modifiers.

---

## Guardrails The Implementer Must Preserve

1. `TrackPatternSlot.sourceRef` remains the single source of truth for source
   mode, clip assignment, generator assignment, modifier assignment, and
   modifier bypass state.
2. Every action in this feature targets the currently selected pattern slot
   only. Do not use bank-wide source helpers as the implementation path for the
   slot wells.
3. An explicit empty source is represented by existing model state:
   `mode == .clip` and `clipID == nil`. Removing a source must not auto-create a
   blank clip.
4. Modifier actions must not create source material implicitly. An empty source
   slot may still carry a modifier and remain silent until a source is added.
5. Unsupported modifier track types must render an explicit unavailable state,
   not a hidden well and not a misleading enabled add action.
6. The engine playback contract is unchanged. `TrackSourceProgram` and snapshot
   compilation continue to read `SourceRef`; no engine redesign is part of this
   feature.
7. Treat `attachedGeneratorID` as legacy compatibility detail only. Do not let
   it drive selected-slot editing or silently fan changes out to sibling slots.

---

## Implementation Read Order

1. Read this handoff.
2. Read [plan.md](plan.md) and execute in phase order.
3. Use [spec.md](spec.md) as the product contract for behavior and acceptance
   criteria.
4. Use [architecture.md](architecture.md) and
   [architecture-review.md](architecture-review.md) as hard guardrails around
   slot scope, empty-source semantics, picker behavior, and legacy helper
   boundaries.
5. Read [existing-state.md](existing-state.md) before changing document helpers
   or reusing any current picker component.

Do not reopen product decisions that are already settled in the spec. If code
reality conflicts with the approved product direction, capture that as an
implementation finding and keep the behavior within the documented guardrails.

---

## Build Sequence

Follow the plan's three phases:

1. **Phase 0 - verification**
   Confirm current extraction seams in `TrackSourceEditorView`, confirm legacy
   bank-level helper side effects, and confirm the current picker/test coverage
   gaps before writing code.
2. **Phase 1 - slot-scoped document mutations**
   Add or narrow document helpers so source and modifier actions operate on the
   selected slot only, then lock them down with regression tests.
3. **Phase 2 - slot-well UI**
   Replace the current source/modifier editor flows with the approved source and
   modifier wells, contained pickers, explicit empty states, and the minimum
   practical UI coverage.

---

## Files And Modules Expected To Change

| Area | Expected work |
|---|---|
| `Sources/Document/Project+TrackSources.swift` | Slot-scoped source helpers and any required narrowing around legacy generator helpers |
| `Sources/UI/TrackSource/TrackSourceEditorView.swift` | Replace the current source/modifier flows with slot-well structure |
| `Sources/UI/TrackSource/` new focused subviews | Source well, modifier well, and contained picker surfaces |
| `Tests/**` covering track-source document behavior | Regression coverage for empty source, selected-slot-only writes, and modifier semantics |
| `Tests/**` covering track-source UI state, if practical | Badges, empty states, picker cancel behavior, and modifier-on-empty-source expectations |

No engine rewrite, persistence migration, wiki work, or `docs/specs/**` /
`docs/plans/**` output belongs in this build.

---

## Acceptance Focus

The implementation is ready to ship to review only when these outcomes are
observable:

- Removing a clip or generator affects only the selected slot and leaves a
  stable explicit empty state.
- `[+] Add Source` exposes the four high-level source actions without leaving
  the track editor.
- `New Blank Generator` is the fast-path recovery action from an empty source.
- Source and modifier tabs both show current-state badges even when not
  selected.
- Modifier add/remove/bypass behavior remains slot-scoped and never creates a
  clip implicitly.
- Empty pool branches and unsupported modifier tracks have explicit UI states
  instead of disappearing controls.

See [spec.md](spec.md) Section 6 for the full acceptance criteria.

---

## Non-Goals And Deferred Follow-Ups

- No multi-stage modifier chain. This remains a single post-source modifier
  slot.
- No "apply to all slots" editing affordances in this feature.
- No general-purpose library workspace redesign.
- No document-shape redesign beyond using the already-supported explicit
  empty-source state.
- No broad cleanup of unrelated track-source architecture unless Phase 0 proves
  a narrow change is required for correctness.

---

## Open Questions

There are no user-blocking product questions left for this item.

Phase 0 in [plan.md](plan.md) intentionally leaves a few implementation findings
to verify in code before edits begin:

- the safest extraction seams inside `TrackSourceEditorView`
- any remaining `attachedGeneratorID` compatibility coupling
- whether picker work should adapt or replace the existing generator-only sheet
- the lightest practical test surfaces for the new UI states

These are implementation checks, not reasons to relitigate the PM direction.

