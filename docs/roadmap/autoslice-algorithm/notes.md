# Autoslice Algorithm Notes

## Raw Intent

```text
Re item 13, the auto slice algorithm should be slightly smarter. I'm not sure what kind of prior art there is around this. The length of the sample can give some indication of a bpm assuming it is 1 bar, 2 bars etc. But there's also the question of whether the transients approximately line up to a grid of 16. The problematic cases are where the snippet of audio isn't exactly a loop - is slightly longer (shorter presents worse challenges). Then it would be nice if there are a bunch of suggested loop start ends. Maybe it looks at the transients to see if they are snares, kicks, hi hats etc. It feels like pattern matching that humans do intuitively, but could be determined by a heuristic. Perhaps we can explore several different options in isolation. Eg don't build it into the app yet. Just take a few samples, and build a couple of simple interfaces demonstrating how it handles the loops.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

Re item 13, the auto slice algorithm should be slightly smarter. I'm not sure what kind of prior art there is around this. The length of the sample can give some indication of a bpm assuming it is 1 bar, 2 bars etc. But there's also the question of whether the transients approximately line up to a grid of 16. The problematic cases are where the snippet of audio isn't exactly a loop - is slightly longer (shorter presents worse challenges). Then it would be nice if there are a bunch of suggested loop start ends. Maybe it looks at the transients to see if they are snares, kicks, hi hats etc. It feels like pattern matching that humans do intuitively, but could be determined by a heuristic. Perhaps we can explore several different options in isolation. Eg don't build it into the app yet. Just take a few samples, and build a couple of simple interfaces demonstrating how it handles the loops.

## Exploration Direction

This item should start as an isolated algorithm/prototype exploration, not an in-app build.

Explore heuristics for:

- deriving plausible BPM/length hypotheses from sample duration assuming 1, 2, 4, or 8 bar loops;
- checking whether detected transients approximately align to a 16-step grid;
- handling snippets that are slightly too long or too short to be exact loops;
- suggesting multiple plausible loop start/end pairs instead of one confident answer;
- optionally classifying transient roles such as kick, snare, and hi-hat when that helps infer a musical grid.

Prototype expectation:

- use a small set of adversarial samples;
- compare several isolated algorithm options;
- build simple interfaces that show loop hypotheses, transient alignment, and suggested start/end points;
- do not wire the experiment into the production app until a heuristic direction has been reviewed.
