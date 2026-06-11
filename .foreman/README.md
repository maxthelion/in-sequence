# Foreman

A single judgment-bearing agent loop for this project. It replaces the
orient/decide/integrate *roles* of the OODA system with one persistent
context, while keeping the parts of that system that earn their keep:
definition-of-done checklists, evidence pairing, standing observer lenses,
and preserved raw intent. Multipass (`.meta/multipass`) continues to exist
and run independently; the foreman reads its state but never writes its
inbox or touches its worktrees.

## How it runs

- `bin/tick.sh` is the wakeup. It does a **cheap deterministic pre-check**
  (fingerprint of watched inputs: new bug reports, unresolved feedback,
  branch list, heartbeat age) and only invokes the model when something
  changed or the heartbeat lapsed. Judgment is never spent on "nothing
  happened".
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
