# Human Attention

Items that need a **human on a real machine** — things CI / the headless build
machine / unattended agents cannot do (real-audio listening, GUI/TCC-gated
visual capture, product/design judgement, merge-intent decisions). One file per
item so nothing is forgotten.

When you clear an item, delete its file (or move it to a dated `done/` note).

## Open items

| Item | Kind | Why it needs you |
|---|---|---|
| [verify-send-fx-deadlock](verify-send-fx-deadlock.md) | verify | real-audio: confirm send-FX drag no longer hangs |
| [verify-slice-click-to-map](verify-slice-click-to-map.md) | verify | GUI: slice click-to-map interaction |
| [verify-in-kit-macro-sheet](verify-in-kit-macro-sheet.md) | verify | GUI: in-kit macro sheet |
| [verify-transient-quality](verify-transient-quality.md) | verify | listening: transient/slice audio quality |
| [verify-observer-sweep-audio-input](verify-observer-sweep-audio-input.md) | verify | GUI: gates merging `observer-sweep-remediation` |
| [routing-source-mixer-split](routing-source-mixer-split.md) | decide+verify | rebase decision + TCC-gated capture gate |
| [stale-worktree-branch-cleanup](stale-worktree-branch-cleanup.md) | decide | ~30 worktrees / branches to triage |

## Context

These were surfaced during the 2026-06-23/24 session. The build machine cannot
run real-audio checks or `SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION` captures, so
they accumulated. None blocks the audio-routing cleanup, which proceeds on the
`audio-routing-cleanup` branch.
