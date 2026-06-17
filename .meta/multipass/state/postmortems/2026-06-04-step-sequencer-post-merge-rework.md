# Step Sequencer Post-Merge Rework Post-Mortem

- date: 2026-06-04
- project: in-sequence
- feature: step-sequencer
- status: process lesson recorded

## What Happened

The Step Sequencer build loop reached terminal complete and was merged. A later
product-owner review of the Track Source clip editor found that the merged
surface still missed part of the approved Variant D intent:

- selecting a step should expose inline rotary/layer controls;
- the old modal or detached inspect flow should not dominate;
- per-step cells should be more space-efficient;
- the Track Source clip editor should share the same selected-step grammar as
  the accepted step sequencer work.

The top loop correctly noticed this as a post-merge product gap:

`.meta/multipass/runtime/loops/project/observe/2026-06-03T15-21Z-step-sequencer-post-merge-gap.md`

The top decider then routed it to the project `implementer` on `main`:

`.meta/multipass/runtime/loops/project/decide/2026-06-03T15-47Z-step-sequencer-track-source-follow-up.md`

The implementer produced useful code and test work, but left it as dirty
uncommitted main-branch changes:

`.meta/multipass/runtime/loops/project/act/2026-06-03T16-29Z-step-sequencer-track-source-follow-up-recovery.md`

## What Went Wrong

The failure was not that the system missed the gap. The observer and decider
both saw it.

The failure was that the repair path was too loosely defined. The decider
treated a feature-specific post-merge UX gap as ordinary scoped main work,
instead of asking whether the completed feature build loop or its branch should
be revived as a focused follow-up loop, rebased from `main`, repaired,
reviewed, and integrated back.

That created three problems:

- the repair bypassed normal build-loop gate pairing;
- the work landed in the main worktree as dirty product files, making ownership
  and audit harder;
- active branches could be affected by main changes without a deliberate
  rebase/integration plan.

## Why It Was Tempting

The feedback was concrete and apparently small. The top loop had an open build
slot but no PM-ready candidate, so the decider chose a fast main-branch fix
rather than spinning up build-loop ceremony.

That instinct was understandable, but it conflated "small" with "safe to do on
main." This was still feature-specific UX rework against a recently merged
feature and should have gone through evidence and review.

## Correct Shape

For post-merge product gaps, the top loop should classify the work before
scheduling it:

- If it is feature-specific and the old feature branch/worktree still exists,
  prefer a focused follow-up build loop on that worktree/branch, rebased from
  current `main` if needed.
- If the old worktree is gone but the change is still feature-specific, create
  a small follow-up branch/worktree rather than editing `main` directly.
- If the issue is a tiny holistic/root fix that is not really tied to one
  feature, route it to the top-level implementer on `main`.
- If the issue exposes stale or contradictory PM artifacts, route PM
  clarification/update before implementation.

In all cases, the output should produce evidence: commit, checks, visual/UX
review when the surface changes, and an integration or closeout record.

## Process Change

The reusable multipass prompts now need to preserve this distinction:

- observers should surface post-merge feature gaps as product facts, not as
  automatic reopen or attention blocks;
- orienters should say whether the gap is feature-specific follow-up,
  holistic main work, PM clarification, or process repair;
- deciders should prefer revived/rebased build-loop rework for feature-specific
  post-merge fixes, and use the top-level implementer only for genuinely small
  main-branch fixes;
- integrators should be able to merge the follow-up branch once the focused
  gates pass.

The goal is not more ceremony. The goal is to keep ownership and evidence
clear enough that post-merge feedback can flow quickly without dirtying `main`
or bypassing review.
