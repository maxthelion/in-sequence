# observability-log-issues

- loop: `build/observability-log-issues`
- status: locked; not consuming an ordinary autonomous build slot while scope is corrected
- branch: `auto/roadmap-21-observability-log-issues`
- worktree: `.worktrees/roadmap-21-observability-log-issues`
- created: 2026-06-07T18:52:15Z
- base commit: `c9962f5825240028e22d74e40bb68d5bc2d0c217`
- feature: `observability-log-issues`
- source PM loop: `pm/observability-log-issues`
- authoritative PM handoff:
  `docs/roadmap/observability-log-issues/implementation-handoff.md`
- authoritative accepted plan:
  `docs/roadmap/observability-log-issues/plan.md`
- authoritative accepted spec:
  `docs/roadmap/observability-log-issues/spec.md`
- authoritative architecture:
  `docs/roadmap/observability-log-issues/architecture.md`
- promotion decision:
  `.meta/multipass/runtime/loops/project/decide/2026-06-07T18-04Z-observability-build-promotion-route.md`
- setup evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-07T18-52Z-observability-log-issues-build-loop-setup.md`
- initial builder request:
  `.meta/multipass/runtime/inbox/done/2026-06-07T185215000Z-Observability-Log-Issues-Phase-0-build-identity-diagnostics-bootstrap.md`
  (created in `pending`; claimed and completed by the runtime after setup)

This is the durable build-loop summary. Transient inboxes, runs, and evidence
live under `.meta/multipass/runtime/loops/build/observability-log-issues/`.

## Compact Build Intent

Observability From Application Logs v1 is a local, app-owned diagnostics to
candidate pipeline. The accepted product direction is queue-first review with
visible build identity, typed diagnostic events, Application Support storage,
redaction before durable issue output, fingerprinted duplicate collapse,
suppression audit, honest provenance, route confidence, and local markdown
review candidates.

The first bounded builder slice is intentionally narrower than the full v1
pipeline:

- move or expose `BuildIdentity` under `Sources/Diagnostics/`;
- preserve existing build metadata stamping through `Info.plist`,
  `project.yml`, and `scripts/open-latest-build.sh`;
- keep or add an always-available visible build identity surface;
- extend Application Support bootstrap with diagnostics subfolders;
- add typed diagnostics storage paths, event envelope, facade, and writer;
- emit one typed launch diagnostic event from `SequencerAIAppDelegate` carrying
  the same build identity shown in the UI;
- prove no `.seqai` document writes and no live playback data-path dependency.

Do not implement the collector, redactor, fingerprint ledger, suppression
policy, route-confidence policy, local markdown review writer, external issue
creation, global Console scraping, in-app dashboard, playback/runtime mutation,
merge, rebase, push, or request lifecycle edits in the first slice.

## Scope Correction / Parked State

Parked on 2026-06-08T14:37:54Z after product-owner review of the feature's
fit with the current OODA loop.

The useful direction is app-side diagnostic evidence for the existing
project-loop `log-observer`: visible build identity, commit/branch/build
attribution, redacted diagnostic events, local storage, and failure emissions
for app launch, bootstrap, playback, and runtime problems. The project
`log-observer` should read that evidence and write observations; the project
orienter and decider should decide what work follows.

The risky direction is a parallel in-app issue candidate / review workflow
that duplicates `.meta/multipass` observations, `runtime-problems.md`, and the
top-loop OODA path. Do not continue building candidate-review behavior until a
revised plan states how it remains only evidence input for OODA, not a second
coordination system.

Current checkpoint `714fdb8` may still be useful as implementation material,
but further autonomous work is paused. Before unlocking, produce a compact
scope-correction note that answers:

- which app diagnostic events and attribution fields remain necessary;
- which candidate/review-writer pieces should be kept, simplified, or removed;
- how the top-loop `log-observer` will consume the resulting files;
- what exact builder slice should run next, if any.

The feature worktree currently contains interrupted uncommitted material from
the 2026-06-08T13:55Z pipeline-wiring builder attempt. Treat this as preserved
scratch, not reviewed output:

- `Sources/App/SequencerAIApp.swift`
- `Sources/App/SequencerAIAppDelegate.swift`
- `Sources/Diagnostics/AppDiagnosticEvent.swift`
- `Sources/Diagnostics/AppDiagnostics.swift`
- `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift`
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticEventTests.swift`
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticsTests.swift`

If the loop is resumed, first decide whether to keep, simplify, or discard
that partial against the scope-correction note above. Do not assume it has
passed tests or architecture review.

## Setup State

The loop container uses the requested branch/worktree names:

- branch: `auto/roadmap-21-observability-log-issues`
- worktree: `.worktrees/roadmap-21-observability-log-issues`
- base commit: `c9962f5825240028e22d74e40bb68d5bc2d0c217`

No product code has been implemented by the project-loop process-fixer setup.

Root `main` had broad pre-existing unrelated dirty state at setup time. The
accepted Observability PM docs were visible in the root checkout, but several
accepted PM files were untracked root coordination/doc dirt when the build
worktree was created. This process-fixer did not move or copy that dirty state
into the new worktree. The initial builder request explicitly requires a
PM-doc visibility check from the build worktree and a compact blocker before
implementation if the accepted files are absent there.

## Current Orientation

Fresh orientation:
`.meta/multipass/runtime/loops/build/observability-log-issues/orient/2026-06-08T14-38Z-build-orienter-progress.md`.

PM authority visibility repair remains valid:
`.meta/multipass/runtime/loops/project/act/2026-06-07T19-05Z-observability-pm-authority-visibility-repair.md`.

Latest committed feature checkpoint remains:

- branch: `auto/roadmap-21-observability-log-issues`
- worktree: `.worktrees/roadmap-21-observability-log-issues`
- HEAD: `714fdb8be29385d76737db53fc6dcd48826d5df5`
- HEAD meaning: completed local review-candidate writer builder checkpoint with
  exact-state builder, architecture, testing, UX/IA, and visual-economy
  evidence for that checkpoint only
- dirty state: dirty after failed pipeline wiring builder run

Committed checkpoint `714fdb8` changed:

- `SequencerAI.xcodeproj/project.pbxproj`
- `Sources/Diagnostics/IssueCandidateReviewWriter.swift`
- `Tests/SequencerAITests/Diagnostics/IssueCandidateReviewWriterTests.swift`

Current dirty partial output changes:

- `Sources/App/SequencerAIApp.swift`
- `Sources/App/SequencerAIAppDelegate.swift`
- `Sources/Diagnostics/AppDiagnosticEvent.swift`
- `Sources/Diagnostics/AppDiagnostics.swift`
- `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift`
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticEventTests.swift`
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticsTests.swift`

Root `main` has broad unrelated dirty state, but the named feature worktree is
the output authority for this loop.

The 2026-06-08T13:55Z builder request attempted the next bounded v1 slice:
pipeline wiring plus first high-value launch/lifecycle/bootstrap emissions.
That run failed before its final artifact with `usage_rate_limit` and `SIGTERM`:
`.meta/multipass/runtime/runs/actors/builder/2026-06-08T135543774Z-Observability-pipeline-wiring-and-first-emissions-slice.failure.md`.

The blocked request now lives at:
`.meta/multipass/runtime/inbox/blocked/2026-06-08T135543774Z-Observability-pipeline-wiring-and-first-emissions-slice.md`.

The dirty diff appears to add typed lifecycle/bootstrap event constructors,
`AppDiagnostics` lifecycle/bootstrap helpers, a local
`DiagnosticIssueCandidatePipeline`, app delegate lifecycle emissions,
app-support/sample-library bootstrap failure emissions, and focused tests. It
is 7 files, 353 insertions, 1 deletion. `git diff --check` passes for the dirty
worktree, but that is only lightweight hygiene evidence.

Paired gate evidence remains valid for previous commit `714fdb8` only. The
2026-06-08T13:40Z retry exact-state observation batch for `714fdb8` completed
all four observer runs after the earlier 05:43Z batch had been blocked by
`usage_rate_limit`:

- architecture: `pass` in
  `.meta/multipass/runtime/runs/actors/architecture-review/2026-06-08T134143234Z-retry-exact-state-review-for-Observability-IssueCandidateReviewWriter-checkpoint-714fdb8.final.md`;
- testing: `testing-pass` in
  `.meta/multipass/runtime/loops/build/observability-log-issues/observe/testing-review/2026-06-08T13-46Z-issue-candidate-review-writer-checkpoint.md`;
- UX/IA: `pass` in
  `.meta/multipass/runtime/loops/build/observability-log-issues/observe/ux-ia-review/2026-06-08T1349Z-issue-candidate-review-writer-checkpoint.md`;
- visual economy: `pass` in
  `.meta/multipass/runtime/loops/build/observability-log-issues/observe/visual-economy-review/2026-06-08T1348Z-issue-candidate-review-writer-checkpoint.md`.

Paired builder evidence for exact checkpoint `714fdb8`:

- builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-08T052653052Z-builder.final.md`
- builder-recorded checks:
  - `IssueCandidateReviewWriterTests`, `ObservedIssueLedgerTests`, and
    `DiagnosticPolicyTests`: passed 18 tests
    with 0 failures;
  - `git diff --check` passed;
  - source guard found no `.seqai`, project-document, playback/audio/MIDI/live
    runtime, external issue, Console, dashboard, or raw-private persistence
    dependency.

