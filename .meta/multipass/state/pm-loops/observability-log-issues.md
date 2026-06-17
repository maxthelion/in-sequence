# Observability Log Issues PM Loop

- updated: 2026-06-07T18:45Z
- loop: `pm/observability-log-issues`
- status: active; PM-ready hold; no further PM artifact action routed
- feature: `observability-log-issues`
- backlog item: 21
- registry manifest:
  `.meta/multipass/config/loops/pm/observability-log-issues.yaml`
- runtime root:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/`
- authoritative product docs: `docs/roadmap/observability-log-issues/`
- latest observation:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/observe/2026-06-07T17-05Z-pm-readiness-observation.md`
- latest orientation:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/orient/2026-06-07T18-42Z-pm-orientation.md`
- latest decision:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/decide/2026-06-07T18-45Z-pm-decision.md`
- latest handled inbox request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-07T174545616Z-pm-artifact-author.md`
- latest action evidence:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/act/2026-06-07T17-49Z-observability-plan-handoff.md`
- setup evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-07T17-02Z-observability-log-issues-pm-loop-setup.md`

## Current Interpretation

Observability From Application Logs remains an upstream PM-buffer lane with
the PM planning layer complete. It has accepted prototype direction,
builder-facing architecture/spec policy, an implementation plan, and an
implementation handoff for the log-to-issue event pipeline. It is ready for
build-loop promotion as PM scope when project capacity and decider routing
choose it.

The lane exists to turn runtime application logs into actionable, deduplicated,
privacy-conscious issue candidates with honest provenance. This supports the
README product spirit by making live-review failures recoverable and
inspectable without disrupting the instrument workflow or flooding automation
with noisy issues.

The accepted product direction is queue-first review: scan fingerprints first,
inspect a generated issue draft second, then create, suppress, or triage with
visible provenance and routing confidence.

## Artifact State

Authoritative product-doc artifacts under
`docs/roadmap/observability-log-issues/` now include:

- `README.md`: roadmap item 21, stage `implementation-handoff`, status text
  refreshed on 2026-06-07 to reflect accepted prototype direction, visible
  build identity requirement, and PM build-loop readiness.
- `notes.md`: raw and clarified product notes for collecting application logs,
  parsing structured events, fingerprinting repeats, attaching provenance, and
  routing actionable signals.
- `user-stories.md`: stories and acceptance signals for log collection,
  structured events, duplicate collapse, issue thresholding, commit provenance,
  routing, reproduction context, and privacy protection.
- `existing-state.md`: implementation/process inventory from 2026-05-03;
  current logging is ad-hoc, no collector or local issue ledger exists, and
  app builds do not yet reliably embed git SHA, branch, timestamp, or dirty
  state.
- `ux-review.md`: accepted prototype direction with queue-first triage as the
  primary flow and issue-draft review/privacy gate as the second step.
- `feedback/2026-06-06-visible-build-identity-for-review.md`: product-owner
  feedback requiring visible commit/branch/dirty/build identity for useful
  runtime review and attribution.
- `architecture.md`: accepted builder-facing policy for authoritative source,
  collector boundary, typed event envelope, local ledger, build identity,
  provenance, redaction, suppression, thresholds, and route confidence.
- `spec.md`: spec-ready-for-plan requirements for build identity, facade,
  collector, redaction, ledger, fingerprinting, thresholds, suppression,
  provenance, routing, review output, states, and tests.
- `plan.md`: accepted implementation plan choosing Application Support
  diagnostics storage, exact Swift modules/files, tests, migration order, local
  markdown candidate output, and review gates.
- `implementation-handoff.md`: builder-ready handoff with first bounded slice,
  target seams, required exit evidence, stop conditions, and build-loop
  boundary.

Missing builder-facing PM artifacts: none known.

## Architecture And Spec Policy Now Locked

The new policy establishes:

- one authoritative runtime evidence source per event, preferably app-owned
  structured diagnostics under Application Support for v1;
- a shared diagnostics facade and typed `AppDiagnosticEvent`-style envelope as
  the durable app contract, with legacy `NSLog`/`Logger` compatibility adapters
  treated as lower confidence;
- a local fingerprint/issue ledger as the first durable issue state, with
  atomic/reviewable persistence and no project-document writes;
- build metadata stamping for commit SHA, branch, dirty state, timestamp,
  build attribution id, app version, bundle build number, and source channel;
- visible build identity in the app, preferably window title or compact
  always-available debug/status surface;
- conservative provenance fields: `observedIn`, `firstSeenIn`, `lastSeenIn`,
  optional evidence-backed `introducedBy`, confidence, and evidence note;
- redaction before ledger persistence, evidence excerpts, or external issue
  creation;
- suppression with reason, actor/reviewer, timestamp, expiry/permanence,
  matching scope, and reopen conditions;
- thresholds for immediate candidates, recurrence candidates, observations,
  suppressed events, and collector-health failures;
- explicit active-worker, sweeper, and human-triage routing with confidence and
  evidence notes.

## Lowest Unmet PM Layer

Lowest unmet layer: none known for PM artifact readiness.

The 2026-06-07T17:49Z PM artifact action authored the implementation plan and
implementation handoff. The 2026-06-07T18:45Z PM decision intentionally routed
no new PM artifact-author request because additional PM authoring would
duplicate settled roadmap work. The lane can be promoted by a future
project-level decider without needing product-owner judgment or more PM
artifact authoring first.

Latest orientation:
`.meta/multipass/runtime/loops/pm/observability-log-issues/orient/2026-06-07T18-42Z-pm-orientation.md`.

Latest decision:
`.meta/multipass/runtime/loops/pm/observability-log-issues/decide/2026-06-07T18-45Z-pm-decision.md`.

Handled PM artifact-author request:
`.meta/multipass/runtime/inbox/claimed/2026-06-07T174545616Z-pm-artifact-author.md`.

Latest PM artifact-author action:
`.meta/multipass/runtime/loops/pm/observability-log-issues/act/2026-06-07T17-49Z-observability-plan-handoff.md`.

## Product-Owner Decision Needs

No immediate product-owner attention is needed.

Current artifacts already accept the queue-first prototype direction, and the
2026-06-06 product-owner feedback gives a clear visible-build-identity
requirement. The plan and handoff make conservative implementable choices for
storage, retention, local review output, and first builder slice without
blocking on human judgment.

Possible future product-owner questions after the local pipeline exists:

- retention duration for redacted evidence excerpts and suppression audit;
- whether the first review surface should be in-app, local markdown, or
  coordinator-side only;
- how visible build identity should appear if the window title becomes crowded.

## Promotion Readiness

Ready for build-loop promotion as PM scope.

Reason: architecture, spec, plan, and implementation handoff are now present.
The handoff constrains implementation to a feature worktree, starts with build
identity plus app-owned diagnostics source and typed launch event, and requires
tests, visual identity evidence, sample local pipeline artifacts, architecture
review, and privacy review before completion.

The 2026-06-07T17:39Z feature-readiness snapshot still says Observability is
not ready because `plan.md` and `implementation-handoff.md` were missing at
that time. Prefer this PM summary, the 2026-06-07T17:49Z PM action evidence,
and the 2026-06-07T18:42Z PM orientation for current PM readiness.

## Routing Boundary

Use `pm/observability-log-issues` for PM observation, orientation, decisions,
and bounded roadmap artifact authoring only. Keep work on `main` in root
coordination state and the authoritative product-doc directory
`docs/roadmap/observability-log-issues/`.

Do not route implementation, review, integration, merge, rebase, push,
worktree deletion, product-code edits, runtime request lifecycle changes, or
build-loop promotion from this summary.

## Evidence Freshness

- PM readiness observation:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/observe/2026-06-07T17-05Z-pm-readiness-observation.md`.
- PM orientation:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/orient/2026-06-07T18-42Z-pm-orientation.md`.
- Project orientation:
  `.meta/multipass/state/ooda/orientation.md` updated 2026-06-07T18:00Z
  identifies Observability as the only fresh builder-ready PM candidate by
  artifact evidence and flags the capacity/readiness helper output as stale.
- Feature readiness:
  `.meta/multipass/state/feature-readiness.md` updated 2026-06-07T17:39Z
  predates the 17:49Z implementation handoff and should not be used as the
  current Observability PM artifact verdict.
- PM decision:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/decide/2026-06-07T18-45Z-pm-decision.md`.
- PM artifact-author request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-07T174545616Z-pm-artifact-author.md`.
- PM artifact-author action:
  `.meta/multipass/runtime/loops/pm/observability-log-issues/act/2026-06-07T17-49Z-observability-plan-handoff.md`.
- Project decision that set up this PM lane:
  `.meta/multipass/runtime/loops/project/decide/2026-06-07T16-49Z-observability-pm-setup-route.md`.
- Setup evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-07T17-02Z-observability-log-issues-pm-loop-setup.md`.

## Checks Run

- Read the 2026-06-07T18:40Z PM orienter request, root README.md, PM loop
  manifest, latest PM readiness observation, prior PM orientation/decision,
  latest PM action evidence, existing durable PM summary, project orientation,
  current-work, holistic status, feature-readiness, and current lane
  README/plan/handoff artifacts.
- Read the 2026-06-07T18:40Z PM decider request, root README.md, PM loop
  manifest, latest PM orientation, durable PM summary, prior PM decision,
  current lane README, and implementation handoff.
- Ran coordinator inventory:
  `bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/inventory.ts --project /Users/maxwilliams/dev/in-sequence`.
- Wrote the 2026-06-07T18:42Z loop-local PM orientation and refreshed this
  durable PM summary.
- Wrote the 2026-06-07T18:45Z loop-local PM decision and refreshed this
  durable PM summary.
- No inbox request, request lifecycle move, product-doc edit, product-code
  edit, build-loop manifest, branch, worktree, merge, rebase, push, worktree
  deletion, test, or visual capture was performed.
