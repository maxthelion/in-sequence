---
id: 29
title: Mixer Channel Levels Everywhere
status: inventory
priority: unset
blocked_by: []
stage: clarify
owner: pm
updated: 2026-06-11
---

# Mixer Channel Levels Everywhere

Every mixer strip (tracks, sends/returns, user buses) gets a live level
meter using the master bus's existing meter as the template
(MasterMeterPublisher / master tap pattern, generalized per strip).
Diagnostic value is the point: per-channel meters localize a dead link in
the audio graph instantly.

Includes the related cosmetic fix: the transport status summary should
describe an audio-input track's actual monitor routing instead of
claiming "No default output".

Raw intent: `docs/roadmap/intent.md` § 2026-06-11 Mixer Channel Levels.
Related: the master-render-to-file test harness (sequencing correctness
without ears) shares the master-tap substrate.
