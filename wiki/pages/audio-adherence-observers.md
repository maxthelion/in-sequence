---
title: "Audio Adherence Observers"
category: "process"
tags: [process, observers, audio, guardrails, realtime, conformity, review]
summary: Four semantic (LLM-judged) observers that complement the deterministic realtime lints for the Audio Engine Hard Rules — they catch INDIRECT violations a grep cannot see, and emit file:line evidence for the OODA loop. They write evidence only; they do not fix or route.
last-modified-by: claude
---

## Purpose

The Audio Engine Hard Rules (see [[architecture-guardrails]] → *Audio Engine
Hard Rules*) are enforced in three layers:

| Layer | Mechanism | What it catches |
|---|---|---|
| Deterministic | `scripts/diagnostics/realtime-path-lint.sh`, `runtime-ownership-lint.sh` | the **literal** banned API token on a known path |
| Behavioural | offline frame-accuracy test (0-frame assertion) | a frame mismatch at runtime |
| **Semantic** | **the four adherence observers (this page)** | the **same violation reached INDIRECTLY**, or a required protective shape that is **missing** |

The lints are exact but literal: they grep a fixed file list for a fixed token
set. They cannot see a new path that re-derives time from a wall clock *through a
helper*, a routing edit that stops the engine *through a helper*, a sample
feature that streams from disk *"just this once"*, or a `disconnect` that simply
*forgot* the silence ramp. That is what these semantic observers judge — INTENT
against the rules.

They follow the [[observer-sweep]] model: **observers write evidence; a reviewer
(person or Claude) synthesises and schedules.** Observers **do not fix and do not
route work** — a violation is evidence for the OODA loop (AGENTS.md → *Loop
Model*), never an auto-fix.

## Where they live + how they are wired

- **Definitions:** `.claude/workflows/audio-adherence-observers.js` — same module
  shape and invocation as `.claude/workflows/observer-sweep.js` (a re-runnable
  workflow spec: `export const meta`, schema constants, one `agent()` call per
  observer, a `sweep()` parallel fan-out). The `agent` / `phase` / `parallel`
  globals are provided by the harness that runs the workflow; there is no in-repo
  JS runtime (observer-sweep is run the same way).
- **Registry:** `meta.observers` in that file lists the four; `meta.triggers`
  lists when to run them (audio-touching diff + periodic sweep).
- **Each observer** = a prompt (flag-criteria + sanctioned exceptions + the Hard
  Rule it maps to + the file scope) plus the shared `OBSERVER_SCHEMA`
  (verdict `PASS`/`FLAG`; per-finding `location` file:line, `finding`,
  `rule_breached`, `why_not_an_exception`; plus `notes`).

## When to run

Run on **any change that touches tick / scheduling / sample / slicer /
audio-graph code**, and on a **periodic sweep**. On a diff, invoke only the
observer(s) whose scope the diff hits; the sweep runs all four.

## How to run

These are LLM-judged observers; they are driven by the orchestrator/agent
harness (like observer-sweep), not a CLI binary. Two shapes:

- **Single observer:** point an agent at the relevant section of
  `audio-adherence-observers.js` (the `agent()` call) with `scope` narrowed to the
  changed file(s); it returns one `OBSERVER_SCHEMA` result (PASS or a FLAG list).
- **Periodic sweep:** run `sweep()` — all four in parallel over their full scope.

Pair them with the deterministic gate first (cheap, exact), then the observers
(semantic, indirect cases):

```sh
scripts/diagnostics/realtime-path-lint.sh
scripts/diagnostics/runtime-ownership-lint.sh
```

(Run each on its own line — no compound shell commands.)

## The four observers

### 1. `audio-clock-conformity` — Hard Rule 1 (+ Rule 2)

**Flags** musical/sounding time derived from a wall clock instead of the unified
`AudioMasterClock`: any `systemUptime` / `Date` / `DispatchTime.now` /
`DispatchSourceTimer` deadline whose value flows into an event's sounding time,
**including indirectly** (a stored seconds value later turned into an
`AVAudioTime`; a helper returning "now"; a new path recomputing a deadline
instead of asking `AudioMasterClock`). Also confirms every scheduled event is
stamped with a **future** `sampleTime`/`AUEventSampleTime`/`MIDITimeStamp`, not
fired "now". Evidence names *which* clock the value came from.

