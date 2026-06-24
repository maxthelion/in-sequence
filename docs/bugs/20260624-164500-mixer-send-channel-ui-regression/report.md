# Bug: UI regression on send channels in the mixer

**Filed:** 2026-06-24 (reported by owner during the audio-routing real-audio pass)
**Area:** Mixer → send channel strips (FX / Send A / Send B return strips)
**Severity:** UI regression (cosmetic/layout)

## Summary

The send channel strips in the Mixer have a layout regression. From the owner's
screenshot, each send (FX) strip's header row looks cramped/clipped: a small
round icon button, a "…" menu, a **truncated "8…" chip** (a value/insert label
that no longer fits), an enable toggle, and a row of small action buttons below
that appear tight/overlapping. The strips read as broken compared to the prior
layout.

## Evidence

Owner-provided screenshot of the mixer send channels (FX strips). Not yet
captured by the harness — add a capture row if reproducing
(`QA_SURFACE_CAPTURE_FILTER=04-mixer`, or a dedicated send-return strip row).

## Notes / suspicion

- Likely a recent change to the send-return strip layout (truncation /
  spacing / chip sizing). Candidate areas: `Sources/UI/Mixer/` send strip views
  (e.g. SendBus strip / MixerBusStrip and shared channel-strip chrome).
- This is INDEPENDENT of the audio-routing-cleanup engine work — it is a
  presentation regression, not a routing/engine issue. File and fix separately.

## Repro (to confirm)

1. Open the Mixer.
2. Observe the Send A / Send B (FX) return strips.
3. Compare header row chip/toggle/button layout against the intended design —
   the value chip truncates ("8…") and the controls look cramped.

## Acceptance

Send-return strip header row lays out cleanly (no truncated chip, no
cramped/overlapping controls), matching the channel-strip grammar used
elsewhere in the mixer.
