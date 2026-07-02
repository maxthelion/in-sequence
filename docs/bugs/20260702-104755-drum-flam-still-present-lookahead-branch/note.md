Drum kit still flams under UI nav load — the look-ahead pump on
engine/precompute-lookahead is not eliminating it (capture evidence).

Full 808 kit, 8 bars @ 120 BPM, navigating the UI throughout (rig nav-load stress,
scripts/capture_8bar.sh + render_8bar.py). Bottom panel of each image = each
detected onset's offset from the 16th-note grid.

Screenshots:
- flam-before-main-52ms.png   — BEFORE (main baseline): worst 52.2 ms, rms 33.0 ms
- flam-after-eba34a0c-61ms.png — AFTER (engine/precompute-lookahead @ eba34a0c): worst 61.4 ms, rms 42.1 ms

Observations:
- The pump has NOT reduced the flam in this capture; worst-case is higher and there
  are more detected onsets (110 vs 75), consistent with more temporal spreading.
- The AFTER deviations are BIMODAL — two tight bands at ~+35 ms and ~-58 ms rather
  than random jitter. That ~93 ms span is suspiciously close to the 100 ms look-ahead
  lead and looks systematic (worth investigating as a possible two-population
  stamping artifact), not generic scheduling noise.
- Caveat: single capture, unseeded generation, under nav load — run-to-run variance
  is real; needs repeat + a no-nav control before a firm conclusion.

---

## RESOLVED — 2026-07-02, commit `320e443c`

Root cause confirmed (independently reproduced the same run, same bimodal
bands): NOT a stamping artifact — a clock-domain skew. TickClock wake
deadlines are `systemUptime`-anchored; the musical origin is the
render-derived host time, ~11-14 ms apart. The pump horizon had a 1 µs
epsilon, so every lead-phased wake measured the next step as (lead + skew)
away, missed it, and dispatched it one wake later — ~14 ms PAST due. Every
steady-state trigger clamped to immediate (`timing-probe`: 272 immediate vs
4 scheduled), and coincident voices split across render-quantum boundaries
(the constant 12.0 ms same-step pairs). The two "bands" are that population
structure plus render_8bar's first-onset grid anchor and ±62.5 ms wrap —
worst/rms from render_8bar.py are unreliable; see
`docs/plans/engine-timing-recovery-evidence/2026-07-02-lookahead-clock-skew/flam_analysis.py`
for the mode-anchored analysis.

Fix: 25 ms clock-skew slack on the dispatch horizon only (stamps unchanged),
`AudioMasterClock.lookAheadClockSkewSlackSeconds`, regression test
`test_liveLookAheadPump_toleratesOriginVsWakeClockSkew`.

Post-fix rig run (same kit, same 40-switch nav load): 0 immediate / 138
scheduled; 73/74 onsets within ±0.65 ms of the grid (rms 0.34 ms); no
same-step pair > 5 ms. Remaining outlier: step-0 cold hit at +34.6 ms
(first-play latency item, tracked separately). Full evidence:
`docs/plans/engine-timing-recovery-evidence/2026-07-02-lookahead-clock-skew/`.
