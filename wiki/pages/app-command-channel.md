---
title: "App Command Channel (live drive + read)"
category: "tooling"
tags: [automation, visual-scenarios, command-file, status, driving, qa]
summary: "Drive and read a running SequencerAI instance over a watched command file + status file — switch UI, add tracks, set sends/scenes, control transport, and read rendered state back. No UDP/socket; this is the established pattern."
last-modified-by: claude
---

## What it is

`Sources/UI/VisualScenarioCommandRunner.swift` gives the running app a
**file-based control channel**: it watches a *command file* for `key=value`
lines, applies them to the live `SequencerDocumentSession` / `EngineController`
on the main actor, and writes a sibling *status file* (`<command-file>.status`)
with the rendered app state. It is bidirectional — you **drive** the app and
**read** what it did. This is what `scripts/visual-scenarios/qa-surface-coverage.sh`
uses to pose every capture; you can use it directly to set up state, reproduce a
UI, or script a change while the app is open.

There is **no UDP/OSC listener** and you don't need one — this channel already
covers "switch UI, add tracks, change things, read data". (A socket listener
could be added later, but it would duplicate this.)

## Enabling it

The command-file path is read **once at startup** from either:

- env `SEQUENCER_AI_VISUAL_COMMAND_FILE=<path>`, or
- `defaults write ai.sequencer.SequencerAI VisualScenarioCommandFile <path>`

Because it's read at startup, **attaching to an already-running instance needs a
relaunch.** Launch the built executable directly with the env set:

```
exe=".../DerivedData/.../Debug/SequencerAI.app/Contents/MacOS/SequencerAI"
dir="$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/sequencer-ai-visual-commands"
mkdir -p "$dir"
SEQUENCER_AI_VISUAL_COMMAND_FILE="$dir/cmd.env" \
  SEQUENCER_AI_NEW_DOCUMENT_FIXTURE="$dir/some-fixture.seqai" \
  "$exe" &
```

**Sandbox:** the app is sandboxed, so the command file (and any fixture) must
live somewhere it can read — use the container tmp dir above, not a repo path.
Reading a fixture straight from the repo fails with `Operation not permitted`.

**No automation gate.** The command runner is NOT behind
`SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION` — that gate only guards the Peekaboo
screenshot script. Driving the app via the command file is always available once
wired. (Normal etiquette still applies: this is interactive/owner-authorized
territory; don't drive the app unattended in a way that could trigger TCC
prompts.)

## Writing commands

Write newline-separated `key=value` lines to the command file atomically
(write to `.tmp`, then `mv` over the real path so the app never reads a partial
file) — this is what `write_visual_command` does in the harness:

```
printf '%s\n' "windowFrame=120,80,1100,780
workspace=mixer
transport=play" > "$dir/cmd.env.tmp"
mv "$dir/cmd.env.tmp" "$dir/cmd.env"
```

## Vocabulary (categories)

The authoritative list is the `command["..."]` keys in
`VisualScenarioCommandRunner.swift` and the `CAPTURES` table in
`qa-surface-coverage.sh`. Broad groups:

- **Transport:** `transport=play|stop`.
- **Navigation:** `workspace=song|phrase|tracks|track|mixer|scenes|library`;
  `workspaceMode=`.
- **Tracks:** `addTrack=slice|...`, `tracksCreateTrackModal=open`,
  `tracksAddDrumGroupModal=open`, `tracksSelect=`, etc.
- **Drum kit:** `drumPartHeaderFixture=kit`, `drumPartHeaderOpenKitView=true`,
  `drumKitMatrixFixture=`, `drumKitMatrixCommand(s)=`, `drumKitMatrixLayer=`,
  `drumKitMatrixDisplayStepCount=`, routing editor commands.
- **Slicer:** `slicerFixture=populated`, `slicerLayer=`, `slicerTab=`,
  `sliceSourceModal=`.
- **Scenes / sends:** `scenesMode=`, `sceneEditorFixture=`, `scenesAddFXModal=`,
  `scenesSelectInsert=`, `sendAInserts=`, `sendBInserts=`.
