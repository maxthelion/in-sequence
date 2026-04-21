# Step-Pattern / Clip Model Review

**Date:** 2026-04-21
**Status:** Investigation — not yet executed. Output is a written review, not code.
**Relates to:** `docs/specs/2026-04-21-clip-ui-tidy-and-per-pattern-lazy-clips-design.md` (the narrow UI tidy Plan 1 runs in parallel), `Sources/Document/StepSequenceTrack.swift`, `Sources/Document/ClipContent.swift`, `Sources/Engine/EngineController.swift`, `Sources/Engine/Blocks/NoteGenerator.swift`, `Sources/Document/GeneratedSourceEvaluator.swift`, `docs/plans/2026-04-21-per-track-owned-clips-opt-in-generators.md`.

## Goal

Pin down, in writing, what the current step-pattern and clip storage model actually does — including the dual storage on `StepSequenceTrack` and `ClipContent.stepSequence` — and recommend a single direction for a future refactor. Neither the maintainer nor recent audits can cleanly explain what `StepSequenceTrack.stepPattern` is for relative to `ClipContent.stepSequence.stepPattern`; both fields exist, both are written, and it is unclear which one the engine authoritatively reads for playback or how (if at all) they stay in sync.

This spec is the **investigation phase**. Its deliverable is a written audit plus a recommendation. A follow-up implementation plan (referenced here as "Plan 3") is written only after the recommendation is approved.

**Verified by:** The investigation produces a single markdown file under `docs/specs/`, committed to the repo, whose sections (see "Deliverable structure" below) are all populated with code-grounded findings (file:line references) and whose "Recommendation" section names one of the proposed directions as the chosen path. After that is approved by the maintainer, a normal TDD implementation plan is written against the chosen direction.

## Non-goals

- Any code change in the document, engine, or UI layers. This spec drives an investigation that produces documentation; code changes land in Plan 3.
- Replacing `AVAudioEngine`, the tick clock, or the generator pipeline. Entirely out of scope.
- Changing save format on disk as part of the investigation. Plan 3 may propose a format change; this spec does not.
- Superseding or blocking Plan 1 (the clip UI tidy). Plan 1 ships in parallel and is independent — it deliberately does not touch the ambiguous storage.
- Deep-diving into generator internals beyond what's needed to understand their step-pattern consumption.

## Principle

The tick hot path reads from *something* to decide whether a step fires at tick T. Today "something" is one of:

- `StepSequenceTrack.stepPattern: [Bool]` on the track itself.
- `ClipContent.stepSequence(stepPattern:[Bool], pitches:[Int])` on a `ClipPoolEntry` referenced by the active pattern slot.
- Generator-produced steps via `NoteGenerator` / `GeneratedSourceEvaluator`.

A fresh audit of reads shows the **engine's playback path currently reads the clip**, while the step grid UI edits **the track**. If that is true, the UI-level step edits would be invisible to playback — which contradicts observable behavior. Either the audit is incomplete, a sync path exists that the audit missed, or a recently-fixed bug has left residue. Until this is pinned down, any refactor is guessing.

Beyond the dual-storage question, the shape itself is inadequate for the expressiveness the project plans to support:

- **Per-step chords.** Today every "on" step plays the track-wide `pitches` array. Melodies that vary per step, or chord progressions across steps, cannot be represented.
- **Micro-timing (swing / humanise).** Today's `[Bool]` step array forces every fired step onto the grid boundary.
- **Fills / ratchets / sub-step bursts.** Today a step either fires once or not at all; no way to fire a step as a 3-stroke flam, a 2-stroke ratchet, or a buzz roll within the step's time window.

Any direction we pick must accommodate all three — at least as an additive extension — and must preserve **O(1) per-step lookup with zero allocations on the tick hot path**.

## Architecture of the investigation

The spec is a procedure document — it describes what to audit, how to audit it, and what the output file must contain. The implementation work is deliberately empty; the value is in the resulting report.

### Deliverable structure (the review document)

