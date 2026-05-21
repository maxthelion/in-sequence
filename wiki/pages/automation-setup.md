---
title: "Automation Setup"
category: "meta"
tags: [automation, multipass, ooda, meta, loops]
summary: Current automation layout for in-sequence as a Multi-Pass v2 client.
last-modified-by: codex
---

## Current Model

`in-sequence` is coordinated by Multi-Pass v2. Meta ticks this project through:

```sh
project/scripts/tick.sh --write
```

The project shim delegates to the reusable runtime:

```sh
bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/tick.ts \
  --project /Users/maxwilliams/dev/in-sequence --write
```

The runtime reads `multipass.yaml`, active loop manifests under
`docs/multi-pass-coordinator/loops/`, central actor prompts from
`/Users/maxwilliams/dev/multi-pass-coordinator/actors/`, and runtime inboxes
under `.meta/multipass/`.

## OODA Discipline

The project loop and feature build loops use four roles:

| Phase | Responsibility | Writes |
| --- | --- | --- |
| observe | Gather facts, reviews, screenshots, logs, branch state, readiness, and process health. | `.meta/multipass/loops/<loop>/observe/` and compact durable summaries when useful |
| orient | Interpret observations against the README, roadmap intent, active work, and the product pyramid. | `.meta/multipass/loops/<loop>/orient/` |
| decide | Schedule one bounded next action when action is useful. | Runtime inbox messages under `.meta/multipass/inbox/pending/` |
| act | Build, review, integrate, or repair one bounded thing. | Actor finals under `.meta/multipass/runs/` plus loop-local completion evidence |

Observers should not route work. Orienters should not schedule work. Deciders
should avoid broad admin churn and prefer concrete progress.

## Live Runtime Layout

```text
multipass.yaml
project/scripts/tick.sh
docs/multi-pass-coordinator/loops/
  project.yaml
  build/<feature>.yaml
docs/multi-pass-coordinator/state/
  work/current-work.md
  feature-readiness.md
  holistic-status.md
  decision-log.md
  build-loops/<feature>.md
.meta/multipass/
  inbox/{pending,claimed,done,blocked}/
  runs/actors/<actor>/
  loops/<loop-id>/{observe,orient,decide,act}/
  activity.ndjson
```

Runtime `.meta/multipass` files are transient evidence and logs. Durable docs
under `docs/multi-pass-coordinator/state/` should stay compact and current.

## Project-Local Evidence

Project-specific visual evidence scripts live in `scripts/visual-scenarios/`.
They should reuse the shared Peekaboo helpers rather than inventing a second
capture mechanism.

Project-specific doctrine belongs in this repo as README/wiki/style-guide files
or as actor addenda configured through `multipass.yaml`. Avoid copying central
actor prompts into this repo unless the project needs a true replacement.

## Retired Behaviour Tree

The old Claude `.claude/hooks/setup-next-action.sh` + `/next-action` behaviour
tree has been retired from the live workflow. It was useful scaffolding, but it
became a second authority for “what happens next” and confused agents now that
Multi-Pass/OODA owns coordination.

Do not recreate `next-action.md` or run `/loop /next-action`. Promote work into
Multi-Pass loops and let observers, orienters, deciders, and actors move it
forward.

`docs/roadmap/next-actions.md` is different: it is roadmap readiness output from
the PM artifact scan, not the retired implementation behaviour tree.

## Useful Commands

```sh
# Inspect active loops and pending work
bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/inventory.ts \
  --project /Users/maxwilliams/dev/in-sequence

# Tick one project iteration
project/scripts/tick.sh --write

# Dry-run without starting actors
project/scripts/tick.sh --dry-run
```

## Related Pages

- [[application-overview]]
- [[architecture-guardrails]]
- [[mixer-grammar]]
- [[project-layout]]
