---
verdict: needs-rework
selected_prototype: null
redirect_to: build-prototypes
reviewed: 2026-05-03
prototypes_reviewed:
  - prototypes/01-inline-bars-matrix.html
  - prototypes/02-summary-row-detail-drawer.html
feedback_applied:
  - feedback/20260503-153024-prototypes-feedback.md
---

# Scenes In Phrases - UX Review

> Superseded on 2026-05-03 by [[feedback:20260503-153024-prototypes-feedback]]. This review captured a coherent direction for the wrong frame: both prototypes treated the feature like a scene-specific page instead of an extension of the current track-oriented Phrase Matrix. Keep this document only as historical context until a replacement prototype pass lands.

## Rework Trigger

The next prototype pass must start from the existing Phrase Matrix shape described in [[wiki:information-architecture-ux]] and [[code:Sources/UI/PhraseWorkspaceView.swift:3]]: tracks across the top, phrases down the rows, existing phrase controls, and track paging preserved. Scenes-in-phrases needs to layer scene A / crossfader / scene B authoring into that matrix rather than moving the feature into a standalone scene workspace.

## What Works

### 02-summary-row-detail-drawer.html (selected direction)

The compact-row variant best satisfies the scanning goal in [[story:5]]. Each phrase stays one row tall, so neighboring phrases can be compared without the matrix collapsing into a tall stack of mixed-height cards. The row-level summary makes the authored scene pair and blend mode legible in the same place where the user already reads phrase order, which keeps the feature anchored in the Phrase Matrix rather than drifting toward a separate scene editor.

The drawer is the right trade for [[story:3]]. Per-bar crossfader authoring is the densest interaction in this feature, and moving it into a selected-phrase detail panel keeps that complexity off the default path. The prototype still keeps the interaction budget tight: one click to select the phrase, one click to switch static vs. per-bar mode, then direct bar edits. That is a better fit for phrase-level scene programming than forcing every automated phrase to permanently expand the grid.

The split between summary row and detail drawer also reinforces the product boundary captured in `existing-state.md`: this is authored phrase behavior, not the live Scene Perform overlay. The row summary says "what this phrase will recall," while the drawer says "how this phrase is programmed." That separation helps avoid confusion between persistent phrase state and live performance controls.

### 01-inline-bars-matrix.html (useful comparison, not the preferred lead)

The inline-bars variant proves that fully in-place editing is possible. It is valuable because it exposes the hardest trade-off directly: maximum glanceability of per-bar motion versus matrix height and comparison cost. Keeping this variant on disk is worthwhile because it gives architecture and spec work a concrete fallback if later implementation constraints make the drawer awkward.

It also demonstrates that the phrase row can carry enough fixture data to stress the three-column Scenes mode: long scene names, static-vs-bar phrases, and short-vs-long phrases all remain understandable.

## What Fails or Is Missing

### 1. Inline per-bar rows scale poorly once several phrases use automation

Variant 1 becomes visually expensive as soon as more than one adjacent phrase uses bar automation. That cuts against [[story:4]] and [[story:5]], which need the matrix to remain a fast comparison tool. The prototype acknowledges this risk, and it is the main reason not to lead with the inline version.

### 2. Scene-library selection is intentionally stubbed in both variants

Both prototypes stop at cycling or stubbed scene pickers. That is acceptable for this stage, but architecture must specify how phrase-owned scene A/B selection reaches the existing scene library without implying that phrase rows own or edit scene contents. The UX direction is sound; the integration path is still undefined.

### 3. Bar automation summaries need a stronger compressed language

Variant 2 is the selected direction, but its compact summary still leaves an architecture/spec task: the matrix row needs a durable shorthand for "static center," "four-bar sweep," or "late jump to B" that remains legible without opening the drawer. The prototype shows the need; it does not fully solve the final encoding.

### 4. Phrase-entry recall timing is not represented

The prototypes correctly focus on authoring, but they do not show when scene A/B recall happens relative to phrase changes. That omission is fine for UX sign-off, yet it means the architecture pass must explicitly define phrase-entry timing and precedence against live Scene Perform overrides.

## UX Checklist

| Criterion | Result |
|-----------|--------|
| All user-story goals reachable from the prototype set | Pass |
| Primary matrix remains scannable across multiple phrases | Pass for variant 2; partial for variant 1 |
| Static vs per-bar crossfader modes are distinguishable | Pass |
| Off-path scene-library behavior clearly stubbed | Pass |
| Adversarial fixture data stresses naming and phrase variation | Pass |
| Detail editing reachable in <= 2 interactions from the row | Pass for variant 2 |

## User-Story Goal Coverage

| Story | Coverage |
|-------|----------|
| [[story:1]] Assign scene slots per phrase | Covered in both variants via Scene A / Scene B row controls |
| [[story:2]] Set one crossfader value for a phrase | Covered in both variants via static blend mode |
| [[story:3]] Author per-bar scene blend changes | Covered in both variants; variant 2 handles density better |
| [[story:4]] Switch phrase view between Tracks and Scenes | Covered via explicit mode framing in both variants |
| [[story:5]] Read scene intent quickly from the phrase row | Covered best by variant 2 |

## Recommended Direction

Do not treat either current prototype as the direction for architecture and spec work.

The replacement prototype pass should preserve the existing Phrase Matrix shell and explore how scene authoring fits inside that track-oriented workspace. It can still reuse useful local ideas from the current files, especially compact summaries and a detail affordance for per-bar automation, but only after the layout is re-anchored to the real phrase page.

Keep the current files only as rejected-but-useful comparisons. They may still inform the interaction budget for summaries and detail editing, but they are not authoritative shapes for the feature anymore.

## Questions or Required Follow-up

1. Architecture should define the compact row summary language for bar automation so phrase rows remain comparable without opening the drawer.
2. Architecture should specify how phrase-owned Scene A/B references bind to the existing `MasterBusScene` library without turning the phrase matrix into a scene-management surface.
3. The spec should define when phrase-authored scene recall wins against live Scene Perform overlays and how that handoff is communicated.
