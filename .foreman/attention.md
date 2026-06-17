# Attention ledger

Items genuinely needing Max, ranked. Each says what it unlocks.

1. **DISK — the build-out is STALLED on it (hard blocker).** Free space
   is only ~2.7Gi of 228Gi; full builds bottom below the 1.5Gi safety
   floor, so NO gate can run. The routing-split slice (and every queued
   slice — 6b Sound panel, 7 slicer row) is code-complete but cannot be
   gated/landed until ~10Gi+ is free. The 82GB WhatsApp cache is already
   resolved (Media now 1.0G); the volume is full from OTHER data — not
   Time-Machine snapshots (only os.update ones present). Likely reclaim:
   Application Support (~24G), Messages (~6G), Downloads, old Xcode
   caches — or more disk. I won't delete personal data. Until ~10Gi+ is
   free the build-out is paused at the gate step.

2. **Dashboard reuse decision.** You chose the track-card matrix as the
   perform surface; the slice-3 PerformOverviewDashboard view (726
   lines) is now unreferenced dead code. It may be the home for the
   "macros live somewhere else" surface (§9 goal, currently unmet).
   Repurpose it for the macro home, or delete it? One word unblocks it.

3. **Review the perform/setup build-out** (5/7 landed: global mode,
   quantised toggles, perform overview, routing tab, capture edits;
   routing-split + kit-first also done/held). Captures pending console
   unlock + a build (disk-gated). Judgment calls parked:
   - LATCH-mode fill taps bypass quantise (immediate even at Q:BAR) —
     confirm or veto.
   - MOM/LATCH fill on the tracks matrix was UI-only (never reached the
     engine); the quantised cue is the first engine-audible fill there.
     Wire MOM/LATCH through? (small follow-up).
   - Tracks-edit card height (capture review F1): shrink to content, or
     fill with destination/source info?

4. **Ear-checks, accumulated** (one playing session covers all):
   - Engine-solidity: "+ Add FX" on a send bus while playing, send-FX
     sliders, fader/pan/send feel on a dense project, AU preset browser
     during playback, stop/BPM while recording. (Behavior change:
     insert-less scene crossfades no longer sum — +3dB mid-fade gone.)
   - Step grid: velocity clamps at the edit; macro taps cycle allowed
     values; multi-select option-cycle applies the tapped target to the
     whole selection.
   - Quantised toggles: arm/cancel feel, group commit on the bar.
   - Audio-input hardware: buffer playback audibility, EVO16 monitoring,
     record-length repro (trace armed).

5. **Tracks-page layer reach** (your 145433 ask made cycler-only layers
   Live-page-only): want them in the layer matrix instead?

6. **swift-atomics dependency** (deprecated OSAtomic shims): adopt the
   package or wait for a macOS 15 target. Low urgency.

---
Recently resolved (kept briefly for context):
- WhatsApp 82GB cache — quarantined then cleared; Media back to 1.0G.
  (Did NOT fix disk; volume still full from other data — see item 1.)
- coreaudiod restart — done; verified healthy (the two HAL tests pass
  directly when it's fresh). Note: it degrades again when app instances
  are force-killed, so unattended agent gates keep the 2 standard skips.
- Routing-split engine regression — critic caught engine changes +
  a deleted test bundled into the UI slice; foreman verified + reverted;
  branch now clean UI-only (awaiting the disk-gated gate). 2nd critic
  save → argues for backlog tweak #2 (precheck flags deleted-test /
  skip-list deltas) becoming mechanical.
