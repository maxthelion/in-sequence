# Decide: stale worktree / branch cleanup

`git worktree list` shows ~30 registered worktrees and the branch list has many
unmerged branches. Most are stale exploration that won't merge. This is a
hygiene decision (what to keep vs delete) — needs an owner call.

## Triage (as of 2026-06-24)

**Keep / live value:**
- `feature/routing-source-mixer-split` — see [its own note](routing-source-mixer-split.md). UI for R4.
- `observer-sweep-remediation` — see [audio-input verify](verify-observer-sweep-audio-input.md). One gate from mergeable.

**Already absorbed — safe to delete:**
- `codex/timing-probe-poc` — 0 commits ahead of main (its timing probe is in main).

**Likely superseded — confirm then delete:**
- `codex/master-bus-scenes` (+10) — master-bus scenes shipped via
  `roadmap-2-scene-perform`; there's a `backup/roadmap-2-scene-perform-pre-main-integration`.
- `codex/runtime-drum-sample-playback` (+2) — sample voice graph-repair; check if in main.

**Stale exploration — bulk-delete candidates:**
- all `codex/probe-overnight-broad-probe-2026-05-05-*` (7)
- all `codex/probe-ux-feedback-pass-2026-05-06-*` (7)
- old `auto/*` roadmap/goal/overnight branches that have since landed differently.

## Action
A focused cleanup pass: for each branch, `git log --oneline main..<branch>`,
confirm nothing unique survives, then `git worktree remove` + `git branch -D`.
Do NOT bundle any of these into the audio-routing-cleanup branch — they are
unrelated and mostly UI/probe work.
