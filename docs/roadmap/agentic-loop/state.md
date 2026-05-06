---
mode: build-planning
status: ready
updated: 2026-05-06T20:20:00+01:00
next_action: run-pass
---

# Agentic Loop State

## Current Mode

build-planning

## Why

The production cherry-pick candidate synthesis passed UX/IA, architecture, and
testing review for build planning. The next agent-side action is to write the
P0 transient performance overlay build plan before any Swift code is ported.

## Next Expected Output

`docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md`

## Current Assumptions

- User attention should only be requested for high-leverage product judgment.
- Agents should handle review, synthesis, and fix scheduling where possible.
- Do not cherry-pick broad probe branches or probe UI state.
- The P0 production path starts with a build plan for a session/engine-owned
  track-performance overlay, including explicit Keep/Discard ownership and
  tests proving audition does not mutate `Project`.

## Blockers

- none
