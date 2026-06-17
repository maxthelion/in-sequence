# In-Sequence Project Spirit

This is the compact read-first context for Multi-Pass actors. Use the full
`README.md` only when this summary or the request leaves a real ambiguity.

In-Sequence is a performance-oriented sequencer for building and manipulating
musical ideas live. The app should feel like an instrument: fast, legible,
recoverable, and coherent under pressure.

Core product priorities:

- Users should be able to build patterns, phrases, scenes, tracks, modifiers,
  mixer routing, and performance controls into one coherent live workflow.
- The UI should preserve musical intent and flow. Avoid isolated panels that
  implement a feature mechanically while weakening the workspace as a whole.
- Prefer visual, inspectable evidence for UX questions: screenshots,
  prototypes, and concrete interaction paths beat long prose.
- Product-owner attention is scarce. Agents should make good bounded guesses,
  build, check, and rework. Ask only for genuinely interesting product calls.

Architecture guardrails:

- Performance-time interaction must not depend on slow document-oriented writes.
  Live parameter changes should go through the runtime/session/live data path
  and fast buffers where appropriate.
- The project document is for authored durable state, undo/redo, persistence,
  and intentional saved changes. Do not use it as the hot path for playback or
  per-gesture performance controls.
- Avoid duplicate code paths, overlapping managers, and parallel abstractions
  that do the same job with different names.
- For architecture review, check local wiki guardrails such as
  `wiki/pages/architecture-guardrails.md`, `wiki/pages/engine-architecture.md`,
  and `wiki/pages/playback-data-path.md` when the request touches runtime,
  audio/MIDI, persistence, or performance controls.

Loop discipline:

- Observers gather evidence. Orienters interpret evidence. Deciders schedule the
  next action. Actors implement or integrate.
- Use compact state and current loop artifacts before raw actor transcripts.
  Runtime logs are fallback evidence, not normal reading material.
- A build output is not done until the current exact state has paired evidence:
  tests, architecture, UX/IA, visual economy, screenshots, or other checklists
  appropriate to the work.
- Post-merge feedback should be handled quickly. Recent feature work can often
  be repaired in its existing worktree; older or cross-cutting issues may belong
  in the top project loop.
