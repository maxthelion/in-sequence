---
id: ux-feedback-pass-2026-05-06
status: scheduled
run_after: "2026-05-06T10:08:00+01:00"
max_parallel: 1
auto_merge: false
requires_peekaboo: true
lanes:
  - id: track-editor-foundation
    title: Track Editor Foundation UX Feedback Pass
    source_branch: codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation
    focus: Start from the previous track-editor probe branch. Read the validated UX baseline, run your own Peekaboo permissions and UI-map/capture check, then revise the surface so history, source chain, step edit, pattern context, and destination are visible as one coherent first-viewport workflow. If you cannot produce a valid capture or UI map, stop and record the capability failure.
  - id: phrase-scene-song-performance
    title: Phrase, Scene, And Song Performance UX Feedback Pass
    source_branch: codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance
    focus: Start from the previous performance probe branch. Read the validated UX baseline, run your own Peekaboo permissions and UI-map/capture check, then revise the performance surface so phrase rows, scene rows, song/free transport, basis phrase, and queued state form a credible instrument rather than sparse panels. If you cannot produce a valid capture or UI map, stop and record the capability failure.
  - id: mixer-routing-and-sends
    title: Mixer Routing And Sends UX Feedback Pass
    source_branch: codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends
    focus: Start from the previous mixer probe branch. Read the validated UX baseline, run your own Peekaboo permissions and UI-map/capture check, then revise the first viewport so the routing graph, busses, sends, master, and fader strip are visible with routing as the main lane idea. If you cannot produce a valid capture or UI map, stop and record the capability failure.
  - id: audio-input-looping-autoslice
    title: Audio Input, Looping, And Autoslice UX Feedback Pass
    source_branch: codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice
    focus: Start from the previous capture probe branch. Read the validated UX baseline, run your own Peekaboo permissions and UI-map/capture check, then sharpen the primary action and musician-facing state for input, shared buffer, loop range, autoslice, and buffer users. If you cannot produce a valid capture or UI map, stop and record the capability failure.
  - id: performance-overrides-pattern-manipulation
    title: Performance Overrides And Pattern Manipulation UX Feedback Pass
    source_branch: codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation
    focus: Start from the previous performance-overrides probe branch. Read the validated UX baseline, run your own Peekaboo permissions and UI-map/capture check, then revise the surface so overrides feel playable and show audible/pattern consequences, target selection, and clear transient state. If you cannot produce a valid capture or UI map, stop and record the capability failure.
  - id: external-control-and-automation
    title: External Control And Automation UX Feedback Pass
    source_branch: codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation
    focus: Start from the previous automation probe branch. Read the validated UX baseline, run your own Peekaboo permissions and UI-map/capture check, then separate developer diagnostics from performer-facing external control and make the issue-draft/action flow visible without burying it below the fold. If you cannot produce a valid capture or UI map, stop and record the capability failure.
---

# UX Feedback Pass - 2026-05-06

## Why This Exists

The first overnight broad-probe loop built useful product shape, but the output
was not checked and fed back into the lane workers before reaching the user.
That left a partial result that still required human inspection.

This pass closes that loop. Each lane resumes from its own previous probe
branch, starts with the validated UX baseline, proves it can run Peekaboo
inspection itself, and then either improves the probe or records why it cannot.

## Required Inputs

- `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`
- `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-postmortem.md`
- the lane's previous result file under
  `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05/`
- the previous probe branch named by `source_branch`

## Operating Rules

- Do not merge or push.
- Work only in this feedback-pass branch/worktree.
- Start with a Peekaboo capability check:
  - `peekaboo permissions status --json`
  - a valid screenshot capture of the lane surface;
  - a `peekaboo see` UI map if possible.
- A valid capture must show the intended lane surface, not an open panel,
  browser, desktop, blank window, or unrelated app state.
- If visual inspection is not possible, write a blocked result and stop before
  making UX changes.
- If visual inspection is possible, apply the UX feedback and produce new
  before/after evidence.
- Preserve the probe nature of the branch; make wrong work easy to discard.

## Output Required

Each lane result should include:

- whether Peekaboo inspection was valid, invalid, or blocked;
- what visual evidence was captured;
- what UX feedback from the baseline was addressed;
- what changed in the probe;
- tests run and result;
- remaining UX critique;
- whether the lane is now ready for harvest, needs another feedback pass, or
  should be discarded/cherry-picked only for model pieces.

## Success Criteria

The pass succeeds if the morning harvest no longer needs the user to inspect six
raw partial branches just to know whether they are worth looking at. Each lane
should return with either improved visual evidence or a clear agent/process
failure that the supervisor can act on.
