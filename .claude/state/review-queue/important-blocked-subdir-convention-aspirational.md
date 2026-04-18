# Important: `review-queue/blocked/` convention is aspirational, not wired

**File:** `.claude/hooks/setup-next-action.sh`, lines 105–110 (comment block above `[1c]`)
**Severity:** Important

## What's wrong

The comment says:

> Only count/dispatch top-level files. Subdirs (e.g. `blocked/` for items awaiting user authorization) are held out of the queue on purpose.

But:

- No `blocked/` directory exists.
- No other doc (wiki, AGENTS, skills) mentions the convention.
- No tool or process moves items into `blocked/` — a human has to do it manually.
- There's nothing that moves items BACK OUT of `blocked/` when their blocker clears.

The comment implies a system; the repo has the hole but not the fill. Aspirational language in load-bearing config rots into cargo-cult.

## What would be right

Either:

1. **Wire the convention** — create `.claude/state/review-queue/blocked/README.md` describing the move-in / move-out process, add a BT action (e.g. `handle-blocked`) or at least document the manual procedure in AGENTS.md, and mention the convention where it's referenced.

2. **Drop the comment** — replace with something like: "subdirs inside review-queue are held out of the top-level scan; use them as needed for parking items."

Option 2 is the smaller fix and preserves the BT's defensiveness. Don't document a convention you haven't wired.

## Acceptance

- Either the `blocked/` convention is documented end-to-end with a move-in/move-out path, or the comment stops naming a convention.