The investigator (Claude or a subagent, executed via a follow-up plan) produces one file:

`docs/specs/2026-04-XX-step-pattern-clip-model-review-findings.md`

With the following sections, in order. Each section has mandatory contents listed below; no section may be left empty or marked TBD.

#### 1. Executive summary (≤200 words)

The three most important findings. What playback actually reads. Whether there is a sync path from track to clip or vice versa. The single-sentence recommendation.

#### 2. Storage inventory

For each of the following, list every read and every write. Cite file:line. Quote short snippets (≤5 lines) when clarifying:

- `StepSequenceTrack.stepPattern: [Bool]`
- `StepSequenceTrack.stepAccents: [Bool]`
- `StepSequenceTrack.pitches: [Int]`
- `ClipContent.stepSequence(stepPattern:pitches:)`'s `stepPattern` payload
- `ClipContent.stepSequence(stepPattern:pitches:)`'s `pitches` payload
- `ClipContent.sliceTriggers(stepPattern:sliceIndexes:)`'s `stepPattern` payload
- `ClipContent.pianoRoll(lengthBars:stepsPerBar:notes:)`'s `notes` payload

For each read site, label: `PLAYBACK` (part of the tick hot path), `UI` (renders only), or `OTHER` (decoding, serialization, tests, migration, analytics).

For each write site, label: `USER` (direct user gesture), `SYSTEM` (default / decode / migration), or `SYNC` (explicit copy from another source). Every `SYNC` site is the main finding of this audit — they are the points where dual storage is reconciled or deliberately not reconciled.

#### 3. Authoritative read for playback

Answer, in one paragraph: at tick T, when the engine decides whether a step fires, which storage does it read? Include the exact call chain (`EngineController.processTick` → … → `GeneratedSourceEvaluator.shouldStepFire`, etc.). Cite file:line at each hop.

If the answer is different for generator-driven vs clip-driven patterns, document both.

#### 4. Sync analysis

Tabulate (markdown table) every observed pair of (UI write site, playback read site). For each pair, state whether a sync path closes the loop:

| UI writes to… | Playback reads from… | Sync path (if any) | Status |
|---|---|---|---|
| `track.stepPattern[i]` via `cycleStep(at:)` | `clip.content.stepSequence.stepPattern[i]` | (describe or "none observed") | Aligned / Broken / Unknown |

Rows where Status is `Broken` or `Unknown` are the immediate bugs — the investigation calls them out explicitly, and Plan 3's scope must include fixes.

#### 5. Performance audit

On a representative project (say 8 tracks, 4 drum + 4 mono, each with a seeded pattern 1), measure the tick hot path using Instruments (os_signpost + Time Profiler). Record:

- Per-tick wall time (μs) at idle vs during playback.
- Allocations per tick: how many `Array` / `[Bool]` / `String` / closure captures. Use Instruments's Allocations instrument.
- Any `firstIndex(where:)`, `dictionary[uuid]`, `for … in tracks` linear scans on the hot path.
- Any cross-thread sync points (locks, `DispatchQueue.sync`, `await`).

Separately, micro-benchmark the step lookup itself: given N tracks each with a 16-step clip, how long does "what fires at tick T" take, averaged over 1M ticks? Compare to a theoretical O(1) array-index lower bound. Note the gap if any.

Record the benchmark code (so Plan 3 can re-run it post-refactor) in `Tests/SequencerAIBench/` or similar. This is the *only* file Plan 2 creates besides the review doc itself.

#### 6. Gap analysis

Evaluate today's model against three acceptance criteria:

1. **Per-step lookup = O(1), zero allocations on the hot path.** Does today's shape meet it? Cite the performance audit numbers.
2. **Per-step chords.** Today's model represents at most "all on-steps play the track's `pitches` chord". Document the exact expressiveness limitation.
3. **Micro-timing.** Today's `[Bool]` array has no per-step offset. Document the limitation.
4. **Fills / ratchets / sub-step bursts.** Today's model has no per-step repeat concept. Document the limitation.
5. **Per-step velocity / accent.** `StepSequenceTrack.stepAccents: [Bool]` gives binary accent; there is no per-step continuous velocity. Document.
6. **Per-step gate length.** Is there any per-step override, or is `track.gateLength` the only control? Document.