**Sanctioned (not flagged):** `AudioMasterClock` is THE one site that may touch
host time for musical timing (render-origin capture/upgrade, provisional origin
fallback, the final `AVAudioTime(hostTime:)` stamp — origin from the render
clock, offset from the tempo map). `TickClock`'s timer is **pump pacing** only.
The control-path note-off **flush** (`flushDetachedMIDINoteOffs`) is an allowed
wall-clock exception. Diagnostics (`SequencerTimingProbe`, `DevActivity`) and
`*OverrideForTesting`/offline seams are not the live path.

### 2. `au-note-path-conformity` — Hard Rule 3

**Flags** on the AU note/tick path: any `DispatchQueue.main` hop / `MainActor.run`
/ `Task { @MainActor }` carrying a per-note trigger (**including** a helper like
the old `performOnMainAsync` wrapping `startNote`); any bare `startNote`/`stopNote`
that sounds/releases a note; any wall-clock note-off (`asyncAfter(.now()+len)`).
Confirms note-on AND note-off both go through `scheduleMIDIEventBlock` with an
`AUEventSampleTime`.

**Sanctioned (not flagged):** the all-notes-off **panic** `stopNote` on the
control path (`realtime-allow-control-stopnote`); main hops for AU **graph
setup / preset** work (`realtime-allow-main-*`); a deliberate note **drop** when
an AU exposes no `scheduleMIDIEventBlock` (correct degradation, not a fallback
main hop). P1 (`7d2e6b5d`) removed the debt hop + added a leaf `auMutationLock`.

### 3. `sample-memory-conformity` — Hard Rule 4

**Flags** any `scheduleSegment(file:)` / `AVAudioFile(forReading:)` /
`cachedFile(url:)` reachable from a slice / one-shot / drum-hit / note-repeat
**trigger**, **including indirectly** (a default-argument fallback that streams
when no resident buffer is set; a new preview/audition/reverse/envelope branch
that opens a file; lazy first-trigger load instead of warm-first). The classic
regression: a forward, no-envelope slice falling through to
`scheduleSegment(file:)` instead of `scheduleBuffer`. Confirms triggered playback
plays a resident `AVAudioPCMBuffer` via `scheduleBuffer` and un-warmed slices are
warmed before firing.

**Sanctioned (not flagged):** exactly the explicitly-annotated bounded large-loop
/ no-resident-buffer streaming fallback (`realtime-allow-file-stream`, e.g.
recorded audio-input loops). The observer **verifies the annotation's claim** —
if a normal triggered slice can reach the annotated stream site, the claim is
false and it IS a finding. P2b (`52fd56c1`) made resident `scheduleBuffer` the
default.

### 4. `graph-mutation-conformity` — Hard Rule 5

**Flags** any `engine.stop()`/`start()` tied to a **topology** change during
playback (**including** a routing/insert/send/scene helper that bounces the
engine to re-wire — lifecycle start/stop is not topology); any
`attach`/`detach`/`connect`/`disconnect`/`reconnect` topology change during
playback not expressed as a gain ramp / bypass toggle on the fixed graph; and
**the key semantic check the lint cannot do** — a `disconnect`/`detach` of a
(possibly) **sounding** node that is **not first ramped to silence** (must be
wrapped by `withTrackGainRampedToSilence`: ramp the gain stage to 0 via
`MixerGainRamp`, splice on down-ramp completion on a fresh main hop, ramp back).
A hard-disconnect of a sounding node is a finding even though the literal
`disconnect` token is "owned" by `MainAudioGraph`.

**Sanctioned (not flagged):** `engine.stop()/start()` at the annotated lifecycle
sites (`routing-lint-allow:` — transport, HAL renegotiation full-rebuild,
master-chain setup); synchronous disconnect on an engine-stopped / already-muted
track (verify the gating proves silence); structural add/remove that ramps to
silence before disconnect (ramp-before-disconnect / fast-path-ready gating).
Shared with the fixed-superset routing plan.

## Validation (proven discriminating, not vacuously passing)

These observers are LLM-judged and need the agent harness to execute, so they
were **not** auto-run here. Each was made precise + self-contained and
**hand-traced against one real past violation and the current fixed shape**, so
it is proven to FLAG the bad shape and PASS the good one. The past-violation
commits are real repo history; the line numbers were read from those commits.

