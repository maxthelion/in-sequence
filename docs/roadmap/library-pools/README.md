---
id: 26
title: Library Pools (Project vs Global Assets)
status: inventory
priority: unset
blocked_by: []
stage: clarify
owner: pm
updated: 2026-06-10
---

# Library Pools (Project vs Global Assets)

Replace the placeholder Library page with a two-level asset model:

- **Global library**: assets that exist outside any project, browsed by
  category — breaks (feed the slicer), recorded audio captured from input
  audio channels, samples, and drum kits.
- **Project pool**: the subset of global assets that have been added into
  the current project. Pool membership is what project features see.

Consumption hooks:

- Creating a drum track/group from the Tracks page should offer the drum
  kits currently in the project pool (today the Create flow only offers the
  hardcoded `DrumKitPreset` enum: 808 / Acoustic / Techno).
- Breaks in the pool feed slice-track creation (AddSliceTrackSheet already
  reads `AudioSampleLibrary` breaks directly — would become pool-scoped).
- Input-audio recordings should land in the global library (today a
  recorded loop is runtime-only: `recordedLoopID` in the engine runtime,
  nothing persisted to any library).

Existing substrate:

- `AudioSampleLibrary` (app-support folders) is already the global store,
  and `AudioSampleCategory` already has breaks + per-drum-voice categories.
- `Project` already has the pool pattern for clips/generators/slice sets
  (`clipPool`, `generatorPool`, `sliceSetPool`) — this adds the analogous
  pool for file-backed assets (samples/kits) referencing the global library.
- Library page is 100% placeholder tiles today; its current category list
  (Templates/Takes/Phrases/Voice Presets/…) does not match this asset-first
  framing and would be superseded.

Open questions for the owner:

1. Pool semantics for file-backed assets: does adding to the project pool
   copy the audio into the document bundle (portable `.seqai`) or reference
   the global app-support path (small documents, breaks if library moves)?
2. Recordings: does every captured input loop auto-land in the global
   library, or only on an explicit save action? How are they named/grouped
   (by track, by date, by take number)?
3. What is a "drum kit" as a library asset: the preset definition (member
   tags + seed patterns, like `DrumKitPreset`) plus a sample mapping per
   voice? Or a folder of samples with tag-derived membership?

## 2026-06-10 owner refinement: kits and pattern templates

Answers part of open question 3 and reshapes the kit model:

- A **drum kit** is a collection of sounds keyed by part type/tag (kick,
  snare, hats…) — nothing else. The current `DrumKitPreset` enum (which
  bundles seed patterns with the kit) is to be removed.
- The global library holds **pools of sounds per part type** (a selection
  of kicks, of snares, …) from which kits draw.
- **Pattern templates** are a separate global concept: a collection of
  clips keyed by part type/tag, applied to a drum group by matching tags.
- Create-drum-track modal ordering: (1) choose sounds — pick a kit from the
  global pool, which populates per-part sounds; (2) optionally prepopulate
  from a global pattern template.
- A template can also be imposed on an existing drum group later, from the
  kit view.

Interlock: the kit-matrix rework feedback
(`docs/roadmap/drum-parts-as-group/feedback/2026-06-06-post-merge-kit-matrix-step-editor-grammar.md`)
should land the "impose template from kit view" hook as part of its
group-level pattern row.

## 2026-06-10 owner refinement: step order maps move here

Creating step-order maps (and editing their values) leaves the phrase page —
the inline step-order workflow panel was removed with the 2026-06-10 phrase
UI fix. Step order maps become library assets like kits and templates:
global step-order presets live in the library, projects draw from them, and
phrases only *toggle* an assigned map via the step-order perform layer (the
same grammar as note repeat). Session APIs for map CRUD already exist
(`appendStepOrderMap`, `renameStepOrderMap`, `setStepOrderMapValues`,
`deleteUnusedStepOrderMap`) — this item gives them their library surface.

→ Spec'd 2026-06-10 as roadmap item 27,
`docs/roadmap/drum-kits-and-templates/spec.md`, which defines the `DrumKit`
and `PatternTemplate` asset shapes this item will shelve in the global
library / project pool.
