# Bug: audible click / glitch when routing a track's output to a bus

**Filed:** 2026-06-26 — Max, real-audio pass (#42), confirming the #59 bus fix.
**Severity:** quality (audible glitch on a routing change). Fix later.

## What happens
After the #59 fix (bus routing now sounds), routing a sounding track's OUTPUT to
the FX bus produces a "slight noticeable change" — a click/glitch on the
transition. The track stays audible (good), but the switch is not click-free.

## Candidate causes (verify)
1. The meter-tap refresh added in the #59 fix: `connectPreparedSampleVoiceOutput`
   calls `removeChannelMeterTapsIfNeeded` + `installChannelMeterTapsIfNeeded` on
   the first voice that wires a bus. Tap install/remove on live nodes mid-route
   can glitch the render — and that refresh does NOT actually fix the bus meter
   (still -inf on real HAL), so it is a prime suspect AND removable dead weight.
2. The route reconnect itself is not ramped-to-silence (Hard Rule 5) — same class
   as docs/bugs/20260626-route-switch-teardown-hard-cut (route-switch teardown
   hard-cut). The bus voice pool build / output reconnect should ramp.

## Fix direction
Try removing the meter-tap refresh from the route path first (it's ineffective).
If a click remains, ramp the route-to-bus reconnect (gain to silence → splice →
gain back), consistent with the ramp-before-disconnect model. Verify on a quiet
single-track fixture by ear + the routing-stress CLICK gate (which is coarse and
did not catch this subtle one — consider tightening).

Status: RESOLVED — 05f7739e (route-switch crossfade)
