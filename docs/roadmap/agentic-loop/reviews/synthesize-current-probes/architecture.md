---
pass: synthesize-current-probes
lens: architecture
status: passed
created: 2026-05-06T13:18:34.339Z
completed: 2026-05-06T14:18:58+01:00
---

# Architecture Review

## Result

Passed for a probe/skeleton build, with production boundaries called out.

The synthesis correctly treats the current branches as evidence and raw
material, not production architecture. It separates document truth, runtime
session state, engine/audio graph behavior, and probe-only fixtures enough for
the next pass to stay reversible.

## Checks

- Shared concepts are named as identities that must be unified: source slot,
  capture artifact, shared audio buffer, transient overlay, routing graph, and
  basis phrase.
- Known bad harvest paths are blocked: UI-local `@State` models, synthetic
  audio capture, fake autoslice, local bus/send identity, and local queued
  phrase state.
- The next pass is scoped as a wireframe/skeleton with no document schema or
  real audio graph changes unless a later production plan explicitly owns them.
- Mixer defaults are recorded as inferred defaults, avoiding unnecessary user
  interruption before a visual source of truth exists.

## Required Follow-Up In Wireframe Pass

- Label each interactive region with its intended owner: document,
  session/runtime, engine, audio graph, or disposable fixture.
- Do not copy probe models as production truth; use seeded fixture state for
  the wireframe and defer real ownership to later build plans.
- Keep route, buffer, phrase, scene, and overlay IDs stable inside the fixture
  so tests can assert identity rather than display coincidence.
