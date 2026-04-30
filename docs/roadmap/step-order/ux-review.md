---
verdict: accepted
selected_prototype: step-order-wireframe.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/step-order-wireframe.html
feedback_applied: []
---

# Step Order — UX Review

## Prototype Evaluated

Single prototype: `prototypes/step-order-wireframe.html`  
Four screens, one per user story. Interaction is live JavaScript. No external dependencies.

---

## What Works

**Story 1 — Remap editor (Screen 1)**

The two-row click model (select output step, then click source step) maps directly onto the mental model from `notes.md`. The prototype annotates the engine insertion point (`PlaybackSnapshot.resolvedStep`, line 67) inline, so the connection between UI gesture and code change is unambiguous. The fixture map `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]` is drawn from the real notes; it exercises the repeated-step case (steps 3, 15 pink) and the gap-then-return case (steps 8–11). The source clip note-presence row correctly shows read-only dot markers and carries an explicit annotation that it is never modified. The simulated playhead advances through the output grid and shows which source step it reads — the non-destructive guarantee is legible without reading the annotation. Auto-advance of the selection cursor after each source pick is a sensible quality-of-life detail.

**Story 2 — Live toggle (Screen 2)**

The toggle pill is the primary action and is visually dominant (accent border box). The pending-state model (change takes effect at next phrase boundary, not immediately) is called out explicitly in both an annotation and the status bar. The toggle event log makes it clear that the action has been registered even before it takes effect. The deferred-application behaviour matches what the user stories require (`Done when: takes effect within the next phrase cycle`).

**Story 3 — Scope selection (Screen 3)**

The scope selector leads with the existing-state recommendation (`Phrase`) and explicitly disables `Project` and `Layer` tabs with a `(future)` label and tooltip. The `Phrase / Track` tab is available as a first-pass alternative. The two description paragraphs explain the operational difference with concrete code references. The scope-change confirmation step (Apply / Cancel) prevents accidental re-scoping.

**Story 4 — Map persistence (Screen 4)**

The map list panel shows three fixture entries with realistic names ("Kick repeat x3", "Shuffle swing", "Reversed intro"), one with no usages (edge case), one with two usages. New-map dialog offers three sensible init modes (sequential, reversed, all-zero). Delete is blocked when the map is in use. Raw-array read-only view updates live as cells are edited. The auto-save-on-save-button pattern with a dirty indicator is clear.

**Guideline compliance**

- Greyscale base with one accent color and semantic-only use of highlight/repeat-warning/success/error. Palette is within six colors.
- Stubs are dashed borders with `→ [label]` text; they are unmistakable.
- One primary action per screen (edit mapping / toggle / scope apply / save map).
- Interaction budget is stated per screen in the header and annotated in click paths.
- Single self-contained HTML file, no build steps.
- Fixture data is consistent across screens (same map name, same 16-entry fixture).

---

## What Fails or Is Missing

**Story 1: no empty-map state**  
If a user creates a new map from Screen 4 and immediately navigates to Screen 1, the map editor shows a valid sequential map (not visually flagged as "identity / no remap"). There is no distinct empty or identity state. A reviewer completing Story 1 cold would not know whether they are looking at an active remap or a default pass-through. The toggle ON/OFF mitigates this but does not fully resolve it.

**Story 1: selection cursor wraps to 0 silently**  
After editing output step 15, the cursor auto-advances to step 0 with no indication. Editing all 16 steps continuously would silently start overwriting. A visual wrap or end-of-range indicator is missing.

**Story 2: "pending" state is annotation-only, not a UI signal**  
The prototype notes that a pending toggle should show a blinking indicator, but this is stubbed (`→ [pending indicator: "will change at bar boundary"]`). The toggle pill itself does not enter a pending state between toggle and phrase boundary. A reviewer trying to verify Story 2's `Done when` criterion (`takes effect within the next phrase cycle`) cannot tell from the prototype UI alone what the intermediate state looks like — they have to read the annotation. This is acceptable for a first-pass prototype but should be called out for architecture.

**Story 3: scope selector does not show a track-level toggle when "Phrase / Track" is selected**  
The track list updates to show `→ [per-track toggle]` as a stub when phrase/track scope is chosen, but the actual toggle affordance per track is completely stubbed. The user story requires that `the scope of the map is visible and adjustable`. At phrase/track scope, adjusting which tracks are enabled is on-path and should have at least a low-fidelity interaction (checkbox stub). The current stub does not let a reviewer complete the "adjustable" half of the story goal.

