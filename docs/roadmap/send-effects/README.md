---
id: 6
title: Send Effects
status: inventory
priority: unset
blocked_by:
  - mixer-busses:open-question-2
stage: review-architecture
owner: pm
updated: 2026-04-30
---

# Send Effects

Status: Inventory — architecture written, pending architecture review.

Three open questions require user input before spec can be written:
1. Send bus insert scope (global vs. scene-scoped) — blocked on Mixer Busses Q2.
2. Return path (`finalOutputMixer` vs. `preMasterMixer`).
3. Muted-track send behavior (mute cuts send tap vs. pre-mute tap).

See `open-questions.md` and `architecture.md` Section 9.
