# MIDI Interfaces Notes

## Raw Intent

```text
Re item 8 - there might already be a plan for it elsewhere. Essentially, we need a way for midi interfaces to control stuff in a view. Ideally, what we receive from the controller doesn't change, we just route it to different stuff in the ui based on the state. So if we are on live track perform mode, it would have the colours of the tracks and their toggle states.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

Re item 8 - there might already be a plan for it elsewhere. Essentially, we need a way for midi interfaces to control stuff in a view. Ideally, what we receive from the controller doesn't change, we just route it to different stuff in the ui based on the state. So if we are on live track perform mode, it would have the colours of the tracks and their toggle states.

## Related Existing Plan

- `docs/plans/2026-04-23-launchpad-mini-control-surface.md` appears to cover much of this space under a Launchpad Mini MK3-specific frame.
- Important alignment point from the user clarification: the incoming controller shape should stay stable, while the active UI/workspace state routes the same controls to different meanings.
- For Live track perform mode, the hardware/view mapping should reflect track colors and toggle states.
- The PM assistant should treat the existing Launchpad plan as source context during user-story and existing-state passes, while checking whether the roadmap item should remain broader than Launchpad-specific support.
