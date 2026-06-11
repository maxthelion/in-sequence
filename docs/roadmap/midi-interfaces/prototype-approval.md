---
feature: midi-interfaces
created: 2026-06-03
gate: prototype
verdict: accepted
source_review: docs/roadmap/midi-interfaces/ux-review.md
selected_prototype: composite
prototypes:
  - docs/roadmap/midi-interfaces/prototypes/01-control-surface-settings.html
  - docs/roadmap/midi-interfaces/prototypes/02-phrase-workspace-grid.html
  - docs/roadmap/midi-interfaces/prototypes/03-live-workspace-grid.html
---

# MIDI Interfaces Prototype Approval

## Verdict

Accepted.

The accepted UX review selects the composite direction across all three MIDI
Interfaces prototypes. The later accepted architecture review, v1 spec, phased
plan, and implementation handoff close the prototype caveats for PM readiness.
No further prototype rework or product-owner decision is required before
project-level build-loop promotion consideration.

This approval is PM/readiness evidence only. It does not promote a build loop,
approve production code, or expand v1 beyond `spec.md` and
`implementation-handoff.md`.

## Basis

- `ux-review.md` carries `verdict: accepted` and selects a composite of the
  Settings, Phrase grid, and Live grid prototypes.
- `architecture-review.md` carries `verdict: accepted` and confirms the UX
  review's edge-pad, workspace naming, playhead, partial-page, and uncolored
  scope questions are resolved by architecture/spec work.
- `spec.md` defines the v1 contract: one Launchpad Mini MK3 in regular MIDI
  Programmer mode, app-scoped preferences, transient workspace context,
  focused-window ownership, exact CC 91-98 mappings, static LED behavior,
  non-goals, and acceptance criteria.
- `plan.md` is marked ready for build queue and sequences the work through
  pre-build verification, MIDI infrastructure, state lifting, device layer,
  workspace adapters, Settings/lifecycle/focus wiring, and integration review.
- `implementation-handoff.md` states there are no user-blocking open questions;
  remaining questions are implementer findings resolved by reading the codebase.

## Approval Scope

Approved v1 prototype evidence:

- Control Surfaces section inside the existing MIDI Settings tab, with an
  enable toggle, endpoint pickers, status row, and Test LEDs affordance.
- Phrase workspace hardware grid with 8x8 phrase-by-track cells, top-row
  layer/page/workspace controls, right-column row-select, and LED state sync.
- Live workspace hardware grid with scope rows, step/bar columns, top-row
  layer/page/workspace/transport controls, right-column scope-select, and a
  green playhead-column override.
- Context-aware routing to the frontmost document and active workspace.

Not approved or inferred from the prototypes:

- A fictional ninth Launchpad top-row pad.
- Modifier chords or long-press gestures in v1.
- General MIDI learn, arbitrary remapping, or additional control surfaces.
- Per-document control-surface preferences.
- Persisted pad state, LED frames, page indices, layer IDs, or selected phrase
  state in `.seqai`.
- Literal production styling, spacing, or implementation structure from the
  HTML prototypes.

## Decisions and Open Questions

Closed for v1:

- The Mini MK3 top-row budget is exhausted by the normative CC 91-98 mappings
  in `spec.md`; modifier gestures are deferred beyond v1.
- `WorkspaceSection.tracks` remains the code name for the Live workspace in v1.
- Live playhead color fully overrides cell state for the active column.
- Out-of-bounds partial-page pads render `.off` and are no-op on press.
- Uncolored real scopes use a non-zero dim-white palette fallback.

Still-open product questions: none.

The remaining named findings are implementer-owned Phase 0 checks from
`plan.md`: macOS focus API, existing or new playhead exposure in
`EngineController`, and the exact Live scope color model path.

## Product-Owner Attention

No product-owner attention is needed for prototype approval or open-question
closure. Existing accepted PM artifacts answer the product decisions needed for
v1 readiness packaging.
