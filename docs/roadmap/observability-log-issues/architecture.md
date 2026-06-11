---
feature: observability-log-issues
created: 2026-06-07
status: accepted-builder-facing-policy
sources:
  - docs/roadmap/observability-log-issues/notes.md
  - docs/roadmap/observability-log-issues/user-stories.md
  - docs/roadmap/observability-log-issues/existing-state.md
  - docs/roadmap/observability-log-issues/ux-review.md
  - docs/roadmap/observability-log-issues/feedback/2026-06-06-visible-build-identity-for-review.md
  - docs/roadmap/observability-log-issues/prototypes/01-log-inbox-routing.html
  - docs/roadmap/observability-log-issues/prototypes/02-issue-draft-review.html
next_artifact: docs/roadmap/observability-log-issues/plan.md
---

# Observability From Application Logs Architecture

This is accepted PM architecture for the log-to-issue event pipeline. It sets
builder-facing policy and boundaries only. It does not promote a build loop,
choose exact Swift type names, or implement product code.

## Product Shape

Observability From Application Logs turns runtime failures into inspectable,
deduplicated, privacy-conscious issue candidates. The workflow follows the
accepted queue-first direction from `01-log-inbox-routing.html`: review event
fingerprints first, inspect a draft issue second, then create, suppress, or
triage with visible provenance and routing confidence.

The first version must be conservative. It should help maintainers see and act
on runtime failures without flooding automation, writing private data into
durable artifacts, or falsely blaming the latest commit.

## Architectural Invariants

1. The collector has one authoritative runtime evidence source per event.
   It may enrich events with build metadata and process context, but it must not
   merge unrelated log streams into a single event without preserving source
   provenance.

2. App code emits typed diagnostic events through one shared facade. Builders
   should not add new ad-hoc `NSLog` parsing rules as the primary contract.
   Legacy `NSLog` and `Logger` output can be adapted during migration, but the
   durable pipeline contract is the typed envelope.

3. A local fingerprint ledger is the first durable issue state. External issue
   creation is downstream of human review and must not be the initial hot path.

4. "Observed in" and "introduced by" are different fields. The pipeline may
   always report the build identity where the event was observed when the app
   supplies it. It may report an introduction only when historical
   absence/presence evidence, a repeatable bisect, or another explicit proof
   supports that claim.

5. Redaction happens before persistence and before external issue creation.
   Raw private paths, sample names, project names, document content, MIDI
   device names, or user-entered text must not be written to the ledger or issue
   draft unless the privacy policy explicitly allows the field.

6. Suppression is audited, not deletion. A suppressed fingerprint keeps enough
   non-private metadata to explain who or what suppressed it, why, when it
   expires, and what evidence would reopen it.

7. Routing recommendations carry confidence. Active-worker, sweeper, and human
   triage routing are explicit states with evidence. Ambiguity routes to human
   triage instead of guessing.

## Pipeline Boundary

The pipeline has four conceptual layers:

1. **Emission**: app runtime code emits typed app events through a shared
   diagnostics facade.
2. **Collection**: a collector reads the authoritative runtime evidence source
   and normalizes events into a stable envelope.
3. **Ledgering**: a local fingerprint ledger deduplicates events, applies
   thresholds, suppression, provenance, and privacy policy, then creates issue
   candidates.
4. **Review and routing**: a queue-first review surface or local markdown queue
   lets a human or automation operator create an issue draft, suppress the
   fingerprint, or mark it for triage.

The first implementation should keep these layers separate even if they live in
one module. Do not let UI review code become the collector, and do not let
parsing raw strings become the durable event model.

## Authoritative Log Source And Collector Boundary

The first builder plan must choose one authoritative source for app runtime
events. The preferred direction is app-owned structured diagnostics under the
Application Support root, with OSLog or existing `NSLog` output treated as
compatibility inputs only while emission is migrated.

Rationale:

- app-owned files can be sandbox-compatible and can use project-controlled
  rotation and redaction rules;
- typed event emission avoids brittle parsing of mixed `NSLog` prefixes;
- macOS unified logging remains useful for debugging, but privacy and retention
  behavior are harder to make product-policy authoritative;
- crash reports can be linked as evidence, but they are not a complete event
  stream for non-crash runtime failures.

Collector responsibilities:

- read only the configured app-owned diagnostic event stream and explicitly
  named compatibility inputs;
- attach collector metadata such as collection time, source kind, host process,
  and parse status;
