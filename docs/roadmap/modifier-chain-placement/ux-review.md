---
verdict: accepted
selected_prototype: modifier-chain-placement-slot-well.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/modifier-chain-placement-slot-well.html
feedback_applied: []
---

# Modifier Chain Placement — UX Review

## Prototype Evaluated

Single variant: `modifier-chain-placement-slot-well.html` (Slot Well variant).

---

## Checklist

### Guidelines compliance (html-prototype-guidelines.md)

| Check | Result |
|---|---|
| Single HTML file, inline CSS + JS | Pass |
| Prototype banner present | Pass |
| Monochrome base with semantic color only | Pass — blue for primary/clip, green for generator/success, purple for modifier, yellow for bypass. Six colors total. |
| Stub treatment with dashed borders and placeholder labels | Pass — right column, pattern palette, clip/generator parameter surfaces all clearly stubbed |
| Fixture data: adversarial (long names, diacritics, edge cases) | Pass — "Vélodrôme Melody Long Title Clip", "Bürolandschaft Countermelody", 16-bar clip, empty-pool edge case present |
| States reachable: empty, occupied, error/loading | Pass — clip-occupied, gen-occupied, empty-slot, picker-open, swap-done, modifier-empty all reachable |
| Primary goal achievable without being told what is stubbed | Pass |
| Not too polished / could be mistaken for production | Pass — Balsamiq feel maintained |
| Interaction budget stated and annotated | Pass — 3-tap budget for story 5 annotated inline; tap counter visible in live-interaction mode |
| Reversibility present (Cancel on picker) | Pass |

---

## Per-story Goal Coverage

### Story 1 — Remove a clip source and replace it with a generator

**Coverage: Met.**

The `[x]` remove button on the clip well is present and prominent. Clicking it triggers the empty-slot state and auto-opens the four-option picker. The interaction handler correctly resets the source tab badge to EMPTY and clears the pattern slot badge. No layout shift occurs — the slot well reuses the same vertical region.

One subtlety: the prototype auto-opens the picker immediately after remove (without requiring a separate tap of the `[+]` button). This is a slightly different flow than the notes describe (notes say the `[+]` appears first, then the user taps it). The prototype's inline auto-open is arguably faster (saves one tap) but deviates from the story's "plus button appears" wording. This is a minor design question worth capturing as an open question rather than a blocker.

### Story 2 — Four-option source picker, on-screen

**Coverage: Met.**

The option grid (2×2) presents all four options without screen navigation. "New Blank Generator" is the primary (green) option. "Select Clip From Pool" and "Select Generator" expand inline sub-panels. The clip pool panel shows a scrollable list with adversarial fixture names. A Cancel button dismisses the whole picker.

The inline expand approach for sub-panels is the right call for staying on screen. The prototype correctly stubs the generator pool panel as well.

### Story 3 — At-a-glance legibility (clip vs. generator vs. empty)

**Coverage: Met.**

The slot tab bar is always visible and always shows type badges (CLIP, GEN, MOD, EMPTY) on both the Source and Modifier tabs without requiring the user to open either tab. The pattern palette slot badges also update on state changes. This addresses the "tell source type before entering the tab" gap identified in existing-state.md.

### Story 4 — Symmetrical modifier slot

**Coverage: Substantially met, modifier picker is stubbed.**

The modifier tab shows the identical slot-well pattern: empty state with `[+]` button, occupied state with name/meta, bypass pill, and `[x]` remove button. Visual language (border color, badge color) is distinct from the source slot (purple vs. blue/green) but uses the same structural pattern.

The modifier option picker is stubbed behind an `alert()`. This is appropriate — the modifier picker options (arpeggiator, transposer, rhythm gate, select modifier) are a valid scope boundary for the prototype. The structural symmetry is the thing being evaluated here, and it is present.

One gap: `GeneratorKind.supportsModifierStage` filtering (from existing-state.md) is not modeled in the prototype. The prototype's fixture data shows "Arpeggiator — Up/Down Cycle" but does not demonstrate the case where no compatible modifiers exist. An adversarial empty-modifier-pool state would have been useful, but this is not a blocker for accepting the direction.

### Story 5 — Clip-to-generator swap in three taps or fewer

**Coverage: Met and verified.**

Click path A (fastest): `[x]` on clip (tap 1) → picker auto-opens → "New Blank Generator" (tap 2) → done. **2 taps.** Within budget.

Click path B: `[x]` on clip (tap 1) → "Select Generator" (tap 2) → tap a generator from sub-panel (tap 3) → done. **3 taps.** Within budget.

The tap counter in the prototype accurately tracks these paths and shows a success message. Both paths complete within the track view with no screen navigation.

---

## What Works

1. **Slot tab bar as persistent state surface.** The tabs stay visible during all states; users can glance at both Source and Modifier badges without opening either tab. This is the single most important structural change from the existing segmented picker.

