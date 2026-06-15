# In-Sequence Multi-Pass Compatibility State

This directory is the compatibility home for the original Multi-Pass loop
state. Multi-Pass was the first reusable coordination shape, built for Codex.
It introduced loop manifests, runtime inboxes, actor runs, compact summaries,
and evidence files.

The live scheduler is now Foreman Coordinator, configured by
`.meta/foreman/foreman.yaml` and normally invoked through:

```sh
/Users/maxwilliams/dev/in-sequence/project/scripts/tick.sh --write
```

Foreman Coordinator was forked from Multi-Pass after the Fable-era Foreman work
showed that some orient/decide/process roles were better combined into a more
judgment-bearing loop. During migration, Foreman Coordinator still writes to
these `.meta/multipass/*` paths so existing evidence and dashboards remain
usable.

## Tracked Project Shape

- `.meta/foreman/foreman.yaml` is the live runtime config.
- `multipass.yaml` is legacy configuration retained for historical tools and
  old evidence.
- `config/` contains project-local loop instances, lanes, and proposals.
- `state/` contains compact durable current state: observations, decisions,
  loop summaries, postmortems, and current work notes.

## Ignored Runtime Noise

- `runtime/inbox/` contains transient actor requests.
- `runtime/runs/` contains actor prompts, results, stdout, stderr, and run
  records.
- `runtime/reports/` contains generated dashboards and JSON feeds.
- `runtime/activity.ndjson` is the append-only activity feed.
- `runtime/build-attribution/` contains local build attribution records.

Agents should read compact files in `state/` first. They should inspect
`runtime/` only when debugging a recent run, token usage, screenshots, or a
specific failure. Historical runtime material should be rotated rather than
allowed to become default prompt context.

Do not recreate `docs/multi-pass-coordinator`; that was the old mixed-shape
home for durable and transient loop artifacts.

Do not use this directory name as an instruction to run the old
`multi-pass-coordinator` binary. Use the project shim unless explicitly
debugging legacy state.
