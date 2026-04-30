# Scene Perform — Implementation Handoff

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [spec.md](spec.md) | Primary build reference. Defines the complete feature contract: behaviour per story, data model touch points, view structure, engine call surface, acceptance criteria, and explicit out-of-scope list. |
| [plan.md](plan.md) | Phase sequence and per-task details. Read this first when starting each phase. The recommended task order is Phase 0 → 1-A → 1-B through 1-F → review gate. |
| [architecture.md](architecture.md) | Invariants and guardrails the implementation must preserve. Non-negotiable. |
| [architecture-review.md](architecture-review.md) | User-approved decisions. Overrides any ambiguity in architecture.md where the two differ. Three open questions from architecture.md were resolved here. |
| [ux-review.md](ux-review.md) | Scope decisions from user feedback and prototype review. Read this to understand what was cut and why before assuming any behaviour from the prototypes. |
| [prototypes/scene-perform-primary.html](prototypes/scene-perform-primary.html) | The selected prototype direction (primary variant). Use for layout reference. Descoped controls (Save Blend pos., Reset, Revert, Save to Scene) are present in the prototype but must not be built — they are stripped per ux-review.md. |
| [prototypes/scene-perform-compact.html](prototypes/scene-perform-compact.html) | Rejected variant for reference. The compact active-scene indicator (edge accent) was rejected in favour of the primary variant's full header inversion. |
| [existing-state.md](existing-state.md) | What the engine already provides, where the code lives, gap analysis per story, and existing test coverage. |

---

## Goal

Scene Perform is a layout and interaction refinement of the perform pane in `ScenesWorkspaceView+Perform.swift`. It restructures the crossfader and scene cards into a three-column layout so the fader sits physically between the two scene cards, adds a hard-switch affordance (tap the card header to snap the fader to that end), and adds a visual active-scene indicator (header colour inversion on the dominant card). No engine, audio, model, or persistence layer changes are required beyond one new computed property on `EngineController`.

---

## Chosen UX Direction

Three-column layout: `Scene A card | crossfader column | Scene B card` using an `HStack(spacing: 0)` with `1fr / ~120px / 1fr` sizing.

The crossfader column contains only: "A" label, vertical fader, blend percentage readout, "B" label. No Reset or Save Blend controls.

Each scene card contains: header (slot label + scene name + scene picker stub) with hard-switch tap target and active-state colour inversion, and a 2-column × 4-row macro grid (all 8 slots visible without scrolling). No card-actions footer (no Modified badge, Revert, or Save to Scene).

Active-scene indicator: full header colour inversion (dark background, white text) on the card where `effectiveCrossfader < 0.5` (A) or `effectiveCrossfader > 0.5` (B). At exactly 0.5, neither card shows the treatment.

See spec.md §Behaviour and §View Structure for the full structural definition.

---

## Guardrails and Invariants

These are hard constraints from `architecture.md` and the architecture review. The implementation must preserve all of them.

**1. Overlay must not be persisted by this feature.**
Live crossfader movement writes to `MasterBusPerformanceOverlayState.crossfaderOverride`, never directly to `MasterBusABSelection.crossfader`. The document is not mutated by any action in this feature (Save Blend and Reset are out of scope). This invariant must hold even if the implementation team is tempted to add a convenience shortcut.

**2. `EngineController` is the single owner of crossfader state.**
Views must not hold or shadow crossfader position locally. The view reads `engineController.effectiveCrossfader` and calls `engineController.setLiveMasterCrossfader(_:)`. No local `@State` or `@Binding` variable for the fader position.

**3. Active-scene indicator is a pure derivation, not stored state.**
`isADominant` and `isBDominant` are computed from `effectiveCrossfader` at point of use. No new stored property is introduced anywhere to track which card is "active".

**4. No model layer changes.**
`MasterBusState`, `MasterBusABSelection`, `MasterBusScene`, `MasterSceneMacroBinding`, `MasterBusHost`, and `SequencerDocumentSession+Mutations` are read-only from this feature's perspective. The only production source file that gains new code is `EngineController.swift` (one computed property). The only file that changes structurally is `ScenesWorkspaceView+Perform.swift`.

**5. Audio thread is not involved in view layout decisions.**
The three-column restructure is pure SwiftUI. `setLiveMasterCrossfader` already routes to `MasterBusHost` correctly. Do not add any audio-layer changes to support this feature.

---

## Sequencing and Phases

### Phase 0 — Pre-Build Verification (read-only, one sitting)

**0-A. Confirm `effectiveCrossfader` does not already exist** on `EngineController` or as an exposed computed value from `applyingPerformanceOverlay(_:)`. Read `Sources/Engine/EngineController.swift` (search for `crossfader` and `abSelection` references). If a matching property already exists under a different name, use it and skip task 1-A.