- **Phrase matrix:** `phraseMatrixTrackCount=`, `phraseMatrixPhraseCount=`,
  `phraseWorkspaceTab=`, `phrasePerformLayer(Selector|Variant)=`,
  `phraseGlobalApply*`, `phraseCapture=`, `phraseSceneSelect=`.
- **Mixer / misc:** `masterGain=`, `windowFrame=`, `quantise=`.
- **Graph-edit (routing self-test):** `trackMute=<idx>:<on|off>`,
  `busMute=<idx>:<on|off>`, `trackAddInsert=<idx>:<native-filter|native-bitcrusher>`,
  `trackRemoveInsert=<idx>:<insertIdx>`, `masterAddInsert=<native-...>`,
  `routeTrackToBus=<idx>:<busIdx|master>`, `trackSend=<idx>:A=<0..1>,B=<0..1>`,
  `removeTrack=<idx>`. (native FX only — no AU; AU effects need an interactive
  permission-granting session.)

Note: many `*Fixture*` commands BUILD state (e.g. `phraseMatrixTrackCount`
forces `workspace=phrase` via `applyPhraseMatrixFixture`), so combining them with
a different `workspace=` can fight — read the apply function before composing.

## Reading state back

After applying, the app writes `<command-file>.status` with `key=value` lines
(see `writeStatus(...)`), including `transport=play|stop`, the resolved
workspace/scenes mode, `*RenderedVisible` flags, and **audio metrics**:
`masterPeak` (dBFS, summed master — ears-free "is signal reaching master") and
`masterMaxSampleDelta` (a normalized discontinuity / click proxy). Poll it with
the `wait_for_status key value timeout` pattern.

CAVEAT (2026-06-25 gate review): `masterPeak` is the SUMMED master, so it cannot
see a single track going silent, and the click proxy's SNR is limited by noisy
sources. Treat them as coarse signals — for routing self-tests use the
`routing-stress` rig below (per-track checks + op post-conditions).

## Headless real-HAL self-test: the routing-stress rig

`scripts/visual-scenarios/routing-stress.sh` drives the graph-edit commands
above over the command channel against a **real HAL engine, headless**, and
auto-detects failures — the tool that found and gated the audio-graph deadlock /
cycle / silence / click bugs. Use it before claiming any graph-edit change is
safe.

- **Real-HAL headless:** set `SEQUENCER_AI_HEADLESS_REAL_HAL=1` to skip the
  command-channel's default offline-render force, so the engine runs on the real
  device (sample-only fixtures → no mic prompt). This is required to reproduce
  HAL-running bugs (live `engine.connect` reconfig deadlocks) that offline mode
  hides.
- **Fixture:** `docs/fixtures/audio-rich-routing-sampleonly.seqai` (sample/native
  only) + `SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1`.
- **Watchdog:** after each command it checks pid-alive + status freshness; on a
  stall it `sample`s the process and logs the blocked stacks (HANG), captures
  `.ips` faulting frames (CRASH), and reads the audio metrics (SILENCE / CLICK).
  Per-op report under `.meta/routing-stress/`.

**Honest limits of the gate** (2026-06-25 review — know these before trusting a
green run): it covers the **output-only, native-FX path, one serial op at a
time** on a single fixture. It does NOT cover AU instruments/effects, audio
input, concurrent/rapid edits, scene crossfades, or sub-watchdog hangs; the
summed-`masterPeak` silence check and the click proxy are coarse (per-track
checks + op post-conditions are being added). A green rig run is necessary, not
sufficient — pair it with a human real-audio pass for the excluded classes.

- The vocabulary is fixed code; adding a new command key or status field means
  editing `VisualScenarioCommandRunner.swift` and rebuilding.
- It mutates the live session on the main actor — it is QA/dev tooling, not a
  product API.

## See also

- `scripts/visual-scenarios/qa-surface-coverage.sh` — the capture harness built
  on this channel (and its `CAPTURES` table = worked command examples).
- AGENTS.md → *Visual Capture Map* and *Driving the running app*.
- [[runtime-observability]] for reading engine/runtime breadcrumbs.
