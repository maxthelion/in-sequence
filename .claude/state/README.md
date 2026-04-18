# Behaviour-tree state

Files in this directory are the **memory** of the `/next-action` behaviour-tree
loop. The tree reads them to decide what to do; actions write them to drive
the next iteration.

## Durable state (committed)

These files carry decisions / observations that should persist across sessions
and be visible on branches:

```
work-item.md                  # current active work-item (at most one)
candidates.md                 # ranked queue of potential work
partial-work.md               # handoff from a timed-out agent
last-review-sha               # HEAD SHA at last /adversarial-review
last-tests-sha                # HEAD SHA at last green test run
last-tests-failure.md         # if present, tests are red
inbox/                        # user-queued messages
  archive/                    # handled inbox items
review-queue/                 # outstanding adversarial critiques
insights/                     # lateral / exploratory ideas
```

Deleting any of these loses a decision the automation had made — don't do it
without intent. Committing them makes branches self-describing ("this branch
has 3 outstanding critiques").

## Generated state (gitignored)

Regenerated on every `setup-next-action.sh` invocation; has no durable
signal beyond whatever the current state files encode:

```
next-action.md                # what the next agent should do (gitignored)
```

`next-action.md` contains a timestamp and the current HEAD SHA by design, so
it would dirty the tree on every run if tracked. It's a *cache* of the BT
evaluation; rerun the evaluator if you need the current answer.

## Rules for contributors

- Only write to this directory via the setup script or the leaf actions of the
  BT skill (`.claude/skills/next-action/SKILL.md`).
- Durable state files should be human-readable markdown or plain text. No JSON,
  no binary.
- When adding a new state file, update this README's taxonomy first; if the
  file is generated, also add it to `.gitignore`.

See `.claude/skills/next-action/SKILL.md` for the selector tree and how each
file is consumed.
