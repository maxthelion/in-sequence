# Plan: Off-thread bar precompute + look-ahead scheduling + event recording

**Status:** Proposed — 2026-06-30
**Builds on:** `docs/plans/2026-06-24-sample-accurate-timing.md` (P0–P3 landed; this picks up the look-ahead pump that plan explicitly deferred, line 98).

## Goal

1. Move generative note production **off the realtime tick path** and precompute the
   next bar on a background task.
2. Give the scheduler a **real look-ahead window** so events are stamped with lead
   time, never at the knife-edge of `when ≤ now` — eliminating the measured
   ~47 ms snare/clap **flam**.
3. **Record the realized event stream** for reproducible playback/capture (record,
   do NOT reseed RNG — reproducibility is a recording, not a re-derivation).

## Background (verified by the 2026-06-30 engine pass)

- Sample-accurate stamping (P0–P3) shipped and is gated by the offline
  frame-accuracy test. But the **look-ahead pump was deferred** (prior plan, line
  98): step N is stamped for ≈ the timer wake that dispatches it. The only safety
  net is the stale→immediate clamp (`SamplePlaybackEngine.effectivePlaybackTime:1810`,
  commit `635cbb3e`), which re-reads `now` per event in the FIFO dispatch loop —
  so same-step triggers split into "scheduled" vs "immediate," and the immediate
  ones gain a render-quantum of latency. That is the flam.
- Generation (euclidean/Markov/chance + a fresh `SystemRandomNumberGenerator()`
  per track per tick, `EngineController:2023`) runs **live per step in
  `prepareTick`** — off the compiled snapshot, on the realtime prepare path.
- `prepareTick` already double-pumps (prepares tick N and N+1) and
  `SequencerSnapshotCompiler` already compiles off-thread. **This is an extension
  of that horizon, not a new architecture.**

## Non-goals / scope boundaries

- **Seeded-RNG reproducibility — explicitly rejected.** Reproducibility comes from
  Phase 0 (recording), not from re-deriving a stream from a seed.
- Voice-allocation redesign, plugin delay compensation — out (per prior plan).
- The broader AU first-play hardening is tracked as bug `20260630-143852`. Phase 1
  here (warm engine) is the shared prerequisite for look-ahead and fixes the
  first-play silence as a side effect; further AU-specific lifecycle work stays in
  that bug.

## Gate-1 decisions — LOCKED 2026-06-30 (these ARE the spec; the fleet optimizes them)

Owner delegated the thresholds; defaults below are locked for this run. Adjust on
return and re-gate if any is wrong.
- **Flam tolerance:** worst-case onset deviation from the 16th grid `< 5 ms` under
  nav load (capture-rig metric, `render_8bar.py` "worst"). Stretch `< 1 ms`.
- **First-play:** first transport run after load must produce AU **and** drum audio
  audible within `10 ms` of the grid — no silent first run.
- **Look-ahead lead:** `100 ms`. Live performance controls still apply at dispatch
  on top, so lead does not hurt responsiveness.
- **Immediate vs bar-quantized:** mute / fill / performance-macros / velocity apply
  immediately (at dispatch); structural generation changes (pattern edits,
  queued-phrase swaps) apply at the next bar boundary.

## Phases (each gated; build the gate before the code)

### Phase 0 — Event recording
- **What:** record the realized note stream as it's produced (track, step, pitch,
  velocity, length, gate, the resolved generative choice) to an in-memory ring +
  optional NDJSON. A replay source feeds the *same* dispatch path from a recording.
- **Why:** the user's reproducibility model; AND it's the deterministic fixture
  substrate for every gate below (a recorded run is a fixed note stream to compare
  timing against).
- **Call sites:** `EngineController.prepareTick` where `GeneratedNote` →
  `noteEvent` (~`:2018-2064`); a recorder sink; a replay source.
- **Executable gate:** record→replay round-trips to a byte-identical event list;
  the headless capture rig can replay a recording deterministically.
- **Risk:** low (additive).

### Phase 1 — Warm engine + valid render origin (prerequisite for look-ahead)
- **What:** keep `AVAudioEngine` running (outputting silence) while a document
  session is active; stop only on shutdown / device change / explicit rebuild.
  Capture the master-clock render origin **only once `lastRenderTime` is valid** —
  do not set `hasOrigin=true` on the provisional `systemUptime` fallback for AU
  stamping.
- **Why:** look-ahead can't stamp future frames without a valid render origin; and
  this closes the cold-start window that causes first-play AU/drum silence.
- **Call sites:** `EngineController.start()/stop()` (`:884`/`:943`),
  `MainAudioGraph.start()/stop()` (`:1212`/`:1223`), `AudioMasterClock.captureOrigin`
  (`:124-138`) + `refreshOriginIfAvailable` (`:247`).
- **Executable gate:** capture-rig assertion — *first* transport run produces AU +
  drum audio within N ms of the grid (first-play-not-silent); no `engine.stop()` on
  transport Stop (lint); offline frame-accuracy still 0-frame; graph-mutation
  adherence observer + `routing-stress.sh` clean.
