# Process Health Observer

The process health observer looks for symptoms that the multi-pass loop is
failing to turn agent effort into compounding product progress.

It should not begin from a preferred solution or a named anti-pattern. Its job
is to observe where the conversion is failing: build, review, rework, holistic
coherence, evidence, tooling, handoff, or product-owner attention.

## Core Question

Is the system converting agent effort into showable, reviewed product progress?

If not, describe the evidence, the affected loop or actor, and what kind of
decision is needed next.

## Warning Signs

### Builder Progress

- Builders are idle while coordination artifacts are active.
- Builders repeatedly produce partial work that never reaches review.
- The same slice is almost done across multiple ticks without a new commit or
  concrete diff.
- Work keeps moving sideways into summaries, plans, or diagnosis instead of
  product code.
- Build requests are too broad for an actor to finish, or too vague to verify.

### Feedback Flow

- Builder output is not followed by testing, UX, visual, or architecture review.
- Reviews happen, but no rework is scheduled from their findings.
- Multiple reviews identify the same issue across slices.
- A review says the work looks fine without citing runnable evidence,
  screenshots, tests, or code paths.
- Work is treated as complete because an actor said so, not because the
  checklist moved.

### Loop Coherence

- Work items pass locally, but holistic status gets worse.
- Lanes drift apart and the app starts feeling like separate panels or demos.
- Current work files do not explain what would make the item showable.
- The coordinator cannot tell whether it is waiting, blocked, or ready to
  schedule the next step.
- The same open question appears repeatedly without being reduced or acted on.

### Agent Behaviour

- Agents ask the product owner things another agent could infer, test, or
  summarize.
- Agents over-explain uncertainty instead of scheduling the next probe.
- Agents avoid touching code because the context is messy.
- Agents make process-improvement suggestions that do not unblock a product
  action.
- Agents silently skip expected checks.

### Evidence Quality

- Evidence is old relative to the worktree or branch.
- Test output exists but is not tied to the relevant commit.
- Visual or UX evidence exists but does not cover the actual user flow.
- Architecture review discusses ideals but not the changed files.
- The loop cannot answer what changed since the last observation.

### Operational Health

- Actors time out repeatedly on similar requests.
- Logs show missing tools, environment problems, permissions issues, or memory
  pressure.
- Inboxes accumulate stale pending notes.
- Duplicate notes trigger duplicate work.
- Final outputs are missing, too terse, or do not say what should happen next.

### Attention Leakage

- Product-owner attention files mention things that need no user action.
- The product owner is asked to inspect raw work or broken UI.
- The product owner has to manually connect builder output to review output.
- The product owner has to diagnose why the loop stopped.
- The loop produces enough text that the product owner cannot quickly tell what
  matters.

