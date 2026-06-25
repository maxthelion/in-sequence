# Audio Graph — make it watertight (no patches, complete the shape)

**Status:** In progress — Max is away until this is worked through. Do NOT ask
him to verify until the GATE below is green (task #51).
**Origin:** Adversarial review (2026-06-25) of the audio-routing-cleanup branch
vs our own artifacts (architecture-guardrails Audio Engine Hard Rules, the
fixed-superset routing plan, the timing plan, the legacy-shape intent).

## Verdict from the review
Anti-bounce milestone reached (no whole-engine stop/start on routing/insert
changes) — but NOT the ideal shape (~20% delivered, all partials). Do not patch
an unfinished system; complete it and make it watertight.

## Findings (recorded as bugs; each has a task)
1. **Deadlock class (regression-by-exposure)** — control paths hold
   `SamplePlaybackEngine.lifecycleLock` across a live `AVAudioEngine` reconnect;
   the tick path needs the same lock every tick → starves → hang. Our removal of
   the stop-first brackets made the hold unbounded (engine live). Root fix, not
   patch: don't hold lifecycleLock across engine mutations; snapshot tick reads.
   Bugs: `docs/bugs/20260625-170500-mixer-mute-deadlock-hang`,
   `docs/bugs/20260625-add-track-effect-deadlock-hang`. Task #47.
2. **No ramps → clicks** — live disconnect/reassign hard-cuts sounding nodes;
   the plan's "ramp to silence before disconnect, equal-power gain ramps" is
   unimplemented. Bug: `…routing-hard-disconnect-clicks`. Task #48.
3. **Mute is the wrong shape** — track mute = trigger-gate, not gain;
   inconsistent with bus mute (gain); perform-layer mute shares the gate. Bug:
   `…track-mute-trigger-gate-not-gain`. Task #49.
4. **Enforcement non-functional** — realtime-path-lint exempts MainAudioGraph
   from graph-mutation checks and omits engine.stop/start. Bug:
   `…realtime-lint-misses-routing`. Task #50.
5. **Add-AU-FX crash** still diagnosed-not-fixed (needs AU = human present).
   `docs/bugs/20260624-170000-add-track-fx-graphlock-reentry-crash`.
6. Untouched: R3 (drum-part pool), R4 (A/A+B/B), P0–P3 (timing). Out of scope
   for "stable graph edits" but part of the full ideal shape.

## Why we kept hitting these blind: self-testing was missing
The command channel could not drive mute / add-fx / route, so the hangs were
only reachable by Max clicking. Fix that FIRST so I root them out myself:
- **Task #45** — command keys for mute, add/remove track + bus + master insert,
  route-to-bus, A/A+B/B sends, scene switch.
- **Task #46** — hang observability: watchdog every driven command (pid +
  status freshness + ping); on stall auto-`sample` and log the blocked stacks.
Then a driven combinatorial harness over graph edits with crash/hang/click/
silence detection (rebuild of the reverted routing-stress idea, but able to hit
the real operations).

## Order of work
1. #45 command vocab + #46 hang observability (enablers — so I can self-test).
2. #47 deadlock root-fix → re-run harness, confirm mute/route/insert don't hang.
3. #48 ramps → confirm no clicks (offline amplitude continuity).
4. #49 mute-as-gain (unified mixer + layer).
5. #50 lint/enforcement so regressions can't recur.
6. (then, separately) R3/R4/P0–P3 toward the full shape.

## GATE before Max verifies (task #51)
The driven harness exercises transport/mute/add-fx/route/scene/send
combinatorially with hang observability and reports **0 crash / 0 hang / 0
detectable click / 0 unexpected silence** across the matrix. Only then notify
Max for the real-audio (AU/permission) verification.

## Testing-permission tiers (recap)
Unattended: sample/native sources only (no AU prompt). AU effects + audio-input:
only with Max present. (memory: audio-test-permission-modes.)
