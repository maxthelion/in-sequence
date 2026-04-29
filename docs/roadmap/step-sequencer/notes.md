# Step Sequencer Notes

## Raw Intent

```text
Re item 3, there are a number of different views that contain a step sequencer. There are different things that can be done in each. But fundamentally, they need to be using similar UI primitives. Whether we are toggling a step on or off, setting a value for it, or choosing an option, it should be all contained in the same UI area. A step needs to combine various pieces of information: whether it is playing now, whether it is selected, whether it is active, and its current value for a given layer. If a step is selected (maybe right click), we could potentially make the macro/layer cells above it editable with their own suitable controls. More than one step could be edited. If steps are selected, we could have some controls underneath for clear, copy, paste etc.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

Re item 3, there are a number of different views that contain a step sequencer. There are different things that can be done in each. But fundamentally, they need to be using similar UI primitives. Whether we are toggling a step on or off, setting a value for it, or choosing an option, it should be all contained in the same UI area. A step needs to combine various pieces of information: whether it is playing now, whether it is selected, whether it is active, and its current value for a given layer. If a step is selected (maybe right click), we could potentially make the macro/layer cells above it editable with their own suitable controls. More than one step could be edited. If steps are selected, we could have some controls underneath for clear, copy, paste etc.
