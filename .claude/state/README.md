# Behaviour-tree state

Files in this directory are the **memory** of the `/next-action` behaviour-tree loop. The tree reads them to decide what to do; actions write them to drive the next iteration.

Structure:

```
.claude/state/
├── work-item.md              # the current active work-item (at most one)
├── candidates.md             # ranked queue of potential work
├── inbox/                    # user-queued messages / redirects
│   └── archive/              # handled inbox items
├── review-queue/             # outstanding adversarial critiques
├── insights/                 # lateral / exploratory ideas
├── last-review-sha           # HEAD SHA at last /adversarial-review run
└── last-tests-sha            # HEAD SHA at last green xcodebuild test
```

See `.claude/skills/next-action/SKILL.md` for the selector tree and how each
file is consumed.

This directory is committed so the state survives across sessions and is
visible in branches. Files here **are part of the project history**.
