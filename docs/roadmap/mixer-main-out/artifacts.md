# Mixer Main Out Artifacts

## 2026-04-29 - Mixer Reference Screenshot

Source: user-provided embedded screenshot in the planning conversation.

The screenshot shows a dark, hardware-inspired mixer surface with:

- Many vertical channel strips across the main area.
- Channel labels such as `Mic 1`, `Mic 2`, `Hydrasynth`, `Octatrack`, `Digitakt`, `Digi 1+2`, `Digi 3`, `Digi 4`, `Digi 5`, `Digi 6`, and `Pedal`.
- Per-channel pan/balance controls near the top.
- Mono/stereo status labels.
- Solo and mute buttons.
- Long vertical fader or level strips with meter markings.
- Lower gain and input controls.
- A right-side `MASTER MIX` panel with a visible output meter.
- Master mix rows or destinations labelled `octa ab`, `pedals?`, `octa cd`, and `Samplers`, each with a small solo control.

## Why This Matters

This artifact appears relevant to item `4`, Mixer Main Out, because it foregrounds a persistent master output area with metering and mix-master identity.

It also cross-cuts:

- Item `5`, Mixer Busses: the right-side master mix rows look like bus/group summaries.
- Item `6`, Send Effects: channel-to-bus/effect routing may need to live in or near this mixer concept.

## Design Signals To Preserve

- The master output is visually distinct from individual channels.
- Metering is not an afterthought; it is a major part of the mixer information hierarchy.
- Channel strips and master/bus summary rows can coexist in the same mixer view.
- Bus/group names can be user-language labels, including uncertain labels like `pedals?`.
- The design suggests fast scanning over explanatory text.

## Open Questions

- Is this artifact primarily about the main output, mixer busses, or the overall mixer view?
- Should master mix rows behave as busses, scenes, destinations, or monitor groups?
- Should this influence the prototype style directly, or only the information architecture?
