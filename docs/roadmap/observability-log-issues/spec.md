---
feature: observability-log-issues
created: 2026-06-07
status: spec-ready-for-plan
sources:
  - docs/roadmap/observability-log-issues/architecture.md
  - docs/roadmap/observability-log-issues/notes.md
  - docs/roadmap/observability-log-issues/user-stories.md
  - docs/roadmap/observability-log-issues/existing-state.md
  - docs/roadmap/observability-log-issues/ux-review.md
  - docs/roadmap/observability-log-issues/feedback/2026-06-06-visible-build-identity-for-review.md
next_artifact: docs/roadmap/observability-log-issues/plan.md
---

# Observability From Application Logs Spec

## Status

Ready for implementation planning. Architecture policy is accepted for PM
purposes, but no build loop should be promoted until a plan and implementation
handoff specify exact files, test targets, and the first persistence root.

## Purpose

The feature converts runtime application logs into local, deduplicated issue
candidates with honest provenance, privacy redaction, suppression audit, and
explicit routing. It exists to make runtime problems found during product
review or live use recoverable without interrupting the app's instrument feel
or flooding automation with noisy duplicates.

## First Implementation Scope

The first build should deliver the local pipeline foundation:

- build metadata stamping and visible build identity;
- shared diagnostic event facade and typed envelope;
- one authoritative app-owned structured diagnostic source;
- collector normalization from that source into sanitized app events;
- local fingerprint/issue ledger;
- threshold, suppression, and route-confidence policy;
- local review output for issue candidates.

External GitHub or Linear issue creation is out of scope for the first build
unless a later plan explicitly adds a reviewed bridge on top of the redacted
local draft.

## User Stories And Acceptance Criteria

### 1. Collect Runtime Log Evidence

- As a developer investigating runtime behavior, I want the app to emit
  structured diagnostic events into a known local source.
- Accepted when a local collector can read the source and produce sanitized
  candidate events with timestamp, severity, subsystem, category, event code,
  message template, source metadata, and build identity when available.

### 2. Convert Logs Into Typed Events

- As a sweeper or triage agent, I want events normalized into consistent fields.
- Accepted when new observability-worthy emission goes through a shared facade
  and compatibility parsing is clearly labeled lower confidence.

### 3. Collapse Duplicate Events

- As a maintainer, I want repeated failures to update one record.
- Accepted when stable fingerprints store first-seen, last-seen, occurrence
  count, state, and redacted evidence references without creating duplicate
  issue candidates.

### 4. Separate Issues From Observations

- As a product and engineering lead, I want warnings and benign logs to stay out
  of the work queue.
- Accepted when the pipeline applies severity, recurrence, and suppression
  thresholds before a ledger record becomes an issue candidate.

### 5. Attach Honest Commit Provenance

- As a developer fixing a generated issue, I want the issue to distinguish
  observed evidence from introduction claims.
- Accepted when generated issue text always uses `observedIn` for the running
  build and leaves `introducedBy` blank unless historical evidence supports it.

### 6. Route Work Explicitly

- As an automation operator, I want issue candidates marked active-worker,
  sweeper, or human triage with confidence.
- Accepted when every candidate carries a route, confidence level, and compact
  explanation.

### 7. Preserve Useful Reproduction Context

- As an implementer, I want compact evidence without searching raw logs.
- Accepted when candidates include redacted message, event code, occurrence
  count, timestamps, build identity, environment summary, and links or
  references to retained evidence.

### 8. Protect Private Data

- As a user or developer, I want private paths and project details sanitized
  before persistence.
- Accepted when redaction runs before ledger writes and events with uncertain
  privacy are held for human triage rather than exported.

## Build Identity Requirements

The app must expose a `BuildIdentity` equivalent with these fields:

```text
BuildIdentity
  commitSHA
  branch
  dirtyState
  buildTimestamp
  buildAttributionID
  appVersion
  bundleBuildNumber
  sourceChannel
```

Required behavior:

- build/open scripts stamp the app with commit, branch, dirty state, and build
  timestamp when available;
- missing values are explicit `unknown`, not omitted;
- launch emits one typed diagnostic event with the active build identity;
- the main window title or always-available debug/status surface shows the same
  identity in a compact form;
