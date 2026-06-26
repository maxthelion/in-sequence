# Bug: routed track's meter goes dead — should show at source AND destination bus

**Filed:** 2026-06-26 — Max, real-audio pass (#42). Fix later.
**Severity:** metering UX.

## What happens
When a track's output is routed to a bus, the SOURCE track's mixer meter stops
showing levels (`track<N>Peak` = -inf) even though the track is producing audio
(it reaches master via the bus). Max: the level should indicate BOTH where the
sound comes from (the source track) and where it's routed to (the bus).

## Expected
- The source track meter keeps showing the track's own output level regardless of
  where it's routed.
- The destination bus meter shows the summed level of everything routed to it.
  (The per-bus meter tap is also currently broken — bus<N>Peak = -inf even with
  signal; see #59 / docs/bugs/20260626-route-track-to-mixer-bus-goes-silent.)

## Fix direction
The track meter source moves/clears when the track routes to a bus (the meter tap
follows the track's terminal, which for a bus-routed sample track is the bus voice
pool, not the per-track filter). Keep a meter tap on the track's own output (pre-
bus) so the source always meters, and fix the bus meter tap so the destination
meters the sum. Relates to the bus-meter-tap gap in #59.

Status: RESOLVED — b19a6941 (source + bus meters)
