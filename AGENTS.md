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
