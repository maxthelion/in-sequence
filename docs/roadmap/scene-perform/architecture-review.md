---
reviewed: 2026-04-30
reviewer: user
status: approved
---

# Scene Perform Architecture Review

## Decision

Architecture approved.

## Approval Note

Use `EngineController.effectiveCrossfader` as the single computed read path, keep live fader movement in `MasterBusPerformanceOverlayState`, make the full card header the hard-switch target, and prefer a custom vertical fader unless implementation testing shows a rotated `Slider` is sufficient.

Reset, Save Blend, Revert, and Save to Scene remain out of scope for this feature.

## Approved Guardrails

- Live crossfader movement remains overlay state and must not mutate the persisted document unless a separate explicit save feature is specified later.
- The view must not own playback truth or shadow crossfader state locally.
- Active-scene indication is derived from the effective crossfader value, not stored as separate state.
- Scene Perform is a layout and interaction refinement over the existing engine/audio path; no master-bus model rewrite is approved here.

## Open Architecture Questions

None for this feature. Implementation may choose the fader control strategy within the approved default above.
