---
id: 27
title: Drum Kits, Pattern Templates, and the Kit Matrix as a Step Editor
status: inventory
priority: unset
blocked_by: []
stage: spec
owner: pm
updated: 2026-06-10
---

# Drum Kits, Pattern Templates, and the Kit Matrix as a Step Editor

One coherent rework of the drum-group workflow, combining two owner inputs:

1. **2026-06-10 kit/template model** (intent.md, library-pools README §2026-06-10):
   a drum kit is a collection of sounds keyed by part tag — nothing else.
   `DrumKitPreset` (which bundles seed patterns into the kit) is removed.
   Pattern templates become a separate global concept: a collection of clips
   keyed by part tag, applied to a drum group by tag matching. Creation modal
   picks sounds first, template second. Templates can also be imposed on an
   existing group from the kit view.
2. **2026-06-06 kit-matrix step-editor-grammar feedback**
   (`docs/roadmap/drum-parts-as-group/feedback/2026-06-06-post-merge-kit-matrix-step-editor-grammar.md`,
   previously unactioned): the kit matrix becomes a real grouped step editor —
   full-size step cells, shared step-layer controls, a group-level pattern row,
   no per-row `P1` navigation buttons.

Artifacts:

- `spec.md` — combined v1 spec (model + creation flow + kit matrix).

Interlocks:

- `docs/roadmap/library-pools/README.md` (id 26) — kits and templates are
  global-library asset types; this spec defines their shape so library-pools
  can shelve them without re-deciding the model.
- `docs/roadmap/drum-parts-as-group/spec.md` — v1 of the kit matrix
  (read-only). This feature supersedes its "no inline editing / no group
  pattern selector" exclusions, which were explicitly marked as future
  extension boundaries there.
