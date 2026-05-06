---
status: ready
created: 2026-05-06T14:16:45+01:00
source_pass: synthesize-current-probes
next_pass: docs/roadmap/agentic-loop/passes/build-holistic-wireframe-from-synthesis.md
---

# Current Product Shape Synthesis

## Product Shape

In-sequence should present one musical workbench where a user can get sound
moving, generate or perform a useful accident, capture it into explicit musical
objects, arrange those objects into phrases and scenes, then perform reversible
changes that can be committed or discarded. The current probes should not be
merged as separate top-level feature panels; their useful parts should be
collapsed into a single flow where tracks/sources, capture buffers, phrase
state, scene blend, mixer routing, and transient performance overrides are all
different views over the same sounding material.

## Whole-App Journey

```text
Start sound
  -> choose/create track or input
  -> attach clip/generator/audio buffer/source
  -> hear current phrase step and selected source

Generate / perform
  -> tweak generator, capture audio, or apply transient overrides
  -> visible meters/playheads/showing-what-is-sounding stay in view

Notice and capture
  -> capture generated notes into clip history
  -> capture audio loop into shared buffer
  -> preserve original source alongside captured explicit data

Shape
  -> edit selected source/slot in Track Editor
  -> use modifiers, step edit, loop range, slices, and macros against the same slot/buffer

Arrange
  -> assign pattern slots, mute/fill/macro layers, phrase length/repeats
  -> bind phrase rows to scene state and song/free transport intent

Perform
  -> select track set, latch/momentary overrides, scene A/B crossfade, mixer route/meter changes
  -> live changes are visibly transient until committed

Preserve / discard
  -> commit performance changes to phrase/scene/song state
  -> save captures as clips/buffers/slices
  -> clear transient overlays and return to authored state
```

## Lane Harvest Matrix

| Lane | Keep | Discard | Retry | Why |
|---|---|---|---|---|
| Track Editor Foundation | History rail + selected slot + source/modifier wells + step editor as one editing surface. Empty source and modifier-after-source vocabulary. | Local fake mutation, unconditional probe panel, project-file churn. | Yes, inside holistic wireframe. | It gives the clearest source-of-truth for clip/generator capture and editing, but must become the track editor shell rather than a stacked panel. |
| Phrase, Scene, And Song Performance | One Perform workspace idea: basis phrase, phrase rows, Scene A/B, crossfader, song/free mode in one surface. `NOW` / `NEXT` / `BASIS` row vocabulary. | Local queued phrase state, always-visible probe tab as-is, any claim that phrase-owned scene recall is solved. | Yes, as lower/workspace band in the holistic wireframe. | It shows phrase/scene coexistence but is too sparse and needs arrangement structure plus commit/discard semantics. |
| Mixer Routing And Sends | Routing-first mixer viewport, fader strip -> busses -> send returns -> post-blend master. Additive solo, confirm delete/reroute, manual clip clear defaults. | UI-local bus/send identity, static graph summary, duplicated mixer strip. | Yes, as supporting mixer lane with richer fixture. | The feedback pass validated routing as the first visible idea; production still needs document/audio graph ownership. |
| Audio Input, Looping, Autoslice | Shared buffer identity across input track, waveform, loop range, autoslice cues, loop deck, and buffer users. Primary action: capture loop to shared buffer. Musician-facing states. | Synthetic recording, bucket autoslice algorithm, UI-local runtime ownership, final-navigation claim that Capture must be global. | Yes, use as strongest first-viewport anchor. | This is the best complete flow from raw sound to reusable material. It should drive the wireframe's capture area. |
| Performance Overrides And Pattern Manipulation | Pure `TrackPerformanceOverrideLayer` concept, selected target set, transient fill/repeat/step-order overlays, clear-on-exit behavior. | Current sparse panel as UX validation, local `@State` ownership, fake latch/momentary behavior, hard-coded 16-step assumptions. | Yes, after disk-gated feedback is rerun or in the wireframe with visible consequence. | The model fits safe performance, but users must see audible/pattern consequences before production UI is trusted. |
| External Control And Automation | Observability model: fingerprinting, redaction, routing, issue draft separation of "observed in" vs "introduced by". Endpoint status as diagnostics. | Top-level Automation tab for normal musician flow, seeded events, in-memory suppression, premature MIDI mapping. | Later, outside the instrument wireframe unless diagnostics are explicitly in scope. | Useful for agent loop/tooling, but it should not compete with music-making surfaces. |

## Shared Concepts To Unify

