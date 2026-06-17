# Clip History Stale Build Postmortem

Date: 2026-05-21

## Summary

Clip History had real partial implementation work, but the project state made
it look both "built" and "blocked" depending on which artifact an agent read.
The merged `main` implementation from `9ae658d` was later rejected by UX review,
while a better stale branch (`auto/roadmap-1-clip-history`) carried useful
repairs that never became the active build authority.

## Timeline

- 2026-05-04 15:57: `9ae658d feat(clip-history): add generator capture modal`
  landed on `main`.
- 2026-05-04 17:09: `9199ed6 docs(roadmap): record clip history modal ux
  review` recorded that the built modal was not acceptable. The review said it
  implemented "save latest capture" rather than selecting a recent history
  region and committing it.
- 2026-05-04 21:04: `036a5d8 fix(clip-history): freeze capture modal state`
  landed on `auto/roadmap-1-clip-history`, moving toward the correct frozen
  source/destination model.
- 2026-05-05 13:20: `02c5545 docs(roadmap): approve clip history prototype`
  approved `clip-history-dual-grid-v4.html`.
- 2026-05-05 19:05: `ced03ab fix(build-loop): surface clip history overwrite
  blocker` stopped the stale branch behind an overwrite-copy question.
- 2026-05-20/21: observers repeatedly reported Clip History as mixed/stale, but
  did not cause PM artifacts to be reconciled or a fresh build loop to be
  created.
- 2026-05-21: PM artifacts were reconciled: v4 is now the build target, the
  rejected modal is marked incomplete, and `build-resume-handoff.md` describes
  how to salvage the old branch safely.

## What Went Wrong

The original implementation was merged before UX evidence closed the feature.
The git history is enough to show order, but not enough to prove the actor,
request, review gate, or go-ahead path that caused the merge. That is an audit
gap.

After UX rejected the built modal, the correction work split into two places:
roadmap docs approved v4, while the stale branch accumulated better engine and
modal work. The PM docs still contained advisory language saying the handoff was
not build-authoritative, so later observers correctly hesitated, but no actor
owned the repair from "mixed evidence" to "fresh buildable state."

The old blocker was too narrow. It focused on overwrite-copy wording, but the
more important blocker was artifact authority: agents could still read old
modal-v1 and save-latest assumptions.

## Process Health Observer Opportunity

A process health observer could have caught this by looking for these warning
signs:

- a feature has code on `main` but the feature README is not `complete` or
  `merged`;
- a UX review says "do not accept" after the commit that added the feature;
- a branch contains later corrective commits for a feature already present on
  `main`;
- readiness artifacts disagree (`next-actions` says ready, README/handoff says
  not authoritative);
- observers repeatedly report the same mixed/stale state without a decider or
  implementer changing the state.

The observer should not decide or repair directly. It should write a compact
observation to the project loop saying: "Clip History is in split-brain state;
route PM artifact reconciliation or create a fresh build-loop handoff." The
orienter/decider can then choose whether to schedule PM repair, promotion, or
cleanup.

## Audit Assessment

We can answer some questions:

- **Did UX review run after the bad implementation?** Yes. `9ae658d` landed at
  15:57 on 2026-05-04; `9199ed6` recorded the rejecting UX review at 17:09.
- **Was there later corrective work?** Yes. `036a5d8`, `0b70ab0`, `636d3f7`,
  and `2e97372` on `auto/roadmap-1-clip-history` contain frozen snapshot,
  capture snapshot, pseudo-clip, and audition work.
- **Is the old branch merge-ready?** No. It is stale, behind current `main`, and
  carries legacy build-loop noise.

We cannot answer cleanly:

- which actor/request decided to merge `9ae658d`;
- whether a required UX gate was absent, skipped, or simply happened later;
- whether product-owner go-ahead was required at the time;
- which exact prompt/inbox message told the implementer to build the bad shape.

The newer v2 loop should improve this by tying actor requests, finals, evidence,
and decisions to loop-local artifacts. This incident shows why merge/audit
observers need to connect commits to feature state, review timing, and artifact
authority.

## Changes Made

- Reconciled `docs/roadmap/clip-history/README.md`, `spec.md`, `plan.md`,
  `implementation-handoff.md`, `architecture.md`, and `existing-state.md`.
- Added `docs/roadmap/clip-history/build-resume-handoff.md`.
- Updated feature readiness so Clip History can be considered for promotion
  once build capacity opens.

## Follow-Up

- Add a process-health observation pattern for "merged code with later rejecting
  review."
- Add or improve merge-audit evidence so a feature merge records the approving
  observation, decision, actor request, and gate state.
- When Clip History is promoted, start from current `main` and harvest the old
  branch deliberately rather than rebasing it wholesale.
