# Test Performance Investigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Understand where `xcodebuild test` time actually goes, apply the config-only wins that require no refactor, and produce the data needed to decide whether a structural change (SPM split, test-target slicing) is worth the cost. Verified by: a committed `.claude/state/test-perf-baseline.md` with cold/warm wall-clock + compile-vs-execute ratios; config wins (parallel tests, coverage off, derivedData path) applied and re-measured; a go/no-go decision on structural work based on data, not hunch; a `scripts/measure-test-time.sh` that anyone can run to reproduce the numbers.

**Architecture:** Three phases, cheap before expensive:

1. **Measure** (Tasks 1–3) — establish baseline; nothing changes yet. If measurement reveals the problem is small, stop here.
2. **Config wins** (Tasks 4–5) — changes that don't require refactors: xcodebuild flags, scheme settings, derivedData placement. Re-measure; keep what works.
3. **Structural decision** (Task 6) — with data in hand, decide whether SPM logic-only split or test-target slicing pays off. Writing the structural plan itself is Task 6's output; executing it is a separate plan.

Bounded by a soft 1-day time cap. Perf investigation is a tarpit; the point is enough data to make informed plan-writing decisions, not a bottom-up rebuild of the test harness.

**Parent spec:** n/a — infrastructure. Sits alongside `qa-infrastructure` and `characterization` as test-harness work. The overnight-loop plans (`overnight-bt-extension`, `execute-plan` cadence) compound any test-time inefficiency linearly; buying speed here shortens every overnight plan run.

**Depends on:** nothing hard. Best run on the current post-cleanup `main` shape (after the legacy-bridge deletion at `60fa69b` and the destination-editor cleanup at `0df85d7`) so the measured baseline reflects the real shipping tree, not a transient hybrid state. Avoid running it while large uncommitted rename/split refactors are in flight, or the numbers will be polluted by one-off compile churn.

**Deliberately deferred:**

- **Actually executing the SPM logic-only split** if Task 6 recommends it — that's a separate plan (`logic-package-split` or similar). This plan only produces the recommendation.
- **Rewriting slow individual tests.** If per-test timing shows one test eats 30% of the budget, note it but don't fix it here (belongs in a fix-critique task).
- **CI-side optimisation** (self-hosted runners, caching strategies, pre-warmed images). GitHub Actions macos-latest is what it is; this plan targets local/overnight dev-machine runs.
- **Build-system alternatives** (Bazel, Tuist beyond xcodegen). Massive scope, not paying off for a 184-test project.

**Status:** `<STATUS_PREFIX>` `<COMPLETED_MARKER>` TBD. Tag TBD (likely no tag — infrastructure plan, no user-visible ship).

---

## File Structure

```
scripts/
  measure-test-time.sh                   # NEW — reproducible timing capture
  perf/
    parse-xcresult-timings.sh            # NEW — per-test-class duration extraction from .xcresult
    (optional) run-subset.sh             # NEW — convenience for -only-testing filters
.claude/state/
  test-perf-baseline.md                  # NEW — recorded numbers + analysis
  test-perf-followup-findings.md         # NEW — what structural change (if any) is warranted
docs/
  plans/
    2026-04-20-test-performance-investigation.md    # this file
    (conditional follow-up if Task 6 recommends one)
project.yml
  # preferred home for persistent scheme / build-setting edits per Task 4
SequencerAI.xcodeproj
  # regenerated from project.yml via xcodegen; don't hand-edit unless measurement proves it unavoidable
```

---

## Task 1: Baseline — cold + warm full-suite timings

**Scope:** Measure a single canonical datapoint so we have a number to compare against. No code changes.

**Steps:**

1. `time DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild clean` + `time xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS'` — this is cold. Record wall-clock.
2. Modify a single test file (add a whitespace char, revert), re-run `xcodebuild test` — this is warm incremental. Record wall-clock.
3. Re-run same warm command without any file change — this is no-op-warm. Record wall-clock.

Capture output to `.claude/state/perf-raw/baseline-run-1.log` (gitignored) and distill the three numbers into `.claude/state/test-perf-baseline.md` under a **Baseline** section.

**Acceptance:**
- Three times recorded: cold, warm-incremental, warm-noop.
- If cold is < 60s, the investigation is probably over. Note this and proceed to Task 2 only if cold > 60s.

- [ ] Run the three timings
- [ ] Record in baseline doc
- [ ] Commit: `chore(perf): baseline xcodebuild test timings`

---

## Task 2: Compile-vs-execute ratio

**Scope:** Know where the time goes. A 3-minute test run that's 10s execution + 2:50 compile is a different problem than 2:50 execution + 10s compile.

**Steps:**

1. Run `xcodebuild test -showBuildTimingSummary ... | tee .claude/state/perf-raw/timing-summary.log` — gives phase-level breakdown: `CompileSwift`, `Ld`, `CodeSign`, `SwiftCompile`.
2. Identify the top-5 slowest build steps and the aggregate compile time vs the XCTest-emitted "Test Suite … passed in X.XXX seconds" total.
3. Ratio: `compile_time_seconds / total_wallclock_seconds` and `test_execution_seconds / total_wallclock_seconds`. Record in baseline doc.

