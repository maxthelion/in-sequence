# Project instructions

**Read `AGENTS.md` (repo root) before starting work, and follow it.** It is the
canonical agent handoff: project overview, automation / loop model, the Visual
Capture Map + running-app command channel, Runtime Diagnostics, the Audio Engine
Hard Rules, and the Bug Reports & Status conventions (including how the bug-reporter
app resolves branches/worktrees). When in doubt about where something lives or how
to run it, AGENTS.md is the first place to look.

## Evidence goes where the bug-reporter app can see it — never `/tmp`

Do not conflate the two sinks (see AGENTS.md → "Where evidence goes"):
- **Bug reports** go in the PRIMARY checkout
  `/Users/maxwilliams/dev/in-sequence/docs/bugs/<YYYYMMDD-HHMMSS-slug>/` — a literal
  path, so a report written in a *worktree's* `docs/bugs` is invisible to the app. An
  audio/waveform render is bug-report evidence and belongs here.
- **Screenshots** (what "captures" usually means) go in
  `.meta/multipass/visual-review/<branch>/` in the relevant worktree; the gallery
  unions these across all worktrees automatically. Not for audio/waveform renders.

Never leave capture output in `/tmp`. The app is sandboxed, so the timing rig writes
its WAV under `~/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/...`.
