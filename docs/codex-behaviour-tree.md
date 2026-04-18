# Codex Behaviour-Tree Loop

This repo's behaviour tree already has the right split for Codex:

- `.claude/hooks/setup-next-action.sh` is the cheap deterministic selector.
- `.claude/state/` is the durable memory.
- Codex executes exactly one leaf action per wake-up, then exits.

The Codex-specific addition is a small helper entrypoint:

```bash
./scripts/codex/bt-iteration.sh
```

That command:

1. refreshes `.claude/state/next-action.md`
2. prints the chosen BT leaf
3. restates the "one action only" contract Codex should follow
4. prints the current `next-action.md` contents

## Why this works

Codex does not need a second planner. The existing behaviour tree already decides what should happen next. The only thing Codex needs is a reliable way to:

- refresh the tree against current state
- see the chosen action
- execute one iteration in a dedicated worktree
- stop cleanly when human input is required

That is exactly what `bt-iteration.sh` prepares.

## Worktree setup

Keep Codex in its own checkout so it does not interfere with Claude's active loop:

```bash
git worktree add -b codex-bt-loop ../sequencer-ai-codex <base-commit-or-branch>
```

The worktree used for the first Codex experiment was:

```text
/Users/maxwilliams/dev/sequencer-ai-codex
```

Because `.claude/state/` is committed, each worktree gets its own branch-local copy of the BT memory. That lets Claude finish its current iteration in the original checkout while Codex experiments safely elsewhere.

## Manual single iteration

From the Codex worktree:

```bash
./scripts/codex/bt-iteration.sh
```

Then Codex should:

1. read `.claude/state/next-action.md`
2. execute exactly one BT action
3. update any state files that action owns
4. rerun `.claude/hooks/setup-next-action.sh`
5. stop

Codex should not chain directly into the next action. The next automation wake-up should trigger a fresh evaluation.

## Heartbeat automation

The most natural Codex-native driver is a thread heartbeat. The heartbeat prompt can stay very small because the repo already contains the selector and the action contract.

Suggested prompt:

```text
Operate only in /Users/maxwilliams/dev/sequencer-ai-codex.
Run ./scripts/codex/bt-iteration.sh first.
Execute exactly one behaviour-tree action from .claude/state/next-action.md.
Use .claude/state/ as durable memory.
If the action needs a human decision or would be unsafe to continue, write a markdown note to .claude/state/inbox/ and stop.
When the action is done, rerun .claude/hooks/setup-next-action.sh and stop.
```

Suggested cadence:

- active implementation: every 30 minutes
- low-touch overnight monitoring: hourly

## Action ownership

Keep the same discipline the Claude loop already uses:

- `setup-next-action.sh` decides
- `next-action.md` describes
- the active action updates only the state files it owns
- the next wake-up re-evaluates everything from scratch

That preserves the trust model of the behaviour tree. Codex is acting as an executor, not a second planner.

## Safety notes

- Leave the original checkout alone if another agent is already using it.
- Prefer a dedicated branch per Codex loop or per day.
- If Codex hits uncertainty, route through `.claude/state/inbox/` rather than improvising across multiple BT leaves.
