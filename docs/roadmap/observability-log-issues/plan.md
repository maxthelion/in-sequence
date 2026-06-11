---
feature: observability-log-issues
created: 2026-06-07
status: ready-for-implementation-handoff
sources:
  - README.md
  - docs/roadmap/observability-log-issues/architecture.md
  - docs/roadmap/observability-log-issues/spec.md
  - docs/roadmap/observability-log-issues/existing-state.md
  - docs/roadmap/observability-log-issues/ux-review.md
  - docs/roadmap/observability-log-issues/feedback/2026-06-06-visible-build-identity-for-review.md
next_artifact: docs/roadmap/observability-log-issues/implementation-handoff.md
---

# Observability From Application Logs Implementation Plan

## Status

Accepted PM implementation plan for the local Observability From Application
Logs v1 pipeline. This plan resolves the first storage root, target files,
tests, migration order, and review output, so `implementation-handoff.md` can
package it for a future build loop.

This plan does not promote a build loop, edit product code, create external
issues, or route implementation.

## Build Goal

Deliver a local, privacy-conscious pipeline that turns app-owned structured
diagnostic events into deduplicated issue candidates with visible build
identity, honest provenance, suppression audit, and explicit route confidence.

The user-facing product value is review recoverability: when a runtime failure
appears during product review or live use, the operator can inspect a
fingerprint, see where it was observed, review redacted evidence, and decide
whether it should become a draft issue, suppression, or human triage item.

## Plan Decisions

### Authoritative Source And Storage Root

Use an app-owned structured diagnostics source under Application Support:

```text
~/Library/Application Support/sequencer-ai/diagnostics/
  events/current.ndjson
  events/archive/
  issues/ledger.json
  issues/evidence/
  review/candidates/
```

First-build persistence choices:

- `events/current.ndjson` is the authoritative event stream for typed
  diagnostics.
- `events/archive/` is reserved for rotation; v1 may rotate by size or keep
  one current file if tests prove bounded writes.
- `issues/ledger.json` is deterministic, sorted JSON with atomic replacement,
  following the `RecentVoicesStore` persistence precedent.
- `issues/evidence/` stores redacted evidence excerpts only.
- `review/candidates/` stores local markdown issue-candidate drafts. External
  GitHub or Linear creation is out of scope.

Do not store observability data in `.seqai` documents, do not write into the
live playback data path, and do not use global Console scraping as the durable
contract.

### Review Output

The first review output is a local markdown candidate:

```text
diagnostics/review/candidates/<fingerprint>.md
```

Each candidate includes front matter and a human-readable body:

- title;
- fingerprint;
- severity and state;
- occurrence count;
- first-seen and last-seen timestamps;
- observed-in, first-seen-in, last-seen-in, and introduced-by fields;
- redacted evidence excerpt;
- reproduction hints when available;
- privacy checklist with kept, removed, and deferred evidence;
- route recommendation, confidence, and evidence note;
- local references to retained redacted evidence.

The markdown queue is the v1 queue-first review surface. An in-app dashboard
or external tracker bridge can be built later on the same ledger and draft
format.

### Retention Defaults

Use conservative local retention until product-owner policy is more specific:

- keep the ledger and suppression audit until manually cleared;
- keep redacted evidence excerpts for 14 days after the last occurrence unless
  the record remains an active candidate;
- keep markdown candidate drafts while the ledger state is `candidate`,
  `draft`, `triage`, or `regressed`;
- never retain raw private event lines after redaction.

These defaults are implementable without product-owner judgment and can be
changed later with a migration.

## Target Files And Modules

### New Diagnostics Module Files

Add a new source folder:

```text
Sources/Diagnostics/
```

Initial files:

- `Sources/Diagnostics/BuildIdentity.swift`: shared build identity model,
  extracted or moved from `Sources/App/SequencerAIAppDelegate.swift`.
- `Sources/Diagnostics/AppDiagnosticEvent.swift`: typed event envelope,
  severity, subsystem/category, source kind, runtime identity, privacy labels.
