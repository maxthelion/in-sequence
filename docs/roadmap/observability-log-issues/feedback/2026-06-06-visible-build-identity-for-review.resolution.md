# Resolution: visible build identity for review

- date: 2026-06-11
- resolved by: Codex interim work, verified and landed by foreman
- commit: e56c5f75

`BuildIdentity` (Sources/App/SequencerAIAppDelegate.swift) reads version,
bundle build, GitCommit, GitBranch, GitDirty, and build-attribution keys
from the bundle, normalising empty/unexpanded `$(...)` values to
"unknown". It is logged at launch (`logSummary`) and surfaced in the UI
via `compactDisplay` in the top bar (StudioTopBar changes in the same
commit).

Verification: full suite green over the change (standard CoreAudio
skips), including new SequencerAIAppDelegateTests cases pinning the
bundle-value cleaning rules.

Remaining: the multipass observability-log-issues loop had partial
pipeline-wiring work for the same feedback in its own worktree
(`.worktrees/roadmap-21-observability-log-issues`, dirty on top of
714fdb8). Its decider should reconcile against this landed
implementation rather than re-landing a parallel one.
