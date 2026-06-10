# Resolution: Kit Matrix Step Editor Grammar

Date: 2026-06-10
Status: spec'd (not yet built)

This feedback sat unactioned in the loop since 2026-06-06. On 2026-06-10 it
was combined with the owner's kits-as-sound-collections / global
pattern-templates direction (intent.md 2026-06-10 entries) into a single
feature spec:

- roadmap item 27: `docs/roadmap/drum-kits-and-templates/README.md`
- spec: `docs/roadmap/drum-kits-and-templates/spec.md`

Mapping of the feedback points into the spec:

- too-small step cells → matrix reuses the single-track editor's full-size
  cell components (Part 3, "Step-editor grammar");
- shared step-editor interface → cells are editable through the same typed
  store mutations; matrix-wide layer controls (on/off, velocity, chance, …);
- layer controls above the multi-part view → same layer selector as the
  single-track editor, applied matrix-wide;
- group-level 1–16 pattern row → fan-out selector across members, mixed-state
  indication, realign on select (no persisted group-pattern object);
- per-row `P1` buttons removed → navigation moves to a part-name chevron;
- generator-slot question → explicitly kept open: v1 renders generator rows
  read-only with a badge; a prototype explores richer treatment before v2.

Interim fixes already landed ahead of the rework (2026-06-10 QA pass):
part rows scroll (P0.3), internal API caption removed, compact
pattern-mismatch badge, routing sheet on StudioModal with real sample names.