- event envelopes copy the active build identity at emission time.

Acceptance checks:

- a review build from a feature branch visibly shows branch, short SHA, dirty
  or clean state, and timestamp/attribution id;
- a launch diagnostic event includes the same fields;
- when metadata is unavailable, provenance confidence becomes low or unknown
  and routing defaults to human triage unless severity demands local review.

## Diagnostic Event Envelope

The first implementation must define a typed app event envelope with these
semantic fields:

```text
AppDiagnosticEvent
  id
  timestamp
  severity
  subsystem
  category
  eventCode
  messageTemplate
  contextFields
  privacyLabels
  stackSignature
  buildIdentity
  runtimeIdentity
  sourceKind
```

Severity values:

- debug;
- info;
- warning;
- error;
- critical.

Subsystem/category map must cover at least:

- app lifecycle;
- document/session;
- engine;
- audio;
- MIDI;
- UI;
- persistence;
- plugin/AU;
- automation;
- collector-health.

Facade requirements:

- event code is required for new observability-worthy events;
- free-form dynamic details go into typed context fields, not string
  interpolation inside the template;
- context fields default to private unless marked safe;
- facade may mirror a concise line to `Logger` or `NSLog`, but the structured
  event is authoritative;
- legacy plain logs can be adapted only through compatibility parsers marked as
  lower confidence.

## Collector Requirements

The collector must:

- read the chosen app-owned structured diagnostic source;
- validate required envelope fields;
- attach collection time and source metadata;
- pass every event through redaction before writing durable state;
- emit collector-health events for unreadable, malformed, or stale sources;
- keep raw unredacted lines out of the ledger and issue drafts;
- avoid project document writes and live playback/runtime mutation.

Malformed events:

- must not be silently dropped;
- should become collector-health observations;
- may become issue candidates only when recurrence or severity threshold passes.

## Redaction Requirements

The redactor must run before persistence.

Required redactions:

- replace home directories and absolute paths with stable placeholders;
- remove or hash document/project names;
- remove or hash sample/media names;
- remove user-entered text and document content;
- redact credentials and environment variable values;
- redact MIDI or plugin labels unless explicitly marked safe;
- trim evidence excerpts to the minimum useful size.

Privacy states:

- `redacted`: safe for local issue candidate;
- `needsReview`: local only, no external creation;
- `blocked`: insufficiently safe to persist evidence excerpt;
- `safe`: field is non-private by policy.

Issue drafts must include a privacy checklist listing kept, removed, and
deferred evidence.

## Fingerprint Ledger Requirements

Each ledger record must contain:

```text
ObservedIssueRecord
  fingerprint
  eventCode
  subsystem
  category
  severity
  state
  firstSeenAt
  lastSeenAt
  firstSeenIn
  lastSeenIn
  occurrenceCount
  observedBuilds
  introducedBy
  provenanceConfidence
  route
  routeConfidence
  suppression
  privacyState
  redactedEvidenceRefs
```

Ledger states:

- observation;
- candidate;
- draft;
- created;
- suppressed;
- triage;
- resolved;
- regressed.

Persistence requirements:

- local first;
- atomic writes or equivalent crash-safe persistence;
- deterministic JSON or another reviewable format unless the build plan proves
  a stronger need;
- no `.seqai` document persistence;
- no external tracker writes in the first local pipeline.

## Fingerprint Rules

The fingerprint hash must include stable failure identity:

- event code;
- subsystem and category;
- normalized severity band;
- normalized stack signature when present;
- failure component id when present.

It must exclude or normalize:

- timestamps;
- absolute paths;
- document names;
- sample/media names;
- UUIDs;
- pointer values;
- volatile counters;
- build timestamp.

The ledger may separately store observed build identity, but build identity
must not split one logical fingerprint into many unrelated records.

## Threshold Policy

Immediate candidate:

- crash or uncaught exception;
- audio engine failure;
- persistence failure or data-loss risk;
- MIDI routing failure blocking expected output;
- repeated UI exception in a core workflow;
- collector-health failure that prevents event collection.

Recurrence candidate:

- three warning/error occurrences in one session;
- same warning/error across two or more builds;
- suppressed fingerprint reappears after expiry;
- severity increases for an existing fingerprint.

Observation only:

