---
feature: track-view-ia
created: 2026-06-19
status: suggested implementation sequence
sources:
  - spec.md
  - reasoning.md
---

# Track View IA Plan

Sequenced slices. Each slice should land with tests + a QA surface capture so the
acceptance criteria can be verified incrementally. Acceptance-criteria numbers
(AC#) reference `spec.md`.

## Slice 0 — Foundations / reuse
- Land on top of `feature/routing-source-mixer-split` (Sound vs Mixer content
  split already done). Resolve the Source→Sound naming. (AC1, AC2)
- Confirm the single-part bar pager primitive is reusable for the kit matrix.

## Slice 1 — Re-cut single-track detail tabs
- Tabs: Steps/Clip · Sound · FX · Macros · Mixer; Patterns row always above tabs.
  (AC1, AC2, AC3)
- Move History out of the tabs (reached via Capture — Slice 7).

## Slice 2 — Per-track FX chain + FX/filter cleanup
- New per-track insert-chain model + FX tab UI: drag-reorder, inline bypass+✕,
  "+ FX", no filler text. Apply same cleanup to Scenes inserts. (AC4, AC5)
- Filter plugin redesign: radial controls, ≥5 types, curve viz, no wet/dry. Keep
  the drum-part filter inside the mini sampler. (AC6, AC7)

## Slice 3 — Macros tab + defaults
- Macros tab (lanes + M1–M8); editable per-type default templates seeded with
  initial values. (AC8)

## Slice 4 — Kit matrix layout
- 16-step grid + bar pager (drop 16/32 toggle); names to the left; reuse track
  step primitives. (AC9, AC10)

## Slice 5 — Kit bus + kit-level tabs
- New drum group defaults to its own bus. (AC11)
- Kit tab bar Matrix · FX · Macros · Mixer at kit-bus scope. (AC13, AC23)

## Slice 6 — Patterns persistence + linking
- Patterns row always visible above the kit tabs. (AC12)
- Explicit link toggle, slot-only ganging; mute/fill/macros per-part. (AC17)
- Collapsed kit cell in track/perform matrix + Song mode; expand pairing. (AC18)
- Structural-divergence → break (auto-unlink, MIXED, re-link). (AC19, AC20)

## Slice 7 — Capture / History
- Capture/Perform header buttons; Capture replaces tab view, patterns stay. (AC14)
- Kit history: all parts together, save as one clip set. (AC15)
- Shared scrubber across all parts + live anchor. (AC16)
- Mirror the Capture→history surface at the single-track altitude.

## Slice 8 — Expand-a-row
- Accordion to the right of the part name; reuse detail surfaces inline;
  Steps/Clip Clip↔Generator switch. (AC21)

## Slice 9 — Scoped Track Perform
- Perform button on track/kit opens the phrase perform UI scoped down (reuse the
  perform-overlay substrate). (AC22)

## Slice 10 — Add Drum Group flow
- Sounds (kit picker + parts list, "+ Add Part" plus button), Patterns
  (templates), Routing (own-bus default). (AC11)

## Verification
- Add/refresh `qa-surface-coverage.sh` rows for each new/changed surface so
  visual evidence exists for AC24.
- Unit tests for: per-track FX chain ordering/bypass; link slot-ganging;
  structural-divergence auto-unlink; macro default seeding; kit history
  clip-set write.
</content>
