Mic permission prompt blocks unattended QA capture (warm-up triggers it before the simulate-input override is set)

Found while running a fresh QA surface capture on 2026-06-19. With no operator
present, the capture harness hung on every attempt; a process sample showed the
main thread blocked in AVAudioEngine IO-unit creation
(`-[AVAudioEngine mainMixerNode] -> GetOutputNode -> GetIOUnit ->
AudioComponentInstanceNew -> CoreAudio HALC -> mach_msg`). The actual cause was a
modal "SequencerAI would like to access the microphone" dialog sitting
unanswered — it blocks audio-engine init until dismissed. (It was NOT a wedged
coreaudiod, though that was a red herring during diagnosis.)

Why the existing mitigation didn't help:
`MainAudioGraph.simulateAudioInputConnectionForTesting` (and
`liveAudioInputAuthorizedOverrideForTesting`) are designed exactly to keep
unattended runs from touching the live input node / mic. BUT they are set by
`VisualScenarioCommandRunner` only AFTER launch (Sources/UI/VisualScenarioCommandRunner.swift:112),
whereas the app's WARM-UP path (`AudioInstrumentChoiceCache.beginWarmingIfNeeded`
-> AU instantiation -> AVAudioEngine output IO unit) runs at app launch, before
the runner — and the default IO unit carries an input scope, so macOS throws the
mic prompt at IO time. The override is too late.

Repro:
1. Ensure mic is not yet authorized for the current build signature (a rebuild
   re-prompts even if status reports authorized — code signature changed).
2. Run scripts/visual-scenarios/qa-surface-coverage.sh with no one at the screen.
3. App hangs in warm-up; ensure_document_window times out; no captures.

Impact: unattended / cron QA capture runs can hang indefinitely on a fresh build.

Proposed fix (engine side):
- Set the simulate-input / auth override BEFORE any audio init when launched in
  visual-automation mode — e.g. read SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION (or a
  dedicated env var) at app start and set
  MainAudioGraph.simulateAudioInputConnectionForTesting /
  liveAudioInputAuthorizedOverrideForTesting in the AppDelegate before
  beginWarmingIfNeeded, OR
- gate the warm-up AU instantiation so it does not create an input-scoped IO unit
  in automation mode, OR
- ensure warm-up uses an output-only / manual-rendering engine that never
  triggers the input authorization.

Acceptance:
- A fresh-build, unauthorized-mic, no-operator run of qa-surface-coverage.sh
  completes without any mic dialog and without hanging.
