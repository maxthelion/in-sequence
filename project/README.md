# Project Tick Shim

Meta ticks `in-sequence` through `project/scripts/tick.sh`.

That script is intentionally small. It delegates to the reusable Multi-Pass v2
runtime in `/Users/maxwilliams/dev/multi-pass-coordinator`:

```sh
bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/tick.ts \
  --project /Users/maxwilliams/dev/in-sequence "$@"
```

The project should not keep a second scheduler, actor roster, or behaviour-tree
model here. Active loops live in `docs/multi-pass-coordinator/loops/`; runtime
inboxes, claims, and actor logs live under `.meta/multipass/`; central actor
prompts live in the Multi-Pass repo.

Any remaining `project/actors`, `project/lib`, or project-local roster files are
legacy from the pre-v2 experiment and should not be treated as live automation.