- reject malformed records into a collector-health event instead of inventing
  missing fields;
- pass events through redaction before durable ledger writes;
- never create external issues directly.

Collector non-goals:

- infer commit introduction from a single log line;
- scrape arbitrary Console output globally;
- read user documents to enrich events;
- write into the project document or live playback/runtime state.

## Shared Logging Facade And Typed Envelope

App code should emit through a small shared diagnostics facade. The facade must
support typed events that can also mirror concise messages to `Logger` or
`NSLog` for developer debugging.

Conceptual envelope:

```text
AppDiagnosticEvent
  id
  timestamp
  severity
  subsystem
  category
  eventCode
  messageTemplate
  privacyClass
  context
  stackTrace
  buildIdentity
  runtimeIdentity
  source
```

Required semantics:

- `eventCode` is stable and builder-authored. It is the primary fingerprint
  input, not the free-form message.
- `messageTemplate` is a non-private template. Dynamic values go in typed
  context fields with privacy labels.
- `severity` uses a small fixed scale: debug, info, warning, error, critical.
- `subsystem` and `category` use an agreed map for app, document, engine, audio,
  MIDI, UI, persistence, plugin/AU, automation, and collector-health.
- `privacyClass` defaults to private until explicitly marked safe.
- `buildIdentity` is stamped at build time and mirrored in visible app UI.
- `runtimeIdentity` may include session id, process id, OS version, app version,
  sandbox flag, and document/session hash, but not a raw file path.

Legacy migration policy:

- existing `NSLog`/`Logger` paths can remain while nearby work is converted;
- new observability-worthy logs should use the facade;
- parsers for old plain-string logs must be labeled compatibility adapters and
  should produce lower routing confidence than typed events.

## Build Metadata And Visible Build Identity

Build identity is both diagnostic evidence and product-review UI. The app must
be stamped at build time with:

- commit SHA;
- branch name;
- dirty or clean state;
- build timestamp or build attribution id;
- app version and bundle build number;
- optional worktree or source channel when available.

The same identity must be available in three places:

- the typed diagnostic envelope;
- launch logs or app-start diagnostic event;
- a visible app surface, preferably the window title or a compact always-
  available debug/status badge.

If build metadata is missing, the app should emit `unknown` explicitly and the
pipeline should lower provenance and routing confidence. Missing metadata must
not block issue creation when the event is severe, but it should default routing
to human triage unless another reliable signal exists.

## Provenance Policy

Every issue candidate has these provenance fields:

- `observedIn`: build identity where the fingerprint occurred;
- `firstSeenIn`: earliest known observed build for the fingerprint in the local
  ledger;
- `lastSeenIn`: most recent observed build for the fingerprint;
- `introducedBy`: optional, evidence-backed attribution;
- `provenanceConfidence`: high, medium, low, or unknown;
- `provenanceEvidence`: compact explanation of the claim.

Allowed `introducedBy` evidence:

- local ledger shows the fingerprint absent in earlier comparable builds and
  first present in a later build;
- a repeatable bisect or targeted reproduction identifies the introducing
  commit;
- a human reviewer sets the field with an evidence note.

Disallowed behavior:

- treating the currently running commit as introduced-by by default;
- assigning blame from branch name alone;
- overwriting earlier first-seen data when the same fingerprint repeats.

## Local Fingerprint And Issue Ledger

The first durable store should be local and app/project owned. It may be under
Application Support for app-owned diagnostics, or under a clearly named
project-local runtime root for coordinator-side review. The builder plan must
choose the exact root and document why it is appropriate.

The ledger stores:

- fingerprint id;
- normalized severity and event code;
- first-seen and last-seen timestamps;
- first-seen and last-seen build identities;
- occurrence count;
- current state: new, candidate, drafted, created, suppressed, triage,
  resolved, regressed;
- suppression metadata when applicable;
- routing recommendation and confidence;
- redacted evidence excerpt references;
- privacy review status.

Lifecycle:

1. New sanitized event arrives.
2. Fingerprint is computed from stable fields.
3. Existing fingerprint is updated or a new ledger record is created.
4. Threshold and suppression policy decide whether the record remains an
   observation or becomes an issue candidate.
5. Review creates a draft, suppresses, routes to triage, or marks resolved.
6. A later occurrence after resolution or suppression expiry can reopen as a
   regression with the original history preserved.

The ledger must use atomic writes or another crash-safe local persistence
pattern. It must not live inside `.seqai` documents and must not participate in
the live playback data path.

