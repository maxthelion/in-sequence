# Step Sequencer Artifacts

## 2026-04-29 - Step Sequencer Reference Screenshots

Source: user-provided embedded screenshots in the planning conversation.

The user provided four screenshots illustrating current or reference step-sequencer UI treatments.

### 1. 16-Step Page Grid

The first screenshot shows a `16-Step Page` view for steps `1-16 of 64`, with page selectors `1-16`, `17-32`, `33-48`, `49-64`.

Observed signals:

- Steps are large rectangular cells in a two-row grid.
- Step `1` is highlighted/active.
- Cells show step number, a compact value display, and empty state text.
- The view is good for scanning a page of steps, but individual cells need to carry multiple states clearly.

### 2. Step Layers Strip

The second screenshot shows a `STEP LAYERS` area with layer tabs such as `Steps`, `Velocity`, and `Chance`, followed by a horizontal row of compact numbered step cells.

Observed signals:

- The active layer is visually distinct.
- Step `1` has a strong selection/active outline.
- This view suggests a reusable primitive for compact step cells.
- It raises the question of how active, selected, currently-playing, and value state coexist in a small cell.

### 3. Layer Cards With Toggle Steps

The third screenshot shows layer cards for `Normal Steps`, `Normal Velocity`, and `Normal Chance`, with a 16-step grid below.

Observed signals:

- Active steps use a bright filled state.
- Inactive steps use an outlined or dimmed state.
- Layer/macro slots such as `M6 Assign`, `M7 Assign`, and `M8 Assign` appear above later steps.
- This view supports the user's idea that layer/macro cells above selected steps could become editable with suitable controls.

### 4. Velocity Layer Values

The fourth screenshot shows the `Normal Velocity` layer selected, with each step represented by a value bar.

Observed signals:

- The same 16-step sequence becomes a value-editing surface.
- Step cells can show a continuous value, not only on/off state.
- The selected layer changes the appropriate control representation while preserving step alignment.
- Text at the bottom describes context: `Normal lane • Velocity view • Single page • 8 notes across 16 steps.`

## Design Signals To Preserve

- Different step-sequencer views should share common UI primitives.
- A step cell must be able to express:
  - currently playing
  - selected
  - active/enabled
  - current value for the selected layer
- Toggle, value, and option editing should happen in the same step area, not in disconnected controls.
- Selected steps may expose editable macro/layer cells above them.
- Multi-step selection should enable batch controls below the sequencer, such as clear, copy, and paste.
- Layer selection should change the cell control type while preserving spatial continuity.

## Cross-References

- Item `9`, Modifier Chain Placement: the wording mentions generated or chained output and layer/macro editability.
- Item `10`, Phrase Features: phrase length and page/chunking may affect step pagination.
- Item `15`, Note Repeat: repeated note behavior may need a layer or per-step control.
- Item `16`, Step Order: ordering may be another layer/view over the same step primitive.