| Observer | Past violation (FLAG) | Current clean (PASS) |
|---|---|---|
| `audio-clock-conformity` | pre-P0 `TickClock.swift` (`cdbbb909^`): tick carries `ProcessInfo.processInfo.systemUptime` (`:48,61,112`) on a `DispatchSourceTimer`, converted straight to the audio stamp in `EngineController.scheduledAudioTime` — sounding time is wall-clock. **Expect FLAG: Rule 1, systemUptime → sounding stamp, not pump-pacing.** | current `AudioMasterClock.swift`: host time touched ONLY for the render-origin anchor + final `AVAudioTime(hostTime:)`, offset from the tempo map; `TickClock`'s timer annotated `pump-pacing`; flush annotated. **Expect PASS (these are the named exceptions).** |
| `au-note-path-conformity` | pre-P1 `AudioInstrumentHost.swift` (`7d2e6b5d^`): `performOnMainAsync { instrument.startNote(...) }` (`:445-446`) + wall-clock note-off `queue.asyncAfter(deadline: .now()+noteLength) { … stopNote }` (`:449-455`). **Expect FLAG: Rule 3, main-hop startNote + wall-clock note-off on the note path.** | current `AudioInstrumentHost.swift`: note-on/off via `scheduleMIDIEventBlock` (`:542+`); the only `stopNote` is the annotated control-path panic (`:657-658`, `realtime-allow-control-stopnote`). **Expect PASS (panic is the named exception).** |
| `sample-memory-conformity` | pre-P2b `SamplePlaybackEngine.swift` (`52fd56c1^`): forward, no-envelope slice falls to `scheduleSegment(file:)` (`:696`) via `cachedFile(url:)` → `AVAudioFile(forReading:)` (`:556,1352`) — streams from disk on the trigger path. **Expect FLAG: Rule 4, forward-slice default streams from disk.** | current `SamplePlaybackEngine.swift`: forward slice schedules a resident buffer via `scheduleBuffer` (`:824`); the single `scheduleSegment` is the annotated bounded large-loop fallback (`:831-832`, `realtime-allow-file-stream`, guarded so warmed assets never reach it). **Expect PASS (only the named large-loop exception).** |
| `graph-mutation-conformity` | pre-`12703e41` live bus-reassign (R1) / insert add-remove (R2): hard-`disconnect` of the sounding source/fanout node with no silence ramp → click. **Expect FLAG: Rule 5, sounding node disconnected without ramp-to-silence.** | current `MainAudioGraph.swift`: live disconnects (e.g. `:944`) run inside the ramp-to-silence guard `withTrackGainRampedToSilence(source:work:)` (`:1845`; ramp to 0, splice on down-ramp completion, ramp back); `engine.stop()/start()` only at annotated lifecycle sites (`:542-567,1127-1128`, `routing-lint-allow:`). **Expect PASS (ramp-before-disconnect + lifecycle exceptions).** |

To **execute** a validation (when the harness is available): run the observer
with `scope` = the past commit's file (e.g. `git show 7d2e6b5d^:…` content) and
expect a FLAG at the cited line; then run it on the current file and expect PASS.

## Honest limits — what these can and cannot catch

- **Can** catch the indirect/intent cases the lints miss: a wall clock reached
  through a helper or stored value, an engine bounce inside a routing helper, a
  disk stream behind a new feature branch, a forgotten silence ramp.
- **Cannot** be a hard CI gate on their own: they are LLM-judged, so they are
  probabilistic and need the agent harness to run (no in-repo runtime). Treat
  them as evidence producers, not blockers. The deterministic lints + the
  offline frame-accuracy test remain the gating layer.
- They reason over **source shape**, not runtime: "is this node actually sounding
  at disconnect?" is judged from the code's gating, not measured. The
  `routing-stress.sh` rig + a human real-audio pass remain the runtime check.
- A finding is **evidence for the OODA loop**, not an auto-fix — synthesis and
  scheduling happen downstream.

See [[architecture-guardrails]], [[observer-sweep]], and
[`docs/plans/2026-06-24-sample-accurate-timing.md`](/Users/maxwilliams/dev/in-sequence/docs/plans/2026-06-24-sample-accurate-timing.md)
(→ *Adherence observers*).
