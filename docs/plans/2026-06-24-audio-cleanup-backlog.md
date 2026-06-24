# Audio Cleanup Backlog (master index)

Single entry point for the audio engine cleanup discussed 2026-06-24. Work
happens on branch **`audio-routing-cleanup`** (off `main` @ c36fbab1). Audio code
stays on the branch — it is **not** merged to `main` until a human does the
real-audio verification (build machine cannot), so the branch can move fast
behind build + offline-test gates.

Plans:
- [Fixed-superset routing](2026-06-24-fixed-superset-routing.md) — R0–R4
- [Sample-accurate timing](2026-06-24-sample-accurate-timing.md) — P0–P3
- Invariants: [architecture-guardrails.md → Audio Engine Hard Rules](/Users/maxwilliams/dev/in-sequence/wiki/pages/architecture-guardrails.md)

## Autonomous goal (no user input needed — gated by build + offline tests)

Execution order (each item = code + its test/lint rule, committed together):

1. **R0** persistent per-track send nodes (task #30) — priority; unblocks R4.
2. **R1** no engine stop/start for track output (task #31)
3. **R2** sends/mixer-bus topology without full restart (task #32)
4. **R3** drum-part node pool (task #33)
5. **P0** unified audio clock + lookahead scheduler (task #35)
6. **P1** AU notes via scheduleMIDIEventBlock (task #36)
7. **P2** sample/slice unified clock + resident buffers (task #37)
8. **P3** MIDI out from unified clock (task #38)
9. **R4** A/A+B/B scene-send gain plumbing (task #34) — needs R0; UI build
   autonomous, GUI confirm is a human item.

Cross-cutting (land per-phase, not standalone — each rule would fail until its
code lands):
- **Lint extension** (task #39) — add each banned-pattern rule as its phase
  removes the violation (clock rule with P0, note-path rule with P1, file-trigger
  rule with P2).
- **Offline test harness** (task #40) — frame-accuracy + no-stop/no-reconnect
  assertions; built as the acceptance gate for P0/P1 and R0–R3.
- **Adherence observers** (task #41) — audio-clock / au-note-path /
  sample-memory / graph-mutation conformity; can be built independently as
  review tooling (don't gate CI).

## Needs the user (NOT in the goal — see `docs/human-attention/`)

- Real-audio / GUI bug verifies: send-fx deadlock, slice click-to-map, in-kit
  macro sheet, transient quality (task #42).
- observer-sweep W4.14 audio-input GUI verify → merge `observer-sweep-remediation`;
  `routing-source-mixer-split` rebase + capture gate; stale worktree/branch
  cleanup (task #43).
- Eventually: real-audio verification of the whole audio-routing-cleanup branch
  before it merges to `main`.

## Notes

- Lint/test rules are coupled to their code change (a rule added before its fix
  would fail CI), so they land inside each phase, not up front.
- The A/A+B/B UI home is the routing tab (`routing-source-mixer-split` reworks
  it) — but R4's audio correctness depends only on R0, so the gain plumbing can
  land without that branch.
