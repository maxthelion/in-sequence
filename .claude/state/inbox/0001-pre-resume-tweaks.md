# Pre-resume tweaks (paused 2026-04-18 at commit `3157b58`)

The user paused the autonomous `/next-action` loop to make several tweaks before resuming. This inbox entry is the handoff note so a fresh Claude session (post-context-clear) can pick up cleanly.

## What was happening when paused

- Plan 0 (App Scaffold) complete; tag `v0.0.1-scaffold`
- Automation infrastructure (BT, hooks, skills) built and self-reviewed via 2 adversarial passes
- Review-queue had 3 outstanding findings from the final adversarial pass (2 Important, 1 Minor) — now committed into `.claude/state/review-queue/`
- Context had reached 66% utilisation; natural pause point

## Tweaks the user is making (before resume)

### 1. Role-specialised subagents

Replace the current "dispatch everything to `general-purpose`" pattern with dedicated subagents declared in `.claude/agents/*.md`. Expected roster:

- `implementer.md` — writes code / tests / fixes. Uses **Sonnet 4.5+**.
- `spec-reviewer.md` — verifies implementation matches spec (charitable).
- `code-quality-reviewer.md` — verifies implementation is well-built (charitable, style/idiom focused).
- `adversarial-reviewer.md` — the uncharitable red-team pass. Already has a prompt at `.claude/skills/adversarial-review/reviewer-prompt.md` — mirror the content into an agent so it can be invoked as a first-class subagent type.
- `wiki-maintainer.md` — updates wiki after a plan completes; reads committed diff + current wiki, proposes updates.
- `explorer.md` — writes candidates during the BT's `explore` fallthrough; broad-context scan.
- `prioritiser.md` — picks one candidate and writes a detailed work-item; medium-context focus.

Each agent's frontmatter should specify:
- `description` — when to use it (the BT setup script doesn't look at this, but a human reading the agents directory orients fast)
- Permission scoping where possible (the wiki-maintainer shouldn't be able to touch `Sources/`; the implementer shouldn't be editing the spec)

When these exist, update `.claude/skills/next-action/SKILL.md`'s action-table column "Dispatch" to name the specific agent rather than "a subagent." Also update `AGENTS.md` § "Per-action subagent configuration" to describe the roster.

### 2. Context-clearing discipline between iterations

Each BT iteration should start with narrow context (see shoe-makers' three-phase context-narrowing principle). The user is adjusting their workflow to clear the context window between iterations so subagents get fresh briefs rather than inheriting the previous iteration's chatter.

For a fresh Claude landing: read `AGENTS.md`, run `session-start.sh`, read this inbox item, then proceed.

## Three outstanding review-queue findings

After the pause-related tweaks, the BT's first substantive work is to address these (already in `.claude/state/review-queue/`):

1. **🟡 `important-pre-git-push-compound-bypass.md`** — `pre-git-push.sh`'s current token-based parse only looks at the first two tokens. Compound commands like `git commit && git push`, `bash -c "git push"`, `FOO=bar git push`, `sudo git push`, `echo safe; git push` all bypass the gate. An in-progress rewrite that scanned all command segments got 80% of the way (8/10 test cases) but stumbled on `bash -c "…"` nested-shell recursion; it was reverted. Fresh context is a better environment than half-progress for the shell-parsing problem. Suggested approach on resume: rewrite `pre-git-push.sh`'s detector in Python with a proper recursive shell-segment scanner, test all 10 compound cases + the 8 non-push cases together.

2. **🟡 `important-allowlist-branch-tag-deletion.md`** — `.claude/settings.json`'s `Bash(git branch:*)` and `Bash(git tag:*)` allowlist patterns are too permissive; `git branch -D <name>` and `git tag -d <name>` are destructive and shouldn't be auto-approved. Narrow to specific safe forms (`git branch`, `git branch --list`, `git branch --show-current`; `git tag`, `git tag --list`) and let `-D`/`-d` prompt.

3. **🔵 `minor-pre-write-file-size-header-comment-contradicts-code.md`** — `pre-write-file-size.sh`'s header comment claims the Edit path uses the current file size as a lower bound, but the Python actually simulates the replacement. Comment fix only.

## What the BT state will say on resume

Running `.claude/hooks/setup-next-action.sh` will evaluate:

- Tests not verified at HEAD (`3157b58` vs `last-tests-sha` of `72d6a6c`) → routes to **`verify-tests`**
- After tests green and `last-tests-sha` updated → routes to **`fix-critique`** (oldest is `important-allowlist-branch-tag-deletion.md` lexicographically, then `important-pre-git-push-compound-bypass.md`, then `minor-…`)
- After the 3 critiques cleared → routes to **`adversarial-review`** of the fix commits (may find new items; that's the loop working)
- Once review-queue stays empty past an adversarial pass → BT falls through to [2d] **`write-next-plan`** for Plan 1 (Core engine)

## Where to find what

- `AGENTS.md` (repo root) — full orientation
- `wiki/pages/automation-setup.md` — automation reference
- `docs/specs/2026-04-18-north-star-design.md` — canonical project spec
- `docs/plans/2026-04-18-app-scaffold.md` — Plan 0 (completed; template for subsequent)
- `.claude/state/` — BT memory (review-queue, inbox, last-*-sha, etc.)
- `.claude/skills/next-action/SKILL.md` — BT action table + model-selection rule
- `.claude/skills/adversarial-review/reviewer-prompt.md` — the uncharitable reviewer prompt (priorities: responsibility violations, duplicate code paths)
- `~/.claude/projects/.../memory/feedback_implementation_model.md` — Sonnet-4.5+ rule

## How to resolve this inbox item

When the tweaks above (role-specialised agents + updated skill/agent docs) are in place, the user can either:

- Delete this file (resolves the inbox) and resume `/loop /next-action`, or
- Move this file to `.claude/state/inbox/archive/` preserving the note for history

The BT's `[1f]` routes to `handle-inbox` when anything is in `inbox/`, so the autonomous loop will surface this for any Claude that lands before the resolution happens.
