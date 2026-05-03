# Track Perform Multi-Select And Latch Notes

## Raw Intent

```text
add an item for multi-select and latch on the track perform screen
```

## Clarification

Captured from user clarification on 2026-05-03.

```text
It's 2 separate things that used to be in the UI when fill layer was active.

1. Select multiple tracks and make changes to one, that affect others.

2. For performance features that are on or off, latch off means that mousedown
sets it on, mouse up turns it off. Vs mouseup toggling the current state.

There are probably UX considerations about how the value for the selected
tracks is changed. Perhaps a modal, or perhaps a tall UI widget to the right or
left of the track matrix. Easiest is that changing one cell changes all the
other selected cells to the same value.
```

## Normalized Concept

This item combines two related Track Perform behaviors that should be considered
together but not collapsed into one model.

### 1. Multi-select linked editing

The user can select multiple tracks on the Track Perform screen. When multiple
tracks are selected, changing a perform cell/value on one selected track applies
the same value to the other selected tracks.

The simplest v1 rule is:

- selected tracks form an edit set;
- changing one selected cell sets the corresponding cell for every selected
  track to the same value;
- unselected tracks are unaffected.

UX needs to decide how selected-track values are represented and edited:

- direct cell editing only;
- a modal;
- a tall side widget to the right or left of the track matrix;
- another progressive-disclosure pattern.

### 2. Latch vs momentary behavior

Performance features that are either on or off need a latch mode:

- **Latch off / momentary:** pointer down turns the feature on; pointer up turns
  it off.
- **Latch on / toggle:** pointer up toggles the feature's current state.

This applies to perform-page features such as Fill, Note Repeat, and other
future on/off performance toggles.

## PM Notes

- Treat multi-select linked editing and latch/momentary behavior as separate
  user-story clusters.
- Prototype the selected-track edit interaction before writing a final spec.
- Prefer the simplest v1 linked-edit behavior: changing one selected cell sets
  the same cell/value across all other selected tracks.
- Consider controller implications later: hardware pads should eventually
  reflect selected state and latched/toggled state, but this item should first
  solve the on-screen Track Perform behavior.
