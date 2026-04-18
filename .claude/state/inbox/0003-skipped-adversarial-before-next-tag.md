# Skipped adversarial review of d82ea2d..3f0aded — re-run before next tag

User directive on 2026-04-18: "we're getting stuck on infrastructure. I
want to move on to the rest of the plan."

`last-review-sha` was bumped from `d82ea2d` to `3f0aded` without running
the adversarial pass over those 8 commits. All 8 are automation/hygiene
(hooks, agents, settings.json, skill docs); no `Sources/` or `Tests/`
changed. Tests green at `3f0aded`. The deferred pass is a belt-and-braces
check, not a safety gate.

## Resolution options

- **Before tagging Plan 1** (or whenever the next adversarial pass runs
  naturally): include `d82ea2d..<current HEAD>` in the review range.
  The reviewer will re-examine the skipped commits alongside whatever
  new code landed.
- Or delete this file if a later adversarial review has already covered
  the range (check the reviewer's "Context" block for the base ref).

## What the skipped review would likely have flagged

Educated guess, not a substitute for running it:

- Scanner two-pass interaction — regex fallback might mask token-scan bugs.
- New prefix-word combinations (`sudo env eval "git push"`) not in tests.
- Deny list still has equals-form (`--delete=feature`) and missing orderings (`-Dfr`, `-fr`).
- "Brief determines scope" rule has ambiguity: what if the brief names
  no file? What if it names two files across scope tiers?
- `execute-plan` SKILL still has its own mini-roster via `subagent_type:`
  names — that's a third place that must stay in sync with AGENTS.md.

None of these are urgent enough to block plan progress, but they're
worth a pass before the next tag.