**Story 4: no map assignment flow**  
Maps can be created and edited but cannot be assigned to a phrase or track from within the prototype. The "Usage" section is read-only. A reviewer asking "how do I get this map onto a phrase?" cannot answer it from the prototype. The user story says `recalled without re-entering values each session`, which implies assignment must be completable. This is the most significant story-coverage gap.

**Cross-screen: no route from Screen 1 (editor) back to Screen 4 (map picker)**  
Screen 1 shows the active map name as a stub (`→ [map name: "Kick repeat x3"]`) with no tap target. A reviewer cannot switch which map is loaded from Screen 1. The route Screen 1 → map picker is missing.

---

## Interaction Budget Verification

| Story | Budget | Actual (click path) | Pass? |
|---|---|---|---|
| 1 — Change a single step mapping | ≤ 2 taps | (1) click output cell → (2) click source cell | Pass |
| 2 — Toggle map on/off | ≤ 2 taps | (1) find toggle (always visible) → (1) tap pill | Pass (1 tap) |
| 3 — Change scope | ≤ 3 taps | (1) click scope tab → (2) click Apply | Pass |
| 4 — Create and save a map | ≤ 4 taps | (1) + New → (2) name → (3) Create → (4) edit cell → Save | Pass with caveat: assignment flow missing so "recalled" goal cannot be verified |

---

## UX Checklist

- [x] Prototype is clearly marked as wireframe, not production proposal
- [x] Stubs are unmistakable
- [x] Fixture data is adversarial and consistent across screens
- [x] One primary action per screen
- [x] Empty / error states reachable — partial (missing empty-map state in editor)
- [x] Reversibility present — Cancel on scope change; Reset to sequential; map deletion blocked when in use
- [x] Non-destructive guarantee legible without reading code annotations
- [ ] All user-story `Done when` criteria completable from prototype — fails for Story 4 (assignment) and partially for Story 3 (per-track toggle)
- [x] Toggle deferred-application behaviour is explained
- [x] Interaction budgets verified

---

## Recommended Direction

Accept this prototype as the architectural and UX basis for Step Order. The two-row select-then-assign model for the remap editor is clear and within budget. The deferred-toggle model (phrase boundary) is well-reasoned and correctly annotated. Named, persistent maps with a pool model fit the existing `patternBanks` pattern noted in `existing-state.md`.

The three gaps below should be carried into architecture and spec rather than requiring a rework round:

1. **Map assignment flow** — how a map is attached to a phrase or phrase/track pair needs a UI path. This is a product decision (is assignment done in the map editor, in the phrase workspace, or both?) that should be resolved in `open-questions.md` or `architecture.md`.

2. **Pending-toggle visual state** — the intermediate state between toggle and phrase boundary needs a concrete affordance (blinking pill, status badge). The interaction is defined; the signal is not. The architecture pass should specify how the snapshot compiler communicates pending state back to the UI.

3. **Phrase/track scope: per-track toggle UI** — if `Phrase / Track` scope is in scope for the first pass, the per-track toggle needs at least a low-fidelity design before spec. If it is deferred, the scope selector should default to `Phrase` only and hide `Phrase / Track` as a future tab.

---

## Open Questions for Architecture

1. **Map assignment model**: Is a step-order map assigned to a phrase (one map per phrase, all tracks use it) or to a phrase+track pair? The existing-state analysis leans toward phrase-level as the simpler first pass, but the prototype exposes both scopes without committing to assignment semantics. The architecture pass must choose one and lock it.

2. **Pending-toggle propagation**: The toggle changes take effect at phrase boundary. Does the UI poll `PlaybackSnapshot` for confirmation, or does the engine post a notification when the new map is loaded? The approach affects how the pending indicator is implemented.

3. **Map pool location in the document model**: `existing-state.md` notes that persistence could live on `PhraseModel` or as a new top-level pool (like `patternBanks`). The prototype assumes a top-level pool (maps are named and shared across phrases). The architecture pass should confirm whether this matches the document model's ownership model.

4. **Fixed 16-step assumption**: `user-stories.md` defers variable-length maps. The prototype hardcodes 16 cells. The architecture pass should note where this assumption is encoded so it can be safely relaxed later without a schema migration.
