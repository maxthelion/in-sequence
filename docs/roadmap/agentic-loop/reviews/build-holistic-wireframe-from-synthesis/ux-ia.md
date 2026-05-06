---
status: reviewed
verdict: needs-correction
reviewed: 2026-05-06T19:34:30+01:00
source_pass: docs/roadmap/agentic-loop/passes/build-holistic-wireframe-from-synthesis.md
visual_evidence: docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/screenshot.png
scheduled_follow_up: docs/roadmap/agentic-loop/passes/correct-holistic-wireframe-commit-discard-evidence.md
---

# UX/IA Review

## Verdict

The holistic wireframe is strong enough to review and should remain the current
product-shape source. It should not be sent to the user yet. Schedule one
agent-side correction pass before asking for product judgment.

## What Passed

- The screenshot is valid and shows the intended Happy Accident Workbench rather
  than a browser/file picker or empty surface.
- The first viewport reads as one workbench: transport, track roster, source and
  capture area, consequence rail, phrase/scene/mixer band, and transient state
  are all visible together.
- The lane synthesis was used well. Audio buffer capture anchors the center,
  clip history stays near the selected source slot, and mixer/scene/phrase state
  appear as consequences of the same sounding material.
- The page answers the basic user questions: what is sounding, what was
  captured, what can be captured next, and what is currently transient.

## Findings

### P0 - Keep and Discard do not show distinct consequences clearly enough

The top bar exposes **Keep** and **Discard**, and the fixture carries target
strings, but the actual viewport does not show where either action will write or
restore without relying on button tooltips. Both click handlers also collapse to
the same visual result: the transient overlay clears.

This is the main product-spirit gap. Safe performance depends on the user seeing
the difference between "write this live change into authored phrase/scene state"
and "restore the authored state." The correction should make the target and
post-action acknowledgement visible in the first viewport.

### P1 - Primary action hierarchy is close but still crowded

The workbench has four strong actions in the first viewport: Keep, Discard,
Capture Generated Clip, and Capture Loop To Shared Buffer. That is acceptable
for a holistic probe, but the next correction should keep capture centered in
the Source/Capture area and make Keep/Discard read as the transient-state
decision, not a competing global primary action.

### P1 - Queued phrase staging is implied, not visible

The bottom band distinguishes NOW and NEXT phrase cards, but it does not show
whether queued phrase changes are staged, committed, or only selected for
playback. This does not block the wireframe review, but it should be captured as
a follow-up default before production phrase work.

## Agent-Side Outcome

No user attention is needed. Schedule a narrow correction pass to strengthen
visible Keep/Discard semantics and then rerun the lens review or promote the
accepted decisions into inferred defaults.
