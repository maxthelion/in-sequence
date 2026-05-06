---
status: reviewed
verdict: pass
reviewed: 2026-05-06T20:20:00+01:00
source_pass: docs/roadmap/agentic-loop/passes/prepare-production-cherry-pick-candidates.md
reviewed_output: docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md
scheduled_follow_up: docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md
---

# Testing Review

## Verdict

Pass for planning. The candidate synthesis separates focused model/test seeds
from probe UI, which is the right test posture before production changes.

No app test run was required for this review because no Swift production code
was changed. The next build-plan pass must define the tests that make the P0
overlay safe to port.

## Evidence Checked

- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js`
- `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`
- `3a1d15d:Tests/SequencerAITests/Engine/TrackPerformanceOverrideLayerTests.swift`
- `a9bdbc4:Tests/SequencerAITests/Diagnostics/ObservabilityProbeModelsTests.swift`
- `99834b3:Tests/SequencerAITests/UI/AudioInputLoopingAutosliceProbeModelTests.swift`
- `6991918:Tests/SequencerAITests/UI/MixerRoutingProbeModelTests.swift`
- `Tests/SequencerAITests/Document/ProjectSetPatternClipIDTests.swift`
- `Tests/SequencerAITests/Engine/PlaybackSnapshotBuffersOnlyTests.swift`
- `Tests/SequencerAITests/Audio/MainAudioGraphTests.swift`

## What Passed

- The P0 performance seed has useful low-level tests and should be ported with
  its tests first, before UI integration.
- The synthesis correctly treats audio and mixer probe tests as learning, not
  production acceptance. They validate UI-local reducer behavior, not real PCM
  capture, audio graph routing, or document persistence.
- The observability tests are plausible developer-tooling seeds because they
  cover fingerprint normalization, redaction, route recommendation, and
  observed-versus-introduced wording.
- The holistic workbench fixture already tested Keep/Discard labels and owner
  transitions, so the production test plan can inherit those semantics without
  asking the user to re-review raw screenshots.

## Caught

The current candidate list names minimum tests, but the P0 integration needs a
stronger production test contract:

- pure layer tests ported unchanged where still valid;
- a test that applying an override leaves `Project` equal until Keep;
- a test that Keep writes the intended phrase cell values and clears the
  overlay;
- a test that Discard clears the overlay and restores authored playback;
- playback-resolution tests showing fill and step-order precedence at the
  snapshot/engine boundary;
- a deferred or explicit limitation test for note-repeat intervals requiring
  sub-step scheduling.

## Scheduled

The next pass should produce a build plan with the above test matrix. It should
not schedule broad `xcodeproj` churn or any probe UI tests as production gates.