| Concept | Unified rule for next pass |
|---|---|
| Sounding state | Every workspace must show the active phrase/step, selected source, and what is currently producing audio or notes. |
| Source slot | A track pattern slot owns clip/generator/audio-source choice; Track Editor edits the slot, Phrase chooses which slot plays. |
| Capture artifact | Captures become explicit clips, audio buffers, slice sets, or history entries with stable identity. |
| Generator recipe vs captured data | Preserve both sides; generated material can be captured without destroying the recipe. |
| Shared audio buffer | Input, loop playback, waveform, autoslice, and buffer users reference one runtime buffer owner. |
| Transient overlay | Performance overrides, scene blends, and live mixer moves sit above authored phrase/scene/mixer state until committed. |
| Commit/discard | Live changes need visible affordances to keep, write to phrase/scene/song, or clear back to authored state. |
| Routing graph | Track outputs, busses, send returns, meters, and master are one mixer graph, not feature-specific panels. |
| Basis phrase | Free/song mode and queued phrase behavior need one read model shared by Phrase, Live, and Perform surfaces. |
| Evidence quality | Visual artifacts count only when capture/UI-map status is valid; invalid probes become process work, not user review. |

## Proposed Wireframe Pass

Build one app-shaped interactive SwiftUI probe or skeleton named **Happy
Accident Workbench**. It should be safe to discard and should not change
document schema, real audio graph contracts, or production playback without an
explicit follow-up plan.

First viewport should show:

```text
Top: transport + active phrase/step + sounding summary + Keep / Discard live changes

Left: Track roster
  - selected track set
  - current slot, generator/clip/audio state
  - badges for captured history, transient overrides, routing/meter state

Center: Source and capture work area
  - selected slot source/modifier chain
  - clip history rail
  - step or waveform editor depending on source type
  - Capture Loop To Shared Buffer / Capture Generated Clip action

Right: Consequence rail
  - what is sounding now
  - buffer users / generated notes / route graph summary
  - transient overlay state with commit/discard target

Bottom band: Arrangement and performance
  - compact phrase rows with pattern/fill/macro summaries
  - Scene A/B and crossfader
  - Track Perform overrides for selected target set
  - mixer routing mini-graph
```

The pass should create a single seeded scenario fixture in the probe model:

- four tracks: drum kit/group, melodic generator, audio input/loop, bass clip;
- two phrases: one playing, one queued;
- one scene A/B blend with visible live override;
- one captured generated clip in history;
- one shared audio buffer with loop range and slice cues;
- one transient override applied to a selected track set;
- one mixer route through a drum bus plus delay/reverb send returns.

## Review Questions For The Wireframe

| Lens | Questions |
|---|---|
| UX/IA | Does the first viewport read as one instrument/workbench, not a dashboard? Is the primary next action obvious? Can the user tell what is sounding, what was generated, what can be captured, and what is only transient? Are edit, perform, commit, and discard states visibly distinct? |
| Architecture | Does every visible control point to a plausible owner: document, session/runtime, engine, audio graph, or probe-only fixture? Are source slot, buffer, phrase, scene, route, and transient overlay identities unified instead of duplicated? Does the pass avoid merging local `@State` as production truth? |
| Testing | Are there focused tests for seeded scenario invariants, capture artifact identity, transient overlay clear/commit labels, and routing summary defaults? Does the visual gate verify the intended window/workspace with Peekaboo screenshot plus UI map? Are invalid captures recorded as blocked/invalid evidence? |

## Agent-Side Follow-Up Work

| Priority | Work | Output |
|---|---|---|
| P0 | Build the holistic wireframe/skeleton from this synthesis. | `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md` plus valid screenshot/UI-map artifacts. |
| P0 | Add a scenario fixture for the wireframe model so visual review does not depend on empty default documents. | Focused tests for fixture identity and first-viewport labels. |
| P1 | Rewrite lane decisions as inferred defaults, not user blockers: history rail near selected slot, audio track + capture page over shared buffers, return-style sends, Perform card taps select targets, app JSONL diagnostics later. | `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`. |
| P1 | Schedule resource-safe retry only for failed UX feedback lanes after disk preflight passes. | Follow-up pass file with `max_parallel: 1` and visual gates. |
| P2 | Prepare cherry-pick candidates for pure model/test artifacts after wireframe review. | Candidate list separating model/tests from UI-local probe state. |

## User Decisions

No immediate user attention is required for the next build round. Use these
agent-inferred defaults for the wireframe:

- show clip history as an always-nearby rail tied to the selected pattern slot;
- treat audio input tracks and a live Capture page as two views over shared runtime buffers;
- keep v1 sends as return-style busses feeding the master;
- make Track Perform card taps select targets in Perform mode, with explicit edit/open affordance;
- prototype queued phrase edits with a visible staging/commit model so accidental queued-phrase mutation is avoided.

After the holistic wireframe has valid visual evidence, the only likely
high-leverage user review is whether the integrated workbench shape feels like
the right source of truth before agents cherry-pick production model pieces.