The builder final also records sample fixture evidence for
`diagnostics/review/candidates/fingerprint-engine-failure.md`, including
redacted-only evidence, privacy checklist text, `Confidence: high`, and
unclaimed introduced-by behavior.

Current missing or insufficient evidence:

- no builder final exists for the current dirty pipeline wiring pass;
- no new commit exists for the dirty partial output;
- no loop-local `act/` completion artifact exists for the current pass;
- no focused `xcodebuild` result exists for the new pipeline/lifecycle/bootstrap
  tests;
- no required sample local evidence exists showing a typed launch, lifecycle, or
  bootstrap event flowing through the local diagnostics path to a redacted
  candidate draft at policy threshold;
- no current source guard evidence exists beyond lightweight orienter
  inspection and `git diff --check`;
- no exact-state architecture, testing, UX/IA, or visual-economy gate evidence
  exists for the dirty partial output;
- retry exact-state observation batch for `714fdb8` is still marked
  `status: open` even though all four observer runs completed:
  `.meta/multipass/runtime/loops/build/observability-log-issues/observe/batches/1780926102273-Observability-IssueCandidateReviewWriter-checkpoint-714fdb8-exact-state-review-retry-2026-06-08T13-40Z/batch.yaml`;
- whole-feature v1 evidence remains missing for wiring local candidate writing
  into the diagnostics pipeline, external issue creation policy/workflow if
  still accepted, and any future user-facing diagnostics review surface or
  dashboard;
