---
title: "Runtime Observability"
category: "observability"
tags: [observability, logging, debugging, audio, samples, playback]
summary: Runtime debugging layers for SequencerAI, from user/session breadcrumbs through opt-in playback probes to future audio capture.
last-modified-by: codex
---

## Purpose

Runtime observability should help answer specific debugging questions without
changing playback behaviour. There are **two distinct concepts here — keep them
separate, do not muddle them**:

### Concept 1 — Activity log (reproduce *what happened*)

"What steps did the user take, and what did the app decide?" — a breadcrumb trail
to **reproduce a problem**: view/workspace switches, transport start/stop, device
changes, recording persistence, a preset being selected, broad audio-graph
lifecycle. This is about the **sequence of actions and decisions**, not timing
accuracy. It is low-rate (one entry per user action / lifecycle event) and is the
first thing to reach for when a bug report is "I did X and then Y broke."

### Concept 2 — Timing probe (is audio firing *at the correct time*?)

"Did this note / sample fire on the intended sample frame, or is it late / the
wrong length?" — sample-accurate **correctness** evidence: tick-clock expected vs
actual, event-dispatch lateness, note-on/note-off sample stamps + gate length,
sample/slice schedule frames, voice selection. This is higher-rate and exists to
answer timing/lateness/stuck-note questions, NOT to reconstruct user steps.

A third, future layer — **audio capture** — extends Concept 2 to the rendered
signal itself (lag, clipping, drift); see "Future Audio Capture" below.

**Do not use one mechanism for both concepts.** A breadcrumb suitable for a button
click is the wrong tool for per-step note timing, and a per-note timing probe is
far too noisy to read as a "what did I do" trail. When adding a trace, first
decide which concept it serves, then use the matching mechanism in the table
below.

## Existing Activity Log

All three trace families below write to macOS unified logging under ONE subsystem:

```text
subsystem == "ai.sequencer.SequencerAI.activity"
```

They compile away in release builds (`#if DEBUG`). There are **three distinct
Swift types** — do not confuse them (a common mistake is calling
`DevActivity.activity(...)`, which does not exist). Map each to a concept above:

| Type | Concept | What it is | Gated by a flag? | Category |
|------|---------|------------|------------------|----------|
| `DevActivity` | **1 — Activity** | Holds the `Logger`s + the unconditional `trace(logger:_)` breadcrumb helper (transport, device, recording, harness, graph lifecycle) | **No** — fires in any DEBUG build | engine / clock / audio-graph / harness / session / library |
| `SequencerTimingProbe` | mixed (see wart) | `activity` / `viewSwitch` serve **Concept 1**; `tickClock` / `processTick` / `eventDispatch` / `sampleSchedule` / `sliceSchedule` / `voiceSelected` serve **Concept 2** | **Yes** — `TimingProbeEnabled` | timing-probe |
| `SampleTriggerTrace` | **2 — Timing** | Opt-in sample dispatch/schedule/drop probes ("was this hi-hat dispatched, and was it late?") | **Yes** — `SampleTriggerTraceEnabled` | sample-trigger |

**Known wart (do not muddle further):** `SequencerTimingProbe` currently carries
BOTH concept-1 action breadcrumbs (`activity`, `viewSwitch`) and concept-2 timing
probes under the SAME flag/category. When you add a probe, pick the method that
matches its concept; if you need a concept-1 breadcrumb prefer `DevActivity.trace`
(unconditional), and reserve `timing-probe` for genuine timing/lateness data. A
future cleanup should split these into separate types/categories.

To add a new gated probe, add a method to the matching enum (e.g. a timing probe
goes on `SequencerTimingProbe`), **not** to `DevActivity`.

Keep all of these sparse enough that post-mortem `log show` output stays readable
— never add an unconditional trace on the per-render or per-step tick path.

## Reading the activity log — gotchas

These bite every time; if `log show` returns nothing, it is almost always one of
these, NOT "the app isn't logging":

1. **`log show` needs `--info` (and `--debug` for debug-level).** Every trace here
   logs at `.info` level (`logger.info(...)`), and `log show` **excludes info/debug
   by default**, returning a silent empty result. Always pass `--info`:
   ```sh
   log show --last 10m --info --predicate 'subsystem == "ai.sequencer.SequencerAI.activity"'
   ```
   `log stream` does NOT need the flag (it includes info/debug live).
2. **The app is SANDBOXED — `defaults write ai.sequencer.SequencerAI …` does NOT
   reach it.** A sandboxed app reads `UserDefaults.standard` from its **container**,
   not the global `~/Library/Preferences`. Writing the bare bundle-id domain
   (as older docs/commands show) lands in the global domain the app never reads, so
   the flag silently has no effect. Write to the **container plist** instead:
   ```sh
   defaults write \
     "$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/Library/Preferences/ai.sequencer.SequencerAI" \
     TimingProbeEnabled -bool YES
   ```
   (same for `SampleTriggerTraceEnabled`). Then relaunch — `open` is fine for the
   defaults path.
3. **`open` does not forward `SEQUENCERAI_*` env vars to the app.** `ENV=1 open Foo.app`
   sets the var on `open`, not the app. The env enable path therefore works ONLY
   when you exec the binary directly (which also bypasses the sandbox-defaults
   issue above):
   ```sh
   SEQUENCERAI_TIMING_PROBE=1 ".../Build/Products/Debug/SequencerAI.app/Contents/MacOS/SequencerAI"
   ```
   Either enable path is read **once at startup**, so a **relaunch is required**
   after changing it.
