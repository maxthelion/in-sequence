# Architecture verdict — 2026-06-12

Synthesis of the three audits (concurrency, mixer-latency, abstraction
layers), one live-sampled deadlock (send-bus Add FX), and the BPM
slowdown Max observed on the tracks page. Question asked: "Is there
anything fundamentally wrong with the current architecture? Do we know
the right shape, but we're not applying it consistently?"

## Verdict

The shape is right and it is known — it is written down in
wiki/pages/playback-data-path.md and engine-architecture.md, and most
of the system follows it. No rewrite is warranted. The failures cluster
in two systemic inconsistencies and one missing enforcement layer:

### 1. The realtime path waits on the main thread (the deadlock and
the BPM-slowdown mechanism — same root)

The documented rule is that the tick path owns playback timing. In
practice the tick path sync-hops to main in several places
(SamplerFilterNode.setDrive, AudioInstrumentHost note-on/off,
syncAudioInputRouting, audioInputCaptureFormat — see concurrency audit
D1–D3). Two consequences, both observed live:

- If main is BUSY, ticks are LATE → audible tempo sag. That is the
  tracks-page BPM slowdown: that page observes tick-rate state in
  heavy view bodies, so playback load inflates main-thread load, and
  the tick queue then queues behind it. Switching to the mixer tore
  down the expensive observation → main freed → tempo recovered.
- If main is BLOCKED (lock held, dialog, re-entrant install), ticks
  stop or deadlock entirely — the sampled hang.

Rule to enforce: **nothing on the tick/audio path may synchronously
wait on main, ever.** Main is a consumer of engine state, never a
dependency of it. (Wave 1 converts the known hops; the contract needs
assertions, below.)

### 2. Invalidation scope is not budgeted (the laggy slider, the heavy
tracks page)

State published at gesture/tick/meter rate flows into broad
invalidation: full snapshot publishes per drag tick, whole-project
phrase-buffer recompiles, whole-strip re-renders at meter rate, large
page bodies observing the playhead. Each instance is small; the
product is UI cost proportional to playback activity — and via (1),
playback timing proportional to UI cost. A closed feedback loop
between the two things that must be independent.

Rule: high-frequency state goes through narrow, dedicated publishers
(the meter-bank/display-state pattern is the house-approved example);
gesture-rate writes go to the live path with no snapshot side effects.

### 3. The contracts are conventions, not mechanisms (why it keeps
coming back)

Lock order, queue ownership, no-sync-hop, publish-outside-locks — all
real rules, all in prose, none enforced. Three confirmed deadlock
classes were "fixed" before and each recurred in new code within days,
because nothing fails fast when a rule is broken.

Enforcement plan (overnight work):
- Debug-only assertions in the hop/lock helpers: "may not hold
  stateLock/graphLock when sync-dispatching", "must be on tick queue",
  "may not mutate @Observable here" (wave 1 starts this).
- A Thread Sanitizer test lane (separate scheme; nightly, not gate).
- Churn stress tests: start/stop × record-arm × preset-open × view
  switches in tight loops — the deadlocks found this week are all
  reachable by such loops.
- The combinatorial render harness (separate brief): builds songs
  programmatically, renders the master, asserts onsets stay on the
  beat grid and output is deterministic; scales track count to chart
  degradation instead of discovering it by feel.

## What is NOT wrong

- Document vs live-path split: correct and mostly respected (the one
  inversion — engine writing the document in capture-save — is queued
  as wave 2 F8).
- Tick state ownership, ring buffers, seqlock pattern, atomic
  transport mirror: sound (one writer-tear hole queued in wave 1).
- The tap→publisher metering shape: sound; just deduplicated to one
  pump (wave 1).
- The theme/component layer post flat-UI: consistent.
- Abstraction audit's 14 findings are consistency debt of the
  known-good shape (two write paths to clip data being the riskiest),
  not evidence of a wrong shape. Consolidation order is in that
  report; wave 2 takes the top three.

## Sequence

Wave 1 (in flight): deadlocks, races, latency causes, meter pump.
Wave 2: tick-path no-main-wait sweep w/ assertions; step-grid write
unification (F1–F3); capture-save inversion (F8); dead code.
Wave 3 (nightly lane): TSan + churn stress + combinatorial render
harness as a standing regression net.