- no merge-readiness review exists for the whole feature.

Potential implementation ambiguity for the recovery builder to resolve: the
partial diff adds `processCurrentIssueCandidates()` and tests the pipeline
directly, but inspected production call sites do not yet show automatic
candidate processing after event emission. That may be intentional bounded
scope or unfinished output; it should be resolved before claiming the requested
"flow through the local diagnostics path" evidence.

Lowest unmet pyramid layer: current partial implementation completion and
paired evidence. The previous writer checkpoint is reviewed, but the current
output is dirty and uncommitted after a failed builder run.

Architecture risk severity: caution for the dirty partial state. The apparent
direction is still diagnostics-local and does not visibly introduce document,
playback, audio/MIDI, live-runtime, external tracker, Console, dashboard, or
raw-private durable persistence dependencies. However, the partial output
touches app bootstrap/lifecycle paths and the diagnostics pipeline without a
builder final, tests, sample output, or architecture review. No line-stop is
recommended from available evidence.

Latest build-decider action:
`.meta/multipass/runtime/loops/build/observability-log-issues/decide/2026-06-08T13-55Z-pipeline-wiring-first-emissions-builder-pass.md`
accepted the reviewed `714fdb8` `IssueCandidateReviewWriter` checkpoint as a
phase checkpoint and scheduled continuation to the next bounded v1 slice.

Latest observation batch:
`.meta/multipass/runtime/loops/build/observability-log-issues/observe/batches/1780926102273-Observability-IssueCandidateReviewWriter-checkpoint-714fdb8-exact-state-review-retry-2026-06-08T13-40Z/batch.yaml`.

Latest builder request:
`.meta/multipass/runtime/inbox/blocked/2026-06-08T135543774Z-Observability-pipeline-wiring-and-first-emissions-slice.md`.

Latest builder final:
No final exists for the latest builder run. Latest completed builder final
remains `.meta/multipass/runtime/runs/actors/builder/2026-06-08T052653052Z-builder.final.md`
for previous commit `714fdb8`.

Next action kind: builder failure recovery and continuation in the existing
feature worktree. The next builder should preserve, complete, or replace the
dirty partial output, then leave a committed checkpoint with the required
focused tests, `git diff --check`, sample candidate evidence, and source guard.
Review should wait until that exact state exists. This is not merge candidacy,
whole-feature completion, top-level escalation, or product-owner attention.
