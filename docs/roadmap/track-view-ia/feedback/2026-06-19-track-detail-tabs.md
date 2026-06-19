# Re-cut Track Detail Into Tabs

Raw product-owner clarification (this session):

> tracks in general need to have more tabs containing different parts: macros for
> a track, FX for a track, and split up the routing/output section to have the
> sound (the AU or MIDI output) and the mixer routing as a separate tab.
> ... Let's give tracks fx.

Interpretation for build:

- The single-track detail is re-cut into five tabs: **Steps/Clip · Sound · FX ·
  Macros · Mixer**.
- **Steps/Clip** = the existing clip/step source grid (the current "Source" grid).
- **Sound** = the instrument only (AU instrument / MIDI out / sampler), reusing
  `routing-source-mixer-split`'s SOUND SOURCE well + `.soundSource` vocabulary.
- **Mixer** = output bus + Send A/B (the MIXER & FX well from that branch).
- **FX** = a genuine **per-track insert chain** — a NEW model concept; inserts
  previously lived only on buses / master / scenes.
- Naming: a top-level "Source" tab already means the clip/note source, so the
  instrument tab must be called **Sound**, never "Source".
- History and Perform leave the tabs (see separate items).
</content>