#### 7. Direction options

Propose three named directions, with trade-offs for each. Template (fill in during investigation):

**Direction A — Per-step trigger on the clip; drop track-level step state.**

```
struct StepTrigger: Codable, Equatable {
    var pitches: [UInt8]     // chord; empty = no note but step still "present" (for retrigger/gating)
    var velocity: UInt8
    var microOffset: Int     // signed ticks; 0 = on-grid
    var gateLength: Int      // ticks; 0 = use track default
    var repeats: Int         // 1 = single hit; 2+ = ratchet; fills in sub-step time
}

struct Clip: Codable, Equatable {
    var id: UUID
    var trackType: TrackType
    var length: Int                  // in steps
    var steps: [StepTrigger?]        // length == self.length; nil = rest
}
```

- `StepSequenceTrack.stepPattern` deleted.
- `StepSequenceTrack.pitches` deleted (moved into per-step trigger).
- `StepSequenceTrack.stepAccents` deleted (encoded as `velocity` on per-step trigger).
- `ClipContent.stepSequence` / `.sliceTriggers` both deleted; `.pianoRoll` either merges or stays as an alternate view of the same data.

Trade-offs: Cleanest model. Every expressiveness gap covered. Biggest refactor surface. Save format breaks; requires migration step.

**Direction B — Keep dual storage, but codify sync.**

Leave `StepSequenceTrack.stepPattern` and `ClipContent.stepSequence` both in place. Add a `Project.syncStepPatterns()` function invoked after every mutation on either side, and add a test that asserts they match after arbitrary edits. Add per-step pitch / microOffset as *optional overlays* (sparse dictionaries `[Int: [UInt8]]` and `[Int: Int]`) so the existing `[Bool]` stays the canonical "is this step on?" answer.

Trade-offs: Minimal disruption, smallest save format delta. Sync is a continuous maintenance tax. The overlay dictionaries are awkward and likely slower than an integrated shape. Does not solve the root cause.

**Direction C — Promote the clip; drop track-level step state.**

Keep `ClipContent` with its cases, but make the clip the sole owner of step data. Delete `StepSequenceTrack.stepPattern`, `stepAccents`, and `pitches`. `.stepSequence`'s payload evolves in a follow-up plan to include per-step chord / micro-timing / fills (essentially the same shape as Direction A, wrapped in the existing `ClipContent.stepSequence` case rather than a new `Clip` struct).

Trade-offs: Middle ground. Keeps the `ClipContent` discriminated union (preserving `.pianoRoll` as a separate case if we still want two content shapes). Smaller delete surface than A. Doesn't pay off the "one canonical shape" simplification.

The investigator may propose additional directions if the audit surfaces considerations the above three do not cover. Keep the list ≤5 to stay reviewable.

#### 8. Recommendation

One option, with rationale. Three paragraphs maximum. Cite the strongest evidence from the audit / perf pass. Call out the single biggest risk and how Plan 3 will mitigate it.

#### 9. Risk register

Table of risks, each with a probability estimate (low / medium / high) and mitigation.

| Risk | Probability | Mitigation |
|---|---|---|
| Save format breakage | … | … |
| Engine regression on the tick hot path | … | … |
| UI regression in the step grid | … | … |
| Hidden dual-storage consumer | … | … |

## Data flow (of the investigation itself)

1. Investigator is dispatched with this spec as context. The implementation plan (Plan 2, to be written *after* this design is approved) is the TDD task list that walks them through each section above.
2. Investigator executes section by section, committing a WIP review file at each checkpoint. Each section is a separate commit so reviewers can follow the trail.
3. When every section is populated, Investigator writes the "Recommendation" section last and opens a PR.
4. Maintainer reviews the findings and either:
   - Approves the recommendation → triggers Plan 3 (implementation).
   - Redirects to one of the other options or asks for more investigation → Plan 2 is re-run on the specific sub-question.

