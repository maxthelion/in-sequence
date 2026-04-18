# 🟡 Important — `pre-git-push.sh` truncates xcodebuild output to the last 5 lines, hiding actual failure information

**File:** `.claude/hooks/pre-git-push.sh:20-25`

## What's wrong

```bash
if ! DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI \
    -destination 'platform=macOS' test 2>&1 | tail -5 >&2; then
  echo "❌ pre-git-push hook: xcodebuild test FAILED — push blocked" >&2
  exit 1
fi
```

The `tail -5` takes only the last 5 lines of xcodebuild output. A real test failure produces hundreds of lines, with the XCTest failure lines typically somewhere in the middle:

```
Test Case '-[SequencerAITests.MIDIClientTests test_…]' started.
… MIDIClientTests.swift:42: error: … XCTAssertEqual failed: …   <-- the useful line
Test Case '-[SequencerAITests.MIDIClientTests test_…]' failed (0.01 seconds).

** TEST FAILED **
The following test failures were detected:
        SequencerAITests.MIDIClientTests.test_…
Testing failed:
        ...
error: Test session failed.
```

`tail -5` catches the `** TEST FAILED **` summary but not the actual assertion text, the file:line, or which test failed. The agent / user reading the hook output has to re-run xcodebuild manually to see the failure. Doubles the cost of every failed push.

Also: `set -o pipefail` plus `| tail -5 >&2` means `tail` must succeed for the pipeline to succeed — verified OK. But the `tail -5 >&2` also implicitly discards xcodebuild's stdout if tail fails. Unlikely but worth a comment if kept.

## What would be right

- **Keep full output on failure; truncate on success.** Save xcodebuild output to a file, then on failure print or path the file to the user; on success print only the last line.
  ```bash
  LOG="$(mktemp /tmp/seqai-test-XXXX.log)"
  if DEVELOPER_DIR=... xcodebuild ... test > "$LOG" 2>&1; then
    tail -1 "$LOG" >&2
    rm -f "$LOG"
  else
    echo "❌ push blocked; test log at $LOG" >&2
    tail -50 "$LOG" >&2
    exit 1
  fi
  ```
- Or, minimally, `tail -50` or `tail -100` — enough to include the assertion line in a typical failure.

## Why it matters

This hook is the critical quality gate before code leaves the machine. When it fails, the user needs to act. An action report that hides the information needed to act breaks the feedback loop — the user reaches for `xcodebuild test` manually, wasting the 2 minutes the hook just spent. Iterated over many pushes, this fatigue leads to bypass (`--no-verify`).
