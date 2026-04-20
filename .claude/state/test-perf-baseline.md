# Test Performance Baseline

Measured on `main` after the post-cleanup tree (`60fa69b`, `0df85d7`) and after the phrase/live split slice (`557592e`). Host machine: local macOS arm64 developer machine via:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64'
```

## Baseline

| Run | Command | Wall clock | User | Sys | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| Cold | `xcodebuild clean` + full `xcodebuild test` | 18.58s | 1.92s | 1.18s | Includes clean build + codesign + full test host launch |
| Warm incremental | `touch Tests/SequencerAITests/PhraseCellPreviewTests.swift` then full `xcodebuild test` | 8.86s | 1.28s | 0.83s | Recompiled a single touched test file, then reran full suite |
| Warm noop | full `xcodebuild test` with no file changes | 7.96s | 1.19s | 0.90s | Essentially the steady-state loop cost |

## Interpretation

- The plan's Task 1 stop condition is satisfied: **cold < 60s**.
- The full-suite cost on this machine is already low enough that structural optimisation work is not justified.
- Warm runs are dominated by Xcode harness overhead rather than test execution. XCTest reported:
  - `196` tests executed
  - `3` skipped
  - `0` failures
  - test execution time: about `3.6s`
- That leaves roughly `4.3s` of warm-noop wall-clock in build/test-host/codesign/launch overhead, which is small for the overnight loop use case.

## Raw logs

- `.claude/state/perf-raw/baseline-cold.log`
- `.claude/state/perf-raw/baseline-warm-incremental.log`
- `.claude/state/perf-raw/baseline-warm-noop.log`