## Error handling

This spec is documentation, so most of "error handling" is about the investigation discipline. The hard rules:

- **No undocumented assumptions.** If the investigator can't cite file:line for a claim, the claim is omitted or explicitly labeled "unverified assumption" with a TODO to verify before the recommendation.
- **If a `SYNC` path is claimed, it must be reproduced in a unit test.** Before the investigation concludes, write a throwaway test that asserts the sync holds after a sample edit. If the test fails, that's a bug finding, not a "we think sync works".
- **Performance numbers must be reproducible.** The benchmark code lands in the repo. Numbers without code are not acceptable.
- **Every "Direction" proposal must state which expressiveness criteria it satisfies.** Fill in the matrix:

  |                        | A | B | C |
  |---|---|---|---|
  | O(1) per-step lookup   | ✓/✗ | ✓/✗ | ✓/✗ |
  | Per-step chords        | ✓/✗ | ✓/✗ | ✓/✗ |
  | Micro-timing           | ✓/✗ | ✓/✗ | ✓/✗ |
  | Fills / ratchets       | ✓/✗ | ✓/✗ | ✓/✗ |
  | Per-step velocity      | ✓/✗ | ✓/✗ | ✓/✗ |
  | Per-step gate length   | ✓/✗ | ✓/✗ | ✓/✗ |

  Any direction with more than two ✗ in its column is disqualified unless the reviewer explicitly accepts the limitation.

## Testing

The investigation is documentation-primary, but it produces two executable artifacts:

1. **A reproduction test for any `SYNC` claim** — ad hoc, placed under `Tests/SequencerAITests/Investigation/StepPatternSyncProbeTests.swift`. Must pass against `main` at the time of writing; if it fails, that's a bug finding that is promoted into the report.

2. **The perf benchmark** — placed under `Tests/SequencerAIBench/StepLookupBenchmark.swift` (create directory if missing). The benchmark is a standalone `measure { ... }` block or uses `XCTest`'s `measure` API; either is fine. The benchmark must run `xcodebuild test` cleanly on a local dev machine and record its numbers in the review doc.

Beyond these two artifacts, no code changes are committed as part of Plan 2.

## Scope

Single investigation document + two executable probes (sync test + perf benchmark). No UI, no engine, no document-layer refactor. Output tagged `v0.0.27-step-pattern-review` at completion of the review.

## Decisions taken

- **Investigation-first, then implementation.** The maintainer explicitly chose this sequencing: the review lands as a reviewable doc before any refactor code. Plan 3 is written only after the recommendation is approved.
- **The review document lives in `docs/specs/`, not `docs/plans/`.** It's a specification of findings, not a task list.
- **Every section is mandatory; no "TBD"s pass review.** The discipline is the point. Vague findings lead to wrong refactors.
- **Three directions presented by default; investigator may propose up to five.** Keeps the decision reviewable without artificially capping creativity.
- **Criteria pre-committed.** O(1) lookup, per-step chords, micro-timing, fills/ratchets, per-step velocity, per-step gate length. Any direction failing more than two is disqualified. This prevents the investigator from proposing a "minimum-change" direction that keeps obvious shortcomings.
- **Performance numbers must be reproducible.** The benchmark code lives in the repo. This also means Plan 3 can run the same benchmark post-refactor to confirm improvement.
- **Plan 2 does not block Plan 1.** Plan 1 ships the UI tidy (dropdown + text-field removal + lazy clip seeding) without touching the ambiguous storage. Plan 3 (the refactor) will touch the storage; it can rebase over Plan 1 cleanly because the UI tidy does not change any storage fields.
- **Save-format migration is Plan 3's problem.** If the chosen direction breaks the save format, Plan 3 includes a migration task. The investigation spec surfaces the risk but doesn't design the migration.
