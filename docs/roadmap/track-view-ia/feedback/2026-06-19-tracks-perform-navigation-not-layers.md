# Tracks Perform should be navigation + selection, not a bespoke layer surface

Raw product-owner clarification (2026-06-19):

> The tracks view is wrong. It shouldn't have the layers stuff — that belongs in
> phrase perform now. It should be for navigating to tracks and selecting them
> for actions (which might include layer perform from selection).

## Evidence (built UI vs. prototypes)

- **Tracks Perform as built** (captures `03-tracks-perform`, `14-tracks-perform-layer-selector`):
  a bespoke layer-perform surface — a `TRACK LAYER` selector opening "CHOOSE
  TRACK LAYER" (Mute, Pattern, Fill, Note-Repeat 1/4→1/64, Step-Order tools,
  Volume, Pan) + per-track mini-grids + Mom/Latch. A *bigger* layer set than
  phrase perform.
- **Phrase Perform as built** (captures `11`, `13b`): the canonical layer surface
  — `LAYERS / SCENES / GLOBAL APPLY`, PHRASE LAYER selector + VALUE + AUTOMATION,
  Mom/Latch, Capture → Save Phrase Copy. Layers live here now.
- **Prototype `03-track-matrix.html`** (intended tracks matrix): *"TracksPerform —
  live card grid. Each card shows a small pattern preview + per-card mute.
  Clicking a normal card opens that track's single-track detail; clicking the kit
  cell opens the kit matrix."* Plus **Edit Set** (selection) + a **Perform**
  button. **No `TRACK LAYER` selector.**
- **Prototype `04-track-perform-scoped.html`** + `feedback/2026-06-19-scoped-track-perform.md`:
  a **Perform ▸** button on a track/kit opens the phrase-style perform UI
  **scoped to that selection** — reuse the phrase grammar, **no bespoke surface**.

## Diagnosis

The tracks Perform matrix kept the old `performance-layer-matrix-tracks` surface,
which predates phrase perform. Now that phrase perform owns layers project-wide
and scoped perform owns layers per-selection, the tracks-matrix layer surface is
a **third, redundant copy**.

## Target

- **Tracks view = navigation + selection.** Card grid (pattern preview + per-card
  mute); click a card → that track's detail; click the kit cell → kit matrix.
  Multi-select ("Edit Set", the `track-perform-multiselect-latch` model).
- **Layer perform from selection** → the **Perform** button launches the
  **scoped phrase-perform UI** for the selected track(s)/kit. No layer selector
  in the matrix.
- **Project-wide layer perform** → **phrase perform only**.

## Related fresh bugs (same IA cluster, handle together)
- `20260619-213834` phrase global-apply should switch fully into track-selector
  mode (currently shows both selection and layers).
- `20260619-213713` layer cards should be interactive (toggle/slider), colour
  divergence, drop the "applies to N tracks" copy.
- `20260619-213241` too many nav levels; narrow the layer selector; merge the
  layer bar with the orange perform bar.
- `20260619-212935` scenes-perform page shouldn't exist; Scenes top-nav → scene
  management.