**0-B. Confirm `performView` entry point and `ViewThatFits` location.** Read `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` and identify the exact call sites of `ViewThatFits(.horizontal)`, `crossfader(...)`, and `performSlot(...)` and their current signatures. Note the lines to remove and the signatures to change before opening an editor.

No code is written in Phase 0.

---

### Phase 1 — UI Build

Phase 1 begins after Phase 0 findings are recorded. All tasks operate on at most two files.

**1-A. Add `effectiveCrossfader` to `EngineController`** (if Phase 0-A confirms it does not exist).

File: `Sources/Engine/EngineController.swift`

```
var effectiveCrossfader: Double {
    masterBusPerformanceOverlay.crossfaderOverride ?? abSelection.crossfader
}
```

Write two unit tests in `Tests/SequencerAITests/Engine/EngineControllerTests.swift`:
- When `crossfaderOverride` is `nil`, returns `abSelection.crossfader`.
- When `crossfaderOverride` is set, returns that value regardless of `abSelection.crossfader`.

This task must complete and pass tests before 1-B through 1-F begin, because those view tasks depend on `engineController.effectiveCrossfader`.

**1-B. Restructure `performView` to three-column layout.**
Replace `VStack { crossfader; ViewThatFits { ... } }` with `HStack(spacing: 0) { performSlot(.a) / crossfaderColumn / performSlot(.b) }`. Remove `ViewThatFits` and its vertical-stack fallback entirely.

**1-C. Build `crossfaderColumn`.**
Preferred implementation: custom vertical drag gesture view mapping vertical offset to `0.0...1.0` (clamped). Rotated `Slider` is acceptable if hit-area and accessibility testing confirm it is adequate. Every drag delta calls `engineController.setLiveMasterCrossfader(newValue)`. Blend readout (percentage) derived from `engineController.effectiveCrossfader` is always visible. Column width fixed at ~120pt. No Reset or Save Blend controls.

**1-D. Update `performSlot` — header hard-switch and active indicator.**
Wrap the header row in a `Button` or `.onTapGesture`: slot A calls `setLiveMasterCrossfader(0.0)`, slot B calls `setLiveMasterCrossfader(1.0)`. Apply full header colour inversion when dominant. Set VoiceOver accessibility labels for the hard-switch action and active state.

Write unit tests for the indicator derivation at `effectiveCrossfader` values 0.0, 0.5, and 1.0 (see plan.md §1-D test table).

**1-E. Update `performSlot` — macro grid layout.**
Remove `ScrollView(.horizontal)`. Replace the flat `HStack` of macro knobs with `LazyVGrid` (2 columns × 4 rows). Verify all eight labels render without truncation at the operating card width. Macro knob values continue to read via the existing `resolvedMacroValue` path.

**1-F. Remove card-actions footer.**
Remove the entire bottom row (Modified badge, Revert button, Save to Scene button). Confirm the scene picker stub and its `clearMasterBusPerformanceOverlay()` call on assignment remain in place.

---

### Review Gate (after Phase 1)

Self-review against spec.md acceptance criteria before marking build complete:

- [ ] Hard-switch: single tap commits fader to 0.0 or 1.0; indicator updates immediately.
- [ ] Live blend: fader travel confined to centre column; blend readout visible during drag.
- [ ] Cue / active indicator: both cards visible; dominant card shows header inversion; 0.5 shows neither.
- [ ] Read both scenes: all eight macros on both cards visible simultaneously; no horizontal scroll.
- [ ] No descoped controls: no Reset, no Save Blend, no Revert, no Save to Scene, no Modified badge.
- [ ] Audio smoothing limitation documented as a known issue (hard-switch produces buffer-boundary step; no ramp in scope).

---

## Files and Modules Touched

| File | Phase | Reason |
|---|---|---|
| `Sources/Engine/EngineController.swift` | 1-A | Add `effectiveCrossfader` computed property |
| `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` | 1-B through 1-F | All view changes |
| `Tests/SequencerAITests/Engine/EngineControllerTests.swift` | 1-A, 1-D | Unit tests for `effectiveCrossfader` and indicator derivation |

No other source files are modified.

---

## Non-Goals (First Version)

Do not build any of the following:

- **Reset to nearest end** (was story 4) — raises unresolved questions about where "the last clean state" is stored during a live performance session. Deferred to the future Live Scene Performance roadmap item.
- **Save Blend pos.** (was story 5) — raises questions about document mutation during a live set. Deferred to the same future item.
- **Save to Scene per-card button** (was story 5) — same deferral reason.
- **Revert per-card button** — the current model mutates the original scene on macro change; a revert path requires a snapshot or overlay model not specified here. Deferred to the future Live Scene Performance item.
- **Modified badge** — removed; there is no recovery action to pair it with.
- **Audio ramp on hard-switch** — requires `MasterBusHost` changes; explicitly out of scope. Document as a known limitation and track separately if the user reports it as a blocker.
- **Narrow-layout or touch fallback** — the three-column layout is unconditional. A narrow-layout adaptation is a separate item if it becomes needed.
- **Accessibility beyond basic labels** — VoiceOver labelling on the hard-switch button and active-state announcement is in scope. Hardware controller mappings, dynamic type scaling, and high-contrast mode support are not assessed here.

