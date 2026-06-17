# Resolution — branch fix/ui-consistency-bugs

Performance layer selector rebuilt on both the Phrase and Tracks perform
surfaces:
- 8 columns wide (8×8 grid grammar).
- Note repeat and step order variants are full-size cells of their own; they
  behave as toggles — tapping the active one returns to normal pattern
  playback.
- Pattern is a plain selectable layer (P1–P16 variant chips removed).
- The whole cell is the button; "SELECT" buttons removed.
- Latch removed from the layer list (it remains a UI behaviour picker, not a
  layer).
