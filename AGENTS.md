# Agent Handoff

Read this first when you land in `in-sequence`.

## Project

`in-sequence` is a macOS-native generative DAW/groovebox built with Swift,
SwiftUI, CoreMIDI, and AVAudioEngine.

The product north star is the root [README.md](/Users/maxwilliams/dev/in-sequence/README.md).
The wiki under `wiki/pages/` contains stable project knowledge such as
architecture guardrails, mixer grammar, and domain references. Roadmap feature
artifacts live under `docs/roadmap/`.

## Current Automation

This repo is a Foreman Coordinator client. Meta ticks it through the project shim:

```sh
/Users/maxwilliams/dev/in-sequence/project/scripts/tick.sh --write
```

The shim delegates to the reusable runtime:

```sh
bun /Users/maxwilliams/dev/foreman-coordinator/src/cli/tick.ts \
  --project /Users/maxwilliams/dev/in-sequence --write
```

Do not use the old `.claude/hooks/setup-next-action.sh` or `/next-action`
behaviour-tree path. Do not route new work through the old
`multi-pass-coordinator` binary unless explicitly debugging legacy state. Those
paths competed with the foreman loop and made agents infer the wrong control
model.

## Loop Model

The live coordination shape is OODA:

- **observe**: observers write facts, screenshots, logs, reviews, and other
  evidence. Observers do not route work.
- **orient**: orienters explain what observations mean against the README,
  roadmap intent, active loops, and the product pyramid.
- **decide**: deciders schedule one bounded next action when useful.
- **act**: builders, reviewers, integrators, and process fixers do the bounded
  work and write completion evidence.

Actor-to-actor inbox chatter should be rare. Prefer loop-local artifacts:

- `.meta/multipass/runtime/loops/<loop-id>/observe/`
- `.meta/multipass/runtime/loops/<loop-id>/orient/`
- `.meta/multipass/runtime/loops/<loop-id>/decide/`
- `.meta/multipass/runtime/loops/<loop-id>/act/` or actor finals under runs

Runtime inbox and actor logs live under `.meta/multipass/`. Compact durable
summaries live under `.meta/multipass/state/`.

## Important Files

- `.meta/foreman/foreman.yaml` configures this repo as a Foreman client.
- `.meta/multipass/multipass.yaml` is legacy compatibility state during the
  handover.
- `.meta/multipass/config/loops/project.yaml` is the top-level project loop.
- `.meta/multipass/config/loops/build/*.yaml` are active feature build loops.
- `.meta/multipass/state/` holds compact current-state summaries.
- `/Users/maxwilliams/dev/foreman-coordinator/actors/` holds central actor prompts.
- `scripts/visual-scenarios/` holds project-local Peekaboo visual evidence scripts.

## Visual Capture Map

When updating or running visual evidence, start here instead of searching:

- `scripts/visual-scenarios/qa-surface-coverage.sh` is the broad screenshot
  capture script. Its `CAPTURES` table is the place to add or update app
  surfaces, including phrase Layers, Scenes, Global Apply, Capture, and
  Automation states.
- `scripts/visual-scenarios/phrase-matrix-navigation.sh` is the smaller
  phrase-matrix paging/layer-switch scenario.
- `scripts/visual-scenarios/phrase-perform-dirty-overlay.sh` is the older
  focused phrase perform overlay/capture scenario.
- `scripts/visual-scenarios/peekaboo-common.sh` owns the visual-automation
  permission gate and shared app/window helpers.
- `Sources/UI/VisualScenarioCommandRunner.swift` maps command-file keys to app
  state and writes `.status` files. Add phrase command support there before
  adding capture rows that need new state.
- `Sources/UI/PhraseWorkspaceView.swift` owns the phrase-local UI surfaces and
  subscribes to `.phraseMatrixVisualCommand` for visual scenario commands.

The capture protocol is command-file driven: scripts write key/value commands
such as `workspace=phrase`, `phraseMatrixLayerID=mute`,
`phrasePerformLayerSelector=open`, or `phrasePerformCapture=open`; the app
writes matching status keys such as `phraseMatrixRenderedVisible`,
`phrasePerformLayerMode`, `phrasePerformLayerSelectorVisible`, and
`trackPerformCaptureVisible`.

## Driving The Running App (command channel)

You can **drive AND read a running SequencerAI instance** over a watched command
file + status file (`VisualScenarioCommandRunner`) — switch workspace, add
tracks, set sends/scenes, control transport (`transport=play|stop`), and read
rendered state back from `<command-file>.status`. No UDP/socket needed; this is
the established pattern (the capture harness is built on it).

- Enable via env `SEQUENCER_AI_VISUAL_COMMAND_FILE=<path>` (or the
  `VisualScenarioCommandFile` default). Read at startup, so attaching to a
  running instance needs a **relaunch**.
- The command file + any fixture must live in a **sandbox-readable** dir, e.g.
  `~/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/sequencer-ai-visual-commands/`
  — a repo path fails with `Operation not permitted`.
