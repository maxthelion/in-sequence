---
feature: track-view-ia
status: ready-for-build-loop-promotion
stage: implementation-handoff
updated: 2026-06-19
sources:
  - README.md
  - docs/roadmap/track-view-ia/spec.md
  - docs/roadmap/track-view-ia/plan.md
  - docs/roadmap/track-view-ia/reasoning.md
  - docs/roadmap/track-view-ia/prototypes/
---

# Track View IA Implementation Handoff

## Purpose

This handoff packages the accepted track-view IA wireframes and decisions into
builder-ready scope. The build loop should implement the product/data/UI
contract in `spec.md`, not blindly recreate the HTML prototypes.

The central outcomes are:

> The track view has three altitudes with one tabbed grammar. Drum kits are
> first-class: own bus, own tabs, explicit (slot-only) pattern linking, accordion
> row-expand, persistent patterns, and a shared scrubbable history saved as one
> clip set. Tracks gain a real per-track insert FX chain. Scoped Track Perform
> reuses the phrase perform UI.

## Authoritative Artifacts

| Artifact | Builder Use |
|---|---|
| `spec.md` | Primary pass/fail behavior + acceptance contract (AC1–AC24). |
| `plan.md` | Suggested slice sequence; each slice maps to AC#s. |
| `reasoning.md` | Rationale + the recorded decisions (#1–#7, #4b). |
| `prototypes/01–06` | Low-fidelity visual + interaction reference. |
| `feedback/` | Atomic product-owner decisions that produced this spec. |

## Build-Loop Boundary

In scope: everything in `spec.md`'s Functional/Data/Engine checklists.

Out of scope (deferred, must not be built this pass):
- Separating the drum-part filter out of the mini sampler into FX (#6 deferred).
- Collapsed-kit-cell behavior in Scenes (only track/perform matrix + Song mode).
- A bespoke scoped-perform surface (must reuse the phrase perform UI).
- Pattern forking on structural divergence (resolution is break, not fork).

## Reuse Guardrails

- Build the Sound/Mixer tabs on `feature/routing-source-mixer-split`'s existing
  SOUND SOURCE / MIXER & FX wells + `.soundSource` vocabulary; do not reinvent.
- Reuse the normal-track step primitives for the kit matrix grid + bar pager.
- Reuse the phrase perform overlay substrate (`p0-track-performance-overlay` /
  `live-perform-fill-overlay`) for scoped Track Perform.
- Per-track insert FX is the one new model concept; everything else re-cuts or
  reuses existing surfaces.

## Verification Expectation

The loop's own evidence must demonstrate AC1–AC24. Prefer the smallest automated
checks (unit tests for the model deltas) plus deterministic QA surface captures
(add/refresh `scripts/visual-scenarios/qa-surface-coverage.sh` rows) compared
against the prototype intent. See `spec.md` → Verification Scenarios.
</content>
