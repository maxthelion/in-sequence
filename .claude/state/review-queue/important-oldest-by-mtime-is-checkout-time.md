# 🟡 Important — `OLDEST` critique / inbox is derived from filesystem mtime, which is checkout time on a fresh clone, not file-creation time

**File:** `.claude/hooks/setup-next-action.sh:71, 108`

## What's wrong

```bash
OLDEST="$(ls -1t "$STATE/review-queue"/*.md 2>/dev/null | tail -1)"   # :71
OLDEST="$(ls -1t "$STATE/inbox"/*.md 2>/dev/null | tail -1)"         # :108
```

`ls -1t` sorts by mtime (newest first); `tail -1` takes the end of the list — i.e. the oldest mtime. The BT then emits a `fix-critique` / `handle-inbox` action referencing that file.

The problem: **mtime is the checkout time on a fresh clone, not the git commit time of the file's first addition**. After `git clone`, all `review-queue/*.md` files have approximately the same mtime (clone timestamp), and the tiebreak is filesystem-order — essentially random.

Consequence: on a machine that clones the repo mid-review-cycle, "the oldest critique" is whichever file happened to be written last by the checkout — not necessarily the oldest actually-filed critique. The BT's claim of determinism ("pure function of state") is false.

Same problem for the inbox.

## What would be right

Several options, in order of robustness:

- **Embed the creation timestamp in the filename.** Rename review-queue files from `severity-slug.md` to `YYYYMMDDTHHMMSS-severity-slug.md`. Then `ls -1` sorts lexically by creation time, no mtime dependency. The reviewer prompt would need to generate filenames with a timestamp prefix.
- **Parse a frontmatter `created:` field** from each file. More structure, but requires each critique writer to set it.
- **Use `git log --diff-filter=A` to find the commit that first added each file**, then sort by that commit date. Robust but slow.

Option 1 is lightest. Suggest filename convention `<severity>-YYYYMMDDTHHMMSS-<slug>.md` (the controlling reviewer writes the timestamp at critique-emission time).

## Why it matters

The BT's value proposition is determinism. "Given state X, produce action Y, always." A dependency on ephemeral filesystem metadata defeats that: the same set of committed files produces different `next-action.md` content on different clones, which will drive `/loop` iterations to pick different critiques to address. In an autonomous overnight run starting on a fresh clone, the ordering matters — a low-priority critique can starve a higher-priority one indefinitely if mtime shuffles the order.
