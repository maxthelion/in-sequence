# Foreman

This directory is the ledger for the Fable-era Foreman experiment and for the
current Foreman-shaped project memory.

The historical Foreman was a single judgment-bearing loop for this project. It
replaced the orient/decide/integrate *roles* of the OODA system with one
persistent context, while keeping the parts of that system that earned their
keep: definition-of-done checklists, evidence pairing, standing observer lenses,
and preserved raw intent.

That experiment was created with the Fable agent, which was more powerful than
the Codex loop available at the time. It produced useful project judgment, but
it was not the final reusable runtime. The current shape is Foreman Coordinator:
Codex runs `/Users/maxwilliams/dev/foreman-coordinator`, using
`.meta/foreman/foreman.yaml` as the live config, while this directory remains a
compact foreman ledger.

Multi-Pass (`.meta/multipass`) was the earlier Codex-first runtime. Its paths
are still used as a compatibility bridge for loop manifests, runtime evidence,
and compact state, but the old `multi-pass-coordinator` binary is not the
normal scheduler now.

## How it runs

- The live project shim is `project/scripts/tick.sh`, which invokes Foreman
  Coordinator.
- `bin/tick.sh` is the older Fable-era wakeup. It is still useful as historical
  reference for the cheap deterministic pre-check idea: watched inputs included
  new bug reports, unresolved feedback, branch list, heartbeat age, and rotating
  observer lenses. Do not assume it is the active scheduler unless a trigger
  explicitly calls it.
- The model invocation is one headless session with `PROMPT.md` as its
  standing instructions. The model is configurable (`FOREMAN_MODEL`); the
  prompt is written so a weaker model on the same prompt degrades into
  caution (it writes attention items instead of acting) rather than chaos.
- Schedule it with cron/launchd, or run `bin/tick.sh` manually after a
  batch of bug reports. `bin/tick.sh --force` skips the pre-check.

## Files

- `PROMPT.md` — the standing prompt. The heart of the mechanism.
- `state.md` — compact picture of what's in flight, written by the foreman
  at the end of every tick. The next tick starts by reading it.
- `attention.md` — the only place that asks for Max's time. Small, ranked,
  each item says what it unlocks.
- `decisions.log.md` — append-only, one line per decision, for audit.
- `checklists/` — definition-of-done gates (bugfix, feature-merge). The
  foreman may not merge anything that fails its checklist.
- `state/watch-fingerprint` — pre-check state, machine-managed.

## Autonomy dial

`FOREMAN_AUTONOMY` in `bin/tick.sh` (or env):

- `full` — fix, dispatch, verify, and merge on green gates without asking.
- `cautious` — everything stops short of merge/destructive actions; those
  become attention items. **Use this when running a weaker model.**

## Current migration rule

When the Foreman Coordinator and this ledger disagree, prefer fresh committed
evidence and the live Foreman config. Preserve the lessons from the Fable
foreman, but route new automation through the Codex-runnable Foreman
Coordinator path.
