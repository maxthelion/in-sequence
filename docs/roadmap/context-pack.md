---
status: ready
updated: 2026-05-06T14:05:00+01:00
---

# in-sequence Context Pack

This is the compact product truth every agent should read before doing
project work. It is deliberately shorter than the wiki and points to longer
references where implementation detail matters.

Some concepts below are aspirational north star, not guaranteed current
implementation. Agents should use this file for product taste and whole-app
direction, then check the wiki/code before assuming a capability exists.

## North Star

In-sequence is a generative DAW/groovebox for turning musical accidents into
arrangements.

The product should make it easy to:

- generate or perform something surprising;
- recognize that it is good;
- capture it before it disappears;
- vary it without losing the original;
- arrange it into phrases/scenes/song structure;
- perform with it again;
- preserve or discard performance changes intentionally.

The app should feel like an instrument and idea playground, not a dashboard of
independent feature panels.

Useful UX compass:

```text
play -> generate -> notice -> capture -> arrange -> perform -> preserve/discard
```

## Whole-App User Stories

- As a user, I want to start with a loop or generator and quickly turn the
  parts I like into reusable clips, phrases, and arrangement structure.
- As a user, I want generated melodies, drums, slices, and modulation to feel
  coordinated so randomness is bounded by musical taste.
- As a user, I want to perform track, phrase, scene, and mixer changes live,
  then capture good moments as durable musical state.
- As a user, I want to change the rules of a system and hear new variations on
  material I already like.
- As a user, I want setup/editing work and performance work to feel connected:
  performance changes should be safe, reversible, and saveable.

## What Matters

- Immediacy: getting sound and variation running quickly is valuable.
- Tasteful curation: happy accidents are good only when the user can bound,
  compare, capture, and return to them.
- Visible consequence: the UI should show what is currently sounding, what is
  being generated, and what can be captured or discarded.
- Whole-app coherence: tracks, clips, phrases, scenes, mixer, and performance
  controls are views over one musical system.
- Safe performance: live gestures should not feel like accidental permanent
  edits unless the user explicitly commits them.
- Visual evidence: UX review should prefer screenshots, wireframes, contact
  sheets, and diagrams over long prose.

## Workspaces And Ownership

- Tracks: roster, creation, grouping, selection, compact status, broad gestures.
- Track Editor: source slots, clips, generators, modifier chains, step editing,
  macro lanes, destination editing.
- Phrase Matrix: phrase rows, track columns, layer values, pattern-slot
  selection, mute/fill/macro values, phrase length/repeats.
- Live / Track Perform: fast performance lens over track/phrase state,
  multi-select, latch/momentary gestures, immediate auditioning.
- Scene Perform: scene A/B selection, crossfader, scene cue/apply behavior, and
  performance changes around scene state.
- Mixer: signal-level decisions: track level/pan, busses, sends, inserts,
  master, metering, scene A/B mixer state where relevant.
- Preferences: app/device setup, MIDI/audio interfaces, library/app support.

## Lanes

- Track Editor Foundation: clip history, modifier chain placement, step
  sequencer, source/modifier shell.
- Phrase, Scene, And Song Performance: phrase features, scene perform, song
  mode/phrase looping, scenes in phrases.
- Mixer Routing And Sends: mixer main out, busses, sends, inserts, master,
  scene/mixer relationships.
- Audio Input, Looping, And Autoslice: input audio, shared buffers, looping,
  waveform, autoslice.
- Performance Overrides And Pattern Manipulation: fill, note repeat, step
  order, track perform multi-select/latch.
- External Control And Automation: MIDI/control surfaces, observability/log
  issue flow. Separate musician-facing control from developer diagnostics.

## Known Decisions And Defaults

- A track is the lane/destination context; a source is what creates note data
  for a pattern slot.
- Clips are explicit data; generators are recipes. The user should be able to
  move between them without losing either.
- Phrases choose layer values over time; pattern slots say what a track can
  play.
- Live/performance surfaces should not create a disconnected runtime-only
  model. If they use an ephemeral performance layer, it must be clearly
  discardable or commit-able back to phrase/scene/song state.
- Mixer v1 should prefer legible return-style sends unless a later pass proves
  arbitrary bus-to-bus routing is necessary.
- Probe branches are evidence and raw material, not validated production UI.

## Known Mistakes To Avoid

- Do not build six disconnected feature panels and call that whole-app
  progress.
- Do not surface broken builds, invalid screenshots, or missing UX checks to
  the user when agents can detect them.
- Do not treat aspirational README concepts as implemented code without
  checking wiki/code.
- Do not bury the main lane idea below the fold in a first viewport.
- Do not let diagnostics/observability screens look like musician-facing
  control surfaces unless that is the explicit goal.
- Do not merge probe-local `@State` models as production architecture.
- Do not ask the user to read piles of artifacts when a synthesis, diagram, or
  wireframe can reduce the decision.

## Wiki Links

- [README](../../README.md) - product spirit and north-star functionality.
- [Application Overview](../../wiki/pages/application-overview.md) - current
  product concepts and workflow.
- [Information Architecture And UX](../../wiki/pages/information-architecture-ux.md)
  - workspace ownership and UX rules.
- [Live View](../../wiki/pages/live-view.md) - current live/performance lens.
- [Document Model](../../wiki/pages/document-model.md) - persistence and source
  references.
- [Playback Data Path](../../wiki/pages/playback-data-path.md) - runtime/tick
  architecture.
- [Routing](../../wiki/pages/routing.md) - routing model references.
- [Portfolio Plan](portfolio-plan.md) - current lane grouping.
- [Visual Baseline](probe-results/visual-baseline-2026-05-06/ux-baseline.md)
  - current UX feedback from overnight probes.
