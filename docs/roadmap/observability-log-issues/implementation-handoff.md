---
feature: observability-log-issues
created: 2026-06-07
status: ready-for-build-loop-promotion
sources:
  - README.md
  - docs/roadmap/observability-log-issues/architecture.md
  - docs/roadmap/observability-log-issues/spec.md
  - docs/roadmap/observability-log-issues/plan.md
  - docs/roadmap/observability-log-issues/existing-state.md
  - docs/roadmap/observability-log-issues/ux-review.md
  - docs/roadmap/observability-log-issues/feedback/2026-06-06-visible-build-identity-for-review.md
  - docs/roadmap/observability-log-issues/prototypes/01-log-inbox-routing.html
  - docs/roadmap/observability-log-issues/prototypes/02-issue-draft-review.html
---

# Observability From Application Logs Implementation Handoff

## Builder Boundary

Implement Observability From Application Logs v1 as a local app-owned
diagnostics-to-candidate pipeline:

- visible and stamped build identity;
- typed diagnostic event envelope and shared facade;
- app-owned structured event stream under Application Support;
- collector validation and collector-health observations;
- redaction before persistence;
- fingerprint ledger with thresholds, suppression, provenance, and route
  confidence;
- local markdown review candidates for queue-first inspection.

Do not broaden the build into external issue creation, global Console
scraping, a full in-app observability dashboard, automatic blame assignment,
project-document diagnostics persistence, or playback/runtime mutation.

## Branch And Worktree Expectations

A future build loop should happen in a feature worktree, not as product-code
dirt on `main`. Unless the decider chooses a different conventional name, use:

- build loop id: `build/observability-log-issues`;
- branch: `auto/roadmap-21-observability-log-issues`;
- worktree: `.worktrees/roadmap-21-observability-log-issues`;
- build-loop evidence root:
  `.meta/multipass/runtime/loops/build/observability-log-issues/`.

This PM lane does not create the build-loop manifest, branch, worktree, inbox
request, merge, rebase, push, or runtime lifecycle move.

## Source Of Truth

Use these PM artifacts in order:

1. `architecture.md` for pipeline invariants, privacy/provenance policy,
   collector boundary, and review-flow decisions.
2. `spec.md` for accepted requirements, states, thresholds, and tests.
3. `plan.md` for storage root, target files, implementation sequence, and
   review gates.
4. `ux-review.md` plus accepted prototypes for queue-first review intent and
   privacy/provenance language.
5. `feedback/2026-06-06-visible-build-identity-for-review.md` for the
   non-negotiable visible build identity requirement.

Settled v1 choices:

- authoritative source:
  `~/Library/Application Support/sequencer-ai/diagnostics/events/current.ndjson`;
- local ledger:
  `~/Library/Application Support/sequencer-ai/diagnostics/issues/ledger.json`;
- redacted evidence root:
  `~/Library/Application Support/sequencer-ai/diagnostics/issues/evidence/`;
- first review output:
  `~/Library/Application Support/sequencer-ai/diagnostics/review/candidates/<fingerprint>.md`;
- persistence format: deterministic JSON or NDJSON with atomic replacement
  where records are rewritten;
- first UI proof: visible build identity in the main window/top-bar or another
  always-available debug/status surface;
- external tracker writes: out of scope.

## First Bounded Builder Slice

Start with build identity, diagnostics storage bootstrap, and one typed launch
event.

The first builder request should:

- move or expose `BuildIdentity` from
  `Sources/App/SequencerAIAppDelegate.swift` into
  `Sources/Diagnostics/BuildIdentity.swift`;
- preserve `Info.plist`, `project.yml`, and `scripts/open-latest-build.sh`
  stamping for commit, branch, dirty state, attribution id, attribution
  version, app version, and bundle build number;
- keep the visible build identity badge in `Sources/UI/StudioTopBar.swift` or
  add an equivalent always-available surface if the current worktree lacks it;
- extend `Sources/Platform/AppSupportBootstrap.swift` with diagnostics
  subfolders;
- add `DiagnosticStoragePaths`, `AppDiagnosticEvent`, `AppDiagnostics`, and
  `DiagnosticEventWriter` under `Sources/Diagnostics/`;
- emit one typed launch diagnostic event from `SequencerAIAppDelegate` carrying
  the same build identity shown in the UI;
- prove no `.seqai` document writes and no live playback data-path dependency.

Stop this slice after focused tests and review evidence. Do not implement the
collector, ledger, review markdown writer, or log migration until the source
contract and visible identity are reviewed.

## Subsequent Builder Slices

Continue in this order after the first slice is reviewed:

1. Add collector validation and collector-health observations over the
   app-owned NDJSON event stream.
2. Add redaction before persistence, with coverage for paths, document names,
   sample/media names, user text, credentials, MIDI labels, and plugin labels.
