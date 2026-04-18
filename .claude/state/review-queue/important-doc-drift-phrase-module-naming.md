# 🟡 Important — cross-doc drift: `reviewer-prompt.md` invokes `Sources/Phrase/` module that `project-layout.md` doesn't plan to create

**Files:**
- `.claude/skills/adversarial-review/reviewer-prompt.md:47`
- `wiki/pages/project-layout.md:107-113`

## What's wrong

The adversarial reviewer prompt (committed in 49361b8) tells the reviewer to hunt for:

> Per-phrase state handled in `Song/` when it should be in `Phrase/`.

i.e. it treats `Sources/Phrase/` as a real, expected subdirectory.

But `wiki/pages/project-layout.md:107-113` — in the **Adding new subdirectories** section that is explicitly the authoritative map — lists:

```
- Sources/Engine/       — Plan 1
- Sources/Coordinator/  — macro coordinator + phrase model (Plan 2)   <--
- Sources/Song/         — Plan 3
- Sources/Chord/        — Plan 4
- Sources/Drums/        — Plan 5
```

Phrase model lives in **`Coordinator/`**, not a separate `Phrase/`. No `Sources/Phrase/` is planned.

The spec (`docs/specs/2026-04-18-north-star-design.md:489-493`) agrees with the wiki: _"Macro coordinator and phrase model — abstract/concrete rows, authored-source blocks, phrase structure"_ as a single sub-spec (#2).

## Related drift

Other inconsistencies among the three committed docs:

1. **`automation-setup.md:82-89`** advertises a session-start banner with lines `│ docs:    north-star at docs/specs/ …` and `│ review:  run /adversarial-review after implementer DONE …`. The actual banner printed by `.claude/hooks/session-start.sh` says `│ BT state: …`, `│ drive: …`, `│ refresh: …` — different content entirely. Documented banner is aspirational; real banner is what the script produces. Verified by running `bash .claude/hooks/session-start.sh`.

2. **`automation-setup.md:50`** lists `scheduled_tasks.lock` in the tree diagram, but the `.gitignore` entry is at `.claude/scheduled_tasks.lock` — the file is in a parent dir of the state files shown but the diagram places it as a peer of `state/`. Minor layout confusion.

3. **`execute-plan/SKILL.md:77`** hard-codes the tag template `v0.0.N-<slug>` while `project-layout.md` and the north-star spec don't constrain the tagging scheme at all. Fine if SKILL.md is authoritative; but no doc says it is.

## What would be right

- Fix the reviewer prompt to use `Coordinator/` (or list "Coordinator (plan 2) / Song (plan 3) — phrase state lives in Coordinator, not Song").
- Update `automation-setup.md`'s banner example to match the actual script output, or update the script to match the doc (the doc's version is arguably more useful — mentions where docs live and what skills to run; real output is more state-oriented).
- Unify on **one** tagging scheme and document it in `project-layout.md` or a new `release-tagging.md` page.

## Why it matters

Adversarial reviews fire based on the reviewer prompt. If the prompt tells the reviewer to hunt for leaks into `Phrase/`, the reviewer will flag a correct-per-layout piece of code as a responsibility violation — wasting cycles and undermining trust in the review. Documentation that tells different stories is worse than no documentation: both readers argue they're following the spec.

The prompt in this diff is the first thing to be reviewed by its own output (this review!). If it self-contradicts the project layout, every future adversarial review starts by re-confusing the next reviewer.
