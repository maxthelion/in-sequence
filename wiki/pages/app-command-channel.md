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

Note: many `*Fixture*` commands BUILD state (e.g. `phraseMatrixTrackCount`
forces `workspace=phrase` via `applyPhraseMatrixFixture`), so combining them with
a different `workspace=` can fight — read the apply function before composing.

## Reading state back

After applying, the app writes `<command-file>.status` with `key=value` lines
(see `writeStatus(...)`), including `transport=play|stop`, the resolved
workspace/scenes mode, and `*RenderedVisible` flags for surfaces. Poll it (the
harness's `wait_for_status key value timeout` pattern) to confirm a command took
effect before acting further.

Today the status file does **not** include a master audio level. Adding a
`masterPeak=` field to `writeStatus` (small change) would allow **ears-free
verification that signal is reaching master** — useful for routing/audio passes
and complementary to the offline-amplitude test
([[architecture-guardrails]] → Audio Engine Hard Rules / the offline frame test).

## Limits

- The vocabulary is fixed code; adding a new command key or status field means
  editing `VisualScenarioCommandRunner.swift` and rebuilding.
- It mutates the live session on the main actor — it is QA/dev tooling, not a
  product API.

## See also

- `scripts/visual-scenarios/qa-surface-coverage.sh` — the capture harness built
  on this channel (and its `CAPTURES` table = worked command examples).
- AGENTS.md → *Visual Capture Map* and *Driving the running app*.
- [[runtime-observability]] for reading engine/runtime breadcrumbs.
