---
status: accepted
created: 2026-05-06T20:12:00+01:00
source_pass: docs/roadmap/agentic-loop/passes/record-wireframe-decisions-as-inferred-defaults.md
source_reviews: docs/roadmap/agentic-loop/reviews/correct-holistic-wireframe-commit-discard-evidence/
product_shape_source: docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md
---

# Inferred Defaults

These defaults reduce user attention for the next build round. They are
agent-inferred planning defaults from the context pack, wiki, lane synthesis,
validated visual baseline, Happy Accident Workbench wireframe, and passing
UX/IA, architecture, and testing reviews.

They are not production schema or audio-graph contracts. Build plans still need
to map each default onto the existing `Project`, `LiveSequencerStoreState`,
`PlaybackSnapshot`, routing, and engine boundaries before implementation.

## Accepted Product Shape

The **Happy Accident Workbench** is the current integrated product-shape source
for planning. It should guide the next build round because it combines tracks,
source slots, capture buffers, clip history, phrase/scene state, mixer routing,
and transient performance changes into one musical flow:

```text
play -> generate -> notice -> capture -> arrange -> perform -> preserve/discard
```

Do not merge the wireframe host or broad lane probes as production UI. Use them
as evidence for model ownership, first-viewport priorities, and build-plan
sequencing.

## Defaults

| Area | Default | Why this is inferable | Build implication |
|---|---|---|---|
| Workbench source of truth | Treat Happy Accident Workbench as the accepted integrated shape until later evidence contradicts it. | The corrected wireframe has valid visual evidence and passed UX/IA, architecture, and testing reviews. | Production plans should cherry-pick model/test concepts into the existing app shape instead of rebuilding six separate feature panels. |
| Keep/Discard | Live performance changes may sit in a runtime session overlay only when the UI shows visible Keep and Discard targets. Keep writes the auditioned change to explicit authored destinations; Discard restores authored state and clears the overlay. | Safe performance is a north-star requirement, and the corrected review accepted visible transaction targets. | Build plans must name overlay source owner, keep destination owners, discard restoration owners, and post-action labels before coding. |
| Live phrase editing boundary | Ordinary Live editing remains a fast lens over phrase cells; transient Perform overrides are the exception and must be explicitly commit-able or discardable. | The Live View wiki says Live edits real phrase state, while the context pack allows ephemeral performance layers only with clear preserve/discard semantics. | Do not introduce a disconnected runtime-only Live model. Any overlay must compile predictably into or above phrase/scene/song state. |
| Runtime audio buffer boundary | Captured sample memory and waveform/runtime transport state belong to runtime audio-buffer ownership; durable buffer identity, loop range, slice cues, source references, and buffer users belong to document buffer references. | The document wiki excludes raw sample data from `.seqai`, and the architecture review accepted the runtime-buffer versus document-reference split. | Audio input, looping, and autoslice plans should share one buffer vocabulary and persist metadata/references rather than duplicating sample memory in the document. |
| Clip history placement | Clip history stays beside the selected pattern slot, not in a detached modal-first flow. Capturing generated output creates explicit clip history while preserving the generator recipe identity. | Track/source boundaries and visual evidence both put history, source choice, and editing in the same selected-slot context. | Track Editor work should keep `SourceRef`-style clip/generator identity intact when capturing, bypassing, or switching modes. |
| Mixer sends | Return-style sends feeding the master are the v1 default. Arbitrary bus-to-bus routing is out of scope until Lane C proves it is necessary. | Portfolio and Lane C notes converge on safer return-style sends, additive solo, global inserts, confirm-delete reroute, post-blend master, and manual clip clear. | Mixer build plans can proceed on return sends and should escalate only if implementation conflicts with routing or audio-graph architecture. |
| Queued phrase edits | Queued phrase edits need visible staging and commit semantics. Silent mutation of a queued phrase is not the default. | The phrase/scene lane and UX review both flagged `NOW` / `NEXT` as useful but insufficient without staging clarity. | Phrase and Scene Perform plans should show whether a queued phrase is only selected, staged for later, committed, or restored. |
| UI-map evidence | UI maps are useful declared evidence, but not production truth unless generated from or checked against the rendered DOM/app surface. | The testing review accepted manual UI maps for the correction while noting they remain manually authored. | Future visual gates should assert key labels and interactions against visible output before using a map as review evidence. |

## Agent-Actionable Follow-Up

1. Prepare production cherry-pick candidates for pure model/test artifacts only:
   transient override model, buffer-reference vocabulary, return-send reducer
   semantics, and source-slot capture/history identity.
   Use `docs/roadmap/agentic-loop/passes/prepare-production-cherry-pick-candidates.md`
   as the next pass brief.
2. Write build plans that map these defaults onto current Swift ownership
   boundaries before touching production UI.
3. Keep the paused UX-feedback retry at `max_parallel: 1` and resume only after
   disk preflight passes; failed lane retries are process work, not user review
   blockers.

## User Attention

No immediate user attention is required. The next high-leverage user checkpoint
is one product judgment after agent-side cherry-pick planning: whether Happy
Accident Workbench should remain the source-of-truth shape for the next
production build round.
