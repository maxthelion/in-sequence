---
verdict: accepted
selected_prototype: prototypes/03-selected-phrase-scene-rail.html
reviewed: 2026-05-03
prototypes_reviewed:
  - prototypes/03-selected-phrase-scene-rail.html
  - prototypes/04-inline-scene-strip-matrix.html
feedback_applied:
  - feedback/20260503-153024-prototypes-feedback.md
---

# Scenes In Phrases — UX Review

Reviewed 2026-05-03 against the replacement prototype pass, the prior rework review in `ux-reviews/ux-review-2026-05-03-needs-rework.md`, the Phrase Matrix existing-state analysis, and the HTML prototype guidelines.

---

## Checklist Results

| Criterion | 03 selected-phrase scene rail | 04 inline scene strip matrix |
|---|---|---|
| Extends the current track-oriented Phrase Matrix instead of replacing it | Pass | Pass |
| Tracks remain visible while scene authoring is active | Pass | Pass |
| `Tracks / Scenes` mode reads as a workspace mode, not a separate page | Pass | Pass |
| Scene intent is readable at row level without opening detail | Pass | Pass |
| Per-bar editing is reachable within 2 to 3 deliberate interactions | Pass | Pass |
| Long names, empty B scene, paging, and mixed phrase states are exercised | Pass | Pass |
| Off-path scene-library behavior is clearly stubbed | Pass | Pass |
| Variant difference is strategic, not cosmetic | Pass | Pass |
| Phrase-to-phrase comparison stays comfortable when several rows are visible | Pass | Partial |
| Reviewer could mistake the wireframe for production UI | Fail | Fail |

---

## What Works

### 03-selected-phrase-scene-rail.html (selected direction)

This variant best satisfies the replacement-pass requirement from [[feedback:20260503-153024-prototypes-feedback]]. It keeps the real Phrase Matrix shell intact: phrase rows stay on the left, track columns stay across the top, phrase actions remain where they already live, and the `Tracks / Scenes` toggle reads like a mode switch inside the existing workspace instead of a jump into a new scene page. That directly addresses [[story:4]] and corrects the main failure called out in the archived review.

The selected-phrase rail is the strongest answer to [[story:3]]. It gives per-bar crossfader authoring enough room to be understandable without forcing every phrase row to permanently expand. The click path stays within budget: switch to `Scenes`, select a phrase, then edit Scene A/B or the bar buttons in the rail. That keeps the dense automation work close to the row being edited while preserving the matrix as a comparison tool.

Story [[story:5]] also works here. Each phrase card already carries a compact scene summary (`A`, blend, `B`), so neighboring phrases remain scannable before the user opens the rail. Long scene names, a missing B scene, and mixed whole-phrase versus per-bar rows all remain legible enough to compare arrangement intent quickly.

### 04-inline-scene-strip-matrix.html (useful comparison, not the preferred lead)

This variant usefully proves that every phrase can carry a more explicit scene strip without abandoning the real Phrase Matrix shape. It is especially strong as a comparison artifact for [[story:5]] because it makes authored scene intent impossible to miss.

Its value is mostly comparative. It shows the upside of stronger row-level summaries, but it also makes the cost of that visibility obvious: more vertical weight per phrase before the user opens detail.

---

## What Fails Or Is Missing

### 1. Variant 04 spends too much row height on always-visible scene chrome

The inline strip is informative, but once several phrases are visible it starts to compete with the track cells rather than framing them. That weakens the main product promise of this pass: scenes-in-phrases should extend the existing matrix, not bury its track comparison function. This is why variant 04 is not the lead direction even though its summaries are strong.

### 2. Compact shorthand for per-bar motion is still unresolved

Both variants show that a phrase row needs a compressed language for crossfader automation, but neither one fully solves the final encoding. `Per-bar curve`, bar pills, and summary chips are enough for prototype sign-off, not enough to freeze the implementation wording. Architecture and spec still need to define what a user reads at a glance for patterns like "static center", "late jump to B", or "4-bar sweep".

### 3. Scene-library binding remains intentionally stubbed

That is acceptable for prototype review, but the architecture pass must still define how phrase-owned Scene A/B selection reaches the existing `MasterBusScene` library without turning the phrase matrix into a scene-management surface. The prototypes are clear about the editing home, not yet about the underlying binding contract.

### 4. Phrase-entry recall timing is still invisible

The prototypes correctly focus on authoring, but they do not tell the user when phrase-authored scene state wins during playback or how it relates to the live Scene Perform overlay. That omission is acceptable here, but it must become explicit in architecture and spec because it is core to [[story:1]], [[story:2]], and [[story:3]].

---

## User-Story Goal Coverage

| Story | Coverage |
|---|---|
| [[story:1]] Assign scene slots per phrase | Covered in both variants through phrase-owned Scene A / Scene B controls |
| [[story:2]] Set a static crossfader value for a whole phrase | Covered in both variants through whole-phrase blend mode |
| [[story:3]] Author per-bar scene blend changes | Covered best by variant 03, where the rail gives bar editing room without bloating every row |
| [[story:4]] Switch the phrase view between track editing and scene editing | Covered in both variants via explicit `Tracks / Scenes` mode framing inside the existing matrix |
| [[story:5]] Read scene intent quickly from the phrase row | Covered in both variants; variant 04 is slightly stronger at first glance, but variant 03 is strong enough without sacrificing comparison density |

---

## Recommended Direction

Accept `prototypes/03-selected-phrase-scene-rail.html` as the direction to take into human prototype review.

It best preserves the actual Phrase Matrix mental model while still making scene authoring feel native to that workspace. The selected-phrase rail gives dense crossfader editing a clear home, keeps track cells visible for musical context, and avoids turning every phrase into a permanently expanded scene card.

Keep `prototypes/04-inline-scene-strip-matrix.html` as a useful rejected comparison. It demonstrates a stronger always-visible summary language, which may still inform the final row shorthand, but it should not be the implementation lead because it spends too much of the matrix's vertical budget on summary chrome.

---

## Questions Or Required Follow-up

1. Human review should focus on whether the selected-phrase rail feels sufficiently local to the chosen phrase, or whether users will prefer the stronger but heavier inline-strip emphasis from variant 04.
2. Architecture should define the compressed row-summary language for phrase-level crossfader automation before spec work starts.
3. Architecture should specify how phrase-authored Scene A/B references bind to the existing scene library and how phrase-entry recall interacts with live Scene Perform overrides.
