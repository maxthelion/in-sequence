---
verdict: accepted
selected_prototype: composite — 01-control-surface-settings.html (story 1/7), 02-phrase-workspace-grid.html (story 4), 03-live-workspace-grid.html (story 5)
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/01-control-surface-settings.html
  - prototypes/02-phrase-workspace-grid.html
  - prototypes/03-live-workspace-grid.html
feedback_applied: []
---

# MIDI Interfaces UX Review — 2026-04-30

## Context

Three HTML wireframes cover distinct story clusters: Settings Control Surfaces
UI (stories 1 and 7), Phrase workspace hardware grid (story 4), and Live
workspace hardware grid (story 5). Stories 2, 3, and 6 are pure system behavior
(Programmer-mode lifecycle, routing dispatch, and window focus ownership) that
have no UX surface to prototype. The review evaluates each prototype against
the standard checklist and the relevant user stories, then makes a verdict.

---

## Checklist Results

| Criterion | P1: Settings | P2: Phrase Grid | P3: Live Grid |
|---|---|---|---|
| Single-file, no build steps | Pass | Pass | Pass |
| Monochrome base, semantic color only | Pass | Pass | Pass |
| Stub regions clearly marked | Pass | Pass | Pass |
| Real interactions on primary path | Pass | Pass | Pass |
| Fixture data is adversarial / varied | Partial | Pass | Pass |
| Interaction budget stated and verified | Pass | Pass | Pass |
| Variants are strategically different, not cosmetic | N/A (single variant per cluster) | N/A | N/A |
| Reviewer cannot mistake for production | Pass | Pass | Pass |
| Primary-path goal completable | Pass | Pass | Pass |
| State machine for error / missing-device paths covered | Pass | Fail (no error state shown) | Fail (no error state shown) |
| Screen and hardware stay in sync on every action | N/A | Pass | Pass |
| Edge-button mapping documented | N/A | Pass | Pass |
| Open architecture questions surfaced | Pass | Pass | Pass |

**Fixture data note for P1:** The settings prototype uses only the happy-path
device name ("Launchpad Mini MK3 LPMiniMK3 MIDI In/Out"). State E (device
missing) is documented as a state card but not interactive. The prototype
would benefit from an interactive "unplug" button to see how the status row
behaves when the saved endpoint disappears. This is a minor gap given that
the state machine is fully documented in the state cards.

---

## Per-Prototype Assessment

### Prototype 1 — Control Surfaces Settings (Stories 1, 7)

**What works:**

- The three-step primary path (toggle → pick input → pick output) meets the
  interaction budget of three or fewer. The status row updates automatically;
  no additional confirmation step is required.
- The enable-then-pick flow gates endpoint pickers behind the toggle, which
  prevents partial configuration state (endpoints selected but surface disabled)
  cleanly.
- The five state cards (Disabled, Enabled/no endpoints, Input-only, Connected,
  Device missing) cover the meaningful surface states without overlap. The
  "output required for LED feedback" warning for the input-only case is a
  useful precision that the user stories do not spell out explicitly.
- The "Test LEDs" button is correctly gated: it requires both endpoints to be
  selected and becomes active exactly when the status badge shows "Connected".
  The 2.5-second cooldown and ephemeral feedback label are appropriately minimal.