- debug/info events;
- one-off warning without core-workflow impact;
- compatibility-parser event without enough stable fields;
- known benign event within active suppression scope.

## Suppression And Audit

Suppression must store:

- reason;
- reviewer or actor id;
- timestamp;
- expiry or permanence;
- matching scope;
- reopen conditions.

Suppression does not erase history. It hides routine repeats from the active
candidate queue while keeping occurrence counts and provenance.

Reopen conditions:

- severity increases;
- stack signature changes materially;
- suppression expires;
- event appears in a new build outside suppression scope;
- reviewer manually reopens.

## Provenance Requirements

Generated issue language must use:

- `Observed in`: always populated when build identity exists;
- `First seen in`: populated from earliest ledger evidence;
- `Last seen in`: populated from latest ledger evidence;
- `Introduced by`: optional and blank unless evidence supports it.

`Introduced by` may be set only when:

- the ledger proves absence before and presence after a build boundary;
- a bisect or reproduction record identifies a commit;
- a human reviewer supplies an evidence note.

The system must never infer introduction from the current commit alone.

## Routing Requirements

Routes:

- `active-worker`;
- `sweeper`;
- `human-triage`.

Confidence:

- high;
- medium;
- low;
- unknown.

Active-worker route requires:

- stamped feature-worktree build identity;
- one matching active build loop or worker;
- threshold passed;
- redaction passed;
- no competing plausible owner.

Sweeper route requires:

- main/stable/review build not owned by one active worker;
- threshold passed;
- redaction passed.

Human triage is required when:

- build identity is missing;
- provenance is ambiguous;
- privacy state is `needsReview` or `blocked`;
- multiple active worktrees may own the event;
- compatibility parsing is the only evidence;
- a suppression or threshold decision needs judgment.

Every route must include a short evidence note.

## Review Output

The first implementation should produce a local reviewable issue draft or queue
record for candidates. A draft must include:

- title;
- fingerprint;
- severity;
- state;
- occurrence count;
- first-seen and last-seen timestamps;
- observed-in, first-seen-in, last-seen-in, and introduced-by fields;
- redacted evidence excerpt;
- reproduction hints when available;
- privacy checklist;
- route recommendation and confidence;
- links or references to retained local evidence.

The queue-first review surface should support:

- create draft;
- mark observation;
- suppress fingerprint;
- send to human triage;
- mark resolved.

External tracker bridges must consume this reviewed draft rather than raw logs.

## Empty, Error, And Missing-Metadata States

Required states:

- no candidate fingerprints;
- collector source unavailable;
- collector source malformed or stale;
- build metadata missing;
- redaction uncertain;
- ledger write failed;
- all events suppressed.

These states may be local/debug-facing in the first build, but they must be
observable and testable.

## Testing Requirements

Build identity:

- stamped metadata is loaded into the app;
- visible identity matches event identity;
- missing metadata is explicit and lowers route/provenance confidence.

Envelope/facade:

- new events require stable event codes;
- context privacy defaults to private;
- emitted events serialize deterministically.

Collector/redaction:

- valid structured events become sanitized candidate inputs;
- malformed source records create collector-health observations;
- private paths, document names, sample names, and user text are redacted before
  ledger writes.

Fingerprint/ledger:

- repeated events update one ledger record;
- volatile values do not change the fingerprint;
- first-seen and last-seen fields update correctly;
- resolved or suppressed fingerprints can regress according to policy.

Thresholds/suppression:

- immediate candidate classes promote correctly;
- repeated warnings promote only after threshold;
- suppression hides routine repeats but preserves audit metadata;
- severity escalation reopens suppressed records.

Provenance/routing:

- observed-in is populated from build metadata;
- introduced-by remains blank without historical proof;
- active-worker route requires one clear active owner;
- ambiguous or missing metadata routes to human triage.

Review output:

- draft issue text uses redacted evidence only;
- privacy checklist lists kept, removed, and deferred evidence;
- route confidence and explanation are visible.

## Non-Goals For First Build

- external issue creation without local review;
- global Console scraping as the authoritative source;
- full in-app diagnostics dashboard;
- storing observability records in project documents;
- automatic blame assignment;
- ingestion of arbitrary test logs unrelated to the running app;
- retention of raw private log lines.
