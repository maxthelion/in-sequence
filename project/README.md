# Project-Local Ticker

This folder contains the project-owned orchestration skeleton for `in-sequence`.

Meta should not decide what the coordinator, build loop, review loops, PM loop,
or process fixer mean. Meta should call `project/scripts/tick.sh`; this project
script owns the local roster and dispatch order.

The first version is intentionally small:

- write a coordinator cadence note when the coordinator has not run recently;
- write a process-fixer note when blocked requests exist;
- dispatch one runnable inbox request per tick by default;
- execute actors through local `project/actors/*/run.sh` scripts;
- leave blocked/malformed requests for a judgment actor instead of collapsing
  them into idle.

The roster lives at `project/scripts/loops.tsv`.

## Runtime Shape

- `project/lib/inbox.sh`: tiny markdown inbox helpers. It only understands a
  minimal `status:` line; no rich frontmatter model is required.
- `project/lib/codex.sh`: one Codex runner with timeout handling.
- `project/actors/<actor>/run.sh`: actor entrypoints.
- `project/behaviour-trees/pm-loop/tick.sh`: wrapper for the existing PM
  behaviour-tree path.

The former shared `multi-pass-coordinator` runtime should be treated as a
reference/template source, not as the project scheduler.
