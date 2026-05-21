# scene-perform

- loop: `build/scene-perform`
- status: active
- branch: `auto/roadmap-2-scene-perform`
- worktree: `.worktrees/roadmap-2-scene-perform`
- created: 2026-05-21T07:44:09.809Z

This is the durable build-loop summary. Transient inboxes, runs, and evidence live under `.meta/multipass/loops/build/scene-perform/`.

## Current Decision

- 2026-05-21T07:49:00Z: first builder action scheduled.
- Current output state: branch is clean at `4ebbc44` and already contains a Scene Perform source/test slice, but it is behind current `main`.
- Merge-tree conflicts to handle before gates: `SequencerAI.xcodeproj/project.pbxproj`, `Sources/Engine/EngineController.swift`, `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`, `docs/roadmap/next-actions.md`.
- Next action: builder should rebase or replay the bounded production slice onto current `main`, preserve the approved Scene Perform behaviour, run focused/full checks as feasible, and capture UI evidence.
