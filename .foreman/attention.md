# Attention ledger

Items genuinely needing Max, ranked. Each says what it unlocks.

1. **Review the perform/setup build-out** (now 4/7 landed: global mode,
   quantised toggles, perform overview, routing tab). Morning captures + gallery
   will be ready at first unlock. Judgment calls parked for you:
   - LATCH-mode fill taps bypass quantise (immediate latch even at
     Q:BAR) — confirm or veto.
   - Pre-existing gap surfaced: MOM/LATCH fill on the tracks matrix
     was UI-only (never reached the engine); the quantised cue is the
     first engine-audible fill there. Wiring MOM/LATCH through is a
     small follow-up if wanted.
   - Tracks-edit card height (capture review F1): shrink to content,
     or fill with destination/source info? (Setup-mode cards; one word
     decides.)
2. **WhatsApp quarantine — final step.** Spot-check chats, then
   `rm -rf ~/whatsapp-media-quarantine` frees 82GB. Disk runs
   one-build-at-a-time until then (~3.8Gi free).
3. **Restart coreaudiod** in a real Terminal (`sudo killall
   coreaudiod` — the `!` prefix can't password-prompt). Then I rerun
   the two HAL tests and the skip list goes to zero.
4. **Ear-checks, accumulated** (one playing session covers all):
   - Engine-solidity fixes: "+ Add FX" on a send bus while playing,
     send-FX sliders, fader/pan/send feel on a dense project, AU
     preset browser during playback, stop/BPM while recording.
     Behavior change: insert-less scene crossfades no longer sum
     (+3dB mid-fade artifact gone).
   - Step grid (unification): velocity clamps at the edit; macro taps
     cycle allowed values; multi-select option-cycle applies the
     tapped target to the whole selection.
   - Quantised toggles: arm/cancel feel, group commit on the bar.
   - Audio-input hardware: buffer playback audibility, EVO16
     monitoring, record-length repro (trace armed).
5. **Tracks-page layer reach** (your 145433 ask made cycler-only
   layers Live-page-only): say the word if you want them in the layer
   matrix instead.
6. **swift-atomics dependency decision** (deprecated OSAtomic shims):
   adopt the package or wait for a macOS 15 target. Low urgency.
