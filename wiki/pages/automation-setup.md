---
title: "Automation Setup"
category: "meta"
tags: [automation, hooks, skills, claude-code, workflow, loop, settings]
summary: How the project uses Claude Code's hooks, skills, and slash commands to automate plan execution, adversarial review, and wiki maintenance. Lives in .claude/ (committed, project-scoped).
last-modified-by: user
---

## What's automated

The project uses a **behaviour-tree driver** (inspired by [shoe-makers](https://github.com/maxthelion/shoe-makers) and Max's [behaviour-trees blog post](https://blog.maxthelion.me/blog/behaviour-trees/)) wrapped around Claude Code's native features.

- **Behaviour tree** — a selector that, on every invocation, picks the single most-urgent action the repo needs and dispatches it. Hygiene (broken tests, unresolved critiques, unreviewed commits) gates implementation (work-items, plan tasks) gates exploration (drift checks, code-smell scans). Described in `.claude/skills/next-action/SKILL.md`.
- **Hooks** (`.claude/hooks/`) enforce non-negotiables every agent must respect.
- **Skills** (`.claude/skills/`) package the workflow steps as invokable units.
- **Settings** (`.claude/settings.json`) wires hooks + permission allowlists so routine commands don't prompt.
- **State** (`.claude/state/`) persists the BT's view of the world across invocations.

## Directory layout

```
.claude/
├── settings.json              # hooks + permissions + statusline        (committed)
├── settings.local.json        # per-user/machine overrides              (gitignored)
├── hooks/
│   ├── pre-git-push.sh        # PreToolUse: runs xcodebuild test before push
│   ├── pre-write-file-size.sh # PreToolUse: blocks writes >1000 lines to Sources/
│   ├── session-start.sh       # SessionStart: status banner + BT state
│   └── setup-next-action.sh   # BT evaluator (pure bash; writes state/next-action.md)
├── skills/
│   ├── next-action/           # autonomous driver — reads next-action.md, dispatches
│   │   └── SKILL.md
│   ├── execute-plan/          # explicit-invocation batch driver (one plan at a time)
│   │   └── SKILL.md
│   └── adversarial-review/
│       ├── SKILL.md
│       └── reviewer-prompt.md
├── state/                     # behaviour-tree memory                   (committed)
│   ├── README.md
│   ├── next-action.md         # what the next invocation should do
│   ├── work-item.md           # active work (at most one)
│   ├── candidates.md          # ranked queue of potential work
│   ├── partial-work.md        # handoff from a timed-out agent
│   ├── last-review-sha        # HEAD at last /adversarial-review
│   ├── last-tests-sha         # HEAD at last green test run
│   ├── last-tests-failure.md  # if present, tests are red
│   ├── inbox/                 # user-queued messages
│   ├── review-queue/          # outstanding critiques
│   └── insights/              # lateral ideas (innovation tier)
├── scheduled_tasks.lock       # runtime — gitignored (.gitignore:39)
```

## Hooks

Installed via `.claude/settings.json`. Every Claude Code session in this repo inherits them — including subagents spawned via `Task`.

### `PreToolUse` on `Bash` — `pre-git-push.sh`

Reads the tool-use JSON on stdin. If the command contains `git push`:

1. Run `xcodebuild test`
2. Abort if tests fail
3. Abort if working tree is dirty

Non-push `Bash` calls pass through. Cost per push: ~30s–2min depending on build cache. Cost per non-push Bash: a few ms.

**Rationale:** commits can be red during TDD; pushes are the real boundary where "ship" happens. Gating at push lets the normal red/green/refactor cycle work while still blocking bad code from leaving the machine.

### `PreToolUse` on `Write` — `pre-write-file-size.sh`

If the target path is under `Sources/`:

- `> 1000` lines: block with a reference to [[code-review-checklist]] §2 ("No god files")
- `> 500` lines: warn, allow

Encodes the file-size discipline mechanically. Agents can't accidentally ship a god-file; the hook rejects it.

### `SessionStart` — `session-start.sh`

Prints a banner (verbatim format produced by the script):

```
┌─ sequencer-ai status
│ plan:     2026-04-18-app-scaffold.md [all complete]
│ last tag: v0.0.1-scaffold   +3 commits
│ BT state: next-action=verify-tests · inbox=0 · critiques=0 · partial=no · work-item=no · candidates=no
│ drive:    /next-action (auto) · /execute-plan (explicit) · /adversarial-review (manual)
│ refresh:  run .claude/hooks/setup-next-action.sh to recompute next-action.md
└─
```

On a fresh repo with no tags, the `last tag:` line reads `history: <N> commits (untagged)` instead. New sessions orient immediately without having to grep git log.

## Permission allowlists

`settings.json.permissions.allow` lists routine commands that shouldn't prompt the user. Current allowlist covers:

- `xcodebuild`, `xcodegen`, `DEVELOPER_DIR=*`
- Common shell tooling (`ls`, `mkdir`, `rm`, `cp`, `mv`, `chmod`, `test`, `file`, `stat`, `wc`, `head`, `tail`, `sort`, `uniq`, `jq`, `which`)
- Git read-only subcommands (`status`, `log`, `diff`, `show`, `branch`, `tag`, `describe`, `rev-parse`, `rev-list`, `ls-files`, `blame`, `config --get`)
- Git write subcommands that shouldn't prompt in the execute-plan cycle (`add`, `commit`, `restore`, `reset HEAD`, `stash`, `check-ignore`)

Destructive git operations (`push`, `reset --hard`, `rebase`, `tag -d`, etc.) are **not** allowlisted — they still prompt, and `push` goes through the pre-git-push hook regardless.

Extend the list in `settings.json` if a routine command starts prompting mid-cycle.

## The behaviour tree

Single-selector tree evaluated by `setup-next-action.sh`:

```
Selector: next-action
│
├─ [1a] Tests not verified at HEAD?           → verify-tests
├─ [1b] Tests failing?                        → fix-tests
├─ [1c] Outstanding critiques?                → fix-critique (oldest)
├─ [1d] Partial-work handoff file present?    → continue-partial-work
├─ [1e] Unreviewed commits since last review? → adversarial-review
├─ [1f] Inbox messages from user?             → handle-inbox (oldest)
│
├─ [2a] Work-item present?                    → execute-work-item
├─ [2b] Candidates queued?                    → prioritise (→ work-item)
├─ [2c] Active plan with unticked tasks?      → promote-plan-task-to-work-item
├─ [2d] Unfinished sub-specs in north-star?   → write-next-plan
│
└─ [3]  Exploration fallthrough               → explore (→ candidates)
```

One action per invocation. Deterministic given state. Pure bash (no LLM) for evaluation; the LLM is reserved for executing the chosen action.

## Skills

### `/next-action`

Reads `.claude/state/next-action.md` (written by the setup script) and dispatches the named action. Pair with `/loop /next-action` for autonomous overnight execution. Each iteration:

1. Setup script re-evaluates the tree (cheap)
2. `/next-action` reads the chosen action and dispatches a subagent for it
3. State files update
4. Exit; loop schedules next iteration

### `/execute-plan`

One invocation runs one plan's complete cycle:

1. Implementer subagent (via `superpowers:subagent-driven-development`)
2. Three reviewers in parallel — spec-compliance, code-quality, adversarial
3. Fix loop until all Critical / Important findings resolved or deferred
4. `/simplify` cleanup
5. Wiki update subagent
6. Plan file: tick all checkboxes, add `Status: ✅ Completed` line
7. `git tag vX.Y.Z-<slug>`

Pair with `/loop /execute-plan` for continuous plan-queue execution overnight.

### `/adversarial-review`

The third reviewer in the pipeline. Dispatches a deliberately uncharitable reviewer against the committed diff. Finds what the charitable spec+quality pair missed. See `.claude/skills/adversarial-review/reviewer-prompt.md` for the prompt.

Invoke on-demand: `/adversarial-review` (diffs latest tag to HEAD) or `/adversarial-review <base-ref>`.

### Others (deferred)

Planned skills that aren't yet implemented — add when the cycle makes them necessary:

- `/next-plan` — picks the next unfinished sub-spec and writes its plan via `superpowers:writing-plans`
- `/update-wiki` — dedicated wiki-maintenance skill. Currently handled inline by `/execute-plan` step 7 (see `.claude/skills/execute-plan/SKILL.md:60-67`), so a standalone skill is genuinely deferred rather than missing.

## Loop-driven autonomous execution

For hands-off overnight execution:

```
/loop /execute-plan
```

The loop skill self-paces via `ScheduleWakeup`. Between iterations it sleeps (short intervals to stay in prompt cache during active work; longer when waiting on something that takes minutes). Wakes up and evaluates whether the next plan is ready.

If `/execute-plan` surfaces a BLOCKED or NEEDS_CONTEXT condition from a subagent, it stops the loop — autonomous runs never push past a "the controller needs to decide" point.

## Remote layer 🚧 Not implemented

Future additions using `superpowers:schedule` / `CronCreate`. None of this is built yet — nothing below currently runs:

- Daily status summary posted to a git-committed status file
- Weekly spec-compliance replay across the whole tree to catch drift between code and spec

These don't need Xcode (they read markdown + diffs), so they can run as remote scheduled agents in the cloud.

## Turning off the automation temporarily

Ad-hoc exploratory work should not fight the hooks. Options:

- **Push bypass (discouraged):** `git push --no-verify` — Claude Code hooks ignore this flag by design; still gated by the hook
- **Disable hook for one session:** delete or move `.claude/settings.json` temporarily (restore before committing)
- **Per-machine override:** create `.claude/settings.local.json` overriding specific hooks (gitignored)

In practice, the hooks don't get in the way of exploratory work — they only fire on `git push` and `Write` to `Sources/`. Everything else is unchanged.

## Related pages

- [[build-system]] — what `xcodebuild test` actually runs
- [[code-review-checklist]] — the standards hooks enforce
- [[project-layout]] — where code lives
