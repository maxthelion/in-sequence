# Project instructions

**Read `AGENTS.md` (repo root) before starting work, and follow it.** It is the
canonical agent handoff: project overview, automation / loop model, the Visual
Capture Map + running-app command channel, Runtime Diagnostics, the Audio Engine
Hard Rules, and the Bug Reports & Status conventions (including how the bug-reporter
app resolves branches/worktrees). When in doubt about where something lives or how
to run it, AGENTS.md is the first place to look.

## Evidence goes where the bug-reporter app can see it

For fresh database-backed bug intake and capture links, use the local CLI:

```sh
bug-reporter help
bug-reporter list-bugs --project in-sequence --status open
bug-reporter list-bugs --project in-sequence --status open --json
bug-reporter show-bug BUG_ID
bug-reporter fetch-capture RUN_ID ROW_ID --project in-sequence --out /tmp/capture.png
```

The JSON listing includes `captureRefs` (`runId`, `rowId`, branch, commit, image
hash, and attachment path). Use that before guessing which gallery screenshot a
new bug refers to. `scripts/bug-status.sh` is still the markdown status counter
for `docs/bugs`; current intake triage usually needs both views.

Do not conflate the two sinks (see AGENTS.md → "Where evidence goes"):
- **Bug reports** go in the PRIMARY checkout
  `/Users/maxwilliams/dev/in-sequence/docs/bugs/<YYYYMMDD-HHMMSS-slug>/` — a literal
  path, so a report written in a *worktree's* `docs/bugs` is invisible to the app. An
  audio/waveform render is bug-report evidence and belongs here.
- **Screenshots** (what "captures" usually means) are a two-step flow: record raw
  PNGs to the temp capture inbox, then let bug-reporter upload/file them for the
  gallery:

  ```sh
  PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
    scripts/visual-scenarios/qa-surface-coverage.sh

  bug-reporter absorb-captures "$TMPDIR/in-sequence-captures/qa-$USER" \
    --project in-sequence \
    --source qa-surface-coverage
  ```

  Peekaboo-backed capture scripts take a shared macOS `lockf` mutex at
  `$TMPDIR/in-sequence-visual-capture.lock` before driving the app. Concurrent
  agents wait up to `SEQUENCER_AI_VISUAL_CAPTURE_LOCK_TIMEOUT_SECONDS` (default
  900s); use `SEQUENCER_AI_DISABLE_VISUAL_CAPTURE_LOCK=1` only for intentional
  debugging.

Do not manually copy standard QA captures into `.meta/multipass/visual-review/`
or run the legacy R2 sync helper for the gallery path. The app is sandboxed, so
the timing rig writes its WAV under
`~/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/...`.
