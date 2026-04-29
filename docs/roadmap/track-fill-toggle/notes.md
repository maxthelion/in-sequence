# Toggle Fill On A Track To Hear It Notes

## Raw Intent

```text
When in the track editor, there's no way to toggle the fill status for it. We need one so that we can preview the fill pattern playing.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

When in the track editor, there's no way to toggle the fill status for it. We need one so that we can preview the fill pattern playing.

## Normalized Concept

The track editor needs a local fill preview toggle.

Purpose:

- let the user hear the track's fill pattern while editing;
- avoid requiring a trip to the perform page just to audition fill behavior;
- make fill status legible while editing the source/clip/generator for the selected track.

Open design questions:

- Is this a temporary preview state scoped to the editor, or does it set the same fill layer state used during performance?
- Where should the toggle live relative to the clip/source editor and lane controls?
- Does it affect only the selected track, or should grouped drum parts inherit/reflect it?
