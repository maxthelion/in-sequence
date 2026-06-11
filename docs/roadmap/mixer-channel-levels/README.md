---
id: 29
title: Mixer Channel Levels Everywhere
status: in-progress
priority: unset
blocked_by: []
stage: build
owner: pm
updated: 2026-06-11
---

# Mixer Channel Levels Everywhere

Every mixer strip (tracks, sends/returns, user buses) gets a live level
meter using the master bus's existing meter as the template
(MasterMeterPublisher / master tap pattern, generalized per strip).
Diagnostic value is the point: per-channel meters localize a dead link in
the audio graph instantly.

## Progress (2026-06-11, `feature/mixer-overhaul`)

Core metering landed:

- `Sources/Audio/ChannelMeterBank.swift` — per-strip `MasterMeterPublisher`
  instances keyed by `ChannelMeterID` (.track/.bus/.send), pumped by one
  main-queue timer; redundant displayState writes are skipped so silent
  strips don't re-render at 60Hz.
- `MainAudioGraph` installs channel taps at the master-tap sites (graph
  build time): bus and send-return input mixers, plus track terminal nodes
  registered via `setTrackMeterSources` (sample filter node, AU host
  output mixer — shared hosts meter all their tracks from one tap — and
  audio-input output mixers; the capture tap keeps node ownership while
  armed).
- Mixer UI renders meter lanes inside every fader (`VerticalLevelFader`)
  and a meter-only lane on send returns; dB readouts everywhere.
- Tests: `ChannelMeterBankTests`, `ChannelMeterTapTests`.

Remaining:

- The cosmetic transport-status fix below (not started).
- Visual QA capture of live meters (console was locked during the slice).

Includes the related cosmetic fix: the transport status summary should
describe an audio-input track's actual monitor routing instead of
claiming "No default output".

Raw intent: `docs/roadmap/intent.md` § 2026-06-11 Mixer Channel Levels.
Related: the master-render-to-file test harness (sequencing correctness
without ears) shares the master-tap substrate.
