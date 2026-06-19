Tracks Perform view should be navigation + selection, not a bespoke layer-perform surface

Screenshots:
- 03-tracks-perform.png
- 14-tracks-perform-layer-selector.png

The tracks Perform view carries its own TRACK LAYER selector ("CHOOSE TRACK
LAYER": Mute, Pattern, Fill, Note-Repeat 1/4-1/64, Step-Order tools, Volume,
Pan) + per-track grids — a duplicate of layer-perform, which now belongs to
phrase perform (project-wide) and scoped track/kit perform (per selection).

Target:
- Tracks view = navigation + selection: card grid (pattern preview + per-card
  mute), click card -> track detail, click kit cell -> kit matrix, multi-select.
- Perform button launches the scoped phrase-perform UI for the selection
  (reuse, no bespoke surface).
- Project-wide layer perform stays in phrase perform only.

See docs/roadmap/track-view-ia/feedback/2026-06-19-tracks-perform-navigation-not-layers.md
and docs/roadmap/tracks-perform-navigation/goal.md.
