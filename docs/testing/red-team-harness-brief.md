# Red-team harness — dispatchable brief

Goal (Max, 2026-06-12): "try to trip it up" — adversarial robustness,
not security. Find the crashes/hangs/desyncs that polite tests and
happy-path QA never hit. This complements the existing nets: the gate
proves intended behavior, TSan proves memory discipline, stress proves
known deadlock shapes, render harness proves timing — the red team
probes the UNKNOWN space with randomness plus invariants.

## Design: seeded chaos + invariants + replayable artifacts

### 1. Chaos driver (UI level)
Build on `VisualScenarioCommandRunner` (it already drives real UI:
workspace switches, fixtures, transport, layer selection, phrase
controls). Add a `chaos` mode: given a SEED, emit a random-but-
reproducible command stream (hundreds of steps) mixing:
- workspace flips mid-playback; rapid mode toggles (edit/perform)
- transport churn (play/stop/BPM extremes 20..999 if the UI allows)
- record-arm/cancel storms on audio-input tracks (simulated input)
- add/delete tracks, busses, FX inserts while playing
- step-grid edit storms (taps, drags, multi-select cycles)
- undo/redo bursts interleaved with live edits
- window resize to min/max between steps (layout robustness)
After EVERY step assert the invariants (below). On failure: save the
seed, step index, screenshot, and the activity-log tail as a bundle
under docs/audits/red-team/<date>-seed<N>/ — the seed makes every
finding replayable.

### 2. Property fuzzing (engine level, headless)
Extend RenderScenario with a seeded random generator: random track
counts/types/patterns/phrase structures/param-change scripts →
render offline → assert the EXISTING harness invariants (on-grid
onsets, deterministic re-render, no dropouts). Random songs catch what
the 9 hand-written scenarios can't. Failing seeds become permanent
regression scenarios.

### 3. Hostile-input corpus (document level)
Decode/apply edge documents: empty project, 0-length/1-step clips,
max-everything (tracks/phrases/sends), absurd BPM, dangling IDs
(deleted-track references, missing step-order maps — the forgiving-
decode paths), duplicate IDs, truncated/corrupt JSON. Assert: no trap,
graceful degradation, save→load round-trips.

## Invariants (the trip-wires — all already exist)
- DEBUG traps: TickPathMainSyncGuard, lock re-entry/hold assertions
- App alive and main thread responsive (watchdog ping < 1s)
- Tick health: loaded median within the isolation-test budget
- Engine/document coherence: selected IDs resolve; runtime registries
  contain no orphans after deletes
- No unbounded growth: topology-install and reconnect counters stay
  proportional to topology changes, not to time
- Activity log contains no "dropped/failed" traces outside scenarios
  that intend them

## Lanes
- 2-3 short seeded chaos smokes in the default gate (fixed seeds, ~10s)
- Long randomized runs env-gated (TEST_RUNNER_SEQUENCERAI_REDTEAM=1),
  candidate for the heartbeat lens roster once stable
- Every found bug: file in docs/bugs with the replay bundle, fix via
  normal slices, keep the seed as a regression test

## Dispatch notes
Standard worktree/disk/Info.plist/commit rules apply (see
.foreman/HANDOFF.md). Sized as 2-3 slices: chaos driver first (most
new signal per token), then property fuzzing (small — extends the
harness), corpus last.
