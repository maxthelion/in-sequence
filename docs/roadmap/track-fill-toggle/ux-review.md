---
verdict: accepted
selected_prototype: 01-header-toggle.html
reviewed: 2026-05-03
prototypes_reviewed:
  - prototypes/01-header-toggle.html
  - prototypes/02-lane-toolbar-toggle.html
feedback_applied: []
---

# Toggle Fill On A Track To Hear It — UX Review

## What Works

### 01-header-toggle.html (selected direction)

The header-placement variant is the clearest expression of [[story:3]]. Putting the control beside `Source` / `Modifiers` frames it as temporary playback state rather than phrase authoring. The prototype also proves the full primary loop in a small interaction budget: preview off, preview on, switched track reset, and generator-disabled all have reachable states.

The selected-track scoping is legible. The left track list changes selection, the header status text names whether preview is active for the current track only, and the step grid highlights only the affected clip track when preview is on. That directly supports [[story:1]], [[story:2]], and [[story:4]].

The generator fallback is handled responsibly. The disabled control plus explicit note avoids implying unsupported behavior, which matches the out-of-scope boundary already recorded in [[story:3]] and `existing-state.md`.

### 02-lane-toolbar-toggle.html (useful comparison, not the preferred direction)

This variant is more discoverable at first glance because the control sits next to the lane chips the user is already reading while editing clip content. It also shows the same state coverage as the selected variant, so the prototype work is not incomplete.

Its value is mostly comparative: it demonstrates why proximity to the lane tabs is not enough on its own when the feature's hardest requirement is "preview, not edit."

## What Fails or Is Missing

### 1. Variant B reads too much like authoring, not playback

Placing the toggle beside `Normal lane` / `Fill lane` makes it feel dangerously close to a data-mode switch. That cuts against the main product requirement from [[story:3]]: the user must understand that this does not mutate the phrase's `"fill-flag"` layer. This is not a small wording problem; it is a placement problem. For that reason, variant B should not be the implementation lead.

### 2. Editor-close reset is described but not demonstrated

Both variants explicitly show reset-on-track-switch, which is good, but the acceptance signals also require reset when the editor closes. The prototypes annotate that rule rather than showing a dedicated close-and-reopen state. That is acceptable for PM sign-off, but the spec should preserve it as a concrete acceptance check rather than letting it disappear into prose.

### 3. Generator fallback copy should stay near the disabled control

The disabled generator state is correct, but in both variants part of the explanation lives in side-panel copy. The final implementation should keep a short explanation adjacent to the disabled control itself so the user does not need to scan the page to learn why preview is unavailable.

## UX Checklist

| Criterion | Result |
|-----------|--------|
| All user-story goals reachable from the prototype | Pass for variant A; partial for variant B because placement undermines the transient-preview message |
| Happy path completable in <= 2 interactions | Pass |
| Active states visually unambiguous | Pass |
| Reset and disabled edge states shown | Pass for track-switch and generator; partial for close-editor reset |
| Off-path UI clearly stubbed | Pass |
| Primary control reads as playback-state, not phrase edit | Pass for variant A; fail for variant B |

## User-Story Goal Coverage

| Story | Coverage |
|-------|----------|
| [[story:1]] Preview fill pattern while editing a track | Covered in both variants |
| [[story:2]] Know whether fill is active during editing | Covered in both variants |
| [[story:3]] Fill preview does not permanently alter the phrase | Covered well by variant A; only weakly by variant B because of placement ambiguity |
| [[story:4]] Fill toggle is scoped to the track being edited | Covered in both variants via track-switch reset and isolated playback notes |

## Recommended Direction

Accept `01-header-toggle.html` as the prototype to take into human review. It best matches the product boundary already established in `existing-state.md`: this feature needs to feel like a temporary, track-scoped runtime override, not a phrase edit.

Keep `02-lane-toolbar-toggle.html` only as a rejected comparison point. It is discoverable, but it invites the wrong mental model by living beside the lane authoring controls.

## Questions or Required Follow-up

1. Human review should specifically confirm that header placement feels discoverable enough without collapsing into the "this edits the lane" confusion of variant B.
2. The next spec should preserve reset-on-editor-close as an explicit acceptance criterion, not only an annotation.
3. The implementation handoff should require inline disabled-state copy for generator-backed tracks near the control itself.
