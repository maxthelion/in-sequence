# Macro Coordinator Verification

Date: 2026-04-20

## Commands

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project /Users/maxwilliams/dev/sequencer-ai/SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS,arch=arm64' test -only-testing:SequencerAITests/EngineControllerMuteTests -only-testing:SequencerAITests/MacroCoordinatorTests -only-testing:SequencerAITests/EngineControllerTests -only-testing:SequencerAITests/TrackFanOutTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project /Users/maxwilliams/dev/sequencer-ai/SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS,arch=arm64' test
rg -n "func processTick|private func dispatchTick|private func prepareTick" /Users/maxwilliams/dev/sequencer-ai/Sources/Engine/EngineController.swift
rg -n "eventQueue" /Users/maxwilliams/dev/sequencer-ai/Sources/Engine
rg -n "MacroCoordinator" /Users/maxwilliams/dev/sequencer-ai/Sources/Engine
./scripts/open-latest-build.sh
```

## Results

- Focused engine slice passed: 24 tests executed, 1 skip, 0 failures.
- Full suite passed: 209 tests executed, 3 skips, 0 failures.
- `EngineController.processTick` is the expected dispatch/prepare seam.
- `eventQueue` usage remains confined to `EngineController`.
- `MacroCoordinator` is declared once and used once from `EngineController`.
- App launch smoke passed via `./scripts/open-latest-build.sh`.

## Note on mute smoke

Direct interactive GUI smoke for toggling phrase mute cells was not possible from this session. Instead, the new `EngineControllerMuteTests` case covers the same walking-skeleton requirement end-to-end:

- mute cell resolves `true`
- direct AU dispatch is suppressed
- routed MIDI output is suppressed
- an unmuted peer track still plays
