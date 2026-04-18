# 🔵 Minor — `automation-setup.md` contains several "aspirational" statements that don't match the committed code

**File:** `wiki/pages/automation-setup.md` (various)

## What's wrong

Several statements in the wiki page describe behaviour that isn't in the actual hook scripts:

1. **Line 193 — "Push bypass (discouraged): `git push --no-verify` — Claude Code hooks ignore this flag by design; still gated by the hook."** The pre-git-push.sh is a `PreToolUse` hook on the `Bash` tool; if the tool matcher runs, `--no-verify` doesn't short-circuit it. True. But this only protects against `git push --no-verify` as a Bash tool call; if an agent shells out via `bash -c 'git push --no-verify'`, the pattern `*"git push"*` still matches. If the agent runs `GIT_TERMINAL_PROMPT=0 git push --no-verify` or uses a custom git wrapper, the hook still fires. Good, but worth tightening the matcher (see `critical-pre-git-push-substring-match.md`).

2. **Lines 82-89 — Banner example shows `│ docs:` and `│ review:` lines** that the actual `session-start.sh` doesn't produce. Real output is `│ BT state:`, `│ drive:`, `│ refresh:`. The doc banner is more useful content-wise (mentions `/simplify`, spec locations) — either update the script to include those lines or update the doc to match reality. Right now it's confusing for anyone reading the doc before running the hook.

3. **Line 50 — `scheduled_tasks.lock` placement** is shown as a peer of `state/`, but `.gitignore:39` puts it at `.claude/scheduled_tasks.lock`. Diagram consistency.

4. **Lines 181-187 — "Remote layer (not built yet)"** is a forward-looking section, which is fine; but it should be explicitly headed with a "🚧 Not implemented" marker so a reader doesn't assume the daily-status summary exists.

5. **Lines 160-166 — `/next-plan` and `/update-wiki` listed under "Others (deferred)"** — OK that they're labeled deferred, but `execute-plan/SKILL.md:61-68` (step 7) describes what amounts to an inline `/update-wiki` implementation. Worth a cross-reference so a reader understands the skill is embedded, not missing.

## What would be right

- Update the doc's banner example to a verbatim copy of what the script currently prints.
- Add `🚧` or `(not yet built)` markers next to forward-looking sections.
- Cross-link the inline wiki-update-step in `execute-plan/SKILL.md` from the "Others (deferred)" section.

## Why it matters

The wiki's value is as a ground-truth reference. When it drifts from the code, future contributors either (a) do extra discovery work to find out which is true, or (b) copy the wiki's claim into their own work, propagating the drift. Both are more expensive than keeping the doc and code in sync from the start.
