---
status: handled
handled_by: pm-assistant
handled_in:
  - docs/roadmap/clip-history/README.md
  - docs/roadmap/clip-history/ux-review.md
  - docs/roadmap/clip-history/spec.md
  - docs/roadmap/clip-history/plan.md
  - docs/roadmap/clip-history/implementation-handoff.md
---

# Clip History Built Modal UX Review

Status: accepted by user on 2026-05-04.

## Verdict

The current build should not be accepted as the Clip History UX. It has the right broad intention, a modal that saves recent generated material into a pattern slot, but it misses the central interaction model: choosing something from recent history and committing it as a clip.

The built modal feels more like "save the latest buffer length" than "browse, audition, and capture the musical moment I just heard."

## Most Important Problem

The built modal has no real history-selection concept.

The approved direction is:

- left side: 16 recent history regions as a 4x4 matrix;
- right side: 16 pattern slots as a matching 4x4 matrix;
- middle or lower area: selected virtual clip preview and length/audition controls;
- save only after a history region and destination slot are both explicit.

The current build shows a step grid for "Most Recent 1 Bar" and a pattern-slot grid. That collapses "history browsing" and "clip preview" into one thing, so the user cannot answer the core question: which bit of the last 16 bars do I want?

## Critical UX Issues

### 1. Interaction path is wrong

Expected:

`Open Clip History -> select history region -> preview/audition virtual clip -> select pattern slot -> save`

Current:

`Open Clip History -> change length maybe -> select destination slot -> save latest capture`

This is a different workflow. It removes the moment-finding part of the feature.

### 2. History and destination are not symmetrical

The accepted direction is two comparable 4x4 matrices. That matters because the task is a transfer operation: take this history cell and save it there.

The current UI makes the right side concrete and the left side abstract.

### 3. The modal starts with too much implied selection

The destination slot defaults to the first non-current slot, and "Save Capture" is visually available immediately. This makes the modal feel like it has already made a decision for the user, when the whole point is controlled capture.

### 4. No clear temporary vs committed distinction

The spec talks about pseudo-clip / virtual clip state. The current UI does not strongly communicate "this is only auditioning; nothing has been saved yet." The prototype had an explicit virtual clip preview row and audition state. The build mostly shows note cells and a save button.

### 5. No overwrite decision flow

Occupied slots show "used" or "current," but there is no confirmation model visible in the built UI. The expected UX is: selecting an occupied slot reveals a clear replace/overwrite row, and save remains gated until confirmed.

### 6. Length control is in the wrong conceptual place

Length currently appears before selecting history. Better: choose a history region first, then length modifies the selected virtual clip/range. Otherwise length feels like a global filter over "latest capture," not a property of the thing being captured.

### 7. Visual hierarchy is not helping

The right-side "Save To Pattern Slot" section is visually clearer than the actual history content, so the destination appears more important than choosing the source material. The primary decision should be "what did I hear that I want?"

### 8. Layout clips and feels cramped

The reviewed screenshot shows content cut off on the left/top and the right matrix crowded. The modal should have a stable minimum size and scroll only in controlled internal regions, not crop the title or primary content.

### 9. Performance bug is UX-critical

The app beachballs after right-side pattern-slot interaction. Process sampling showed the main thread blocked in:

`TimelineView -> ClipHistoryCaptureSheet.body -> engineController.capturedClipContent -> EngineController.withStateLock -> mutex wait`

Pattern-slot selection should be a cheap local UI action. Instead it triggers re-rendering that reads live engine capture via `TimelineView`, which can block on the engine lock.

## Prototype Comparison

The prototype had four conceptual regions:

- title bar;
- history region;
- virtual clip preview/audition;
- pattern slot picker/footer.

The build compresses history and preview into one step grid, loses audition, loses explicit history selection, and makes save too available.

Do not copy the prototype literally. The later 4x4 feedback supersedes the prototype's horizontal strip. Preserve the prototype's flow, but redraw the source/destination as two 4x4 matrices.

## Recommended Redesign

Top:

`Clip History - [Track Name]`

Small text: "Frozen from the moment this modal opened."

Main:

- Left panel: `Recent History`
- 4x4 cells labelled `-16` through `-1`, or `1-16 oldest -> newest`
- Each cell shows a tiny note/activity preview and empty state

Right panel:

- `Save To Pattern`
- 4x4 pattern slots, same visual scale as history cells
- Occupied/current/empty states clear

Lower panel:

- `Virtual Clip Preview`
- selected history region
- length selector
- optional audition/stop
- active step count

Footer:

- Cancel
- Save to selected pattern slot
- Save disabled until source + destination are selected
- Occupied destination requires confirm replace

## Acceptance Criteria For Rework

- Opening the modal freezes a snapshot once; no live polling in `body`.
- Right-side pattern-slot clicks do not touch `EngineController`.
- User must explicitly select a history cell.
- User must explicitly select a destination slot.
- Save disabled until both are selected.
- Occupied slot requires overwrite confirmation.
- Empty history state still shows the 4x4 history matrix, but save/audition are disabled.
- The visual relationship reads as "source history -> destination pattern."
- The modal does not crop title/content at the tested app window size.

## Severity

- P0: Remove `TimelineView` / render-path engine reads causing beachball.
- P1: Rework modal IA to source 4x4 + destination 4x4.
- P1: Gate save behind explicit source/destination/overwrite decisions.
- P2: Improve visual polish after the interaction model is corrected.
