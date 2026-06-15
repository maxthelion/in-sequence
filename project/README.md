# Project Tick Shim

Meta ticks `in-sequence` through `project/scripts/tick.sh`.

That script is intentionally small. It delegates to the reusable Foreman
Coordinator runtime in `/Users/maxwilliams/dev/foreman-coordinator`:

```sh
bun /Users/maxwilliams/dev/foreman-coordinator/src/cli/tick.ts \
  --project /Users/maxwilliams/dev/in-sequence "$@"
```

The project should not keep a second scheduler, actor roster, or behaviour-tree
model here. The old Multi-Pass shape was the first Codex loop; the Fable-era
Foreman shape proved useful because it held more judgment in one place. The
current hybrid is Foreman Coordinator: Codex runs the reusable Foreman runtime,
while the project temporarily keeps the existing `.meta/multipass/*` evidence
paths as a compatibility bridge.

Current locations:

- `.meta/foreman/foreman.yaml` is the live Foreman Coordinator config.
- `.meta/multipass/config/loops/` contains active loop manifests until the
  migration finishes.
- `.meta/multipass/runtime/` contains inboxes, claims, actor logs, and activity.
- `.meta/multipass/state/` contains compact durable summaries.
- `/Users/maxwilliams/dev/foreman-coordinator/actors/` contains central actor
  prompts.
- `project/actors/` may contain explicit project-local overrides named by
  `.meta/foreman/foreman.yaml`; other local actor files are legacy evidence, not
  a scheduler.
