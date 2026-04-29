# Audio Looping Notes

## Raw Intent

```text
I think this might duplicate the input audio idea as it relates to tracks. A second idea that is lower priority is to have a separate live looping page that allows toggling record and playback of capable tracks at a macro level.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

I think this might duplicate the input audio idea as it relates to tracks. A second idea that is lower priority is to have a separate live looping page that allows toggling record and playback of capable tracks at a macro level.

## Relationship To Input Audio

The track-level audio looping idea likely overlaps with item 7, Input Audio:

- selecting an audio input/interface;
- creating an audio track that can monitor input;
- recording input to a buffer;
- switching a track between live input and recorded loop playback.

Avoid duplicating that work here unless the later story/spec pass finds a genuinely separate loop-specific track concern.

## Lower-Priority Live Looping Page

A separate lower-priority direction is a macro live-looping page:

- shows tracks that are capable of recording/playback loops;
- lets the performer toggle recording and playback at the track level;
- acts as a performance control surface rather than a detailed audio-track editor.

This should probably remain secondary until the Input Audio track model is clearer.