- `Sources/Diagnostics/AppDiagnostics.swift`: shared facade for emitting typed
  events and optionally mirroring concise developer logs.
- `Sources/Diagnostics/DiagnosticEventWriter.swift`: app-owned NDJSON writer
  for `diagnostics/events/current.ndjson`.
- `Sources/Diagnostics/DiagnosticCollector.swift`: validates source records,
  attaches collection metadata, and emits collector-health observations.
- `Sources/Diagnostics/DiagnosticRedactor.swift`: redacts paths, document and
  sample names, user text, credentials, MIDI/plugin labels, and uncertain
  private fields.
- `Sources/Diagnostics/DiagnosticFingerprint.swift`: computes stable
  fingerprints from event code, subsystem, category, severity band, stack
  signature, and component id while normalizing volatile values.
- `Sources/Diagnostics/ObservedIssueLedger.swift`: atomic deterministic JSON
  store for `ObservedIssueRecord`.
- `Sources/Diagnostics/DiagnosticPolicy.swift`: threshold, suppression,
  provenance, and routing-confidence decisions.
- `Sources/Diagnostics/IssueCandidateReviewWriter.swift`: writes local
  markdown candidate drafts from redacted ledger records.

### Existing Files To Update

Build identity and launch integration:

- `Sources/Resources/Info.plist`: keep git/build keys present and covered by
  tests.
- `project.yml`: keep `GIT_COMMIT`, `GIT_BRANCH`, `GIT_DIRTY`,
  `BUILD_ATTRIBUTION_ID`, and `BUILD_ATTRIBUTION_VERSION` settings available.
- `scripts/open-latest-build.sh`: continue passing stamped metadata and writing
  attribution manifests.
- `Sources/App/SequencerAIAppDelegate.swift`: use shared `BuildIdentity` and
  emit a typed launch diagnostic event.
- `Sources/UI/StudioTopBar.swift`: keep or add the compact visible build
  identity badge; verify it matches the event identity.

Storage and bootstrap:

- `Sources/Platform/AppSupportBootstrap.swift`: add
  `diagnostics/events`, `diagnostics/events/archive`, `diagnostics/issues`,
  `diagnostics/issues/evidence`, and `diagnostics/review/candidates` to the
  ensured app-support structure.
- `Sources/App/SequencerAIApp.swift`: initialize diagnostics storage and facade
  after the app-support root is available; convert bootstrap failures to typed
  diagnostics while retaining concise developer logging.

First emission migration:

- `Sources/App/SequencerAIAppDelegate.swift`: launch, resign-active, and
  termination lifecycle events.
- `Sources/App/SequencerAIApp.swift`: app-support and sample-library bootstrap
  failures.
- `Sources/Engine/EngineController.swift`: setup/shutdown/apply failures that
  meet warning/error threshold relevance.
- `Sources/Engine/Executor.swift`: unknown block parameter update through the
  facade as a low-confidence compatibility or debug event.
- `Sources/UI/TrackDestinationEditor.swift`: AU window preparation timeout and
  preset stepping failures.
- `Sources/UI/TrackDestination/PresetBrowserSheetViewModel.swift`: preset load
  failures.

Do not attempt a wholesale logging rewrite in the first build. New
observability-worthy events should use the facade; existing ad-hoc `NSLog` or
`Logger` calls can migrate incrementally when touched by this feature.

## Implementation Sequence

### 1. Harden Build Identity And Visible Review Identity

Goal: make every review run visibly and diagnostically attributable.

Work:

- Move or expose `BuildIdentity` from the app delegate into
  `Sources/Diagnostics/BuildIdentity.swift`.
- Preserve explicit `unknown` values for unstamped metadata.
- Verify `Info.plist`, `project.yml`, and `scripts/open-latest-build.sh` stamp
  commit, branch, dirty state, attribution id, attribution version, app
  version, and bundle build number.
- Ensure the app emits one typed launch event carrying the same build identity.
- Keep the main window or always-available top-bar badge showing branch, short
  SHA, dirty/clean state, and attribution version.

Exit evidence:

