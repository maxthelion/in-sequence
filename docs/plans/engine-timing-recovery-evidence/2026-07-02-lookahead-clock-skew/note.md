# 2026-07-02 — look-ahead clock-skew flam: found and fixed by the earless rig

Evidence for commit `320e443c` (fix) and the capture-rig run that found it.

## How it was found

Ran the committed capture rig (`capture_8bar.sh` + `render_8bar.py`, commit
`7cd06dba`) against the branch after the July hygiene pass — first rig run
since the July-1 recovery commits. `render_8bar.py`'s naive first-onset grid
anchor is misleading (it anchors to the masterRender start transient); the
robust re-analysis (`flam_analysis.py` here — mode-anchored grid, residual
clustering, per-step pair detection) showed:

- residual smear −8.5..+15.5 ms (rms 5.6 ms) instead of a tight grid;
- a **constant 12.0 ms same-step pair on every beat** (one render quantum,
  512 frames @ 44.1 kHz) — coincident voices split across quantum boundaries;
- sample files ruled out: all StarterSamples attacks ≤ 4 ms into the file;
- timing probe: **272 `mode=immediate` vs 4 `mode=scheduled`** — the Phase-3
  "zero immediate under load" gate was red at runtime while every offline
  rail was green.

## Root cause

TickClock wake deadlines are `systemUptime`-anchored; the musical origin is
the render-derived host time. Same mach timebase, different anchors —
measured ~11–14 ms apart. The pump horizon (`due <= pumpMusical + lead`) had
a 1 µs epsilon, so each lead-phased wake measured the next step as
(lead + skew) away, missed it, and dispatched it one wake later — ~14 ms past
due → `effectivePlaybackTime` clamped every steady-state trigger to
immediate. Deterministic tests never caught it because they synthesize wake
times and origin from the same base; the skew only exists across real clock
domains.

## Fix

`AudioMasterClock.lookAheadClockSkewSlackSeconds = 0.025` added to the
dispatch horizon only (`EngineController.livePumpShouldProcessStep`). Event
stamps remain the true musical due time. Regression test:
`EngineControllerSampleTriggerTests.test_liveLookAheadPump_toleratesOriginVsWakeClockSkew`
(reproduces the measured 14 ms skew; red without the slack).

## Post-fix rig run (same 808 kit + 40 workspace switches under playback)

- `before-fix.png` / `after-fix.png` — render_8bar output for both runs.
- 73/74 onsets within **±0.65 ms** of the 16th grid, **rms 0.34 ms**
  (Gate-1 stretch target was < 1 ms; locked target < 5 ms).
- **No same-step pair > 5 ms** — the 12 ms quantum flams are gone.
- Timing probe: **0 immediate / 138 scheduled**.
- Onset count 109 → 74: coincident voices now land sample-identical and
  merge into single transients.
- One remaining outlier: **+34.6 ms at t≈0.51 s** — the step-0 knife-edge
  cold hit (dispatched immediately at transport start by design). This is the
  first-play latency item; measure against the ≤10 ms first-play gate.

WAVs (6.7 MB each, not committed): app container
`tmp/drum-timing/8bar-20260702.wav` (before), `8bar-postfix.wav` (after).

## Operational gotchas discovered running the rig

1. **Mic TCC at launch blocks the whole app** since the July-1
   warm-graph-at-session-init change: session init starts the graph, the
   graph pulls the input side, and a rebuilt (re-signed) binary re-triggers
   the microphone prompt — the app shows no window until it is answered.
   Unattended rig runs stall (capture script's 30 s patience expires).
   Follow-up: defer input-node arming until an audio-input feature is
   actually used, so sample-only sessions never touch mic TCC (also a
   fresh-install UX issue: mic prompt at first document open with no user
   intent).
2. `capture_8bar.sh` ends with `kill -9`; a stray instance keeps watching
   `cmd.env` and can steal the next run's commands — kill leftovers first.
3. `render_8bar.py`'s deviation panel anchors to the first detected onset
   (often the render-start transient) — use `flam_analysis.py` for verdicts.