- The picker note ("Selecting the regular MIDI (not DAW) endpoints is required
  for Programmer mode") surfaces an important onboarding detail exactly where
  the user needs it.
- The Control Surfaces section sits within the existing MIDI tab rather than
  adding a new top-level tab, which matches the acceptance signal in
  `user-stories.md`.
- Stub sections for Inputs, Outputs, and Virtual preserve the context of the
  existing preferences structure while keeping the prototype focused.

**What fails or is limited:**

- State E (device missing) is shown only as a read-only state card. There is no
  interactive path to reach it in the prototype. A reviewer cannot verify that
  the status row correctly degrades when the previously saved endpoint disappears
  from the CoreMIDI device list. This is acceptable for a prototype given the
  state card describes the expected behavior in detail, but the implementer
  should be aware this path is not click-verified.
- The prototype shows "Connected — Programmer mode active" as the connected
  status label, but it is not clear whether this label should also include the
  surface name. For multi-surface future support, the label might need to be
  richer. This is a forward-compatibility open question, not a blocking gap for
  v1.
- The "Enabled — enter Programmer mode on connect" toggle sub-label is a useful
  clue about the lifecycle behavior, but it disappears once endpoints are set
  and the status badge takes over. Consider whether this phrasing should persist
  as a smaller help note below the toggle or only in the disabled state.
- No persistence affordance is shown (e.g., no "Save" button, since the
  implementation will use `@AppStorage` / `UserDefaults`). The annotation notes
  this, but the prototype does not make the "this persists automatically" notion
  visible to the user. Production implementations should ensure a restart-survival
  cue (e.g., the endpoint names pre-populated on first open after a relaunch).

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Enable and configure a control surface | Fully covered: toggle, pickers, status row, persistence noted |
| 7. Test LEDs | Fully covered: button gating, feedback label, 2.5s cooldown |

---

### Prototype 2 — Phrase Workspace Hardware Grid (Story 4)

**What works:**

- The side-by-side layout (on-screen app left, hardware Launchpad representation
  right) makes the bidirectional sync contract immediately clear. Clicking a
  pad on the hardware updates the on-screen matrix and vice versa; the round-trip
  is one interaction.
- The full 9×9 grid (8 grid rows + 1 CC top row, 8 track columns + 1 right-col
  row-select column) is physically accurate to the Launchpad Mini MK3 layout.
  The edge button mapping (track-page left/right on top row, phrase-page
  left/right on top row, layer selectors on top row, row-select on right column)
  is clear from the annotation and confirmed by the pad labels.
- Paging works correctly: track pages advance through 16 tracks in groups of 8;
  phrase pages advance through 16 phrases in groups of 8. Both the on-screen
  page controls and the hardware edge pads fire the same actions.
- The LED color key covers all six semantic states (empty, filled, selected row,
  playing, pattern-slot, scalar) plus the four edge categories (layer, phrase-page,
  track-page, row-select). The "active" yellow-amber highlight correctly
  identifies the current layer and reachable-page directions.
- The fixture data is adversarial: 16 tracks × 16 phrases with a mix of playing,
  pattern-slot, scalar, and filled states ensures the color coding can be visually
  distinguished. One track has a long name ("Lead Synth w/longer name") that
  tests header truncation.
- The architecture annotation correctly calls out that `trackPage` and the new
  `phrasePage` must be lifted from `PhraseWorkspaceView` private state into a
  shared `WorkspaceControlSurfaceContext`. This is the right finding.

**What fails or is limited:**

- There is no representation of what happens when fewer than 8 phrases exist on a
  page (i.e., the bottom rows of the hardware grid when the phrase count is not
  a multiple of 8). The current prototype uses exactly 16 phrases which fills
  both pages perfectly. With 10 phrases, rows 3–8 of page 2 would be empty pads.
  The prototype does not show how empty-page pads should render (off/dark) or
  whether they should accept input.
- The row-select buttons on the right column update `selectedPhraseRow` for the
  phrase rows visible on the current page, but the visual distinction between
  "this row is the selected phrase" and "this row is a row-select button" is
  subtle. On the hardware, the right column always renders as `lp-edge-rowsel`
  (dark blue) except when that row is the selected phrase (`lp-edge-active`,
  amber). A user looking only at the hardware might not know which column serves
  as the row-select affordance; there is no label convention for that on the
  physical device. This is a hardware UX constraint, not a prototype defect, but
  the spec should document whether an introductory onboarding animation or a
  Settings tooltip is needed.
- The layer tab area on the on-screen view and the layer-select buttons on the
  hardware top row are in sync in the prototype, but the on-screen layer name
  labels ("Pattern", "Boolean", "Velocity", "Pitch") do not map one-to-one to a
  human-readable cue on hardware. Hardware pad position is the only identity cue
  for layer selection from hardware. This is a known constraint of the Launchpad
  form factor.
- The prototype does not show what the playing state looks like when `ph3` is
  both playing and selected (i.e., if the user clicks the row-select for the
  playing row). In the fixture, Ph3 is always playing and the selected row starts
  as Ph1, so the compound "selected + playing" cell state is never triggered
  interactively. The implementation should define a precedence rule.

**User story coverage:**

| Story | Coverage |
|---|---|
| 4. Phrase workspace editing from hardware | Largely covered: pad presses edit cells, LED colors reflect states, edge buttons navigate layers/pages, row-select updates selectedPhraseID. Gap: partial-page behavior not shown. |

---

### Prototype 3 — Live Workspace Hardware Grid (Story 5)

**What works:**

- The transport integration is the most architecturally significant addition in
  this prototype. The play/stop button on the top-right edge pad advances the
  playhead column at a visible tempo, and the green playhead column marches
  correctly through the visible step window. This is the "playhead column visually
  distinct during playback" requirement confirmed in one click.
- The scope-row color coding (each row carries a distinct color for its scope
  track group) directly addresses the "track colors and toggle states" language
  in `notes.md`. The right-column edge pads use dimmed versions of the scope
  colors, giving the hardware a visual scent of scope identity even without a
  screen.
- Steps-vs-bars mode switching is correctly prototyped: clicking "Bars" reduces
  the column count from 16 to 8 and resets the column page. The hardware
  edge-button mapping (scope-page left/right, col-page left/right, layer selectors)
  is laid out on the top CC row as annotated.
- The fixture data is adversarial: 10 scopes, 16 steps, 4 layers, with pattern,
  scalar, and boolean states mixed throughout. The second scope has a long name
  that exercises the scope sidebar truncation.
- The layer tab row transforms correctly between Layers 0–3 with hardware
  edge pads and on-screen tabs staying synchronized.
- The architecture annotation surfaces the important open question of whether
  `WorkspaceSection.tracks` should be renamed `.live` or a new `.live` case
  added, and that `scopePage` and `colPage` must be lifted from
  `LiveWorkspaceView` private state. These findings are coherent with
  `existing-state.md`.

**What fails or is limited:**

- Story 5 specifies that edge buttons should handle "workspace switching" — the
  user should be able to flip from Live to Phrase workspace from hardware. The
  prototype annotates this intent in the `hw-annotations` div
  (`[switch to Phrase ws]`) but the top CC row only has 8 pad slots and all 8
  are already allocated (scope-prev, scope-next, col-prev, col-next, 4× layer).
  The "workspace switch" pad is mentioned in the annotation but not included in
  the rendered grid because the Mini MK3 top CC row has exactly 8 pads. The
  play/stop pad is placed as the 9th position in the prototype JS comment
  with an explicit note: "not real hardware, annotated as design decision". This
  is a real constraint conflict: 8 edge pads minus 8 already-assigned functions
  equals zero room for workspace-switch or play/stop. The spec must resolve
  which functions get edge pads and which require a chord or long-press gesture.
  This is the most significant unresolved design question in the prototype set.
- The playhead column coloring completely overrides cell state: a pattern-slot
  cell in the playhead column renders as solid green (`lp-playhead`) with no
  visual distinction from an empty playhead cell. The user story says "playhead
  column is visually distinct during playback" but does not specify whether
  content-type information should still be legible in the playhead column. The
  prototype implicitly chooses full override; the spec should make this explicit.
- When both scope paging and column paging are at page 0, the "prev" edge pads
  are dimmed (inactive). When scopes or columns are at the last page, the "next"
  edge pads are dimmed. This is correct. However, the "dimmed" state uses the
  same `lp-edge-scope` / `lp-edge-step` classes (dark gray) rather than an
  explicit "disabled" visual. On real hardware, a fully unlit pad is meaningful
  (off = not assigned). The prototype should clarify whether unreachable
  navigation pads should be fully dark (no function) or the dim color (function
  exists but would be a no-op).
- Scope colors are hard-coded in the prototype as positional CSS classes
  (`c0`–`c9`). In production, scope colors will come from the project's track
  group color data. The prototype does not test what happens when a scope has no
  assigned color (e.g., ungrouped tracks). The spec should address the fallback
  palette entry for uncolored scopes.

**User story coverage:**

| Story | Coverage |
|---|---|
| 5. Live workspace performance from hardware | Largely covered: scope rows, step/bar columns, paging, layer switching, playhead column, transport. Gap: workspace-switch pad mapping unresolved; play/stop allocation conflict documented but not resolved. |

---

## Cross-Prototype Issues

### Edge-pad budget on the Mini MK3

The Launchpad Mini MK3 top CC row has 8 pads. Prototype 2 (Phrase) uses all 8
(2 track-page + 2 phrase-page + 4 layer). Prototype 3 (Live) also uses all 8
(2 scope-page + 2 col-page + 4 layer). Neither leaves room for workspace-switch
or play/stop in the top row. The workarounds used in the prototypes are:

- P2 moves workspace-switch off the top row entirely (not shown).
- P3 adds a 9th pad in the JS rendering loop with a comment that this is not
  real hardware, and assigns play/stop there.

The spec must define which functions map to the top CC row in each workspace and
which are reassigned to a modifier-chord (e.g., hold a layer pad + press
something else) or omitted from hardware in v1. This is a top-priority design
decision before architecture.

### Bidirectional sync model

Both grid prototypes show screen-to-hardware and hardware-to-screen sync working
correctly in the prototype JS. In production, this sync must flow through the
`WorkspaceControlSurfaceContext` and the relevant adapter
(`PhraseControlSurfaceAdapter` / `LiveControlSurfaceAdapter`). The prototypes
confirm the desired interaction model but do not de-risk the implementation path
for bidirectional binding with SwiftUI's `@State` / `@Observable`. This is
correctly deferred to architecture.

### Stories 2, 3, and 6 have no prototype coverage

These stories (Programmer-mode lifecycle, context-aware routing, window-focus
ownership) are pure system behaviors. No prototype is possible or needed for
them. Their acceptance signals are verifiable only at integration test level.
The architecture pass must address all three.

---

## Recommendation

**Accept all three prototypes as the direction for architecture and spec.**

Each prototype establishes the right interaction model for its story cluster:

1. Settings prototype: three-step configure path with five documented states is
   minimal and complete for stories 1 and 7.
2. Phrase grid prototype: bidirectional pad-to-cell sync with paging and layer
   switching is the correct mental model for story 4.
3. Live grid prototype: scope-row color coding with column paging and playhead
   tracking is the correct mental model for story 5.

**Required inputs for architecture before spec:**

1. **Edge-pad budget resolution.** The top CC row cannot simultaneously hold
   navigation, layer-select, workspace-switch, and transport. The architecture
   (or a user decision) must assign the top 8 pads for each workspace context
   and specify how play/stop and workspace-switch are handled if there is no
   room. Options: (a) dedicate a CC pad to workspace-switch and drop one
   navigation direction, (b) use a long-press or modifier chord for transport
   and workspace-switch, (c) defer workspace-switch from hardware to v2.
2. **`.tracks` vs `.live` workspace section name.** Both grid prototypes reference
   the "Live [tracks]" workspace using the current `WorkspaceSection.tracks` case.
   The architecture should decide whether to rename this case, add an alias, or
   leave it as-is and note the naming inconsistency in comments.
3. **Playhead column cell-state override rule.** Does the playhead override all
   cell colors entirely, or does it blend/tint the existing cell state?
4. **Partial-page rendering for hardware grid rows that fall outside the data
   bounds.** Empty pads should be dark (off); pressing them should be a no-op.
   This must be specified explicitly.
5. **Uncolored scope fallback.** What LED color does a scope row use if its
   track group has no assigned color?

**Elements settled by the prototypes (carry forward):**

- The Settings toggle + endpoint-picker + status-row + Test-LEDs layout for
  stories 1 and 7.
- The five-state machine for the Control Surfaces section (Disabled, Enabled/no
  endpoints, Input-only, Connected, Device missing).
- The 9×9 grid representation with semantic edge-button allocation for both
  workspaces.
- The six LED semantic states (empty, filled, selected, playing, pattern-slot,
  scalar) and the "active" amber highlight for current layer/page.
- The scope-color-per-row convention in the Live grid right column.
- The playhead column rendered as green in the Live grid.
- The annotation-driven architecture findings for state lifting
  (`trackPage`, `phrasePage`, `scopePage`, `colPage` must leave local `@State`).

---

## Next Action

Advance to `write-architecture`. The five required inputs listed above are
architecture-level decisions, not user-facing product decisions, with the
exception of item 1 (edge-pad budget). Item 1 may require a brief user
clarification before the architecture can be finalized — if so, the
architecture pass should surface it as an open question rather than blocking
the entire stage.
