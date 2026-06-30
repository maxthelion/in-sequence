# Fleet operating brief — precompute / look-ahead / event-recording

You are one agent in an ADLC pipeline implementing
`docs/plans/2026-06-30-precompute-lookahead-recording.md` (the SPEC). Read it first.
This brief is your contract. Violating a HARD RULE fails your ticket.

## Where you work — HARD RULES
- **Work ONLY in this worktree:** `/Users/maxwilliams/dev/in-sequence/.worktrees/drum-timing`
  on branch `engine/precompute-lookahead`. Use absolute paths.
- **NEVER touch, checkout, merge to, or push `main`.** Never `git push`. Integration
  to `main` is the owner's job at Gate 2 (human review). You only commit to this branch.
- **No compound shell commands** (no `&&`, `;`, or chained pipes) — run each separately.
- Commit your own work when your ticket's gate is green. Trailer, exactly:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01XsyRbX7LZV94hHiwD5KmX2
  ```
- After a build, if `df -h /` shows < 4Gi free, delete the worktree's `DerivedData`
  before continuing.

## Frozen rails — HARD RULE (reward-hacking defense)
Once the Rail phase commits a rail file, it is **frozen**. As a BUILDER you must NOT
edit, weaken, delete, skip (`XCTSkip`/`.skip`), or stub any rail file:
- `Tests/SequencerAITests/Audio/OfflineFrameAccuracyTests.swift`
- any `Tests/.../*LookAhead*`, `*Precompute*`, `*EventRecording*`, `*WarmEngine*` test
- the lint scripts under `scripts/diagnostics/`
- the capture-rig scripts (`capture_8bar.sh`, `render_8bar.py`, etc.)
You MAY add your own internal unit tests (work product, reviewed — not rails). The
integrator verifies a **rails-diff-empty proof**: `git diff` of rail files must be
empty across your build commits.

## Audio Engine Hard Rules (from AGENTS.md — do not violate)
- No allocation, locking, logging, or Swift runtime calls on the realtime render/tick
  path. Generation must move OFF the tick path (that is the point of Phase 2).
- All cross-thread audio state via the established lock-swap / snapshot mechanism.
- Graph mutations only through the existing safe paths (the graph-mutation adherence
  observer + `routing-stress.sh` guard this).
- Sample-accurate stamping (P0–P3, already landed) must stay intact.

## The gates (run these; a ticket is DONE only when its gate is green)
Run from the worktree root. Confirm exact invocation against `AGENTS.md` if one fails.
1. **Build + offline frame-accuracy (PRIMARY rail, deterministic, 0-frame):**
   `xcodebuild test -scheme SequencerAI -destination 'platform=macOS' -only-testing:SequencerAITests/OfflineFrameAccuracyTests`
2. **Full unit suite:** `xcodebuild test -scheme SequencerAI -destination 'platform=macOS'`
3. **Realtime-path lint:** `bash scripts/diagnostics/realtime-path-lint.sh`
4. **Runtime-ownership lint:** `bash scripts/diagnostics/runtime-ownership-lint.sh`
5. **Routing stress (graph-edit safety):** `bash scripts/visual-scenarios/routing-stress.sh`
6. **Behavioral flam capture (Gate-2 evidence; needs the built app + audio device):**
   build the app, then `bash capture_8bar.sh <path-to-built-app-binary> /tmp/flam.wav`,
   then `python3 render_8bar.py /tmp/flam.wav /tmp/flam.png 120 8` — read the `worst=`
   number. Target `< 5 ms` (Gate-1). If a device is unavailable, record that and rely
   on the deterministic look-ahead unit rail instead; do not fake the number.

## ADLC discipline by role
- **Rail author:** write rails from the SPEC only; never read the implementation.
  Before freezing, run the **adversarial audit**: revert the intended fix to a no-op
  and confirm the rail goes RED. A rail that stays green when the feature is absent is
  ceremonial — fix it. Rails must start RED (feature not built yet) and compile.
- **Builder:** implement the smallest change that makes your ticket's frozen rail
  green without touching rails. Build, run gates, commit on green. If you flail (gate
  red after 3 honest attempts), STOP and write a `BLOCKER:` note — do not hack the gate.
- **Prosecutor:** you are charged to REFUTE — find what is wrong; if nothing, say so.
  One lens only (correctness / Hard-Rule-conformance / spec-vs-impl / timing-regression
  / test-audit). See only diff + spec + rails, never the builder's transcript. Every
  finding is a CLAIM: reproduce it (failing test, trace, or capture) or it dies.
- **Integrator:** verify rails-diff-empty + all gates green; never merge to main.

## Reporting
Return raw structured data, not prose for a human. Cite file:line. State gate results
as pass/fail with the actual command output, never "should pass."
