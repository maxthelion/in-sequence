# Project Work Observer Bounded Cadence Addendum

This project has a large `.meta/multipass` archive and many durable summaries.
Routine work-observer cadence must stay bounded enough to finish and produce a
small evidence artifact.

## Default Read Set

For a routine cadence request, start from compact state instead of rebuilding
history:

1. Read the request and `README.md`.
2. Read `.meta/multipass/state/work/current-work.md`.
3. Read the current project orientation:
   `.meta/multipass/state/ooda/orientation.md`.
4. Read only compact summaries that clarify the active work named there:
   `.meta/multipass/state/feature-readiness.md`,
   `.meta/multipass/state/flow-status.md`,
   `.meta/multipass/state/holistic-status.md`,
   `.meta/multipass/state/decision-log.md`, and the active
   `.meta/multipass/state/build-loops/*.md` summaries.
5. Run small status helpers only when useful: `inventory.ts`,
   `build-capacity.ts`, `recent-runs.ts`, `failure-recovery.ts`, and
   `scripts/multi-pass/inbox-status.sh`.

Open loop-local artifacts, actor finals, blocked requests, raw stdout/stderr,
or broad inbox/history paths only when the compact state names the exact path
and it changes the observation.

## Scope Limits

- Do not recursively scan `.meta/multipass/runtime/loops`, `.meta/multipass/runtime/runs`, or
  the blocked inbox during routine cadence.
- Do not print or paste broad `git diff` output into the final response,
  current-work state, or observation artifact. Summarize changed files and the
  evidence meaning instead.
- Do not update multiple durable state surfaces from a work-observer cadence.
  Write one loop-local observation under `.meta/multipass/runtime/loops/project/observe/`
  and update `.meta/multipass/state/work/current-work.md` only when
  the compact state is stale or materially wrong.
- If the compact state is contradictory and cannot be corrected within the
  bounded read set, record that as an evidence risk and stop. The orienter or
  decider will route a narrower repair.

## Output Shape

Keep the observation concise:

- active work and exact output states;
- missing, stale, failed, or superseded evidence pairings;
- lowest unmet readiness for each active item;
- what would make each item showable;
- checks run.

No inbox messages, lifecycle moves, product-code edits, merges, rebases,
visual capture, or product-owner questions belong in this actor.
