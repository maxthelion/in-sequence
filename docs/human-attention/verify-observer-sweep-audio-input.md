# Verify: observer-sweep W4.14 audio-input GUI

**Branch:** `observer-sweep-remediation` (tip `dd0e1266`), 15/15 remediation
items complete **except** this verification. This is the **only** thing gating
merging that branch to `main`.

## Why a human
W4.14 is an audio-input GUI behaviour that needs a real interface + window
(live audio-input routing into the graph / scenes). Headless can't drive it.

## How to verify
1. Check out `observer-sweep-remediation`, build, run.
2. Exercise the audio-input GUI path described in
   `docs/observers/2026-06-23/09-scheduled-round.md` (W4.14).
3. PASS → merge `observer-sweep-remediation` to `main`.

## Refs
- `docs/observers/2026-06-23/09-scheduled-round.md` (the wave list)
