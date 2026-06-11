# Resolution

Fixed in `Sources/UI/Slicer/SliceTrackWorkspaceView.swift`.

- When no loop is attached, the Sample Player panel (and its "Step 1" eyebrow
  and "No loop assigned / Create a slice track from a break loop first."
  text) is not rendered at all — exactly the "remove it in this scenario"
  suggestion. If the right column has nothing left to show (no routes
  either), the whole column disappears and the slice clip area gets the
  width back.
- The panel's remaining empty states ("No slices yet", "No assigned slice")
  lost their explainer sentences; the guidance moved to tooltips
  (ux-canon rule 3).
