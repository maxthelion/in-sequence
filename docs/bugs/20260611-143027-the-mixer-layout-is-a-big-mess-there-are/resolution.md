# Resolution — mixer layout overhaul

Branch: `feature/mixer-overhaul`. Each ruling from the note, and what
changed (all in `Sources/UI/Mixer/`, `Sources/UI/MixerView.swift`,
`Sources/UI/Theme/StudioMixerStrip.swift` unless noted):

1. **Multiple controls for adding busses** — the BUSSES zone header (with
   its own Add Bus button) is gone; the single Add Bus card remains, sized
   to the strip footprint so it sits among the strips as a same-kind card.

2. **Busses rendered lower than other strips** — bus strips are now direct
   siblings of the track strips in the one strip row (no wrapper header, no
   extra vertical padding). All strip kinds share the fixed slot grid:
   header / FX / levels / pan / actions / footer.

3. **Volume bars don't show levels like the master** — every fader now
   renders live L/R meter lanes behind a translucent level fill, fed by
   real per-channel taps (see roadmap 29 / `ChannelMeterBank`). Send
   returns render the same lane as a pure meter. Levels read in dB like
   the master.

4. **Pan below the volume with a side-to-side element** — pan is a
   dedicated fixed-height slot directly under the fader, rendered by the
   new `StudioSlideControl` (app-styled horizontal slider with center
   detent, L/C/R readout). This deliberately overrides the 2026-06-10
   review's rotary-pan recommendation per this note.

5. **Channel titles different sizes** — all strip headers use one small
   style (`MixerStripHeader`, labelBold + micro caption): tracks, busses,
   sends, master.

6. **Send A/B too much text; volume bar aligned** — send strips are down to
   a dot + "SEND A"/"SEND B" header, the shared insert list, an aligned
   meter lane in the levels slot, and a "→ Master" footer.

7. **Sends grouped next to the master** — at full width the two send
   strips sit as fixed siblings immediately left of the master column,
   outside the scrolling track/bus row. (In the compact sub-540pt
   presentation they trail the scroll so narrow windows stay usable.)

8. **Consistent space allocation for FX** — the processing slot is one
   fixed height (128pt) across channels, busses, sends, and the master;
   the master column now uses the same `StudioMixerStrip` scaffold, so its
   FX chain, fader/meter, side-to-side row (the A/B blend), and actions
   align row-for-row with every other strip.

9. **Send FX rotaries move in place / debounce** — the per-channel send
   knobs are now `StudioRotaryKnob`s that turn in place while dragging (no
   popover slider). Live drag ticks drive the engine through the scoped
   send path, epsilon-gated by `ThrottledMixValue`, with a commit on
   release — removing the jumpy popover round trip.

10. **Solo banner misaligns everything** — the banner is gone. Solo state
    surfaces as a fixed amber SOLO pill in the master column header (a
    fixed-height slot, so nothing shifts); clicking it clears all solo.
    Soloed strips still highlight amber.

Verification: unit suites green (strip scaffold metrics, slide-control
model, dB labels, channel meter bank + tap plumbing, existing mixer/master
tests). Visual QA capture pending (console was locked during this slice).
