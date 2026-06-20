# Resolution

Resolved 2026-06-20 by moving the visual-automation audio-input override to app
startup, before launch-time AU warm-up can touch CoreAudio IO.

Implemented changes:

- `VisualScenarioLaunchOverrides.installIfConfigured()` now installs
  `MainAudioGraph.simulateAudioInputConnectionForTesting = true` and
  `MainAudioGraph.liveAudioInputAuthorizedOverrideForTesting = true` whenever
  the visual command-file protocol is configured.
- `SequencerAIAppDelegate.applicationWillFinishLaunching` calls that helper
  before `AudioInstrumentChoiceCache` warm-up.
- `SequencerAIApp.init` also calls the helper before its fallback instrument and
  effect cache warm-up calls.
- The focused XCTest injects the delegate warm-up closure and asserts both
  overrides are already installed at the exact point warm-up runs.

Evidence:

```sh
xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/SequencerAIAppDelegateTests/test_applicationWillFinishLaunching_installsVisualScenarioAudioOverridesBeforeWarmup
```

Result: passed, 1 test, 0 failures.

Remaining evidence gap: fresh-build unauthorized-mic visual capture was not run
from this unattended actor because `SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION` was
unset. Next manual acceptance in an interactive, pre-authorized session:

```sh
SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1 scripts/visual-scenarios/qa-surface-coverage.sh
```