- Write atomically (`.tmp` then `mv`); poll the `.status` file to confirm a
  command landed.
- NOT gated by `SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION` (that gate only guards the
  Peekaboo screenshot script).

For **audio graph-edit safety**, drive `scripts/visual-scenarios/routing-stress.sh`
(headless real-HAL via `SEQUENCER_AI_HEADLESS_REAL_HAL=1`): it walks mute / add-fx
/ route / sends / scenes with a hang/crash/silence/click watchdog and is how the
routing deadlock/cycle/silence/click bugs were found and gated. A green run is
necessary-not-sufficient (output-only, native-FX, serial ops) — pair with a human
real-audio pass for AU/input/concurrent cases.

Full reference + vocabulary + the rig's honest limits:
[`wiki/pages/app-command-channel.md`](wiki/pages/app-command-channel.md).

## Runtime Diagnostics

For engine/runtime debugging, use the in-app activity log — not `print`, `NSLog`,
or `/tmp` files. `DevActivity` (`Sources/App/DevActivity.swift`) writes
debug-build breadcrumbs to macOS unified logging under subsystem
`ai.sequencer.SequencerAI.activity` (categories: `engine`, `clock`,
`audio-graph`, `harness`, `session`, `library`). It survives hangs and crashes,
so a post-mortem path can be reconstructed. Read it back with:

```sh
log show --last 10m --style compact \
  --predicate 'subsystem == "ai.sequencer.SequencerAI.activity"'
```

or live with `log stream` and the same predicate. Add new diagnostics through
`DevActivity.trace(...)` (keep it sparse — no unconditional tick-path logs), and
prefer the opt-in `sample-trigger` category for per-step playback probes.

**Full reference: [`wiki/pages/runtime-observability.md`](wiki/pages/runtime-observability.md)** —
read it before adding runtime logging or chasing an engine/playback bug.

## Audio Engine Hard Rules

Audio timing/routing/realtime have **invariants**, not preferences. They are
non-local and their failures are intermittent, so a change can pass tests + lints
and still be wrong. Do not band-aid a symptom (deadlock, glitch) while leaving a
violating shape in place; changing an invariant needs a plan + product-owner
sign-off. The six rules (full text + enforcement in
[`wiki/pages/architecture-guardrails.md`](wiki/pages/architecture-guardrails.md)
→ *Audio Engine Hard Rules*):

1. **One audio-derived master clock** — musical time comes from the engine
   render `sampleTime`, never `systemUptime`/`Date`/`DispatchTime`/timer deadline.
2. **Schedule ahead, never fire "now"** — stamp events with a future
   `sampleTime`/`AUEventSampleTime`/`MIDITimeStamp` via the lookahead scheduler.
3. **AU notes are sample-stamped** via `scheduleMIDIEventBlock` — never a
   `DispatchQueue.main` hop or bare `startNote`/`stopNote` on the note path.
4. **Triggered playback reads resident `AVAudioPCMBuffer`s** (`scheduleBuffer`) —
   never `scheduleSegment(file:)`/`AVAudioFile(forReading:)` on a trigger path
   (file streaming only for large loops, annotated).
5. **Routing is gain + bypass on a fixed graph** — never `engine.stop()/start()`
   for topology during playback; never `disconnect` a sounding node (ramp to
   silence first). Structural add/remove uses a pre-attached node pool.
6. **The render thread is sacred** — no alloc/locks/file-IO/ARC churn; control↔
   audio via lock-free buffers; capture is sink→ring→writer-thread.

Enforced by `realtime-path-lint.sh`, `runtime-ownership-lint.sh`, an offline
frame-accuracy test (assert 0-frame error), and the audio adherence observers.
Migration plan: [`docs/plans/2026-06-24-sample-accurate-timing.md`](docs/plans/2026-06-24-sample-accurate-timing.md).

## UX Canon Lint

UI surfaces have a codified canon (`docs/ux-canon.md`) enforced by
`scripts/diagnostics/ux-canon-lint.sh` — strict zero-tolerance, run it next to
the audio lints for any change under `Sources/UI`. It fails on translucent
accent fills (Rule 12), system-grey escapes bypassing `StudioTheme` tokens,
and explainer-prose `Text` sentences on working surfaces (Rule 3). Legitimate
sentence slots (destructive-confirm messages) live in
`scripts/diagnostics/ux-canon-prose-allowlist.txt`; a genuinely-correct
neutral/opacity use takes an inline `// ux-canon-allow: <reason>` annotation.
Section switchers use `StudioSectionPills` + `StudioTabWell`; value/layer
selectors use `StudioSegmentedControl`/`StudioModeSegmentedPill` (the locked
Variant D grammar — `docs/roadmap/track-view-ia/tab-unification-and-canon-creep.md`).

## Bug Reports & Status

