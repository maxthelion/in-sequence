# READY TO VERIFY: audio-graph watertight pass

Branch `audio-routing-cleanup`. Self-tested headless to the gate: every
graph-edit-during-playback op is **0 hang / 0 crash / 0 silence / 0 click**
(scripts/visual-scenarios/routing-stress.sh, real-HAL headless), build green,
lint exit 0 (now enforces Rule 5), audio test suites 53/53.

## Fixed + verified (all committed, nothing on main)
- **Deadlock class** (mute / add-effect hangs) — lifecycleLock is now a leaf
  lock (never held across an engine mutation) + a DEBUG guard. (4f41158e)
- **2nd-insert render-recursion** — send-bus legs wired once, not per reconnect.
  (5f2e77d2)
- **Route-to-master silence** — re-establishes master voices on bus teardown.
  (eccc0ab8)
- **Mute = ramped gain**, unified mixer + perform-layer; MIDI keeps gate.
  (b4701881)
- **No clicks** — ramp-to-silence before any live disconnect/reassign. (12703e41)
- **Enforcement** — lint fails on engine.stop/start in routing paths. + a
  headless self-test rig (command channel: transport/mute/add-fx/route/sends/
  scenes + hang/click observability).

## Your real-audio pass (needs your ears / AU permission)
Launch the AU fixture? No — for routing checks use the SAMPLE-ONLY fixture
(sounds instantly, no prompts):
`SEQUENCER_AI_NEW_DOCUMENT_FIXTURE=<container>/audio-rich-routing-sampleonly.seqai SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1 <app exe>` — or just run the app and play.

1. With audio playing, do each: **mute a track** (should be instant + a ringing
   voice cuts/returns, not "next note"), **change a track's output bus**,
   **add/remove a native filter/bitcrusher insert** (incl. a 2nd insert),
   **drag sends**, **switch scenes**, **add/remove a track**. Confirm by ear:
   no hang, no gap, **no click**.
2. **Ramp feel:** clicks are gated headless but the *feel* is yours — 12ms is the
   default; tell me if any edit still ticks and I'll tune it.
3. **AU effect insert** (the one that needs the permission modal): add a real
   AU *effect* to a track — was a separate graph-lock crash
   (docs/bugs/20260624-170000). Check whether the lock + cycle fixes resolved it
   or it still crashes; that's the one item the rig can't cover.
4. If 1–3 pass → merge `audio-routing-cleanup` to `main`.

## Still open (separate, not blocking this pass)
- R3 (drum-part pool), R4 (A/A+B/B selector), P0–P3 (sample-accurate timing) —
  the broader ideal-shape items, untouched.
