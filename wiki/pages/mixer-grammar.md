# Mixer Grammar

The mixer is a performance surface. It should read as one coherent signal-flow
workspace rather than a set of unrelated feature panels.

Use this page with `docs/roadmap/mixer-style-guide.md` when building or
reviewing Mixer Main Out, Mixer Busses, Send Effects, and future mixer-lane
work.

## Core Shape

- Tracks, busses, fixed send returns, and master output are all part of one
  horizontal mixer lane.
- Each unit should feel like a vertical strip or a close relative of a strip.
- The user should be able to scan left-to-right from sound sources, through
  groups/returns, to master output.
- Special capabilities are allowed, but they should be accommodated inside the
  shared strip grammar.

## Strip Family

- Track strips hold source identity, level, pan, sends, mute/solo, routing, and
  compact state.
- Bus strips hold group identity, inserts, level, pan, mute/solo, and fixed
  output to master.
- Send A/B are fixed return strips. They should sit near master and read like
  shared wet-return channels. They are NOT scene selectors: do not reuse the
  per-track `sendA`/`sendB` gains to stand in for "which master scene a track
  feeds" (that is the deferred `docs/roadmap/selective-scene-inputs/` item and
  needs its own model — a 2026-06 "Scene Send" selector that conflated the two
  was reverted, see `docs/plans/2026-06-24-fixed-superset-routing.md` §R4).
- Master Out is the final strip. It can include the scene crossfader and master
  FX, but it should still align with the mixer system.

## Visual Rules

- Faders and meters should share a common size language and align predictably.
- Buttons must remain legible in every state.
- Add/FX affordances should feel like mixer controls, not unrelated cards.
- Primary mixer controls should not be pushed below the fold when horizontal
  space is available.
- Sections must not overlap at the review window size.
- Labels should preserve identity and state; avoid truncation that hides the
  meaningful part of a strip name.

## Review Use

Visual and UX reviewers should include an explicit project-grammar row when a
mixer surface is under review:

| Check | Evidence | Verdict |
|---|---|---|
| Does the surface conform to `wiki/pages/mixer-grammar.md` and `docs/roadmap/mixer-style-guide.md`? | screenshot paths | pass / needs-correction / evidence-insufficient |