- Unit coverage for stamped metadata, placeholder cleanup, and missing
  metadata.
- A visual or screenshot check showing the visible build identity in a review
  build.
- A launch event fixture showing the same identity as the visible badge.

### 2. Add Diagnostics Storage Bootstrap

Goal: establish the app-owned local root before writing events.

Work:

- Extend `AppSupportBootstrap` with the diagnostics subfolders listed above.
- Add tests proving the directories are created idempotently.
- Add a single `DiagnosticStoragePaths` helper under `Sources/Diagnostics/` so
  all writers use the same root.
- Ensure tests can inject temporary roots and do not write to the developer's
  real Application Support directory.

Exit evidence:

- `AppSupportBootstrapTests` include diagnostics directories.
- Diagnostics path tests prove exact paths for events, ledger, evidence, and
  review candidates.

### 3. Define Typed Envelope, Facade, And Event Writer

Goal: create the durable app contract for new diagnostics.

Work:

- Add `AppDiagnosticEvent` with required fields from the spec.
- Add severity, subsystem/category, source kind, privacy state, and context
  privacy labels.
- Add `AppDiagnostics` facade with dependency injection for tests.
- Add deterministic JSON-line serialization to `events/current.ndjson`.
- Mirror concise developer messages to `Logger` or `NSLog` only as secondary
  output.
- Make event code required for warning/error/critical events.

Exit evidence:

- Tests prove deterministic serialization, required event codes, default
  private context, explicit build identity, and injected writer behavior.
- Launch/bootstrap code can emit through the facade without touching document
  or playback state.

### 4. Add Collector, Redactor, Fingerprint, And Ledger

Goal: turn structured events into durable sanitized issue records.

Work:

- Implement `DiagnosticCollector` over the app-owned NDJSON source.
- Validate required envelope fields and emit collector-health observations for
  malformed records.
- Run `DiagnosticRedactor` before any ledger or evidence write.
- Compute stable fingerprints that exclude timestamps, build timestamp, paths,
  document names, sample/media names, UUIDs, pointer values, and volatile
  counters.
- Implement `ObservedIssueLedger` as sorted JSON with atomic replacement and an
  `NSLock` or equivalent serialization guard.
- Store occurrence count, first/last seen, observed builds, provenance fields,
  suppression, privacy state, route, and redacted evidence references.

Exit evidence:

- Tests prove repeated events update one record, volatile fields do not split
  fingerprints, first/last seen update correctly, and redaction precedes
  persistence.
- Malformed records produce collector-health observations instead of silent
  drops.

### 5. Add Thresholds, Suppression, Provenance, And Routing Policy

Goal: separate observations from issue candidates without false blame.

Work:

- Encode immediate candidate classes from the spec.
- Promote warning/error recurrence after three occurrences in one session or
  appearance across two stamped builds.
- Implement suppression metadata: reason, reviewer or actor id, timestamp,
  expiry/permanence, matching scope, and reopen conditions.
- Always populate `observedIn` when build identity exists.
- Keep `introducedBy` blank unless ledger history, bisect/reproduction
  evidence, or human review explicitly supports it.
- Route to `active-worker`, `sweeper`, or `human-triage` with confidence and a
  compact evidence note.
- Default missing metadata, privacy uncertainty, compatibility-only evidence,
  or multiple plausible owners to human triage.

Exit evidence:

- Tests cover immediate promotion, recurrence promotion, suppression audit,
  severity escalation reopening, honest introduced-by behavior, and route
  confidence downgrade cases.

### 6. Write Local Review Candidate Drafts

Goal: produce the first queue-first review output.

Work:

- Add `IssueCandidateReviewWriter`.
- Write one markdown candidate per active fingerprint under
  `diagnostics/review/candidates/`.
- Include the privacy checklist and provenance language from the accepted
  prototype/spec.
- Rewrite candidate markdown deterministically when the ledger record changes.
- Keep external tracker creation out of scope.

Exit evidence:

- Tests prove candidate markdown contains redacted evidence only, privacy
  checklist entries, route confidence, and blank `Introduced by` without proof.
