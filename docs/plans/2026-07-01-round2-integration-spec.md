# Round-2 spec: real P2/P3 integration (informed by round-1 hollowness)

Read alongside `2026-06-30-precompute-lookahead-recording.md` (spec) and
`2026-06-30-FLEET-BRIEF.md` (contract). Round-1 built scaffolding but its own
prosecution proved P2/P3 were NOT integrated. This round makes them real. All
HARD RULES from the brief still apply — work only on `engine/precompute-lookahead`
in the drum-timing worktree, never touch main.

## What round-1 actually shipped (verified — do not re-trust the round-1 commits)
- **P0 event recording:** types + late wiring into prepareTick. Roughly landed.
- **P1 warm-engine + render-derived origin + in-flight-tick stop-guard:** landed;
  this is the real first-play-silence groundwork. Keep it.
- **P2 precompute — HOLLOW.** `prepareTick` still calls
  `BarPrecomputeEvaluator.resolveStep(` synchronously per step
  (`EngineController.swift:2288`); that seam constructs a fresh
  `SystemRandomNumberGenerator()` and runs the generator inline
  (`BarPrecompute.swift:214`). Generation never moved off the tick thread; it was
  renamed. The comment at `EngineController.swift:2280` claiming otherwise is false.
- **P3 look-ahead — WRONG MECHANISM.** The flam "fix" shifts the master-clock
  origin by a fixed ~100 ms rather than dispatching early. Net effect: ~100 ms of
  absolute first-play latency, which DEFEATS the ≤10 ms first-play gate. The real
  lead surface `leadStampedAudioTime` is dead in production.
- **No acoustic evidence at all** (`flamWorstMs: -1`): capture rig needs an
  attended/unlocked session + python numpy/matplotlib. Deterministic gates only.

## Frozen gates (authored by the gate-owner, NOT the builder — do not weaken)
1. `OfflineFrameAccuracyTests` — 0-frame (already green; must stay green).
2. **`realtime-path-lint` Rule 2 (NEW, currently RED)** — forbids
   `BarPrecomputeEvaluator.resolveStep(` / `SystemRandomNumberGenerator(` on the
   tick-path files. Make it green by having `prepareTick` CONSUME a precomputed
   bar produced off-thread — NOT by adding a `realtime-allow` annotation. An
   annotation that does not genuinely run off the realtime path is a HARD-RULE
   violation and will be treated as reward-hacking.
3. `runtime-ownership-lint` — must stay green.

## Round-2 objectives (each needs a NEW deterministic rail authored first, RED)
### P2 — generation genuinely off the tick path
- **Design:** a background scheduler precomputes the next bar's realized notes
  (per track) into a buffer, published to the tick path via the existing snapshot
  lock-swap. `prepareTick` reads from that buffer and does zero generation.
  Inline fallback to today's path only if the buffer is not ready at the boundary
  (log/annotate it; it must not be the steady state).
- **Rail (author RED, adversarial-audit informed):** a deterministic integration
  test that drives ticks through `EngineController` and asserts (a) the realized
  notes for a bar equal the precomputed buffer, and (b) a test seam counting live
  per-step generator evaluations during a tick reads **0**. Adversarial audit: the
  KNOWN-hollow implementation (synchronous `resolveStep` in prepareTick) MUST make
  this rail RED. Plus Rule 2 lint green.

### P3 — real early dispatch, not an origin delay
- **Design:** stamp events with the 100 ms lead and hand them to the schedulers
  EARLY (ahead of the dispatch wake) so `effectivePlaybackTime` never sees a
  past-due `when`; `leadStampedAudioTime` must be the live path. Do NOT globally
  delay the master-clock origin.
- **Rail (author RED, adversarial-audit informed):** a deterministic test on the
  offline harness asserting first-play absolute latency ≤ **10 ms** (catches the
  ~100 ms origin-delay), and that `leadStampedAudioTime` is invoked on the live
  dispatch path with the configured lead. Adversarial audit: the KNOWN-hollow
  implementation (fixed origin-shift; lead-less `leadStampedAudioTime`) MUST make
  this rail RED.

## Anti-hollowness rules for this round (from round-1's failure modes)
- A rail that stays green when the fix is reverted to the known-hollow form is
  ceremonial — the rail author must demonstrate the revert goes RED before freezing.
- Builders may not edit rails or the Rule 2 lint, and may not satisfy Rule 2 with
  an annotation. Prove `railsDiffEmpty` before committing.
- Prosecutors: your round-1 counterparts were right. Re-check that P2 generation is
  genuinely off-thread (not renamed) and P3 is early-dispatch (not origin-delay).
- Acoustic verification (capture rig) stays a Gate-2 attended task; do not fabricate
  a flam number.
