# Next Action

Generated: 2026-04-18T12:03:24Z
Repo HEAD: bf78e41
Branch:    main

## Action: verify-tests

Tests have not been verified at `bf78e419aa321a4626361e77f264ef291df801d9`.
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' test`
On pass, update `.claude/state/last-tests-sha` with the HEAD SHA.
On fail, the next setup pass will route to `fix-tests` with the failing output.

---

_Invoke `/next-action` to execute. The skill reads this file and dispatches the appropriate subagent._
