---
name: adversarial-review
description: Red-team review of a git diff. Dispatches a deliberately uncharitable reviewer that assumes bugs exist, tests are inadequate, and corners were cut. Complements the standard spec-compliance and code-quality reviews; does NOT replace them. Invoke after an implementer reports DONE and the spec + quality reviewers have passed.
---

# Adversarial Review

## When to use

After a plan (or task within a plan) has been implemented, spec-compliance-reviewed, and code-quality-reviewed — **but before** tagging or pushing. The charitable reviewers have already said "looks fine"; this review asks "what did they miss?"

## What it does

Dispatches a subagent with an **uncharitable** mindset against the committed diff. Two hunt-targets are prioritized above everything else:

1. **Responsibility violations** — code placed in the wrong module, dependencies that cross boundaries in the wrong direction, knowledge leaking between subsystems. Caught against the dependency-direction rules in [[project-layout]].
2. **Duplicate / forked code paths** — new code that reimplements something that already existed. New helpers parallel to existing ones, forked types, copy-paste with drift, new test fixtures when test helpers already exist. The reviewer names both the new code and the existing equivalent and recommends the consolidation direction.

Beyond those two, the reviewer also assumes:

- Bugs exist even if tests pass
- Tests may pass for the wrong reason (tautological assertions, mocks drifting from reality, missing failure-path coverage)
- Names can lie — implementations may not match the contract they advertise
- Corners may have been cut where no one will notice
- Future extensions will break something — find where
- Resource ownership / threading / error paths are the common bug sites — poke them hard

## Usage

Invoke with either:

- `/adversarial-review` — reviews the diff between the latest tag and `HEAD`
- `/adversarial-review <base-ref>` — reviews the diff between `<base-ref>` and `HEAD`

Example: `/adversarial-review v0.0.1-scaffold`

## What to do with findings

The reviewer returns **Critical**, **Important**, and **Minor** findings. Treatment:

- **Critical** → stop, fix before tagging. A critical adversarial finding that the spec+quality reviewers missed is the point of this review.
- **Important** → either fix or consciously defer with a TODO + linked issue. Don't silently ignore.
- **Minor** → your call; add to backlog if they point at genuine debt.

Reported findings are also a useful input to [[code-review-checklist]] updates — if the adversarial reviewer repeatedly finds the same class of issue that the checklist didn't catch, add a checklist item.

## Pairing

This review is the third of a three-stage pipeline:

1. `spec-reviewer` (superpowers:subagent-driven-development) — "did they build what was asked?"
2. `code-quality-reviewer` (superpowers:code-reviewer) — "is it well-built?"
3. `adversarial-review` (this skill) — "what's wrong that the first two didn't see?"

Run all three. Each has a different mindset and will find different issues.

## Prompt template

See `./reviewer-prompt.md` in this skill directory for the exact instructions dispatched to the subagent. Keep the "be uncharitable" framing — the whole point is to counteract the default agreeable stance.

## Steps when invoked

1. Resolve the base ref (argument given, or latest tag, or `main~1` as fallback)
2. Collect the diff: `git diff <base>..HEAD` and `git log <base>..HEAD --oneline`
3. Collect the plan / spec paths currently active (latest in `docs/plans/`, parent spec in `docs/specs/`)
4. Dispatch a subagent with the reviewer prompt and all the above
5. Surface the subagent's findings verbatim, grouped by severity
6. Do not automatically fix or commit anything — findings are surfaced for the controller to act on
