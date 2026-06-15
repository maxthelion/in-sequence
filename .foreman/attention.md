# Attention ledger

Items genuinely needing Max, ranked. Each says what it unlocks.

0. **Dashboard reuse decision (slice 5 follow-up, not urgent).** You
   chose the track-card matrix as the perform surface; the slice-3
   PerformOverviewDashboard view (726 lines) is now unreferenced. I'm
   NOT deleting it — you said macros "live somewhere else," and the
   dashboard's row+macro-rack layout may be the home for that. Tell me:
   repurpose it for the macro home, or delete it as dead code? (Its
   own tests still pass since the view compiles; only the perform-mode
   invalidation test needed fixing, which the finish pass is doing.)

1. **Review the perform/setup build-out** (now 4/7 landed; slice 5
   capture-edits is green on its feature branch and awaiting landing:
   global mode,
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
3. **Ear-checks, accumulated** (one playing session covers all):
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
4. **Tracks-page layer reach** (your 145433 ask made cycler-only
   layers Live-page-only): say the word if you want them in the layer
   matrix instead.
5. **swift-atomics dependency decision** (deprecated OSAtomic shims):
   adopt the package or wait for a macOS 15 target. Low urgency.