**Acceptance:**
- Baseline doc shows the ratio. Notes the top-5 slowest compile units if compile dominates.

- [ ] Run timing summary
- [ ] Distill into baseline doc
- [ ] Commit: `chore(perf): compile-vs-execute ratio recorded`

---

## Task 3: Per-test-class timing

**Scope:** If execute-time matters, know which test classes own it. Even if compile dominates, per-class numbers tell us whether `-only-testing:` filters are worth wiring into plans.

**Steps:**

1. Run `xcodebuild test -resultBundlePath .claude/state/perf-raw/result.xcresult -scheme SequencerAI ...`.
2. Create `scripts/perf/parse-xcresult-timings.sh` that uses `xcrun xcresulttool` to extract per-test-class duration from the bundle and emit a flat TSV sorted desc by duration.
3. Record the top-10 slowest classes in baseline doc.

**Acceptance:**
- Script exists and produces a sorted TSV reproducibly.
- Baseline doc shows top-10 test classes with their durations + what percentage of total test time each owns.

- [ ] Write the parse script
- [ ] Run against a fresh `.xcresult`
- [ ] Record top-10 in baseline doc
- [ ] Commit: `feat(scripts): parse-xcresult-timings`

---

## Task 4: Apply config-only wins + re-measure

**Scope:** Config changes, no refactor. Each is independently reversible.

**Candidates (apply each, re-run cold + warm-incremental + warm-noop after each, keep if it helps):**

