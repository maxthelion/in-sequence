---
feature: drum-kit-matrix-sound-prep
status: ready-for-build-loop-promotion
stage: implementation-handoff
created: 2026-07-05
sources:
  - docs/roadmap/drum-kit-matrix-sound-prep/spec.md
  - docs/roadmap/drum-kit-matrix-sound-prep/plan.md
  - .meta/multipass/state/bug-intake.md#G6
---

# Drum Kit Matrix Sound Prep Implementation Handoff

## Purpose

This handoff packages the accepted G6 PM artifacts into one builder-ready
follow-up pass. It should be used to open a future build loop, but it does not
itself promote a build loop, route implementation, create a worktree, merge, or
update bug statuses.

The intended outcome is a tighter drum-kit Tracks and kit-matrix experience:
kit tracks share the compact track grid grammar, drum-part names/rows remain
visible, kit-level patterns avoid duplicated controls, and drum-part Sound
states clearly distinguish no source, sampler, missing sample, and AU source.

## Build-Loop Boundary

A future build loop should implement only the bounded first pass described in
`spec.md` and `plan.md`:

- kit-track matrix compression in the Tracks grid;
- kit-matrix title, pattern, part-row, and tab-selector compression;
- drum-part sound-source affordance and language cleanup;
- focused tests and visual/canon evidence for those states.

Do not broaden the loop into:

- general slicer, audio, or normal-track header compression;
- mixer, routing, sends, or FX redesign;
- AU runtime lifecycle or human-present acoustic validation;
- Scenes IA or scene perform behavior;
- Track Perform mini-cell or phrase/global-apply polish.

## Authoritative Artifacts

| Artifact | Builder Use |
|---|---|
| `spec.md` | Primary behavior contract and acceptance criteria. |
| `plan.md` | Conservative implementation and verification sequence. |
| `docs/ux-canon.md` | Visual/copy/style constraints for the UI pass. |
| `scripts/diagnostics/ux-canon-lint.sh` | Required deterministic canon gate for touched UI. |

The source bug notes are useful for intent, but several contain local resolved
status lines. Treat them as evidence of the product contract, not as a request
to reimplement already-satisfied code.

## Suggested First Builder Slice

Start with a read-only seam check and a compact evidence note:

- Does `TracksMatrixView` still render kit tracks as flat grid cells when
  collapsed and expanded?
- Does the kit matrix still use 16 step columns, a bar pager, left part-name
  column, kit-level pattern slots in the header, and the shared tab grammar?
- Does drum-part Sound route `.none`, resolved sample, missing sample, and AU
  instrument to distinct surfaces?
- Which acceptance criteria are already satisfied on current main?

Only after that check should the builder edit the smallest surface that still
violates the spec.

## Required Evidence

The promoted build loop should produce:

- focused test evidence for any changed sound-source routing or destination
  mutation surface;
- `scripts/diagnostics/ux-canon-lint.sh` evidence;
- screenshots or deterministic visual evidence for collapsed kit cell,
  expanded kit cells, kit matrix, no-sound-source chooser, missing sample,
  sampler part, and AU part if reachable without human-present AU validation;
- explicit note if visual automation is unavailable due to TCC/focus gate;
- explicit note that no AU runtime lifecycle or acoustic safety claim was made.

## Product-Owner Attention

No product-owner decision is needed to promote this first pass. The default
contract is clear enough:

- kit patterns are global for this version;
- kit and parts use compact track grammar;
- no sound source is distinct from a broken/missing sampler;
- AU loading is a visible sound-source affordance, not a runtime validation
  promise.

Ask for product-owner attention only if implementation uncovers a new choice,
such as shared whole-kit AU versus per-part own-AU behavior, or if satisfying
the surface contract would require AU lifecycle work.
