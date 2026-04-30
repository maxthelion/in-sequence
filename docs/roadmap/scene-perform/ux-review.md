---
created: 2026-04-29
prototypes_reviewed:
  - prototypes/scene-perform-primary.html
  - prototypes/scene-perform-compact.html
feedback_applied: feedback/20260430-102206-prototypes-feedback.md
---

# Scene Perform — UX Review

## Feedback Summary

User feedback received after prototype review:

> "Let's take out 'save blend pos' 'reset' and record them as a new feature which is about live performing scenes. It brings up a lot of questions about where it's stored. Likewise, let's take out the revert and save to scene features. At the moment, if the scene is modified, it modifies the original. Those other behaviours can be a new feature."

This feedback has two distinct descoping decisions:

1. **Remove from crossfader column:** "Save Blend pos." and "Reset to nearest" — these imply persistence decisions that are not resolved for this feature, and belong to a future "live scene performance" feature.
2. **Remove from per-card actions:** "Revert" and "Save to Scene" per-slot buttons — modifying a scene in perform mode currently modifies the original directly; the recovery and save-back behaviors are deferred to a new feature.

---

## Scope Revision: What Is In and Out

### Kept in Scene Perform

- Three-column layout: Scene A card | crossfader column | Scene B card
- Hard-switch: clicking a scene card header snaps the fader to that end (story 1)
- Live crossfader blend: drag the fader in the centre column (story 2)
- Cue the off-side scene: both cards visible simultaneously with macro slot values (story 3)
- Active scene visual indicator: distinguishing which card is currently dominant (story 3)
- Read both scenes at a glance without scrolling (story 6)

### Removed from Scene Perform (deferred to a new feature)

- **Reset to nearest end** — was story 4; descoped. Raises unresolved questions about where "the last clean state" is stored during a live performance session.
- **Save Blend pos.** — was story 5 (crossfader position); descoped. Raises questions about document mutation during a live set.
- **Revert** per-card button — descoped. Current model mutates the original scene on macro change; a revert path needs a snapshot or overlay model that is not specified for this feature.
- **Save to Scene** per-card button — descoped. Same reason: deferred alongside Revert to the future live-performance-scenes feature.

The per-card action footer (card-actions row containing Modified badge, Revert, Save to Scene) is removed from the perform-mode card entirely for now. If macro overrides are active, no badge is needed either because there is no recovery action to signal.

---

## Prototype Review

### What Works in Both Variants

- The three-column grid (`1fr / 120px / 1fr`) is the correct structural answer to the "crossfader too wide" complaint in the original notes. The fader travel distance is limited to the centre column width, which is what the user asked for.
- Hard-switch via card header click is correctly implemented: one interaction, fader snaps, active indicator updates. Interaction budget met.
- The blend readout (percentage) updates live during drag and sits inside the crossfader column where it is always visible.
- Both prototypes use the same fixture data, so the layout comparison is fair.
- Stubs (mode toggle, scene picker) are clearly marked with dashed borders.
- The inline Save Blend confirm row (now descoped) demonstrated a reasonable pattern for future reference in the live-performance-scenes feature.

### What Fails (now descoped controls)

- **Save Blend pos. button and Reset button in the crossfader column:** both prototypes include these. Per feedback they are removed from scope. The crossfader column becomes fader + A/B labels + blend readout only, with no persist or reset controls.
- **Revert and Save to Scene buttons in card-actions footer:** both prototypes include these. Per feedback the entire card-actions footer is removed from this feature scope. The modified-badge is also unnecessary without those actions.

### Primary vs Compact: Remaining Differences

With the descoped controls removed, the two variants still differ in two meaningful ways:

| Dimension | Primary | Compact |
|---|---|---|
| Macro grid layout | 2 columns × 4 rows | 4 columns × 2 rows |
| Active-scene indicator | Full header colour inversion (dark bg, white text) | Left/right edge accent (3px border) + LIVE strip below header |

**Macro grid:** The 4×2 compact grid risks label truncation at standard card widths. The 2×4 primary grid fits the full label ("M5 Delay Send", "M7 Bit Rate") without truncation and at a readable 10px. The 2×4 layout is preferred.

**Active-scene indicator:** The primary variant's full header inversion is unambiguous under stage conditions (high contrast, large hit area). The compact variant's edge accent is subtler and risks being missed at a glance, particularly on a narrow card. The primary variant's header treatment is preferred for a live performance tool where glanceable state is essential.

---

## Checklist (against `docs/html-prototype-guidelines.md`)

- [x] Monochrome base, system font, no decorative flourishes
- [x] Semantic color only for state (active card, blended value, override dot)
- [x] Stubs clearly marked with dashed borders
- [x] Primary goal (hard-switch) achievable in 1 interaction
- [x] Interaction budget stated and annotated in HTML comments
- [x] Real interactions on the path under test (fader drag, hard-switch, state buttons)
- [x] Loading/empty/error states: idle, a-active, b-active, mid-blend, post-reset, save-confirm all reachable
- [x] Same fixtures across both variants
- [x] Single HTML file, no frameworks
- [ ] **Save Blend confirm and Reset annotation:** present in prototypes but now descoped — not a prototype defect, just confirms the scope cut

---

## Recommended Direction

**Adopt the primary variant layout with the descoped controls stripped.**

Specifically:

1. Three-column layout: `Scene A card | crossfader column | Scene B card` with `1fr / ~120px / 1fr` grid.
2. Crossfader column contains only: A/B labels, the slider, and the blend readout. No Reset, no Save Blend.
3. Scene cards: header (slot label + scene name + scene picker stub) + macro grid (2 columns × 4 rows, no scrolling) + no card-actions footer.
4. Active-scene indicator: full header colour inversion on the dominant card (fader < 50 → A; fader > 50 → B; exactly 50 → neither).
5. Hard-switch affordance: clicking/tapping the card header snaps the fader to that end.

The macro knob interaction (adjusting values on either card) remains available but without any in-pane save or revert path. Macro changes take effect on the original scene immediately, which is the current model behaviour. The consequence of this is that the "MODIFIED" badge and card-actions row are not needed in this feature's perform view.

---

## Deferred Feature Note

The descoped controls (Save Blend pos., Reset, Revert, Save to Scene) form the core of a new roadmap item: **Live Scene Performance** (working title). That feature needs to resolve:

- Whether live macro overrides create an ephemeral overlay (non-destructive) or mutate the scene directly
- Where a saved blend position is stored (document, session, or separate performance snapshot)
- The reset target semantics (nearest end vs last-clean persisted state)
- Whether Revert requires an overlay model or a snapshot

These are not in scope for Scene Perform.

---

## User Stories Affected

| Story | Status after feedback |
|---|---|
| 1. Hard-switch | **In scope** — no change |
| 2. Blend live with repositioned crossfader | **In scope** — no change |
| 3. Cue off-side scene / active indicator | **In scope** — no change |
| 4. Recover from accidental partial blend (Reset) | **Descoped** — moved to future Live Scene Performance feature |
| 5. Save a live blend (Save Blend pos., Save to Scene) | **Descoped** — moved to future Live Scene Performance feature |
| 6. Read both scenes at a glance | **In scope** — no change |

`user-stories.md` retains all six stories for historical record. The spec should only cover stories 1, 2, 3, and 6. Stories 4 and 5 should be clearly marked as descoped with a pointer to the future feature.

---

## Next Action

Write `spec.md` based on stories 1, 2, 3, and 6 only, the primary variant layout direction above, and the existing-state gap analysis (UX/layout gaps for those four stories only). Stories 4 and 5 should appear as an explicit out-of-scope section.
