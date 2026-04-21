# Followup: Routing should live inside the DAG, not beside it

**Severity:** architectural; not blocking MVP. Plan-seed for after the coordinator + first-few-layers work lands.

**Observation.** The spec (`docs/specs/2026-04-18-north-star-design.md` §"Pipeline layer") presents routing as **block composition**: sinks are DAG nodes — `midi-out`, `voice-route(tag → destination map)`, `macro-row[name]`, `audio-param[bus, param]`, `chord-context`, `trigger[fill-flag | ...]`. Transforms upstream of those sinks (`note-repeat`, `step-order`, `voice-split`, `voice-merge`, `density-gate`, `interpret`) compose with them.

Current reality (`Sources/Engine/`):
- Only `MidiOut` and `ChordContextSink` exist as sink blocks.
- `MIDIRouter` is a parallel runtime outside the DAG. `EngineController.processTick` pulls generator outputs from the executor's result dictionary and hands them to the router, which matches source/filter/destination and fans out. None of that composition surfaces as blocks.
- `VoiceTag` is carried on `NoteEvent` but there is no `voice-route` block. The closest thing is `Route.Filter.voiceTag(tag)` — single-tag filter, single-destination per route. The spec's "each tag maps to a list of destinations; every destination receives the event" (resolved open-question in the north star) is not expressible today.

**Why it matters.** The "compositional uniformity" goal (§Design goals 3) is partially already fractured. Every future fan-out feature (per-tag routing, macro-row writers, audio-param writers, fill triggers) either becomes another external subsystem or has to be retrofitted into the DAG later. Landing transform blocks (§Components inventory: `force-to-scale`, `quantise-to-chord`, `note-repeat`, `step-order`, `voice-split/merge`, `density-gate`, `interpret`, `tap-prev`) makes the gap worse — transforms are most useful when they can compose with sinks.

**Sub-items this covers:**
- Promote `voice-route` to a block with `[VoiceTag: [RouteDestination]]` map. Existing `Route` + `MIDIRouter` become authoring / snapshot plumbing for the block's config, not a parallel runtime.
- Introduce `MacroRowWriter` / `AudioParamWriter` / `Trigger[fill-flag]` sink block kinds — unblocks the `.macroRow(...)` layer target wiring (all blocks read macro rows via `interpret`).
- Migrate `MidiOut` off direct `MIDIClient.send`; route events through `ScheduledEvent.routedMIDI` so dispatch is the only thing that talks to CoreMIDI (this was already flagged as deferred by the coordinator plan).

**Preconditions.** Should land **after** the coordinator + EventQueue plan (needs `ScheduledEvent` as the dispatch primitive) and **after** at least `.volume` / `.transpose` are wired (so the macro-row pattern is established). Pushing earlier risks designing block kinds before we've seen two or three layers actually flow through them.

**Not a near-term blocker.** The current router works for MVP. Record this so it does not silently accumulate — every new route feature that lands in the parallel runtime is a future migration cost.