User-filed bug reports live under `docs/bugs/<timestamp-slug>/` (each is a
`note.md`/`report.md` + optional screenshots, dropped by the intake tool). To see
how many are left and of what status:

```sh
scripts/bug-status.sh          # summary counts (RESOLVED / WONTFIX / OPEN / total)
scripts/bug-status.sh --open   # + list the OPEN bug dirs
scripts/bug-status.sh --all    # + every bug dir with its status
```

**Status convention** (the script reads any `*.md` in each bug dir):
- **RESOLVED** — the dir has a `Status: RESOLVED` (or `FIXED`/`DONE`) line, OR a
  `## RESOLVED` / `## ROOT CAUSE + FIX` heading, OR `RESOLVED (20…`.
- **WONTFIX** — a `Status: WONTFIX` (or `WON'T FIX`/`DUPLICATE`/`INVALID`) line.
- **OPEN** — anything else (freshly-filed intake bugs default to OPEN).

When you fix or reject a bug, append a `Status: RESOLVED <commit>` (or
`Status: WONTFIX <reason>`) line to its note/report so the count stays accurate.

### Where evidence goes (the bug-reporter app + branch handling)

The local bug-reporter app is `~/dev/bug-reporter` (`node server.js`, port 4747),
configured by `~/dev/bug-reporter/config.json`. It has two distinct sinks with
different branch/worktree behaviour — **do not conflate them**:

- **Bug reports** → `outputDir` = **`/Users/maxwilliams/dev/in-sequence/docs/bugs`**,
  the PRIMARY checkout — a literal path, branch-agnostic. A report written in a
  *worktree's* `docs/bugs` is INVISIBLE to the app. So file reports into the primary
  checkout's `docs/bugs/<YYYYMMDD-HHMMSS-slug>/` (a `note.md`: first line = title,
  images under a `Screenshots:` list) even when you are working in a worktree.
- **Screenshots** (what "captures" usually refers to) → the gallery scans
  `galleryDir` = `.meta/multipass/visual-review/<branch>/` and UNIONS it across every
  open git worktree (`git worktree list`), partitioned by branch subdir (the worktree
  copy wins over a merged main copy). A branch's UI screenshots go in *that branch's
  worktree* under `.meta/multipass/visual-review/<name>/` and appear automatically.
  This is a UI-screenshot mechanism — NOT for audio/waveform renders.

Never leave evidence in `/tmp` (the app never sees it). The app is sandboxed; the
drum-timing rig (`capture_8bar.sh` + `render_8bar.py`) must write its WAV under
`~/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/...` (it cannot write
`/tmp`). An audio/waveform render is bug-report *evidence* — it goes in the primary
checkout's `docs/bugs/<slug>/`, not the screenshot gallery.

## How To Orient

Run:

```sh
bun /Users/maxwilliams/dev/foreman-coordinator/src/cli/inventory.ts \
  --project /Users/maxwilliams/dev/in-sequence
```

Then read the current summaries:

- `.meta/multipass/state/work/current-work.md`
- `.meta/multipass/state/feature-readiness.md`
- `.meta/multipass/state/holistic-status.md`
- `.meta/multipass/state/decision-log.md`
- active build-loop summaries in `.meta/multipass/state/build-loops/`

If those summaries disagree with fresh evidence under `.meta/multipass/runtime/loops/`
or actor finals under `.meta/multipass/runtime/runs/`, prefer the fresher evidence and
update the compact summary through the loop.

## Working Rules

- Feature implementation should happen in build-loop worktrees, not as dirty
  production-code changes on `main`.
- Review the actual built surface for UX/visual decisions. Use Peekaboo
  screenshots where relevant.
- Unattended agents must not run Peekaboo, visual scenario scripts, `osascript`
  UI automation, or app-control flows that can trigger macOS TCC prompts unless
  `SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1` is explicitly set for an interactive,
  pre-authorized session. If the gate is closed, record
  `capture-permission-or-focus` / `evidence-insufficient` instead of retrying.
- Audio test source by permission tier: **unattended/headless audio runs use
  sample sources only** (`Destination.sample`/`.slicer` — deterministic, no
  prompt). **AU instruments/effects and audio-input tests only when a human is
  present** to grant the macOS "lower permissions?" / mic-TCC modal — a headless
  launch can't dismiss it and blocks (no audio, `masterPeak=-inf`). Note:
  `.internalSampler(.drumKitDefault)` is NOT an implemented sound source.
- Keep the README/project spirit in view, but do not make every actor reread the
  whole repo.
- Human attention is precious. Ask only when the product owner has a genuinely
  interesting product decision to make.
- If deterministic tooling is stale or broken, record that as process evidence
  and let the OODA loop route the repair. Do not let a brittle script become the
  only authority.

## Legacy Claude Files

Some `.claude` hooks and skills remain for Claude Code ergonomics, such as
push/file-size guards and adversarial review prompts. They are not the project
scheduler.

Historical `.claude/state` files may still exist as old evidence. Treat them as
legacy context, not current control state.
