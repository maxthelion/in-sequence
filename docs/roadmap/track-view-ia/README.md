---
status: ready-for-build-loop-promotion
stage: implementation-handoff
priority: high
blocked_by: []
---

# Track View IA

Reorganises the track view into three altitudes with a consistent tabbed
grammar, and makes drum kits first-class:

- track matrix, kit matrix, and single-track/part detail altitudes;
- re-cut detail tabs (Steps/Clip · Sound · FX · Macros · Mixer);
- per-track insert FX (new model concept) + FX/filter cleanups;
- drum kits route to their own bus; kit-level FX / Macros / Mixer tabs;
- explicit pattern linking (slot-only) + collapsed kit cell;
- accordion expand of a kit row into inline part controls;
- patterns always visible; Capture/Perform header buttons;
- shared kit history with a scrubber, saved as one clip set;
- scoped Track Perform reusing the phrase perform UI.

## Artifacts

- [spec.md](spec.md) — accepted builder-facing behavior spec + acceptance criteria
- [plan.md](plan.md) — suggested implementation sequence / slices
- [implementation-handoff.md](implementation-handoff.md) — build-loop scope + boundary
- [user-stories.md](user-stories.md)
- [reasoning.md](reasoning.md) — IA rationale + decisions
- [prototypes/README.md](prototypes/README.md) — wireframes index
- [prototypes/01-track-detail-tabs.html](prototypes/01-track-detail-tabs.html)
- [prototypes/02-kit-matrix.html](prototypes/02-kit-matrix.html)
- [prototypes/03-track-matrix.html](prototypes/03-track-matrix.html)
- [prototypes/04-track-perform-scoped.html](prototypes/04-track-perform-scoped.html)
- [prototypes/05-sound-fx-filter.html](prototypes/05-sound-fx-filter.html)
- [prototypes/06-add-drum-group.html](prototypes/06-add-drum-group.html)

## Feedback (decisions)

- [feedback/README.md](feedback/README.md) — index of the 12 atomic decision items

## Reference Captures Used

- `.meta/multipass/visual-review/03-tracks-perform.png`
- `.meta/multipass/visual-review/18-track-source-clip.png`
- `.meta/multipass/visual-review/21-track-modifier-tab.png`
- `.meta/multipass/visual-review/22-track-history-tab.png`
- `.meta/multipass/visual-review/22b-track-routing-tab.png`
- `.meta/multipass/visual-review/28-drum-part.png`
- `.meta/multipass/visual-review/29-drum-kit-matrix.png`
- `.meta/multipass/visual-review/30-drum-kit-matrix-32.png`
- `.meta/multipass/visual-review/05a-scenes-edit-empty.png`
- `.meta/multipass/visual-review/05b-scenes-edit-content.png`
- `.meta/multipass/visual-review/31-drum-kit-routing.png`

## Related In-Flight Work

- `feature/routing-source-mixer-split` — already splits the routing tab into a
  SOUND SOURCE well + MIXER & FX well; reuse for the Sound/Mixer tabs.
- `auto/p0-track-performance-overlay` + `codex/live-perform-fill-overlay` — the
  perform overlay substrate for scoped Track Perform.
</content>