2. **Slot well as unified metaphor.** Occupied, empty, and transition states all live in the same visual container. The dashed-border empty state cleanly signals "needs filling" without introducing a new vocabulary.

3. **Auto-open picker on remove.** The prototype's choice to auto-open the picker immediately after removal is faster than a two-step tap-to-reveal flow. This is worth validating with the user but is a reasonable default.

4. **Inline expansion over modal push.** The sub-panels for clip pool and generator pool expand inside the existing left column, avoiding screen navigation. This directly satisfies the story requirements.

5. **Primary option hierarchy in picker.** "New Blank Generator" is visually primary (green border and background). The other three options are equal-weight. This matches the intent from notes.md: fastest path is generator, other options are progressive disclosure.

6. **Bypass pill placement.** The bypass toggle sits beside the remove button in the modifier well, not in a separate panel. This is a clean, compact arrangement.

7. **Fixture data quality.** Long names, diacritics, varied bar lengths, and an "(empty clip)" entry in the pool all stress-test the layout. The clip name truncation in the tab type label (handled in `finishSwapWithGen`) is noted.

---

## What Fails or Needs Attention

1. **Plus button vs. auto-open discrepancy.** After the remove action, the prototype skips the explicit `[+]` button tap and auto-opens the picker. The `[+]` button is technically rendered in `state-empty-well` but is hidden when the picker is already open. If the user cancels the picker, the `[+]` reappears. The behavior is internally consistent but the "plus button appears first" step from the notes is elided in the happy path. This should be recorded as a product decision to confirm.

2. **Modifier picker is fully stubbed.** The modifier option picker is behind an `alert()`. This was a scoping choice and is acceptable, but the direction for modifier options (what the four/N options are) is unspecified. This does not block accepting the UX direction, but it must be addressed in the spec.

3. **No empty-modifier-pool state.** If no compatible modifier generators exist in the project pool, the current prototype does not show what happens (existing-state.md notes that the current code hides the "Add Modifier" button in this case). The new `[+]` approach should clarify the expected behavior: hide `[+]`, show `[+]` disabled with a tooltip, or show a "no compatible modifiers" message inside the picker. This is an open question for spec.

4. **"Select Generator" sub-panel is a stub.** The generator pool sub-panel is populated with three fixture entries but selecting one calls `handleSelectGen()` which routes through the same `finishSwapWithGen()` function. This is functionally correct for the prototype but the sub-panel does not model the `GeneratorKind.supportsModifierStage` filter. Fine for this stage.

5. **Long tab-type text truncation is handled inconsistently.** The `finishSwapWithGen` truncation logic uses 22-character cutoff in JS but the initial state's "Vélodrôme Melody Long Title Clip" renders at full length in the tab. Not a design concern — just a prototype fidelity note.

6. **No error state for failed add operations.** If creating a new blank generator fails (e.g., incompatible track type), the prototype has no error state. This is not a concern for the direction decision but must be addressed in spec.

---

## Architecture Cross-check

The prototype models the `removeClipSource` mutation gap correctly — it annotates it as a model change needed in existing-state.md and does not pretend the mutation exists. The clip pool picker component is correctly identified as a new component. Both gaps are consistent with the existing-state.md findings.

The prototype does not model the per-pattern-slot vs. per-track concern, which is appropriate for a UX prototype. The architecture pass will need to address that the mutations operate at slot level, not track level.

---

## Recommended Direction

Accept the slot-well design as the direction for spec.

The prototype demonstrates that the slot-well metaphor:

- makes source and modifier state legible at a glance (story 3)
- supports the fastest clip-to-generator swap in two taps (story 5)
- provides a coherent add/remove pattern for both source and modifier (story 4)
- keeps all interactions within the track view (story 2)

No rework is needed before writing the architecture and spec. The open items below should be resolved in the spec, not in a prototype revision.

---

## Open Items for Spec

1. **Auto-open vs. explicit plus**: should the picker auto-open immediately on remove (2-tap path), or should the user tap `[+]` explicitly (3-tap path)? The prototype defaults to auto-open; this should be confirmed.

2. **Modifier picker options**: what are the specific modifier type options shown in the modifier picker? The notes mention arpeggiator, transposer, rhythm gate — spec must enumerate them and confirm they map to existing `GeneratorKind` values.

3. **Empty modifier pool behavior**: when no compatible modifier generators exist, what does the modifier slot show — `[+]` disabled, `[+]` hidden, or `[+]` that opens an informational state?

4. **"Select Clip From Pool" and "Select Generator" with empty pools**: both paths should have an empty-pool state that is reachable and understandable.

5. **Picker dismissal and slot state**: if the user opens the picker from `[+]` (without having just removed a source), cancels, and the slot is still empty, the slot well should remain visually empty (not revert to anything). The prototype handles this correctly; spec should make it explicit.
