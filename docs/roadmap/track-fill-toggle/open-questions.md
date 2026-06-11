# Track Fill Toggle Decisions And Open Questions

- packaged: 2026-06-04
- source concerns: `concerns.md`
- source existing-state analysis: `existing-state.md`
- source UX review: `ux-review.md`
- status: core v1 product questions resolved; builder handoff still incomplete

## Resolved V1 Decisions

### Runtime Model

Fill preview is a transient runtime override, not a phrase mutation.

The preview toggle must shadow the compiled phrase fill value during playback
for the selected track only. It must not write the phrase `"fill-flag"` boolean
layer and must not mark the document modified by itself.

### Scope

Fill preview is scoped to the selected/open track in the track editor.

Turning preview on for one track must not force fill behavior on sibling tracks,
including sibling drum parts. Switching the selected track resets preview to off.
Closing the editor also resets preview to off.

### Source Coverage

V1 applies to clip-backed tracks only.

Generator-backed tracks are out of scope for v1 because current playback only
uses `fillEnabled` in the clip source path. Generator-backed tracks should show
a disabled or unavailable state with nearby explanatory copy. Generator fill
support, if desired later, is a separate feature.

### Placement

The accepted placement is the editor header direction in
`prototypes/01-header-toggle.html`.

The lane-toolbar direction in `prototypes/02-lane-toolbar-toggle.html` is
rejected for implementation lead because it risks reading as lane authoring
rather than temporary playback preview.

## Residual Acceptance Notes

These are not product-owner blockers, but they must be carried into the next
architecture/spec artifacts:

- Header placement should remain discoverable enough even though it is separated
  from the lane tabs.
- The final UI should keep disabled generator explanation near the disabled
  control itself.
- Reset-on-editor-close must be an explicit acceptance check, because prototypes
  demonstrated track-switch reset directly but only annotated close reset.
- Mid-playback toggling should take effect quickly enough to audition fill
  without restarting transport; target acceptance remains within at most one
  phrase step.
- The spec must explicitly verify that phrase cells and document dirty state do
  not change when preview toggles.

## Open Builder-Readiness Questions

The core product choices are resolved. The remaining questions are architecture
and handoff questions, not product-owner decisions:

- Which runtime object owns the live per-track fill-preview override?
- Where does the override shadow compiled `fillEnabled` before clip step
  evaluation?
- How is override state cleared on track switch and editor close?
- How does the UI observe runtime preview state without treating it as document
  state?
- Which tests prove phrase non-mutation, dirty-flag preservation, per-track
  isolation, clip-only behavior, and reset lifecycle?

## Product-Owner Attention

No product-owner lock is needed for the next PM artifact layer.

Product-owner attention would become useful only if a future architecture or
spec cannot preserve both approved requirements at once:

- the toggle is discoverable in the header placement; and
- the toggle remains unambiguously a non-mutating playback preview.

## Next Artifact Dependencies

This file closes the first decision-packaging gap. The lane remains not ready
for build-loop promotion until accepted builder-facing artifacts exist:

- `architecture.md`;
- `spec.md`;
- `plan.md`;
- `implementation-handoff.md`.
