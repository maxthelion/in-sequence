# Bug: muting a track does NOT mute its sends — muted track still bleeds via Send A/B

**Filed:** 2026-06-26 — found by Max during the real-audio verification pass (#42).
**Severity:** functional mute bug (audible) — a "muted" track is still heard.
**Status:** Open — record now, fix later (per Max).

## What happens
With a sample track feeding Send A (to the FX/aux bus), pressing MUTE on that
track silences its DRY output but the track KEEPS sending signal out via Send A →
FX bus → master. So a "muted" track is still audible through its send.

## Why (architecture)
Mute is implemented as a gain ramp on the track's DRY output gain stage
(`setTrackMuteGain` → the track mixer / dry gain). But the send taps (sendA/sendB
mixers) split from the per-track FANOUT and are NOT downstream of that mute gain —
so they are unaffected by mute. Effective mute currently = dry-path gain → 0 only;
the send legs keep their levels.

Chain (sample/native): voices → trackMixer → trackFilter → fanout →
{ dry → preMaster, sendA → Send A bus, sendB → Send B bus }. The mute gain does
not cover the sendA/sendB legs.

## Expected
Muting a track should silence its ENTIRE contribution to the mix, including its
sends (Send A and Send B). A muted track must be inaudible everywhere.

## Fix direction (later)
Make "effective mute" cover the send legs too — e.g. ramp the sendA/sendB mixer
gains to 0 alongside the dry mute (and restore on unmute), OR apply the mute gain
at a node upstream of the fanout split so dry + both sends are all attenuated by
one gain stage. Must stay click-free (ramped, like the existing mute) and respect
the OR-combine (mixer-mute OR layer-mute) + per-source mute model. Add a
routing-stress / unit assertion that a muted track's send-bus contribution drops
to silence (the rig currently checks the track's own peak / dry path, not its
send-bus contribution — extend it).

## Relates to
#49 (mute as gain), #54 (mute OR-combine + routed-audio mute consistency). This is
the send-leg gap in that mute model.

Status: RESOLVED — ae862ac9 (mute now silences sends)
