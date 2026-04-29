# Step Sequencer User Stories

## Stories

### 1. Unified Step Cell Primitive

- **As a:** musician building a sequence across any view (page grid, step layers strip, layer cards)
- **I want:** every step cell to use the same visual primitive regardless of which view I am in
- **So that:** I do not have to re-learn interaction patterns when switching between views
- **Done when:** toggling, value editing, and option selection all happen inside the step cell area, with no disconnected external controls, and the cell looks and behaves consistently across all three known views (page grid, step layers strip, layer cards)

### 2. Step State Legibility

- **As a:** musician monitoring a running sequence
- **I want:** each step cell to simultaneously communicate whether it is currently playing, whether it is selected, whether it is active/enabled, and what its value is for the current layer
- **So that:** I can read the full state of a step at a glance without opening any secondary panel
- **Done when:** all four states (playing, selected, active, value) are visually distinguishable on a single cell at any playback speed, and they compose without visual ambiguity

### 3. Right-Click Step Selection and Layer Editing

- **As a:** musician wanting to fine-tune a specific step
- **I want:** right-clicking a step to select it and reveal editable macro and layer controls above that step column
- **So that:** I can adjust per-step macro or layer values without navigating away from the step grid
- **Done when:** right-clicking a step marks it as selected, the macro/layer cells above the step become interactive with appropriate controls for each layer type (toggle, value slider, option picker), and the rest of the grid remains visible and functional

### 4. Multi-Step Selection

- **As a:** musician editing multiple steps in one action
- **I want:** to be able to select more than one step at a time (via right-click or another gesture)
- **So that:** I can apply changes—such as setting a velocity value or a chance percentage—to several steps simultaneously without repeating the action on each one
- **Done when:** selecting multiple steps shows all of them in a selected visual state, any layer-cell edit or batch command applies to all selected steps, and the selection can be cleared with a single action

### 5. Contextual Batch Action Bar

- **As a:** musician editing sequences quickly
- **I want:** when one or more steps are selected, a contextual bar to appear (likely below the sequencer) with actions such as clear, copy, and paste
- **So that:** I can perform common step management tasks without hunting through menus
- **Done when:** the batch action bar appears whenever at least one step is selected, is hidden when no steps are selected, and clear/copy/paste all operate correctly on the current selection

### 6. Layer-Driven Cell Control Type

- **As a:** musician switching between editing step triggers, velocities, and chance values
- **I want:** the control type shown in each step cell to change automatically when I switch the active layer (e.g., toggle for Steps, value bar for Velocity, percentage for Chance)
- **So that:** the sequencer grid always shows me the most useful representation for the currently selected layer without breaking spatial alignment
- **Done when:** switching the active layer transforms every step cell's control type while keeping step positions spatially aligned, and value changes made in one layer do not visually interfere with other layers

---

## Acceptance Signals

- A sequence musician can navigate between all views containing a step sequencer and recognize cells as the same primitive
- Playing, selected, active, and value states are all visible on a single cell simultaneously without any state being hidden or cropped
- Right-clicking a step in any view surfaces per-step layer editing inline
- Multi-step edits (e.g., set all selected steps to 50% chance) apply correctly and immediately
- The batch action bar appears on selection and disappears on deselection with no layout shift
- Switching the active layer from Steps to Velocity changes cells from toggles to value bars; switching back restores toggles with previous state intact

## Assumptions

- The existing codebase already has at least one step-sequencer view rendering step cells; the work is unification and state enrichment, not a greenfield grid
- "Right-click" is the intended selection gesture on desktop; a long-press or secondary tap may be needed for touch, but this is not yet specified
- Macro/layer cells that become editable above selected steps correspond to the same layer tabs already visible in the Step Layers strip view
- "Clear" removes active state from selected steps; it does not delete steps from the sequence length
- Copy and paste operate on the step data for all currently visible/edited layers within the selection, not just the active layer (open question — see below)
- The step cell primitive should remain usable inside the four screenshot contexts identified in artifacts.md; no additional views are assumed at this stage
