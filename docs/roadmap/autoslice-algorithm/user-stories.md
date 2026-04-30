# Autoslice Algorithm User Stories

## Stories

### 1. BPM hypothesis from sample duration

- **As a:** producer dropping a sample into the sequencer
- **I want:** the app to infer plausible BPM and bar-length candidates from the sample's duration (assuming 1, 2, 4, or 8 bar loops)
- **So that:** I don't have to manually tap-tempo or calculate BPM before I can start working with the sample
- **Done when:** given a sample duration, the algorithm returns a ranked list of (BPM, bar-count) hypotheses that cover the most musically probable interpretations

### 2. Transient alignment check against a 16-step grid

- **As a:** producer working with a drum loop
- **I want:** the algorithm to check whether detected transients approximately line up to a 16-step grid at each candidate BPM
- **So that:** I can quickly know which BPM hypothesis actually fits the feel of the loop, not just the math
- **Done when:** for each BPM hypothesis, the algorithm scores how well transients land on 16th-note boundaries, and surfaces that score alongside the hypothesis

### 3. Handling slightly-too-long audio snippets

- **As a:** producer whose loop recording is a few milliseconds longer than an exact bar
- **I want:** the algorithm to suggest adjusted loop start/end points that produce a musically clean loop, rather than refusing to suggest anything or assuming the sample is off
- **So that:** I can recover a usable loop from an imperfect recording without manual waveform trimming
- **Done when:** the algorithm proposes one or more trimmed start/end pairs that produce a near-perfect grid-aligned loop, ranked by fit quality; slightly-too-long samples are handled more gracefully than slightly-too-short ones

### 4. Multiple ranked loop-start/end suggestions

- **As a:** producer unsure which interpretation of an ambiguous sample is correct
- **I want:** a small set of plausible loop start/end suggestions rather than one confident (potentially wrong) answer
- **So that:** I can audition a few options and pick the one that sounds right, with the algorithm doing the heavy lifting of generating candidates
- **Done when:** the output includes at least two distinct start/end pair candidates with associated confidence or fit scores, ordered from most to least likely

### 5. Optional transient role classification (kick, snare, hi-hat)

- **As a:** producer working with a mixed drum loop
- **I want:** the algorithm to attempt to classify each detected transient as a kick, snare, or hi-hat (or unclassified)
- **So that:** the grid alignment check can weight musically significant hits (e.g., snares on beats 2 and 4) more heavily when scoring BPM hypotheses
- **Done when:** the prototype demonstrates that classification improves grid-alignment scoring on at least one adversarial sample; this is an optional enhancement, not a requirement for all stories above

### 6. Isolated prototype exploration (not wired into production)

- **As a:** PM/developer evaluating algorithm options before committing to an in-app build
- **I want:** several isolated algorithm variants demonstrated through simple standalone interfaces
- **So that:** I can compare how each heuristic handles a curated set of adversarial samples without risking the production sequencer
- **Done when:** at least two distinct algorithm variants are demonstrated side-by-side on the same sample set; the interfaces show loop hypotheses, transient alignment visualisation, and suggested start/end points; nothing is wired into the production app

## Acceptance Signals

- Dropping a clean 2-bar loop at an unknown BPM produces at least one hypothesis that matches the loop's actual BPM within ±1 BPM.
- A loop recorded slightly long (e.g., an extra 50–200 ms of bleed) receives at least one suggested trim that makes it grid-clean.
- An ambiguous sample receives multiple distinct start/end suggestions, not just one.
- The prototype UI makes it visually obvious where detected transients fall relative to the proposed grid.
- The exploration runs entirely outside the production app; no changes to `Sources/` are required to evaluate the heuristics.

## Assumptions

- The initial exploration phase deliberately avoids in-app integration; this is a research/prototype milestone, not a shipped feature.
- "Slightly too long" is the primary problem case; slightly-too-short samples are acknowledged as harder and are lower priority for the prototype.
- Transient detection itself (onset detection) is treated as a dependency the algorithm can call — this story set does not specify how transient detection is implemented.
- The adversarial sample set will be assembled by the developer or PM before prototype testing begins.
- BPM hypotheses are restricted to musically sensible values (e.g., 60–200 BPM) to keep the candidate list tractable.
