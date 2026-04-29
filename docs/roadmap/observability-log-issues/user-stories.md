# Observability From Application Logs User Stories

## Stories

### 1. Collect Runtime Log Evidence
- **As a:** developer investigating sequencer-ai runtime behavior
- **I want:** a script or loop to collect relevant application logs from a known source
- **So that:** runtime failures found outside the test suite become visible to the roadmap and automation loop
- **Done when:** the collector can read the agreed log source and produce a structured record for each candidate event, including timestamp, severity, subsystem or category, message, and any available build metadata.

### 2. Convert Logs Into Structured Events
- **As a:** sweeper or triage agent
- **I want:** raw log lines parsed into consistent event fields
- **So that:** issues can be grouped, filtered, routed, and fixed without rereading noisy log output by hand
- **Done when:** each event can carry severity, message, stack trace when present, app or document context when present, app version, git commit SHA, branch, build timestamp, dirty-tree status, and runtime environment when available.

### 3. Collapse Duplicate Events
- **As a:** maintainer watching the issue queue
- **I want:** repeated occurrences of the same runtime problem to update one issue instead of creating many
- **So that:** the observability loop stays useful during noisy failures and long-running sessions
- **Done when:** the pipeline fingerprints events, stores first-seen and last-seen evidence, increments occurrence counts, and avoids opening a new issue for an already-known fingerprint.

### 4. Separate Issues From Observations
- **As a:** product and engineering lead
- **I want:** clear rules for when a log event becomes an actionable issue
- **So that:** warnings and benign logs do not drown out crashes, data loss risks, and broken core workflows
- **Done when:** the pipeline applies threshold rules that escalate crashes, audio engine failures, data loss risk, MIDI routing failures, persistence failures, and repeated UI exceptions while allowing known benign logs to be suppressed.

### 5. Attach Honest Commit Provenance
- **As a:** developer fixing a generated issue
- **I want:** each issue to say where the problem was observed and only claim introduction when there is evidence
- **So that:** fixes are routed to the right person without falsely blaming the latest commit
- **Done when:** generated issues distinguish "observed in commit X" from "introduced by commit X" and only make introduction claims when historical fingerprint evidence supports the attribution.

### 6. Route Work To The Right Queue
- **As a:** automation operator
- **I want:** log-derived issues routed according to branch and active-work ownership
- **So that:** regressions from current in-flight work stay with the active worker, while mainline problems go to a sweeper queue
- **Done when:** new issues can be marked for active-worker handoff, sweeper work, or human triage when provenance is ambiguous.

### 7. Preserve Useful Reproduction Context
- **As a:** implementer receiving a log-derived issue
- **I want:** compact context included with the issue
- **So that:** I can understand the failure quickly without searching the full log history
- **Done when:** generated issues include a concise log excerpt, occurrence metadata, reproduction hints when available, recent user action when available, and links or references to the retained evidence.

### 8. Protect Private User Data
- **As a:** user or developer running local debug builds
- **I want:** logs sanitized before they become persistent issues
- **So that:** private file paths, project names, sample names, and document contents are not captured casually
- **Done when:** the pipeline applies privacy rules before writing issues and either redacts sensitive fields or marks events for human triage when safe redaction is uncertain.

## Acceptance Signals

- A first implementation can run locally against the chosen application log source and produce structured candidate events.
- Repeated instances of the same runtime problem update one issue record rather than creating duplicates.
- Generated issue text includes severity, fingerprint, first-seen and last-seen metadata, occurrence count, compact evidence, and available build provenance.
- Commit language is conservative: the system reports "observed in" from app build metadata and reserves "introduced by" for cases with historical absence/presence evidence.
- The routing decision is explicit on each issue: active worker, sweeper queue, or needs triage.
- Known benign events can be suppressed without deleting historical evidence for real issues.
- The issue pipeline does not persist private paths, sample names, or document-specific data unless the privacy policy explicitly allows it.
- The system can be reviewed manually before any bridge to GitHub, Linear, or another external tracker is added.

## Assumptions

- The initial version should keep generated issue state local before integrating with external trackers.
- The authoritative log source is not decided yet and should be inspected during the existing-state phase.
- Build metadata will likely need to be embedded into the app so log events can report commit, branch, build timestamp, and dirty status reliably.
- "Observed in commit" is easier and safer than "introduced by commit"; introduction attribution needs stored historical fingerprint evidence or a repeatable bisect workflow.
- Ambiguous ownership should route to triage instead of guessing.
- Privacy filtering is part of the minimum viable workflow, not a later enhancement.
