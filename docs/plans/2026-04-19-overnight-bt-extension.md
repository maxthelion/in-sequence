# Overnight Behaviour-Tree Extension — Holistic Review + Octoclean + Revert-on-Regression

> **Status:** DRAFT — rescued from chat transcript 2026-04-19. Eight-task plan for making overnight autonomous refactoring safe.

**Goal:** Extend the BT from "review the last diff" to "holistically assess the whole codebase, refactor with a mechanical fitness function, revert on regression." Turns the overnight loop from a hoping-the-tests-cover-it operation into a measure-twice-cut-once one. Depends on the characterization goldens being in place (they are the fitness function).

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` (BT section). Follow-up to `characterization` plan.

**Depends on:**
- `characterization` plan completed — goldens + `verify-characterization.sh` are the mechanical fitness function
- `cleanup-post-reshape` ideally done first so the holistic review isn't flooded with known-deferred findings

**Status:** Not started. Tag TBD (probably `v0.0.13-overnight-bt` or similar).

**Reference material:**
- Shoe-makers blog + repo (`github.com/maxthelion/shoe-makers`) — canonical pattern for autonomous BT refactoring
- Octoclean (`github.com/maxthelion/octoclean`, installed at `/Users/maxwilliams/dev/octoclean/`) — code-health scoring as fitness function. JS/TS-focused but ~70% applies to Swift via `lizard` + LLM assessment layer.
- Michael Feathers' characterization testing article — rationale for the goldens

---

## The gaps this plan fills

1. **BT only reviews the last diff.** `adversarial-review` runs against `last-review-sha..HEAD` — purely diff-based. Can't surface "900-line `PhraseModel.swift` violates file-size cap" because nothing in the last diff touched it.
2. **Reviewer has no WIP awareness.** When it flags the duplicate `TrackGroup` declaration, it can't tell that's "Task 3 of the reshape plan mid-flight" vs "real drift." Produces noise.
3. **`fix-critique` greedily processes whatever's in `review-queue/`** — no room for "defer, a planned task handles this."
4. **BT trusts the implementer's test run.** A broken refactor can sit on `main` until humans review the branch next morning.
5. **No fan-in awareness.** A refactor can try to change the most-connected file and cascade-break everything.
6. **No daily-branch enforcement.** `/loop` on `main` can corrupt it.
7. **Invariants not cross-referenced.** `docs/specs/north-star-design.md` can change without the BT noticing it should re-check code-vs-spec drift.

---

## Tasks

### Task 1: Swift code-health probe
`scripts/codehealth/swift-scan.sh` runs `lizard Sources/` (complexity) + duplication check (need `jscpd` install or custom) + dead-public-symbol grep (or `periphery scan` if usable) + churn×complexity (via `git log --name-only` aggregation). Emits JSON in the shape octoclean consumes so the two can interoperate.

Alternative: adapt octoclean itself to accept Swift projects (it's TS/JS-centric; `madge`/`ts-unused-exports` don't apply but `lizard` + LLM assessment do).

- [ ] Decide: adapt octoclean vs. build Swift-specific scan script
- [ ] Implement
- [ ] Commit: `feat(scripts): swift code-health scan`

### Task 2: Baseline + revert-on-regression wrapper
`.claude/hooks/pre-refactor-baseline.sh` captures `{ healthScore, goldensPass, testsPass }` into `.claude/state/last-baseline.json`. `post-refactor-verify.sh` re-measures; if any metric worse, revert the last commit with a note dropped into `.claude/state/inbox/`.

Critical: goldens check is the authoritative gate; health score is advisory (it's a heuristic; a principled refactor can legitimately lower the score short-term).

- [ ] Hook scripts
- [ ] Wire into BT via settings.json
- [ ] Commit: `build(hooks): baseline + revert-on-regression`

### Task 3: `holistic-review` BT action
Runs (a) `swift-scan`, (b) `octowiki-invariants`, (c) `adversarial-reviewer` with whole-codebase scope. Merges findings into `review-queue/` with severity frontmatter + `covered-by: <plan>` annotation where a finding overlaps WIP.

Scheduled when `review-queue/` is empty AND N commits since last holistic pass (N=20). State via new `.claude/state/last-holistic-review-sha`.

BT placement: between `[1e] unreviewed commits → adversarial-review` and `[2a] open work-item`. Order: `[1e.5] commits-since-holistic > threshold? → holistic-review`.

- [ ] New skill `holistic-review` (reuses `/adversarial-review` with wider scope arg)
- [ ] Emitter in `setup-next-action.sh`
- [ ] Commit: `feat(bt): holistic-review action`

### Task 4: Finding frontmatter + triage (`covered-by`)
Reviewer prompt extended: for each finding, check whether an open plan in `docs/plans/` already addresses the file/concern. If yes, add `covered-by: <plan-filename>` to the finding's frontmatter.

`fix-critique` parses the frontmatter. If `covered-by:` is present AND the referenced plan isn't marked completed, skip that finding (move to `review-queue/covered/`; stays out of the oldest-file scan).

Natural cleanup: when the referenced plan completes, a `reap-covered-findings` step moves `covered/` back to the queue for a post-plan pass. Or leave them — next holistic review re-raises if still valid.

- [ ] Extend reviewer prompt
- [ ] Extend `fix-critique` to parse + triage
- [ ] `reap-covered-findings` tick
- [ ] Commit: `feat(bt): covered-by finding triage`

### Task 5: Fan-in awareness in implementer dispatch
Before dispatching `fix-critique`, consult the latest scan's high-fan-in list; annotate the implementer brief with "do not modify these files unless the critique explicitly targets them." Protects against cascade breakage.

Derives fan-in from grep of import/reference patterns (or from the octoclean scan output if it includes this).

- [ ] Fan-in computation in the scan
- [ ] Brief annotation in dispatch
- [ ] Commit: `feat(bt): fan-in awareness in implementer dispatch`

### Task 6: Daily auto-branch enforcement
`setup-next-action.sh` checks the current branch name; if it's `main` during `/loop` execution, refuses to route (or warns hard). Convention: overnight runs checkout `auto/YYYY-MM-DD`. Humans review and merge in the morning.

AGENTS.md update: document the workflow. *Currently AGENTS.md has a brief nod but it's not enforced.*

- [ ] Branch check in `setup-next-action.sh`
- [ ] AGENTS.md update
- [ ] Commit: `build(bt): daily auto-branch enforcement`

### Task 7: Pre-commit hook — no duplicate top-level types
Already scoped as Task 8 of the characterization plan. If that ships first, this task is a no-op; otherwise implement here. ~20 lines of bash, runs on the existing PreToolUse Bash hook.

- [ ] Skip if characterization plan already shipped it
- [ ] Otherwise: `.claude/hooks/pre-commit-no-duplicate-types.sh`
- [ ] Commit: `build(hooks): pre-commit refuses duplicate top-level types`

### Task 8: Invariants cross-reference
`.claude/state/last-invariants-sha` tracks the spec's hash; BT notices when the spec has changed since the last invariant-drift check and routes to `octowiki:invariants` as an overnight priority.

- [ ] State file + hash-on-setup check in `setup-next-action.sh`
- [ ] Commit: `feat(bt): invariants cross-reference`

---

## Code-review-checklist addition (documentation-only)

Add a rule to the code-review checklist: *"A reshape plan is not complete until every reader of the prior representation is migrated or deleted. Adding new types alongside old ones and letting later plans 'clean up' is the #1 source of drift findings."* This is the meta-assessment that would have prevented the cleanup-post-reshape plan from being needed.

Deliver as part of Task 6 (AGENTS.md update) or wherever the checklist lives.

---

## Overnight loop, post-plan

```
tick 1:  verify-tests → pass → bump last-tests-sha
tick 2:  adversarial-review (on last diff) → findings
tick 3:  fix-critique (first real finding) → commit
tick 4:  verify-characterization → pass → continue
tick 5:  verify-tests → pass → continue
...
tick 10: review-queue empty → N commits since holistic > threshold → holistic-review
tick 11: holistic findings filed with covered-by: where applicable
tick 12: fix-critique picks first NOT-covered finding → commit
tick 13: verify-characterization → FAIL → revert commit + inbox note
...
tick M:  holistic queue empty → BT routes to write-next-plan / promote-plan-task
```

Morning: human reviews `auto/YYYY-MM-DD` branch, merges the good stuff.

---

## Open questions

- Octoclean reuse vs. Swift-native: spend a half-day trying `codehealth scan` against this repo to see what comes out before committing to either path.
- Health-score regression vs. goldens regression: treat goldens as authoritative (revert); treat health as advisory (log but don't revert). Otherwise principled refactors that temporarily widen complexity get blocked.
- Does `periphery` cover the dead-public-symbol gap? Worth a spike.
- Overlap with `qa-infrastructure` plan — that plan covers SwiftUI snapshot tests; this plan covers whole-codebase refactoring safety. Distinct but adjacent.
