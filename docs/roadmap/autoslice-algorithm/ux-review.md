---
verdict: accepted
selected_prototype: loop-boundary-heuristic.html
reviewed: 2026-04-30
prototypes_reviewed:
  - bpm-hypothesis.html
  - transient-grid-alignment.html
  - loop-boundary-heuristic.html
feedback_applied: []
---

# Autoslice Algorithm — UX Review

Prototypes reviewed on 2026-04-30. All three are standalone HTML algorithm sandboxes — not in-app mockups. The evaluation criterion is whether each variant demonstrates its algorithmic hypothesis convincingly on the adversarial fixture set and surfaces enough information to choose a direction for specification.

---

## Prototype 1 — `bpm-hypothesis.html`

**What it does.** Accepts a sample duration in seconds and sweeps bar counts (1, 2, 4, 8) to derive exact BPM candidates. Rounds each to the nearest 0.5 BPM, computes a duration error in milliseconds, and applies a light penalty for fractional BPM values ("human score"). Results are shown in a ranked table with a score-bar column.

**What works.** The fixture set is well-chosen: clean loops, slightly-too-long samples (80ms and 200ms bleed), and genuinely ambiguous durations (the "2-bar@127 or 1-bar@63.5" case). The ranking approach — exact BPM derivation per bar count, then score-by-deviation — is correct and simple enough to implement in Swift with no dependencies. The warning when the top candidate has >100ms error is a useful signal. The table makes it trivially easy to see that a 200ms-bleed sample still surfaces the correct BPM at rank 1 with a depressed score rather than silently failing.

**What fails.** This sandbox is input-only: it cannot validate its output against transient data. A 3.780s sample correctly shows "Ambiguous: 2-bar@127 or 1-bar@63.5" but there is no path to resolve the ambiguity — the prototype ends at the hypothesis table. The "BPM step resolution" parameter is exposed but not actually used by the algorithm (the algorithm derives exact BPM analytically, not by grid sweep), which is misleading to a reader. The stub note pointing to sandbox 2 acknowledges the gap, but there is no way to flow through.

**Story coverage.** Stories 1 and 4 (BPM hypothesis, multiple ranked suggestions): well demonstrated. Stories 2, 3, 5: not covered. Story 6 (isolated exploration): satisfied.

---

## Prototype 2 — `transient-grid-alignment.html`

**What it does.** Accepts a BPM, bar count, and a list of transient onset times in seconds. Scores how many onsets fall within a snap tolerance of a 16th-note grid. Also runs a trim-candidate sweep: slides the loop start forward in small increments (up to one step or 500ms), scoring alignment at each offset, and returns the top 5 ranked by alignment score. A Canvas visualisation draws the grid, loop region, tolerance bands, and transients (green = on-grid, red = off-grid).

**What works.** The Canvas visualisation is the strongest element across all three prototypes. Grid lines at 16th-note, beat, and bar levels with tolerance shading make it immediately readable which transients are snapping. The "wrong BPM hypothesis" fixture (140 BPM applied to a 120 BPM loop) correctly produces low alignment scores and a sea of red — the test the heuristic needs to pass. The bleed fixtures correctly show the trim-candidate table surfacing a non-zero start offset as the best candidate. The baseline vs. best-trim comparison in the canvas annotation (e.g. "6/8 on-grid without trim; 7/8 with best trim") is a clean way to communicate the trim value.

**What fails.** The trim search range is limited to one 16th-note step (`maxTrim = Math.min(stepDur, 0.5)`), which means samples with more than one step of bleed will not find a clean trim. The 200ms-bleed fixture at 120 BPM has a step duration of 125ms, so 200ms bleed exceeds the cap. In practice this is the adversarial case the notes specifically call out as important. The prototype silently produces an incorrect best-trim suggestion on that fixture rather than flagging the limitation. There is also no way to test multiple BPM hypotheses in sequence — BPM must be typed manually, making cross-hypothesis comparison slow. The transient list input is a plain textarea rather than an editable table, so adding or modifying onsets is tedious.

**Story coverage.** Stories 2 and 3 (alignment check, slightly-too-long): partially demonstrated. Story 4 (ranked candidates): demonstrated via trim table, though the candidate set is limited to five trim offsets. Stories 1, 5: not covered. Story 6: satisfied.

---

## Prototype 3 — `loop-boundary-heuristic.html`

**What it does.** The most complete of the three. Accepts BPM, bars, a snap tolerance, a start-search range, and a transient list via an editable row table (time + role dropdowns). Sweeps start offsets at 5ms resolution across the full search range (up to 1000ms, configurable), scores each against the grid, de-duplicates candidates within 20ms, and returns the top N. A role-weighting toggle makes kicks and snares count 2x in the alignment score. The Canvas visualisation is richer than sandbox 2: it colour-codes transients by role (kick = red, snare = blue, hat/other = green), shows out-of-loop-range transients as dimmed dashed lines, and annotates the best candidate's start/end times. An "auto-classify" button assigns positional roles (kick on beats 1/3, snare on 2/4, hat otherwise) from the current BPM.

