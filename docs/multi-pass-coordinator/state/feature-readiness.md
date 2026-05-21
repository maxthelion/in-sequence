# Feature Readiness State

- updated: 2026-05-21
- source: manual PM cleanup after build/merge audit

## ready-for-promotion

- `scene-perform` and `step-sequencer` still have PM-ready evidence and no
  active feature build-loop manifest in the v2 runtime.

## promoted / active

- `mixer-busses` is promoted to build loop `build/mixer-busses` on branch
  `auto/roadmap-5-mixer-busses-ui-finish`, worktree
  `.worktrees/roadmap-5-mixer-busses-ui-finish`.

## complete / do not promote

- `mixer-main-out` is marked `status: complete`, `stage: merged`; `main`
  contains `auto/roadmap-4-mixer-main-out`.
- `send-effects` is marked `status: complete`, `stage: merged`; `main`
  contains `auto/roadmap-6-send-effects`.
- `modifier-chain-placement` is marked `status: complete`, `stage: merged`;
  `main` contains `integration/modifier-chain-7520dbd`.

## stale branch note

- Older modifier-chain branches `auto/roadmap-9-modifier-chain-placement` and
  `auto/goal-9-modifier-chain-placement` are retained as historical/stale
  worktrees for now. They should not be used as merge candidates without a
  separate worktree-hygiene review.