1. **Parallel test execution** — `-parallel-testing-enabled YES -parallel-testing-worker-count 4` (tune count based on cores). Typically 2–3× speedup on XCTest execute when there are many test classes and no shared-state contention. Verify no flakiness.
2. **Disable code coverage** unless a task needs it — `-enableCodeCoverage NO`. Often 10–30% speedup when coverage would otherwise be on (check scheme default; Xcode's default varies).
3. **Persistent `-derivedDataPath`** for agent runs — `-derivedDataPath .build/xcode-derived`. Avoids DerivedData thrash between agent/IDE switching. Adds to `.gitignore`.
4. **`-skipPackagePluginValidation`** — trivial if applicable.
5. **Scheme-level optimisation for tests** — `-configuration Debug` typically right; confirm the test scheme doesn't unnecessarily build Release.
6. **Disable `-enableAddressSanitizer` / `ThreadSanitizer`** if on by default for the test scheme. They slow execution substantially.

**Steps:**
- Apply each candidate independently. Measure. Keep only the ones that helped, dropping any that introduced flakiness.
- Capture per-candidate numbers in `.claude/state/test-perf-baseline.md` under a **Config Wins** section.
- Update `scripts/measure-test-time.sh` (written in Task 7) to use the kept flags.
- For persistent project/scheme settings, prefer editing [project.yml](/Users/maxwilliams/dev/sequencer-ai/project.yml) and regenerating with `xcodegen generate` rather than hand-editing the generated `.xcodeproj`.

**Acceptance:**
- At least the three config flags applied and re-measured.
- Baseline doc shows pre/post wall-clock per candidate.

- [ ] Apply + measure each candidate
- [ ] Keep the winners; revert losers
- [ ] Commit (may be several commits): `perf(test): <flag> reduces warm run from X to Y`

---

## Task 5: Identify low-hanging test-execution hotspots

**Scope:** Given per-test-class data from Task 3, surface the 1–2 classes that obviously waste time (slow setUp/tearDown, redundant fixtures, sleeps for async). Don't fix — just surface.

**Steps:**
- For each top-5 slowest class, grep for: `sleep`, `Task.sleep`, large-literal fixture construction, `JSONDecoder()` instantiation inside a loop, `XCTestCase.addTeardownBlock` patterns.
- Write findings to `.claude/state/test-perf-followup-findings.md`.
- Do NOT write fixes. Each is a candidate for a fix-critique task.

**Acceptance:**
- Followup findings doc lists concrete test:line pointers with one-liner on the suspected hotspot cause.

- [ ] Grep + document
- [ ] Commit: `chore(perf): surface test-execution hotspots`

---

## Task 6: Structural decision

**Scope:** With measured baseline + config-win numbers + hotspot list in hand, decide: *does a structural refactor pay off?*

**Decision framework:**

| Observation | Recommendation |
|---|---|
| Total warm-incremental < 30s after config wins | **Stop here.** Good enough for plan execution. |
| Compile time > 2× execute time | Candidate: SPM logic-only split (Document / Musical / Engine as `swift test`-able package; `swift test` is 5–10× faster than `xcodebuild test`). Write a `logic-package-split` plan. |
| Execute time dominates; 2–3 test classes own > 50% of it | Candidate: fix-critique the hotspots inline; no structural plan needed. |
| UI target compile is most of the time | Candidate: test-target slicing (UI tests in their own scheme; plans specify `-scheme SequencerAIDocumentTests` vs `-scheme SequencerAIUITests` per task). |
| No dominant pattern, just broad 20% speedup available | **Stop.** Config wins are it. |

Write the recommendation (with the data that supports it) to `.claude/state/test-perf-followup-findings.md` under a **Decision** section. If a structural plan is warranted, draft a one-page spec for it in `docs/plans/` (can be a stub with `Status: DRAFT`).

**Acceptance:**
- Decision section written and committed.
- If a follow-up plan is warranted, its stub file exists and is linked.

- [ ] Make the call based on data
- [ ] Write decision + (optional) follow-up plan stub
- [ ] Commit: `docs(perf): test performance decision and (optional) follow-up plan`

---

## Task 7: Reproducible measurement script

**Scope:** Pack the measurement protocol into `scripts/measure-test-time.sh` so future plans / humans can rerun and compare. Uses the config wins from Task 4. Emits a markdown summary block to stdout that can be pasted into a status update.

**Files:**
- Create: `scripts/measure-test-time.sh`
- Update: `.gitignore` — `.claude/state/perf-raw/`, `.build/xcode-derived/`

**Script behaviour:**
- Three modes: `--cold` (clean + test), `--warm` (test only), `--compare <ref>` (compare against a previously-committed baseline).
- Writes raw logs to `.claude/state/perf-raw/<timestamp>/`.
- Writes a markdown summary to stdout and to `.claude/state/test-perf-latest.md`.

**Acceptance:**
- Running `bash scripts/measure-test-time.sh --warm` in a clean worktree produces the same numbers recorded in the baseline doc (± 10%).

- [ ] Write script
- [ ] Verify reproducibility
- [ ] Commit: `feat(scripts): reproducible measure-test-time`

---

## Task 8: Per-task test-filter convention for plans

**Scope:** If Task 6's decision is "keep things as they are" or "slice targets," update plan-writing convention so future plan tasks specify `-only-testing:` filters instead of defaulting to full-suite. Saves 10–30× on per-task verification cost for single-module changes.

**Files:**
- Modify: `AGENTS.md` — add a concrete "test-filter rule": a task that modifies only `Sources/Document/**` runs a focused `-only-testing:` slice; full-suite only on the plan's final verify task.
- Modify: `.claude/skills/execute-plan/SKILL.md` (and any other actually-used execution skill if needed) so plan execution inherits the same per-task filter convention instead of defaulting to the full suite every time.

**Acceptance:**
- Documented rule, one example.

- [ ] Document convention in the real repo guidance files (`AGENTS.md`, then the execution skill if needed)
- [ ] Commit: `docs(plan): per-task xcodebuild test-filter rule`

---

## Task 9: Close

- [ ] Replace `- [ ]` with `- [x]` for completed steps
- [ ] Add `Status:` line after Parent spec
- [ ] Commit: `docs(plan): mark test-performance-investigation completed`
- [ ] Tag (optional; infrastructure): if tagging, `git tag -a vX.Y.Z-test-perf -m "Test-time baseline recorded; config wins applied; structural decision made"`

---

## Goal-to-task traceability

| Goal | Task |
|---|---|
| Know baseline | 1 |
| Know compile vs execute split | 2 |
| Know per-class time distribution | 3 |
| Apply cheap config wins | 4 |
| Surface hotspots (don't fix) | 5 |
| Make structural decision with data | 6 |
| Reproducible measurement | 7 |
| Plan-writing convention for filters | 8 |

## Stop conditions (don't pull this thread forever)

- **Task 1 cold time < 60s:** plan is done after Task 1. Record result, close.
- **Task 4 config wins halve the time:** Tasks 5–6 are still worth ~15 min, but Task 8 (filter convention) alone probably yields the next-biggest improvement for overnight loops.
- **Cumulative time on this plan > 1 day:** stop. Write up whatever's measured, make the decision with whatever data exists, and either ship as-is or explicitly defer the follow-up.

## Open questions

- **Does the project already use xcbeautify or similar?** Check before writing custom parsing; a pretty printer might already exist and may have timing extraction built in.
- **Is `swift test` viable for Document-only on current code?** The module currently compiles against Xcode's SDK but Document theoretically doesn't import Apple-specific frameworks (per earlier reconnaissance). Quick spike: `swift build --target Document` (requires an SPM shim). If it compiles, SPM logic-only split is 1-day effort for a likely 5–10× test-time win on logic changes. Task 6 decision point.
- **Parallel-test flakiness.** Any shared `UserDefaults`, `FileManager`-based test harness, or singleton state across test classes will flake under `-parallel-testing-enabled`. If flakes surface in Task 4, the cost is investigating test isolation; skip the flag and note the blocker in followup-findings.
- **Does `xcresulttool` have a stable JSON output shape across Xcode minor versions?** If not, `parse-xcresult-timings.sh` needs a version pin comment.
