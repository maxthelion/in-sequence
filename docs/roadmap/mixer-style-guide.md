# Mixer Style Guide

This is project-local review authority for the shared mixer surface. Use it
with `wiki/pages/mixer-grammar.md` when building or reviewing Mixer Main Out,
Mixer Busses, Send Effects, and any future mixer-lane work.

## Intent

The mixer should read as one coherent performance surface, not a collection of
feature panels. Tracks, user busses, fixed send returns, and master output can
have different capabilities, but they should share a visible strip grammar so
the signal flow is immediately legible.

Ableton-style session/mixer layout is a useful reference for return/master
placement and strip consistency. It is not a visual skin to copy.

## Strip Grammar

- Tracks, busses, send returns, and master output are vertical mixer strips or
  close relatives of vertical strips.
- Primary level controls and meters align on a shared vertical rhythm.
- Pan, mute, solo, routing, sends, inserts, and names sit in predictable strip
  zones, even when a strip omits some controls.
- Busses may use grouped styling, but they still belong in the same horizontal
  mixer lane as tracks and master.
- Send A and Send B are fixed return strips. They should sit near the master
  area and read like mixer returns, not detached cards below the primary lane.
- Master Out may be compact and special, but it should align visually with the
  mixer strip system.

## Alignment And Space

- At the review desktop size, the primary track -> busses -> sends -> master
  lane must be visible without sections overlapping or being cut off.
- Do not stack persistent mixer sections in a way that hides primary controls
  below the fold while there is unused horizontal space.
- Add-bus and add-FX affordances should occupy stable, predictable slots and
  should not dominate the strip when they are not the primary live control.
- Special controls such as master scene crossfader and insert chains must be
  accommodated inside the strip grammar rather than creating disconnected
  panels.

## Readability

- Button text must remain readable in normal, selected, muted, solo, bypassed,
  disabled, and destructive states.
- Labels must not truncate in a way that hides the strip identity or important
  state. Prefer a shorter layout or tooltip/secondary text over invisible
  meaning.
- Color should distinguish identity and state without making unrelated strips
  look like different applications.
- Meter colors should reflect real audio state and clipping risk; warning
  colors should not imply danger when the level is safe.

## Review Checklist

Reviewers should fail or request correction when:

- adjacent mixer strips use unrelated fader/meter sizes or alignment;
- send returns are detached from the mixer lane;
- bus, send, or master sections overlap at the target window size;
- controls are present but unreadable;
- feature-specific UI makes the mixer feel like separate panels rather than one
  performance surface;
- screenshots do not show enough of the mixer to judge alignment, return
  placement, and master relationship.
