---
created: 2026-05-03
status: active
reviewer: codex
scope: roadmap-portfolio
---

# Roadmap Portfolio Plan

This document is the cross-feature planning view. It exists because advancing
each item independently creates too many human review points and can miss that
several roadmap items are really different views of the same underlying model
or UI surface.

The goal is to move the whole roadmap forward with fewer interruptions:

- group features that should be understood or built together;
- sequence features that touch the same files or runtime contracts;
- identify which user decisions are genuinely blocking;
- avoid asking for prototype approval on every item when a lane-level decision
  would be better.

## Current Portfolio State

### Ready or nearly ready for build

| Item | Feature | Portfolio note |
|---|---|---|
| 1 | Clip History | Already promoted into a build worktree. Keep isolated because it touches generator/track-source UI and engine capture state. |
| 2 | Scene Perform | Buildable, small, and mostly local to scene perform UI plus crossfader read path. |
| 3 | Step Sequencer | Buildable direction approved. Should wait until source/modifier shell churn is understood because it touches the track editor editing surface. |
| 9 | Modifier Chain Placement | Buildable and should probably precede Step Sequencer because it reshapes the track-source shell that step editing lives inside. |
| 8 | MIDI Interfaces | Has mature build artifacts, but metadata/prototype approval state is inconsistent. Treat as "ready after metadata cleanup", not as a fresh prototype-review demand. |

### Actually blocked

| Item | Feature | Blocking shape |
|---|---|---|
| 4 | Mixer Main Out | Product questions remain, but they overlap item 5 and item 6. Resolve as a mixer-lane decision, not as isolated questions. |
| 5 | Mixer Busses | Same mixer lane as item 4/6. Solo model, insert scope, and delete/reroute behavior are the real decisions. |

### Prototype review pile

Items 6, 7, 10, 11, 12, 13, 14, 15, 16, 18, 21, 22, and 24 currently surface
as human prototype-review work. That is too much direct user attention. Most of
these should instead be grouped into lane-level reviews so the user sees
strategic choices, not every HTML file.

### Deferred

Items 17, 19, 20, 23, and 25 are intentionally deferred. Leave them out of
ordinary PM/build selection unless the user reactivates them or a lane review
explicitly pulls one forward.

## Recommended Lanes

### Lane A - Track Editor Foundation

**Items:** 1 Clip History, 9 Modifier Chain Placement, 3 Step Sequencer.

**Shared surface:** track editor, source/generator UI, clip editing surface,
selected pattern slot state, transient editor state.

**Recommended order:**

1. Finish the active Clip History build or park it with a clear handoff.
2. Build Modifier Chain Placement to settle the source/modifier slot shell.
3. Build Step Sequencer primitives inside the settled shell.

**Why not parallel?** These items are likely to touch overlapping SwiftUI files.
Parallel worktrees could easily produce competing structures for the same track
editor. Use one build lane or explicitly split by file ownership only after the
current source shell is stable.

**User attention needed now:** none. The risks are implementation coordination
risks, not product questions.

### Lane B - Phrase, Scene, and Song Performance

**Items:** 2 Scene Perform, 10 Phrase Features, 11 Song Mode And Phrase Looping,
22 Scenes In Phrases. Item 25 Selective Scene Inputs remains deferred but is
conceptually adjacent.

**Shared surface:** phrase matrix, free/song mode transport, basis phrase,
scene A/B selection, crossfader state.

**Recommended order:**

1. Build Scene Perform first because it is scoped and independent.
2. Do a lane architecture pass for Phrase Features + Song Mode + Scenes In
   Phrases before promoting any of them.
3. Redo Scenes In Phrases prototypes against the real track-oriented phrase
   page before asking the user to approve them.

**User attention needed now:** one lane-level review later: how phrase rows,
scene rows, and basis phrase controls should coexist. Do not ask the user to
review all phrase/scenes prototypes separately yet.

### Lane C - Mixer Routing and Sends

**Items:** 4 Mixer Main Out, 5 Mixer Busses, 6 Send Effects.

**Shared model:** audio graph ownership, bus routing, insert chains, send/return
semantics, scene A/B mixer state, meters and clipping.

**Recommended order:**

