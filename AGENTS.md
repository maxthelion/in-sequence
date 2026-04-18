# Agent Handoff

A fresh Claude session landing in this repo should read this file first. It covers what the project is, how the autonomous build loop works, what state to inspect to orient, and how to resume or pause the loop safely.

## What this repo is

`sequencer-ai` — a macOS-native step sequencer (Swift + SwiftUI + CoreMIDI + AVAudioEngine). The north-star design lives at `docs/specs/2026-04-18-north-star-design.md`. The spec enumerates 13 implementation sub-specs (Plans 0 through 12) in its **Decomposition** section.

**Plan 0 (App Scaffold)** is complete — tag `v0.0.1-scaffold`. The repo has a working macOS app skeleton: document-based, three-column SwiftUI shell, CoreMIDI client with virtual endpoints, app-support library bootstrap. Plans 1 through 12 are still to execute.

## The automation mechanism

The repo is set up to build itself overnight via an autonomous **behaviour-tree loop** inspired by [shoe-makers](https://github.com/maxthelion/shoe-makers). One action per loop iteration; hygiene (broken tests, critiques, reviews) gates implementation (work-items, plan tasks) gates exploration.

**Full reference:** `wiki/pages/automation-setup.md`. Below is the short orientation — for a new Claude, read both.

### Architecture

- **`.claude/hooks/setup-next-action.sh`** — pure bash. Reads `.claude/state/` + git state. Evaluates the selector tree deterministically. Writes `.claude/state/next-action.md` naming the single action to take next. Runs instantly; no LLM.
- **`/next-action` skill** — reads `.claude/state/next-action.md`, dispatches the named action via a subagent. Under `/loop /next-action`, this becomes the continuous driver.
- **`.claude/state/`** — the BT's memory. See [`.claude/state/README.md`](.claude/state/README.md) for what's durable vs generated.
- **`.claude/settings.json`** — hooks + permission allowlists + statusline. The hooks gate `git push` (test + dirty-tree check), the `Write`/`Edit` file-size cap (blocks >1000 lines under `Sources/` or `Tests/`), and a `SessionStart` banner.

### The behaviour tree

```
Selector: next-action
│
├─ [1a] Tests not verified at HEAD?             → verify-tests
├─ [1b] Tests failing?                          → fix-tests
├─ [1c] Outstanding critiques in review-queue?  → fix-critique (oldest)
├─ [1d] Partial-work handoff present?           → continue-partial-work
├─ [1e] Unreviewed commits since last review?   → adversarial-review
├─ [1f] Inbox messages from user?               → handle-inbox (oldest)
│
├─ [2a] Work-item present?                      → execute-work-item
├─ [2b] Candidates queued?                      → prioritise (→ work-item)
├─ [2c] Active plan with unticked tasks?        → promote-plan-task-to-work-item
├─ [2d] Unfinished sub-specs in north-star?     → write-next-plan
│
└─ [3]  Exploration fallthrough                 → explore (→ candidates)
```

## How to monitor (as a new Claude)

Run these three things in order when you land:

1. **`.claude/hooks/session-start.sh`** — the banner tells you the current plan, tag + commits-ahead, BT state counters (next-action / inbox / critiques / partial / work-item / candidates), and how to drive.

2. **`git log --oneline | head -15`** — see what the last run(s) did. Commits follow the pattern `<type>(scope): <summary>`, with `fix(automation): …` signalling review fixes.

3. **`ls .claude/state/ && ls .claude/state/review-queue/ && ls .claude/state/inbox/`** — see what state the BT is operating on. If `review-queue/` is non-empty, the loop is working through critiques. If `inbox/` is non-empty, something needs human attention (treat as a signal to slow down and read the inbox items before doing more work).

4. **`.claude/hooks/setup-next-action.sh`** — writes a fresh `.claude/state/next-action.md`. Read it to know what the BT thinks should happen next.

## How to resume the loop

**Single iteration (recommended for mid-session work):**

```
.claude/hooks/setup-next-action.sh        # evaluate tree
cat .claude/state/next-action.md          # see what's next
# then dispatch the action — either invoke /next-action, or manually
# dispatch a subagent for the action named (verify-tests, fix-critique,
# adversarial-review, execute-work-item, etc.)
```

**Continuous (autonomous overnight runs):**

```
/loop /next-action
```

Before running the loop continuously, strongly consider:

- Moving to a daily branch: `git checkout -b auto/YYYY-MM-DD`. This follows the shoe-makers discipline of nothing reaching `main` without human review.
- Confirming `.claude/state/inbox/` is empty (unresolved user requests block progress in the right way, but you should know about them).
- Running `.claude/hooks/setup-next-action.sh` first and reading the chosen action — if it looks unsafe or off-base, pause.

## How to pause the loop

If the loop is running under `/loop`, press Ctrl-C in Claude Code or send an inbox message:

```
printf '# please pause\n\n<your reason>\n' > .claude/state/inbox/$(date +%s)-pause.md
```

The next iteration's BT evaluation routes to `handle-inbox` ([1f]); `/next-action`'s handling of inbox items is designed to exit and wait for the user.

## How each action works

### Reviews

- **`verify-tests`** — run `xcodebuild test`. On pass, write HEAD SHA to `.claude/state/last-tests-sha`. On fail, write output to `.claude/state/last-tests-failure.md` — the next iteration routes to `fix-tests`.
- **`fix-tests`** — dispatch an implementer subagent briefed with the failing output. Scope: make tests green without changing contracts.
- **`adversarial-review`** — invoke the reviewer at `.claude/skills/adversarial-review/reviewer-prompt.md` against `git diff <last-review-sha>..HEAD`. Each finding becomes a file in `.claude/state/review-queue/` named `<severity>-<slug>.md`. Update `last-review-sha` on completion. The reviewer prioritises (1) responsibility violations and (2) duplicate / forked code paths above the usual checks.
- **`fix-critique`** — oldest file (lexicographic, not mtime) from `review-queue/` is the brief. Implementer fixes, deletes the file, commits.

### Work execution

- **`execute-work-item`** — briefed with `.claude/state/work-item.md`. Uses `superpowers:subagent-driven-development` for the implementer + review cycle.
- **`prioritise`** — reads `candidates.md`, picks one, writes a detailed `work-item.md` with the specific brief the executor will need.
- **`promote-plan-task-to-work-item`** — if the active plan has unticked `- [ ]` tasks, the next one becomes a work-item.
- **`write-next-plan`** — invokes `superpowers:writing-plans` for the next sub-spec from the north-star.
- **`explore`** — writes new candidates: wiki-code drift, TODOs, coverage gaps, etc.

### Context-narrowing discipline

From the shoe-makers pattern: each phase hands off a well-scoped brief.

- **Explore** (broad context) → `candidates.md`
- **Prioritise** (medium context) → `work-item.md`
- **Execute** (narrow context — only reads `work-item.md`)

If `execute-work-item` is reading broadly to figure out what to do, the prioritise step didn't write a good brief. That's a signal to improve the prioritise prompt, not to workaround in execute.

## Per-action subagent configuration (ongoing work)

The current implementation dispatches all actions through a `general-purpose` subagent. Future iterations are moving to **role-specialised subagents** (e.g., a dedicated reviewer agent, implementer agent, wiki-maintainer agent), declared in `.claude/agents/` with appropriate permission scoping. If you find `.claude/agents/*.md` files on a fresh land, they're the current roster. Check `.claude/settings.json` for agent-specific hook overrides.

Role-based permissions aren't yet enforced by Claude Code's subagent layer natively — today it's by convention in the dispatch prompts.

### Model selection

**Implementation subagents must use Sonnet 4.5 or newer.** In the `Agent` tool, pass `model: "sonnet"` (which resolves to the current default — Sonnet 4.6 / Opus 4.7) explicitly. Never dispatch code-writing work to Haiku or older Sonnet. This applies to:

- `execute-work-item`, `fix-critique`, `fix-tests`, `continue-partial-work` (implementers)
- `promote-plan-task-to-work-item` execution
- `write-next-plan` (invokes `superpowers:writing-plans`, which itself dispatches further)

Reviewers (spec-compliance, code-quality, adversarial), explore / prioritise coordinators, and status-summary agents can use default models — the quality bar for review / triage is lower-stakes than for code generation.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Hook blocks every Bash call with "xcodebuild test FAILED" | Tests genuinely failing at HEAD, OR hook mis-detecting a push | Run `xcodebuild test` manually; check `.claude/state/last-tests-failure.md` |
| `setup-next-action.sh` produces stale next-action | Script exited mid-evaluation | Check `find docs/plans -maxdepth 1 -type f -name '*.md'` succeeds; check `last-review-sha` exists and points at a reachable commit |
| Loop keeps picking the same critique | `fix-critique` fixed the underlying issue but didn't delete the file | Manually delete the file; re-run setup |
| Adversarial review finds the same issue repeatedly | Review fixes introducing new instances of the pattern | Step back, address the root cause across the codebase — don't patch each instance |
| Tests green locally, hook still blocks push | Dirty tree (stash or commit first) | `git status`; commit or stash |

## Non-negotiables (hooks enforce these mechanically)

- **Tests must pass to push.** `pre-git-push.sh` runs `xcodebuild test` before every real push.
- **Files under Sources/ and Tests/ must stay under 1000 lines.** `pre-write-file-size.sh` blocks both Write and Edit operations that would breach the cap.
- **The working tree must be clean to push.** Part of the same hook.

If a hook gets in your way, fix the underlying condition — don't disable the hook.

## Key references (read before deep work)

- `docs/specs/2026-04-18-north-star-design.md` — the canonical spec, all 22 open questions resolved
- `docs/plans/2026-04-18-app-scaffold.md` — Plan 0 (✅ completed), template for subsequent plans
- `wiki/pages/automation-setup.md` — full automation reference
- `wiki/pages/code-review-checklist.md` — project review standards; every review aligns with this
- `wiki/pages/project-layout.md` — module boundaries + dependency direction
- `wiki/pages/midi-layer.md`, `wiki/pages/document-model.md`, `wiki/pages/build-system.md` — stable truths from Plan 0
- `.claude/skills/adversarial-review/reviewer-prompt.md` — the uncharitable reviewer used by `/adversarial-review`
- `.claude/skills/next-action/SKILL.md` — action table for the BT leaves

## Writing style

Follow what's in `wiki/pages/code-review-checklist.md` and match the existing code's naming / structure. The project is intentionally decomposed into small focused files — don't create god files, don't create `Utils.swift`. If you're unsure where something goes, check `wiki/pages/project-layout.md` for the current module boundaries.

## Final note for a fresh Claude

The automation's whole value is that it produces **trustworthy** decisions. If you spot something that looks off — the BT picked an action that doesn't make sense given the state, the hooks flagged something unexpected, a review finding contradicts what you just read — **pause and investigate before proceeding**. Drop a note in `.claude/state/inbox/` describing what confused you; the user will see it and clarify. The loop-driven model only works when each agent can trust the previous agent's output.

Happy building.