- **Risk:** medium (lifecycle change).

### Phase 2 — Off-thread next-bar precompute
- **What:** extend the prepare horizon from 1 step to 1 bar (or one phrase-cycle
  chunk) and move generative evaluation to a background queue. Publish the
  precomputed bar's **notes** (tempo-independent) via the existing snapshot
  lock-swap. **Invalidate + regenerate** on any generation-input change (pattern
  edit, queued-phrase swap, generation-affecting macro). Inline fallback to today's
  live path if not ready at the boundary (graceful degradation, no new failure
  mode). Immediate controls (mute/fill/macro/velocity) stay applied at dispatch.
- **Why:** removes generation cost/alloc from the realtime path; produces the
  look-ahead buffer Phase 3 needs.
- **Call sites:** `SequencerSnapshotCompiler` (carry precomputed generated notes),
  `EngineController.prepareTick` (consume precomputed instead of evaluating live),
  `GeneratedSourceEvaluator` (run in the background compile).
- **Executable gate:** realtime-path-lint shows no RNG/alloc on the tick path; a
  recorded run *with* precompute == a recorded run *without* (same notes —
  equivalence); `process-tick durationMs` probe drops materially.
- **Risk:** medium (invalidation correctness — the equivalence test is the gate).

### Phase 3 — Look-ahead scheduling pump (the flam fix)
- **What:** with a warm origin (P1) + a precomputed bar (P2), stamp events with a
  fixed lead (~100 ms) ahead of dispatch and hand them to the sample/AU schedulers
  early, so `effectivePlaybackTime` never sees a past-due `when`. Keep P0's
  musical→frame stamping; add the horizon the prior plan deferred.
- **Why:** eliminates the stale→immediate flam at the source.
- **Call sites:** `EngineController` prepare/dispatch split (`:1873-2394`), the
  dispatch horizon, `scheduledAudioTime`/`scheduledAUNoteSampleTime`,
  `effectivePlaybackTime` (should now rarely/never clamp).
- **Executable gate (headline):** capture-rig flam assertion — in the 808 full-kit
  + nav-load run, snare/clap onsets land **< 5 ms** from kick/hat (was ~47 ms);
  **zero "immediate"-mode triggers** in the timing probe under normal load; offline
  frame-accuracy still 0-frame.
- **Risk:** highest (scheduler re-plumb) → **N-version it** (below).

## Enforcing gates (frozen, executable, builder cannot touch)

