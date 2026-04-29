# Modifier Chain Placement Notes

## Raw Intent

```text
Re item 9. The track UI is a bit confusing re source and modifiers. I'd like it to be a bit like source and modifier slots are tabs. In each, there is a sort of UI well/holder that can contain an item. For the source, this would be either a clip, or a generator. The model should be that the current source can be removed, making a plus button for adding a new source (rather than the current "switch to generator source"). The options when the source is empty should be add new blank clip, select clip from pool, new blank generator, select generator. This UI needs to be quick, the most likely flow is that the track starts with a clip, and the user wants to remove it for a generator. Selecting other options should be the progressive disclosure. Maybe we have a modal for those options, ideally it stays within the same screen. Similar treatment for the modifiers well.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

Re item 9. The track UI is a bit confusing re source and modifiers. I'd like it to be a bit like source and modifier slots are tabs. In each, there is a sort of UI well/holder that can contain an item. For the source, this would be either a clip, or a generator. The model should be that the current source can be removed, making a plus button for adding a new source (rather than the current "switch to generator source"). The options when the source is empty should be add new blank clip, select clip from pool, new blank generator, select generator. This UI needs to be quick, the most likely flow is that the track starts with a clip, and the user wants to remove it for a generator. Selecting other options should be the progressive disclosure. Maybe we have a modal for those options, ideally it stays within the same screen. Similar treatment for the modifiers well.
