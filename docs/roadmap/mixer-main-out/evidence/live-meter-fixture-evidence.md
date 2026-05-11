# Mixer Main Out Live Meter Fixture Evidence

Date: 2026-05-11

## Fixture

- Fixture document:
  `docs/roadmap/mixer-main-out/fixtures/mixer-main-out-live-meter.seqai`
- Loader:
  `SEQUENCER_AI_NEW_DOCUMENT_FIXTURE` points new visual-review documents at the
  fixture while leaving normal app launches unchanged.
- Scenario:
  `scripts/visual-scenarios/mixer-main-out.sh`

The fixture creates one sample-backed track named `Live Meter Kick` with a
single active step using the starter `kick/kick-01.wav` sample. The sampler gain
is intentionally high so transport playback should move the production Master
Out meter and latch `CLIP` when the fader is raised.

## Capture Attempts

Latest failed production capture:

- `.claude/state/visual-review/20260511T150728Z-live-meter-fixture/`
- Captured: `scenario-mixer-main-out-normal.png`
- Notes: `scenario-mixer-main-out-capture-notes.md`
- Blocked before: `scenario-mixer-main-out-live-meter.png`,
  `scenario-mixer-main-out-fader-high.png`,
  `scenario-mixer-main-out-fader-low.png`,
  `scenario-mixer-main-out-restored.png`,
  `scenario-mixer-main-out-clipped-cleared.png`

The app terminates immediately after transport start with:

```text
player started when in a disconnected state
```

The stack points to `AVAudioPlayerNode.play()` inside
`SamplePlaybackEngine.play(...)`, dispatched from `EngineController.dispatchTick`.
This is a production sample-trigger playback blocker, not a fixture decode
problem: the normal capture shows the fixture-loaded sample track, and focused
fixture decode tests pass.

## Next Evidence Step

Fix the production sample-trigger graph crash, then rerun:

```bash
PEEKABOO_OUTPUT_DIR=.claude/state/visual-review/<timestamp>-live-meter-fixture \
  ./scripts/visual-scenarios/mixer-main-out.sh
```

The expected successful folder should contain normal, live-meter, fader-high,
clipped, fader-low, restored, and clipped-cleared states before UX/IA review.
