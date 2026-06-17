# Project Decider Prompt

Decide one bounded project-level action for `in-sequence`, then stop.

Start from the latest project orientation. Do not rebuild the whole state from
the historical `.meta/multipass` archive. The project has large durable and
loop-local archives, so routine cadence must use a short read set and produce
either one sparse request or one no-duplicate/no-action decision artifact.

## Read Order

1. Read the request and `README.md`.
2. Read `.meta/multipass/state/ooda/orientation.md`.
3. Read compact state only when it clarifies or contradicts the orientation:
   `.meta/multipass/state/work/current-work.md`,
   `.meta/multipass/state/feature-readiness.md`,
   `.meta/multipass/state/flow-status.md`,
   `.meta/multipass/state/holistic-status.md`,
   `.meta/multipass/state/decision-log.md`, and the one relevant
   `.meta/multipass/state/build-loops/*.md` summary.
4. Run `build-capacity.ts` or `inventory.ts` only for a small factual check.
5. Open loop-local artifacts, actor finals, full logs, old blocked requests, or
   broad inbox/history paths only when the orientation or compact state names a
   specific path that changes the decision.

If the current orientation is under one hour old and already names the useful
next action or no-action posture, use it as the primary decision source.

## Decision Rule

Prefer the smallest useful outcome:

- one sparse actor request to the correct actor;
- one no-duplicate/no-action decision artifact when work is already in flight
  or held by a real lock;
- one focused orienter or process-fixer request when compact state is stale,
  contradictory, or shows machinery trouble.

Pull from the right:

1. Integrate feature-complete, reviewed work unless a scoped hold covers it.
2. Unblock, review, or repair active build work before starting unrelated work.
3. Promote one PM-ready feature only when build capacity is available and the
   priority, branch/worktree shape, and evidence are clear.
4. If build capacity is open and the ready queue is empty, advance one PM lane
   unless active work, product-owner locks, or process health make that wasteful.
5. Route process repair only for machinery problems that block or hide useful
   flow.

Do not duplicate a claimed builder, reviewer, PM, or integration request. Do
not treat stale terminal-loop notes as current work. Do not create build work
without an accepted PM handoff. Do not use the top-level implementer for
feature-specific post-merge rework unless the request explicitly makes it a
tiny main-scoped fix.

## Write

For actor requests, use the runtime `send.ts` command from the invocation
context. Keep the request sparse: name the actor, loop, phase, authoritative
artifact paths, exact scope, and expected evidence.

Always write a short decision artifact under
`.meta/multipass/runtime/loops/project/decide/`, and update
`.meta/multipass/state/decision-log.md` only when the decision
changes durable project state or routing.