## Fingerprinting Policy

The fingerprint should be stable across noisy values while still separating
distinct failures.

Primary inputs:

- event code;
- subsystem and category;
- normalized severity band;
- normalized stack signature when present;
- failure site or component id when present.

Excluded or normalized inputs:

- timestamps;
- absolute file paths;
- document names;
- sample names;
- pointer values;
- UUIDs;
- changing numeric counters unless explicitly part of the failure identity.

Compatibility string-log fingerprints should be marked lower confidence and
should normalize dynamic substrings before hashing.

## Privacy And Redaction

Privacy is a minimum viable architecture requirement. The pipeline must redact
before writing the ledger, writing evidence excerpts, or creating external
issue drafts.

Redact by default:

- absolute user paths and home directory names;
- document names and project names;
- sample names and imported media names;
- MIDI device names when they include user-defined labels;
- plugin preset names if they may reveal private work;
- free-form user-entered text and document content;
- environment variables and credentials.

Allowed retained fields:

- stable event code and subsystem;
- coarse OS/app/build metadata;
- hashed document/session identifiers;
- redacted stack signatures;
- compact message templates with private values replaced.

When the redactor cannot classify a field safely, the event should be retained
as a private triage candidate with no external issue creation until human
review.

## Thresholds And Suppression

The pipeline must separate observations from issues.

Immediate issue-candidate thresholds:

- crash or uncaught exception evidence;
- audio engine start/stop/render failure;
- persistence failure or data-loss risk;
- MIDI routing failure that prevents expected note/control output;
- repeated UI exception or interaction failure in a core workflow;
- collector-health failure that prevents observability itself from running.

Repeated issue-candidate thresholds:

- warning/error fingerprint occurs at least three times in one session;
- warning/error fingerprint appears across two or more stamped builds;
- suppressed fingerprint reappears after expiry or with higher severity.

Suppression policy:

- suppression requires a reason;
- suppression records actor/reviewer, timestamp, expiry or permanence, and
  matching scope;
- suppression hides routine repeats from the active queue but does not delete
  occurrence counts;
- severity escalation, changed stack signature, new build after expiry, or
  explicit reviewer action can reopen a suppressed fingerprint.

## Routing Confidence

Routing is a recommendation, not silent assignment.

Active-worker route is high confidence only when:

- the event was observed in a stamped feature-worktree build;
- the branch/worktree maps to one active build loop or active worker;
- the fingerprint was absent from the ledger on the current base/main evidence;
- privacy redaction passed.

Sweeper route is high confidence when:

- the event was observed on `main`, a stable branch, or a review build not tied
  to one active worker;
- the fingerprint is new or regressed;
- privacy redaction passed;
- issue threshold passed.

Human triage is required when:

- build identity is missing or unknown;
- more than one active worktree could plausibly own the event;
- the event comes from compatibility string parsing only and lacks stable
  fields;
- privacy redaction is uncertain;
- introduced-by evidence is requested but not available;
- suppression scope is disputed or expired in an unclear way.

Every issue candidate must display the suggested route and why that route was
chosen. The UI should not hide low confidence behind a confident button label.

## UI And Review Boundary

The architecture accepts a two-step operator flow:

1. Queue-first fingerprint review: scan severity, occurrence count, observed-in
   build, last seen, route recommendation, and suppression state.
2. Draft review: inspect issue body, privacy checklist, kept/removed/deferred
   evidence, provenance language, and destination before external creation.

The first implementation can keep review local. External GitHub or Linear
bridges are downstream and must use the same redacted draft body and provenance
fields.

## Non-Goals

- Global Console scraping as the authoritative product contract.
- Automatic external issue creation without local review.
- Claiming `introducedBy` from a single observed build.
- Storing raw private log lines in durable artifacts.
- Persisting diagnostics inside project documents.
- Routing low-confidence events to active workers by default.
- Building a full in-app observability dashboard before the event envelope,
  ledger, redaction, and review policy exist.

## Open Readiness Items For Plan

- Choose the exact first authoritative source: app-owned structured diagnostics
  file, OSLog adapter, or hybrid migration path with one authoritative typed
  source.
- Choose the exact local ledger root and file format.
- Define the first Swift names for the diagnostics facade and event envelope.
- Define build-stamping integration with existing build/open scripts.
- Decide the initial review surface: local markdown queue, in-app debug surface,
  or coordinator-side artifact queue.
- Define retention defaults for evidence excerpts and suppressed fingerprints.