Authored and committed BEFORE the corresponding phase's code, then locked:
- Offline frame-accuracy test (0-frame) — existing primary gate.
- `realtime-path-lint` + `runtime-ownership-lint` — Audio Engine Hard Rules.
- The four audio-adherence-observers (semantic).
- **NEW capture-rig assertions** (this session's rig): flam `< 5 ms`,
  first-play-not-silent, zero-immediate-under-load. Built in Phase 0, frozen.
- `routing-stress.sh` — no hang/click/silence regressions.

## Overnight autonomous execution (ADLC)

Per the ADLC series (voodootikigod.com/adlc-1..7): build the workflow around how
**models** fail, not how humans do; every gate traces to a model failure mode.
This task is a **bounded, gated re-plumb with a crisp behavioral metric** (the
measured flam + first-play audibility) — so it maps cleanly onto the 8-phase ADLC
with **exactly two human gates**, NOT the OODA improvement daemon.

### Why this beats reusing the multipass/OODA machinery here
OODA/Foreman is a continuous-*improvement* daemon (right for open-ended grind).
This has a definite "done" (gates green) and a pass/fail success metric. ADLC fits:
author-and-freeze rails → build → prosecute → two human gates → distill, with the
fleet stopping on green. **Crucially we keep the repo's rarest asset — deterministic
audio gates (offline frame-accuracy 0-frame test, realtime/ownership lints, the
adherence observers, and this session's headless capture rig). Those ARE the rails.**
Relief-first adoption (adlc-7): don't stand up a whole framework — layer ADLC
discipline (frozen rails + prosecution + N-version on the one risky phase) onto the
gates that already exist.

### Mapping the engine plan onto the 8 phases
- **P0 Triage** — done: the engine pass established risk × blast-radius (Phase 1
  lifecycle and Phase 3 scheduler are the high-risk, low-rail-density work).
- **P1 Interrogate → HUMAN GATE 1.** This doc is the spec; "every acceptance
  criterion names its verification method" (it does). Gate 1 = you approve the plan
  **and the gate thresholds** (flam `< 5 ms`, first-play window, lead-time value).
- **P2 Decompose** — slice each phase into atomic tickets with explicit contracts;
  cold-start check (a cheap model finds ticket gaps) before railing.
- **P3 Rail** — author the executable gates **from the spec, in contexts that never
  see the implementation**, then **freeze them at the tool layer** (not the prompt):
  the new capture-rig assertions (flam `<5ms`, first-play-not-silent,
  zero-immediate-under-load) + offline-frame-accuracy + lints. Two non-negotiables:
  - **Adversarial pre-freeze audit:** revert the fix to a no-op — the flam gate MUST
    go red. If stubbing the implementation keeps the suite green, the gate is
    ceremonial. (For audio: a mutation that re-introduces the stale→immediate clamp
    must make the flam assertion fail.)
  - **Mechanical freeze:** a pre-tool-use hook / file-hash check fails the build run
    if any rail file changes; merge requires a **rails-diff-empty proof**. Builders
    may write internal unit tests (work product, reviewed) but those never gate them.
- **P4 Build** — fresh agent per ticket against frozen rails, single writer per
  partition, worktree isolation. Phases are a dependency CHAIN (P0→P1→P2→P3), so the
  parallelism is **within** the risky phase: **N-version Phase 3** — 3 independent
  scheduler implementations in parallel worktrees, no shared context (adlc-5: width
  ~3–5 from the build:integration ratio; here serialize the chain, fan out only the
  hard link). Discard-and-retry a flailing builder; don't repair it.
- **P5 Prosecute** — refute charters ("find what's wrong; if nothing, say so"),
  **one lens per fresh context** (correctness / Hard-Rule-conformance / spec-vs-impl
  diff / timing-regression / test-audit), each seeing only diff+spec+rails, never the
  builder's transcript. **Findings are claims: reproduce-or-kill** (a verifier writes
  a failing test or a triggering capture, or the finding dies). **Loop until dry** (2
  consecutive zero-verified passes). And **measure the prosecutor's recall**: plant
  N realistic timing defects (mechanical mutants + LLM-authored subtle ones — e.g. a
  lead-time sign flip, an off-by-one frame stamp, a dropped invalidation) into a copy
  of the diff and confirm the stack catches them; fail if recall < threshold. Recall
  travels in the merge evidence.
- **P6 Integrate → HUMAN GATE 2 (behavioral acceptance).** This is where audio is
  ideal: you **run the demo** — listen to the 808 kit (is the flam gone?) and read
  the before/after capture-rig measurement + the prosecution recall report. "Is this
  what I meant, running?"
- **P7 Distill** — simplify the new code under still-green rails (F7 bloat); **mine**
  recurring findings into permanent defenses: the flam gate becomes a standing CI
  gate, a new "look-ahead / warm-origin conformity" check joins the audio-adherence
  observers or realtime-path-lint, and any spec gap becomes an interrogation question.
  This is what makes the next audio change cheaper (adlc-6 compounding).

### Failure-mode coverage (each gate → the model failure it defends)
F1 premature-satisfaction → executable behavioral gates (the rig measures real
audio). F2 sycophancy → separate prosecutors, refute charter, never self-review.
F3 context-rot → atomic tickets, fresh context per ticket, pass conclusions not
transcripts. F4 hallucination → no claim crosses a boundary without deterministic
proof. F5 reward-hacking → mechanically-frozen rails + rails-diff-empty proof +
adversarial pre-freeze audit + diff-scoped mutation testing. F6 finding-count →
loop-until-dry. F7 bloat → P7 distill. F8 coherence → one pinned model per ticket.
Exploited: E1 N-version Phase 3; E2/E4 refute charter + fresh-context critics;
E3 discard-and-retry.

### Cost dials (adlc-5) for this DAG
- **Cost:** Phase 3 (critical path, low rail density at first) → frontier model
  direct; Phases 0/2 (higher rail density once P3-rails exist) → cheap-first ladder.
- **Wall-clock:** the phase DAG is a chain (hard data deps), so width is spent on
  N-version Phase 3, not across phases. Control flow is code (a deterministic
  workflow), judgment is models — never a model-as-scheduler.
- **Accuracy:** for the genuinely-ambiguous knobs (lead-time ms; which live controls
  must stay immediate), fan 3 cheap agents in fresh contexts; convergence = settled,
  divergence = a measured multiple-choice for Gate 1 rather than a vague question.

### The two human gates (barbell)
- **G1 — tonight, before launch:** approve this plan + the **frozen gate
  thresholds**. The gates are the spec; if a threshold is wrong the fleet optimizes
  the wrong thing. (Optionally also adjudicate the ambiguity-sampled knobs.)
- **G2 — morning:** behavioral acceptance — hear the kit, read the before/after flam
  + recall report, approve the rails-diff-empty merge to `main`.

I can encode the whole thing as one deterministic workflow (rail → N-build → gate →
prosecute-until-dry → select → distill) that runs the fleet overnight, stops on
green, and surfaces only at G1/G2 — **once you sign off the gates (G1).**

## Risks / honest caveats

- Phase 1 (warm engine) changes transport lifecycle — the riskiest steady-state
  change; land it behind the offline test + graph-mutation observer + routing-stress.
- Phase 2 invalidation is the correctness crux; the record→replay equivalence test
  is the load-bearing gate, not prose review.
- Phase 3 look-ahead lead interacts with live performance controls — verify
  mute/fill/macro still feel immediate (applied at dispatch on top of the
  precomputed bar), not bar-quantized.
- A generation input that's *continuously* modulated intra-bar would be sampled
  once at bar start under precompute; audit whether any exists (most macros
  modulate output per-step at dispatch, which is unaffected).