**What works.** The full-range start-offset sweep (up to 1000ms) directly addresses the gap in sandbox 2: the "2-bar @ 120 BPM + 180ms bleed" fixture correctly surfaces a near-zero-ms start offset as rank 1 and 60ms as rank 2, because both are valid clean loop starts once the bleed transient at 4.060s falls outside the loop window. The role-weighting toggle lets you test the hypothesis that musical significance of hits matters to alignment scoring — and on the "perfect 2-bar" fixture the difference is small (because all transients are already on-grid), while on sparser or ambiguous fixtures the weighting produces a meaningfully different ranking. The de-duplication step (20ms minimum separation between candidates) prevents the results table from filling with near-identical offsets.

The editable transient table is a qualitative improvement over sandbox 2's textarea: each row has an independent time input and role dropdown, the delete button works per-row, and "Add transient" appends with a sensible default. This makes it practical to compare how a single ambiguous fixture behaves with vs. without role assignments.

**What fails.** BPM is still a fixed input — the user must coordinate with sandbox 1 manually to feed in the top hypothesis. The "ambiguous: double-time feel" fixture is the hardest case, and the prototype correctly surfaces ambiguity (several candidates cluster around the same score) but provides no guidance on how to resolve it. The auto-classify heuristic is purely positional (beat index), not spectral, which the prototype honestly labels — but this means the toggle labelled "role weighting" can give a false sense of the full algorithm's capability until spectral classification exists. The canvas visualisation always shows the best candidate's loop region, not the currently selected candidate from the table — clicking an alternate row in the table does not update the canvas. This is a missing interaction that would be important if this sandbox were used to audition candidates.

**Story coverage.** Stories 3, 4, 5 (slightly-too-long, ranked suggestions, role classification): well demonstrated. Story 2 (alignment scoring): demonstrated through the score column and canvas. Story 1 (BPM hypothesis): not covered in isolation. Story 6: satisfied.

---

## Recommended Direction

**Advance on sandbox 3 (`loop-boundary-heuristic.html`) as the primary algorithm direction, with sandbox 1's BPM-from-duration logic as the upstream step that feeds it.**

Sandbox 3 is the only prototype that handles the full slightly-too-long problem within a realistic search range, surfaces multiple de-duplicated start/end candidates with scores, and demonstrates role-weighted alignment. Sandbox 1 provides the BPM hypothesis list that sandbox 3 needs as input. Sandbox 2's canvas visualisation idiom should be carried forward (and already appears in sandbox 3), but sandbox 2's trim logic is inferior to sandbox 3's full-range sweep.

The recommended pipeline for specification:

1. BPM hypothesis function (sandbox 1 logic): given `lengthSeconds`, return ranked `[(bpm, bars, fitScore)]`.
2. For each top-N hypothesis, run the alignment sweep (sandbox 3 logic): given transient frame positions and a `(bpm, bars)` pair, return ranked `[(startOffset, endOffset, alignScore, meanDist)]`.
3. Merge results across hypotheses into a single ranked list of `(bpm, bars, startOffset, endOffset, compositeScore)`.
4. Role weighting (sandbox 3 toggle): treat as an optional enhancement once step 2 is working.

One thing to resolve before writing spec: the auto-classify step in sandbox 3 is not spectral. The spec should be explicit about whether role classification is in-scope for the first implementation or deferred, and if in-scope, whether it depends on spectral analysis of the PCM buffer (which would require new code in `SliceAnalyzer`) or accepts a positional heuristic as a first pass.

---

## Open Questions

1. **Role classification scope for v1.** Is positional classification (beat-index heuristic) acceptable for the first build, or does v1 require spectral kick/snare/hat classification? The sandbox demonstrates both paths but they differ significantly in implementation complexity.

2. **Trim search range.** The spec will need to define a maximum start-offset search range. Sandbox 3 defaults to 400ms configurable to 1000ms. What is the real-world bound — is 500ms of bleed the practical worst case for the samples the app is expected to handle?

3. **Multi-hypothesis BPM iteration.** Should the pipeline automatically iterate over the top-N BPM hypotheses from sandbox 1 and surface a merged candidate list, or should the user pick a BPM hypothesis first (matching the current bar-count picker UX)? This affects whether the output is a flat candidate list or a two-step confirmation flow.

4. **Candidate audition.** All three sandboxes stub the audition button. Once brought into the app, will "audition a loop candidate" re-trigger the engine from a proposed start frame, or show a waveform preview? This should be answered during architecture, not assumed during spec.