3. Add fingerprinting and `ObservedIssueLedger` with deterministic atomic JSON
   persistence under `diagnostics/issues/ledger.json`.
4. Add threshold, suppression, provenance, and routing policy. Keep
   `introducedBy` blank unless evidence supports it.
5. Add `IssueCandidateReviewWriter` for local markdown drafts under
   `diagnostics/review/candidates/`.
6. Migrate first high-value emissions: app lifecycle/bootstrap failures,
   selected engine setup/shutdown/apply failures, AU window preparation
   timeout, preset stepping failures, and preset load failures.
7. Produce sample local evidence: launch event, redacted ledger record, and
   markdown candidate draft.

## Target Seams

New files:

- `Sources/Diagnostics/BuildIdentity.swift`;
- `Sources/Diagnostics/AppDiagnosticEvent.swift`;
- `Sources/Diagnostics/AppDiagnostics.swift`;
- `Sources/Diagnostics/DiagnosticStoragePaths.swift`;
- `Sources/Diagnostics/DiagnosticEventWriter.swift`;
- `Sources/Diagnostics/DiagnosticCollector.swift`;
- `Sources/Diagnostics/DiagnosticRedactor.swift`;
- `Sources/Diagnostics/DiagnosticFingerprint.swift`;
- `Sources/Diagnostics/ObservedIssueLedger.swift`;
- `Sources/Diagnostics/DiagnosticPolicy.swift`;
- `Sources/Diagnostics/IssueCandidateReviewWriter.swift`.

Existing files:

- `Sources/Resources/Info.plist`;
- `project.yml`;
- `scripts/open-latest-build.sh`;
- `Sources/Platform/AppSupportBootstrap.swift`;
- `Sources/App/SequencerAIApp.swift`;
- `Sources/App/SequencerAIAppDelegate.swift`;
- `Sources/UI/StudioTopBar.swift`;
- `Sources/Engine/EngineController.swift`;
- `Sources/Engine/Executor.swift`;
- `Sources/UI/TrackDestinationEditor.swift`;
- `Sources/UI/TrackDestination/PresetBrowserSheetViewModel.swift`.

Primary tests:

- `Tests/SequencerAITests/Diagnostics/BuildIdentityTests.swift`;
- `Tests/SequencerAITests/Diagnostics/DiagnosticStoragePathsTests.swift`;
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticEventTests.swift`;
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticsTests.swift`;
- `Tests/SequencerAITests/Diagnostics/DiagnosticEventWriterTests.swift`;
- `Tests/SequencerAITests/Diagnostics/DiagnosticCollectorTests.swift`;
- `Tests/SequencerAITests/Diagnostics/DiagnosticRedactorTests.swift`;
- `Tests/SequencerAITests/Diagnostics/DiagnosticFingerprintTests.swift`;
- `Tests/SequencerAITests/Diagnostics/ObservedIssueLedgerTests.swift`;
- `Tests/SequencerAITests/Diagnostics/DiagnosticPolicyTests.swift`;
- `Tests/SequencerAITests/Diagnostics/IssueCandidateReviewWriterTests.swift`;
- updates to `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift`;
- updates to `Tests/SequencerAITests/AppSupportBootstrapTests.swift`.

## Required Exit Evidence

The build loop is complete only when it leaves compact evidence for:

- unit-test results from:

```sh
xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS,arch=arm64' test
```

- visible build identity screenshot or Peekaboo capture;
- a typed launch event from `diagnostics/events/current.ndjson`;
- a malformed event producing a collector-health observation;
- a redacted ledger record proving duplicate collapse and first/last seen
  updates;
- a suppression audit example with reason, reviewer/actor, timestamp, expiry
  or permanence, scope, and reopen conditions;
- route-confidence examples for active-worker, sweeper, and human-triage,
  including missing metadata downgrade;
- local markdown candidate output with redacted evidence, privacy checklist,
  honest provenance fields, and route evidence note;
- architecture review confirming no `.seqai` persistence, no playback hot path
  coupling, and no external issue creation;
- privacy review confirming raw private values are not persisted.

## Stop Conditions

Stop and write rework evidence instead of broadening the build if:

- build identity cannot be made visible and matched to emitted events;
- diagnostics cannot write reliably to the sandbox-compatible Application
  Support root;
- redaction cannot run before ledger/evidence/review output writes;
- ledger persistence cannot be made deterministic and crash-safe enough for
  local review;
- route/provenance policy would require guessing introduced-by blame from a
  single observed build.

## Product-Owner Attention

No product-owner attention is required before build-loop promotion. The PM
policy accepts queue-first review, visible build identity, local review output,
and conservative retention defaults. Product-owner review can refine retention
duration or an in-app dashboard after the local pipeline exists.
