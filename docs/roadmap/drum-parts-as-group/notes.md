# Drum Parts As A Group Notes

## Raw Intent

```text
At the moment, the individual drum tracks seem to have no relation to each other. At the top of the pages, there should be an option to shift left or right through the parts within a drum track, and a button to open a view for the drum track itself. This will need some prototyping. Essentially it would be good to have a view of all the steps for each of the parts as a matrix with the name of the part on the left. Otherwise it's hard to visualise what all the steps are doing. The wrinkle is that patterns are independent for each part, so there's no guarantee they'll be playing together. One idea is to have a kit pattern selector that contains sets of track pattern ids. Another wrinkle is that some tracks might have generators, and different layers. So not everything will be editable from a single UI.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

At the moment, the individual drum tracks seem to have no relation to each other. At the top of the pages, there should be an option to shift left or right through the parts within a drum track, and a button to open a view for the drum track itself. This will need some prototyping. Essentially it would be good to have a view of all the steps for each of the parts as a matrix with the name of the part on the left. Otherwise it's hard to visualise what all the steps are doing. The wrinkle is that patterns are independent for each part, so there's no guarantee they'll be playing together. One idea is to have a kit pattern selector that contains sets of track pattern ids. Another wrinkle is that some tracks might have generators, and different layers. So not everything will be editable from a single UI.

## 2026-04-29 Clarification

```text
The drum kit view would also allow setting up an alternative destination for the parts, for example a shared destination, and defining what a trigger relates to in that model. For example, each part could be a different MIDI channel, or each part could be a different MIDI note.
```

## Routing And Trigger Model

The drum kit/group view should also cover group-level routing semantics:

- parts may keep individual destinations or use an alternative/shared destination;
- a trigger needs an explicit interpretation within the kit model;
- one possible mapping is one part per MIDI channel;
- another possible mapping is one part per MIDI note.

This overlaps with item 19, Drum Kit Group View, but the musical problem belongs here too: grouped drum parts need a coherent routing and trigger model, not only a visual matrix.