1. Write one mixer-lane architecture note that resolves signal flow for tracks,
   busses, sends, master out, scenes A/B, and meters.
2. Use that note to answer or replace the current open questions for items 4
   and 5.
3. Build the model/routing foundation before polishing mixer strip UI.

**User attention needed now:** yes, but only as lane decisions:

- confirm bus solo behavior: additive solo is the safer DAW-like default unless
  the product intentionally wants exclusive solo;
- confirm bus insert scope: ordinary busses and sends should have global
  inserts unless explicitly scene-scoped later;
- confirm bus deletion behavior: show confirmation with affected routes before
  rerouting to master.

The master fader should be global post-blend; clip indicators should clear
manually unless the user asks for timed reset. These can be recorded as defaults
without another user interruption.

### Lane D - Audio Input, Looping, and Autoslice

**Items:** 7 Input Audio, 14 Audio Looping, 13 Autoslice Algorithm.

**Shared model:** audio interface preferences, input tracks, record buffers,
record scheduling, waveform display, loop boundary/slice heuristics.

**Recommended order:**

1. Input Audio first: select interface, create input track, route to mixer,
   record into buffer.
2. Audio Looping second: macro live-looping page and capable-track controls.
3. Autoslice Algorithm third: isolate sample heuristics and prototype outside
   the main app before committing to an in-app algorithm.

**User attention needed now:** no. The next useful move is a combined
architecture pass so record buffer, loop playback, and slice analysis do not
invent three incompatible waveform/buffer models.

### Lane E - Performance Overrides and Pattern Manipulation

**Items:** 18 Track Fill Toggle, 15 Note Repeat, 16 Step Order, 24 Track Perform
Multi-Select And Latch.

**Shared model:** transient performance overrides, latch/momentary behavior,
track selection sets, selected-track batch edits, fill/repeat/step-order layers.

**Recommended order:**

1. Write a lane architecture note for transient track-performance overrides.
2. Build Track Perform Multi-Select And Latch first because it defines how users
   target one or more tracks.
3. Build Track Fill Toggle as the first override.
4. Build Note Repeat and Step Order after the override model is proven.

**User attention needed now:** no. Item 18's concern has already been resolved:
fill preview is a transient runtime override, not phrase mutation; generator
tracks can be unavailable in v1.

### Lane F - External Control and Automation

**Items:** 8 MIDI Interfaces, 21 Observability From Application Logs.

**Shared theme:** outside systems observe or control the app, but the technical
surfaces are separate.

**Recommended order:**

1. MIDI Interfaces after the main performance UI contracts settle enough that
   hardware mappings are not targeting moving shapes.
2. Observability can proceed independently as a developer/tooling feature, but
   should not compete with music-making lanes for product review time.

**User attention needed now:** none, except metadata cleanup for item 8 if the
selector continues to treat it as needing prototype approval despite having
handoff artifacts.

## How The PM Loop Should Change

The PM loop should not blindly surface every `human-review-prototypes` item as
equally urgent. That creates a "review inbox" instead of a roadmap.

Recommended deterministic behavior:

1. Continue to let per-feature blockers win when an item is actively selected
   for promotion or build.
2. When there is no autonomous PM-agent item, run or surface a portfolio pass
   before asking the user to review another prototype.
3. The portfolio pass should classify items into lanes, identify build order,
   and collapse repeated human-review needs into lane-level decisions.
4. Only surface a user item when it blocks a lane decision, invalidates an
   approved direction, or prevents a build handoff.

The output of that pass should be a concise "User Attention" section:

- true blockers;
- strategic prototype choices that cannot be inferred;
- build-order decisions where two good paths conflict.

Everything else should continue in PM/build loops without interrupting the user.

## Current Recommendation

Do not ask the user to review every outstanding prototype.

Move the roadmap forward in this order:

1. Let the build loop finish or park Clip History.
2. Promote/build Modifier Chain Placement next, then Step Sequencer.
3. Use one mixer-lane architecture pass to resolve items 4, 5, and 6 together.
4. Use one performance-override architecture pass for items 18, 15, 16, and 24.
5. Redo Scenes In Phrases only after the phrase lane architecture grounds it in
   the existing track-oriented phrase page.

Immediate user attention should be limited to the mixer-lane decisions above.