4. **When in doubt, `log stream` beats `log show`.** `log stream --info --debug
   --predicate '…' > /tmp/x.log &` captures live (no level-flag surprises, no
   time-window skew); reproduce, then read the file.
5. **Do not use `NSLog`/`print` for diagnostics.** They are not reliably captured
   by `log show` in this app (sandbox + level filtering), so a probe written with
   `NSLog` looks like "nothing is logging." Route every probe through
   `DevActivity` / `SequencerTimingProbe` / `SampleTriggerTrace` (os.Logger).
6. **Filter by category to cut noise**, e.g. add
   `AND category == "timing-probe"` (or `"sample-trigger"`) to the predicate.

## Sample Trigger Trace

When debugging drum-kit or sample-routing problems, use the opt-in
`sample-trigger` category rather than adding unconditional logs to the tick path.

The first probe records the dispatch boundary in `EngineController`: after the
track destination has resolved and the sample file has been found, but before
`SamplePlaybackEngine` schedules playback. That answers whether a sample-backed
track produced a trigger and whether the engine could resolve its sample.

The same flag also records the playback scheduling boundary in
`SamplePlaybackEngine`, including the difference between the requested host time
and the moment the main-queue scheduling work actually runs. Positive `late`
values mean the scheduler is behind the intended playback time. Large positive
values during UI interaction point to main-thread scheduling latency rather than
missing sequencer events.

Enable it with (container path — see the sandbox gotcha above; the bare
`defaults write ai.sequencer.SequencerAI …` form does NOT reach the sandboxed app):

```sh
defaults write \
  "$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/Library/Preferences/ai.sequencer.SequencerAI" \
  SampleTriggerTraceEnabled -bool YES
```

Then restart the app and watch:

```sh
log stream --style compact \
  --predicate 'subsystem == "ai.sequencer.SequencerAI.activity" AND category == "sample-trigger"'
```

For a bounded post-mortem view:

```sh
log show --last 5m --style compact \
  --predicate 'subsystem == "ai.sequencer.SequencerAI.activity" AND category == "sample-trigger"'
```

Disable it with:

```sh
defaults delete ai.sequencer.SequencerAI SampleTriggerTraceEnabled
```

The same trace can also be enabled for direct executable launches with:

```sh
SEQUENCERAI_SAMPLE_TRIGGER_TRACE=1
```

## Interpreting Sample Trace Output

For the missing hi-hat class of bugs:

- `sample dispatch ... file=...hat...` means the sequencer and sample lookup got
  as far as the playback engine; investigate voice scheduling, gain, mute,
  routing, or mix output.
- `sample drop ... reason=missing-sample` means the step produced a trigger, but
  the sample library could not find the referenced sample ID.
- `sample drop ... reason=unresolved-file` means the sample record exists, but
  its file reference could not resolve on disk.
- `sample schedule ... late=... mode=scheduled` shows a future host time was
  preserved for sample-accurate playback.
- `sample schedule ... late=... mode=immediate` means playback degraded to
  immediate scheduling. This is expected for nil times and stale host times; it
  avoids asking `AVAudioPlayerNode` to schedule a short sample in the past.
- no hi-hat dispatch/drop while kick/snare dispatches appear means the problem
  is upstream: pattern contents, track mute/layer resolution, drum group
  inheritance, or generator output.

## Timing Probe POC

For UI-induced lag investigations, the debug build also has an opt-in
`timing-probe` category. It records a shared monotonic timestamp for:

- view switches and setup/perform mode changes;
- tick-clock expected vs actual fire time;
- `processTick` duration and drained event count;
- audio event dispatch lateness;
- sample schedules with normalized start/length;
- slice schedules with start/end frames, choke, reverse, and voice mode;
- sample-engine voice selection, including whether mono scheduling stops the
  prior voice.

Enable it with (container path — see the sandbox gotcha above; the bare
`defaults write ai.sequencer.SequencerAI …` form does NOT reach the sandboxed app):

```sh
defaults write \
  "$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/Library/Preferences/ai.sequencer.SequencerAI" \
  TimingProbeEnabled -bool YES
```

Then restart the app, press Play, reproduce the lag, and collect a bounded
report:

```sh
scripts/diagnostics/timing-probe-report.sh 10
```

Set `TIMING_PROBE_LATE_MS` to change the report threshold:

```sh
TIMING_PROBE_LATE_MS=5 scripts/diagnostics/timing-probe-report.sh 10
```

Disable it with:

```sh
defaults delete ai.sequencer.SequencerAI TimingProbeEnabled
```

## Future Audio Capture

Some bugs cannot be answered from events alone. UI interaction causing audio lag,
clipping, missing mix output, or timing drift needs signal-level evidence.

The preferred future shape is an explicitly enabled rolling master-output
capture, probably a short ring such as the latest 60 seconds. It should be:

- off by default;
- written outside project documents;
- bounded in disk use;
- clearly marked as diagnostic data;
- separated from the real-time render path enough that it does not create the
  timing problem being measured.

Event traces and audio capture should complement each other. Event traces answer
"did the app intend to play this?"; audio capture answers "what actually came
out?".

## Relation To Log-To-Issue Observability

The roadmap observability feature is a higher-level pipeline for turning runtime
evidence into deduplicated issue candidates. Its durable contract should be a
typed diagnostic envelope, not arbitrary string scraping.

The sample trigger trace is lower-level and temporary by design. It may become an
input to that pipeline later, but it should not force every playback event into
durable issue storage.
