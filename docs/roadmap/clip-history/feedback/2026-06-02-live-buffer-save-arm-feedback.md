# Clip History Feedback: Live Buffer, Audition, Save Arm

- date: 2026-06-02
- source: product-owner live review of `auto/roadmap-1-clip-history-v2` at `414840b`
- loop: `build/clip-history`

## Problem

The current inline History tab is close enough in layout direction, but the behavior and preview semantics are wrong.

## Required Corrections

1. The large virtual preview should be divided horizontally by the number of steps in the current history selection.
   - For a 16-step one-bar selection, show 16 horizontal step regions.
   - Do not render a few oversized horizontal blocks that make the rhythm unreadable.
   - The preview should feel more like a compact piano-roll/time-grid than abstract bars.
   - The current long bars appear partly caused by alignment/selection-duration rendering: longer history selections make the bars narrower. The fix is not just resizing. The preview needs explicit time alignment and pitch placement.
   - Notes should reflect pitch vertically, even in compact form, so the preview reads as musical material rather than a row of undifferentiated activity blocks.

2. Pattern slots should not pulse all the time.
   - The intended model is: pressing `Save Clip` arms the top pattern row as the destination chooser.
   - Only while save is armed should the pattern slots visually indicate that they can be pressed.
   - If save is not armed, the pattern row should behave like normal pattern selection/navigation.

3. Remove or justify the `Refresh` button.
   - It is not clear what it does.
   - The history should not need manual refresh as its primary mental model.

4. History should always write to a circular buffer.
   - When no history segment is selected, the preview should show the currently filling live bar as notes arrive from generation or clip playback.
   - When a history segment is selected, the selected segment becomes the audition source and the preview displays that selected history.
   - Deselecting the segment should leave audition mode and return the preview to the live rolling/current-bar view.

## Acceptance

- The History tab works for generator and clip sources.
- The default state communicates live capture/rolling history, not a static saved clip.
- Selecting a history segment clearly enters audition for that segment.
- Deselecting clearly exits audition.
- `Save Clip` clearly arms destination pattern slots and does not make the pattern row pulse outside that state.
- The preview is rhythmically legible at the current review window size.
- The preview is pitch-legible enough to distinguish high/low notes and melodic contour.