---

## Open Questions and Risks

**No blocking open questions.** The architecture review (`architecture-review.md`) resolved all three questions that were open after the architecture pass:

1. `effectiveCrossfader` is a computed property on `EngineController` (not inline in the view).
2. Preferred fader implementation is a custom vertical drag gesture view; rotated `Slider` is the fallback if testing confirms it is adequate.
3. The full card header is the hard-switch tap target (not a separate button inside it).

**Known risks for the implementation team (non-blocking):**

| Risk | Likelihood | Mitigation |
|---|---|---|
| Rotated `Slider` hit area behaves incorrectly | Medium | Default to custom drag gesture view; rotated `Slider` is the fallback, not the default. |
| Macro label truncation at narrower-than-expected card width | Low | Verify at operating window width in task 1-E; minor cosmetic tuning (font size, label abbreviation) does not require PM approval. |
| Hard-switch produces audible pop at buffer boundary | Known | Documented in spec as a known limitation. Do not add a ramp — that requires `MasterBusHost` changes outside this feature's scope. |
| Concurrent `EngineController` edits from another in-flight feature | Low | Confirm no other feature is actively touching `EngineController` before merging task 1-A. |

---

## Acceptance Criteria

Condensed from spec.md §Acceptance Criteria.

**Story 1 — Hard-switch:**
- [ ] Single click or tap on a scene card header snaps the fader to that end (0.0 for A, 1.0 for B).
- [ ] Active indicator updates immediately to reflect the new dominant card.
- [ ] No navigation away from the perform pane is required.

**Story 2 — Live blend:**
- [ ] Crossfader control is visually positioned between the two scene cards.
- [ ] Dragging end-to-end covers only the centre column width, not the full pane.
- [ ] Blend percentage readout updates continuously during a drag and is always visible.

**Story 3 — Cue / active indicator:**
- [ ] Both scene cards are simultaneously visible without scrolling or switching views.
- [ ] Dominant card (as determined by `effectiveCrossfader`) displays full header colour inversion.
- [ ] Non-dominant card renders in the default style.
- [ ] At exactly 0.5, neither card shows the active treatment.
- [ ] Macro slot values on both cards reflect current state (including any live overrides).

**Story 6 — Read both scenes at a glance:**
- [ ] All eight macro slots on both scene cards are visible simultaneously without horizontal scrolling.
- [ ] Each macro slot label is not truncated at the operating pane width.
- [ ] Scene A card, crossfader column, and Scene B card appear side by side in a single unscrolled viewport.

---

## Testing Expectations

### Engine Layer (Phase 1-A)

- `effectiveCrossfader` returns `abSelection.crossfader` when `crossfaderOverride` is `nil`.
- `effectiveCrossfader` returns `crossfaderOverride` when it is set, regardless of `abSelection.crossfader`.

### Indicator Logic (Phase 1-D)

| `effectiveCrossfader` | Expected `isADominant` | Expected `isBDominant` |
|---|---|---|
| `0.0` | `true` | `false` |
| `0.5` | `false` | `false` |
| `1.0` | `false` | `true` |

### Existing Tests (must remain passing unmodified)

- `Tests/SequencerAITests/Document/MasterBusStateTests.swift` — no model changes; all tests should pass as-is.
- `Tests/SequencerAITests/Audio/MasterBusHostTests.swift` — no audio changes; all tests should pass as-is.
- `Tests/SequencerAITests/App/SequencerDocumentSessionMasterBusTests.swift` — no session mutation changes; all tests should pass as-is.

---

## Key Source Locations

| What | Location |
|---|---|
| `MasterBusABSelection`, `MasterBusPerformanceOverlayState` | `Sources/Document/MasterBus.swift` (AB selection: line 685; overlay state: line 631) |
| `applyingPerformanceOverlay(_:)` (overlay merge reference) | `Sources/Document/MasterBus.swift` line 203 |
| `setLiveMasterCrossfader(_:)`, `clearMasterBusPerformanceOverlay()` | `Sources/Engine/EngineController.swift` lines 486–497 |
| `masterBusPerformanceOverlay` property | `Sources/Engine/EngineController.swift` line 113 |
| `MasterBusHost.setLiveCrossfaderOverride`, `equalPowerGains` | `Sources/Audio/MasterBusHost.swift` lines 129, 188 |
| Perform view entry point | `Sources/UI/Mixer/ScenesWorkspaceView.swift` (mode switch at line 69) |
| `performView`, `crossfader`, `performSlot` | `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` |
| `ViewThatFits` fallback (to remove) | `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` lines 5–26 |
| Existing `EngineController` tests | `Tests/SequencerAITests/Engine/EngineControllerTests.swift` |
