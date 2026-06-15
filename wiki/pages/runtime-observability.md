---
title: "Runtime Observability"
category: "observability"
tags: [observability, logging, debugging, audio, samples, playback]
summary: Runtime debugging layers for SequencerAI, from user/session breadcrumbs through opt-in playback probes to future audio capture.
last-modified-by: codex
---

## Purpose

Runtime observability should help answer specific debugging questions without
changing playback behaviour. SequencerAI has a real-time audio path, so
diagnostics must be chosen by cost:

- user/session breadcrumbs for reconstructing broad interaction paths;
- opt-in playback event probes for questions such as "was this hi-hat sample
  dispatched?";
- future audio capture for questions about the actual rendered signal, timing,
  lag, or clipping.

Do not use one logging mechanism for all three. A trace that is suitable for a
button click may be too expensive or too noisy for every played step.

## Existing Activity Log

`DevActivity` writes debug-build breadcrumbs to macOS unified logging under:

```text
subsystem == "ai.sequencer.SequencerAI.activity"
```

It is useful for app/session/audio-graph breadcrumbs, for example:

- transport start/stop;
- device changes;
- recording persistence;
- visual harness commands;
- broad audio-graph lifecycle events.

The activity log compiles away in release builds. It should stay sparse enough
that post-mortem `log show` output remains readable.

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

Enable it with:

```sh
defaults write ai.sequencer.SequencerAI SampleTriggerTraceEnabled -bool YES
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
