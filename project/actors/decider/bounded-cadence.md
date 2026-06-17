# Project Decider Bounded Cadence Addendum

This project has a large historical `.meta/multipass` archive. For routine
cadence requests, bound the read set before deciding.

Even on routine cadence, your job is not broad inspection. Use orientation as
the situation brief, then choose the smallest action that improves project
flow: integrate reviewed work, unblock active build work, advance PM prep when
the ready queue is thin, route scoped main/process fixes, or record no-action.

For this project, routine cadence should still protect throughput. Read the
configured build concurrency from `.meta/multipass/multipass.yaml` or the `build-capacity.ts`
output. Aim to keep configured build slots fed with valuable work, and aim to
maintain at least two PM-ready or nearly-ready feature/lane candidates. If a
build slot is open and the ready queue is empty, that is not a passive
no-action state: either promote ready work, start/advance PM prep for another
promising lane, or name the concrete blocker.

## Bounded Read Order

1. Read the request and `README.md`.
2. Read the current orientation first:
   `.meta/multipass/state/ooda/orientation.md`.
3. Read compact state only when it clarifies or contradicts orientation:
   `.meta/multipass/state/work/current-work.md`,
   `.meta/multipass/state/feature-readiness.md`,
   `.meta/multipass/state/flow-status.md`,
   `.meta/multipass/state/holistic-status.md`,
   `.meta/multipass/state/decision-log.md`, and the relevant
   `.meta/multipass/state/build-loops/*.md` summary.
4. Run live helper CLIs only for small factual checks, especially
   `inventory.ts` and `build-capacity.ts`.
5. Open loop-local artifacts, actor finals, full logs, or old blocked requests
   only when the current orientation or compact state names a specific path
   that changes the decision.

Do not recursively scan all `.meta/multipass/runtime/loops/*`, all actor finals, or the
full blocked inbox during cadence. Those archives are fallback evidence, not
the default decision surface.

## Bounded Decision Rule

Prefer one of these outcomes:

- one sparse request to the correct actor;
- one no-duplicate/no-action decision artifact when current orientation says no
  project-level action is useful;
- a focused orienter/process-fixer request when the compact state is stale,
  contradictory, or shows harness trouble.

Do not treat "one PM loop is active" as sufficient by itself. If the upstream
buffer is still empty and build capacity is open or likely to open, schedule or
advance another PM lane unless there is a real sequencing, resource, or product
reason not to.

If a current orientation is under one hour old and already identifies the next
useful action or no-action posture, use it as the primary decision source. If no
clear project-level action appears after the bounded read set, write a short
no-action decision artifact and final evidence instead of expanding the search.
