# READY for your verification — audio routing + sample-accurate timing

**Status (2026-06-26):** The entire autonomous audio backlog is **built, committed,
and machine-verified** on branch `audio-routing-cleanup`. What remains is the work
that genuinely needs a human: real-audio listening with AU instruments / audio
input / external MIDI hardware (a headless agent can't grant the TCC/"lower
permissions" modal, instantiate a real AU, or hear a flam), plus one product
decision. Everything sample/slice-based + structural is gated by the offline
0-frame test, the routing-stress rig, the lints, and the adherence observers.

## What landed (commits, newest first)
- `cd29a770` #41 — 4 semantic adherence observers (clock / AU-note / sample-memory / graph-mutation)
- `7e44af1a` P3 — MIDI-out on the unified clock + per-port offset plumbing
- `7d2e6b5d` P1 — AU notes via `scheduleMIDIEventBlock` (the AU-vs-slice flam fix)
- `a4f2d0be` #39 — realtime-path-lint enforces unified-clock (Rule 1) + resident-buffer (Rule 4)
- `52fd56c1` P2b — triggered playback reads resident buffers, never streams from disk
- `cdbbb909` P0 — one audio-derived master clock + musical-position stamping
- `5990e7d7` #40 — offline frame-accuracy + no-stop/no-reconnect test harness
- `7d8aecf6` #57 — fix intermittent route-to-master / drum-part-add voice-loss silence
- `a36dce5a` R4 — per-track scene-send selector A / A+B / B (engine+model+rig; UI deferred)
- `e6c38ceb` R3 — drum-part add/remove watertight via the live path + ramp-before-detach removal
- (plus R0–R2, the deadlock/ramp/mute fixes, and the gate-honesty work from earlier)

## Please verify with real audio (the human tier)
1. **AU instruments — zero-flam (P1).** Put an AU instrument track and a slice/sample
   track on the SAME step and listen: they should sound together, no flam. Machine-
   verified that the AU note-on stamp equals the slice's frame *under the captured-
   origin model*; the unverifiable bit is whether a real AU honors that absolute
   render frame (output-node vs AU internal render-clock base equality). Also check
   audible gate length. Known limit: same-pitch overlap on channel 0 can have a
   note-off cut a retrigger.
2. **Routing with AU + audio-input (R3/R4/#57).** During playback: mute/unmute,
   add/remove FX, route track↔bus, switch A/A+B/B sends, add/remove drum parts,
   route-to-master — on AU and audio-input tracks (the rig only covers sample/native).
   Listen for clicks, dropouts, or a track going silent. (The sample path is rig-green.)
3. **External MIDI hardware (P3).** External gear should play on the shared timeline.
   The per-port output offset is **plumbed but defaults to 0 and has no UI yet** — if
   gear is early/late, that's the calibration knob to wire to a setting and tune
   (`MidiOut.setOutputOffsetSeconds` / the `outputOffsetSeconds` param).
4. **R4 selector UI (deferred).** The A/A+B/B engine+model+rig are done; the segmented
   Picker UI was deliberately deferred to land on the `feature/routing-source-mixer-split`
   tab rework (adding it to the current tab would force a merge conflict). Exact
   remaining UI step is in `docs/plans/2026-06-24-fixed-superset-routing.md` (R4).

## One product decision (blocks nothing)
`docs/human-attention/DECISION-au-group-member-mute.md` — muting one member of a
shared-host `.inheritGroup` AU group: group-level mute vs per-member gate vs per-
member gain stage. Pick when convenient; the rest doesn't depend on it.

## Known open items (filed, not regressions from this work)
- `docs/bugs/20260626-route-switch-teardown-hard-cut/` — the bus↔master *route-switch*
  teardown still hard-cuts (removal is fixed; a watertight route-switch crossfade is
  backlog — a naïve defer regressed route-to-master, so it needs a real crossfade).

## Heads-up: test host CoreAudio is degraded
After this long session of repeated real-HAL rig runs + offline-render tests, a
**full `xcodebuild test` shows ~70 CoreAudio `HALC_ShellObject` meter/master-render
failures** — environmental, not from this work (stash-confirmed on baseline; the
focused audio suites + the routing-stress rig all pass). **Restart `coreaudiod`
(or reboot) before trusting a full-suite run** (see memory: in-sequence build/test
gotchas).