- Manual evidence or fixture output shows a candidate draft for a sample
  engine failure.

### 7. Migrate First High-Value Log Emissions

Goal: seed the pipeline from real runtime paths without broad churn.

Work:

- Convert launch/app lifecycle and bootstrap failures first.
- Convert selected engine setup/shutdown/apply failures second.
- Convert AU/preset failures third.
- Leave debug-only step-grid tap diagnostics as debug-only unless a later plan
  chooses them as observability-worthy.
- Compatibility string parsing is optional for v1 and must be marked lower
  confidence if added.

Exit evidence:

- Tests or fixtures prove migrated events carry stable event codes and privacy
  labels.
- A review run can produce at least one typed launch event and one synthetic or
  fixture issue candidate.

## Test Plan

Primary test files:

- `Tests/SequencerAITests/Diagnostics/BuildIdentityTests.swift`
- `Tests/SequencerAITests/Diagnostics/DiagnosticStoragePathsTests.swift`
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticEventTests.swift`
- `Tests/SequencerAITests/Diagnostics/AppDiagnosticsTests.swift`
- `Tests/SequencerAITests/Diagnostics/DiagnosticEventWriterTests.swift`
- `Tests/SequencerAITests/Diagnostics/DiagnosticCollectorTests.swift`
- `Tests/SequencerAITests/Diagnostics/DiagnosticRedactorTests.swift`
- `Tests/SequencerAITests/Diagnostics/DiagnosticFingerprintTests.swift`
- `Tests/SequencerAITests/Diagnostics/ObservedIssueLedgerTests.swift`
- `Tests/SequencerAITests/Diagnostics/DiagnosticPolicyTests.swift`
- `Tests/SequencerAITests/Diagnostics/IssueCandidateReviewWriterTests.swift`

Existing test updates:

- `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift`
- `Tests/SequencerAITests/AppSupportBootstrapTests.swift`
- `Tests/SequencerAITests/Platform/RecentVoicesStoreTests.swift` only as a
  persistence precedent; do not couple diagnostics to voices.

Acceptance checks:

- Build identity: stamped metadata loads, visible identity matches event
  identity, and missing values are explicit `unknown`.
- Storage: diagnostics directories are created idempotently under injectable
  roots.
- Envelope/facade: event code requirements, privacy defaults, deterministic
  serialization, and app-owned writes.
- Collector/redaction: valid events become sanitized inputs; malformed records
  become collector-health observations; private data is redacted before writes.
- Fingerprint/ledger: duplicate collapse, volatile-value normalization,
  first/last seen updates, suppression/regression behavior.
- Provenance/routing: observed-in is populated, introduced-by remains blank
  without proof, ambiguous or missing metadata routes to human triage.
- Review output: local markdown drafts use redacted evidence only and include
  privacy/provenance/route checklists.

Expected command:

```sh
xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS,arch=arm64' test
```

## Review Gates

Before a future build loop is considered complete, it must leave compact
evidence for:

- unit-test results covering the diagnostics module and updated app-support
  bootstrap;
- a review-build screenshot or Peekaboo capture showing visible build identity;
- a sample typed launch event from `events/current.ndjson`;
- a sample redacted ledger record from `issues/ledger.json`;
- a sample markdown candidate from `review/candidates/`;
- architecture review confirming no `.seqai` persistence and no playback hot
  path dependency;
- privacy review confirming raw private data is not retained.

## V1 Exclusions

Do not implement in v1:

- external GitHub or Linear issue creation;
- global Console scraping as authoritative input;
- full in-app diagnostics dashboard;
- raw private log persistence;
- automatic introduced-by/blame assignment;
- project document persistence for diagnostics;
- live playback mutation from diagnostics;
- ingestion of arbitrary test logs unrelated to the running app.

## Product-Owner Attention

No product-owner attention is needed for this plan. The accepted queue-first
direction, visible build identity feedback, and conservative local retention
defaults are enough to proceed. Future product-owner review may refine
retention duration or the final in-app review surface after the local pipeline
exists.
