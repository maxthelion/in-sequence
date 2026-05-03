---
verdict: accepted
selected_prototype: 01-log-inbox-routing.html
reviewed: 2026-05-03
prototypes_reviewed:
  - prototypes/01-log-inbox-routing.html
  - prototypes/02-issue-draft-review.html
feedback_applied: []
---

# Observability From Application Logs — UX Review

## What Works

### 01-log-inbox-routing.html

The queue-first direction makes the core operator job legible immediately: scan new fingerprints, see severity and occurrence count, compare observed-commit context, then choose whether the event becomes an issue, a suppression, or a triage item. That directly supports the dedupe, thresholding, provenance, routing, and privacy stories without pretending the collector itself is already solved.

The strongest decision in this prototype is the separation between `Observed in` and `Introduced by`. That avoids false blame on the latest commit and keeps the provenance language honest. The routing card also handles the most important ownership split well: active worktree vs sweeper vs human triage.

The selected event detail is specific enough to review before action. It shows first-seen and last-seen timestamps, the worktree or branch context, a redacted evidence sample, and explicit route choices next to the action buttons. That keeps the primary controls local to the thing they affect.

### 02-issue-draft-review.html

The detail-first review screen is a useful companion, especially for privacy-sensitive events. It makes the release gate concrete by forcing the reviewer to inspect the draft issue body, the queue destination, and the privacy/provenance checklist before approval. The "introduced by" field staying blank until evidence exists is the right default.

This prototype also shows a good downstream policy boundary: what data is kept, what is removed, and what is deferred. That is valuable input for architecture and spec even though it is not the primary navigation surface.

## What Fails or Is Missing

### 1. The handoff from queue to draft review is implied, not demonstrated

Prototype 1 has a `Create issue draft` action and Prototype 2 shows the draft-review screen, but the transition is only inferable. The direction still works, but the user review should confirm that the intended flow is "queue overview first, draft inspection second" rather than two competing entry points.

### 2. Empty, collector-failure, and no-provenance states are not shown

The happy path is well covered, but the workflow does not yet show what happens when there are no actionable fingerprints, the collector fails to load logs, or build metadata is missing entirely. Those are important because this feature exists to deal with imperfect runtime evidence.

### 3. Suppression management is still too stubbed to trust long-term noise control

The queue-first prototype includes a `Suppress fingerprint` action, but it does not show the audit trail, reason capture, expiry rules, or how a suppressed event returns when it regresses. That is acceptable for prototype review, but architecture should treat suppression policy as a first-class requirement rather than a button label.

### 4. Route confidence needs a clearer explanation when multiple worktrees are active

Prototype 1 correctly distinguishes active-worker routing from sweeper routing, but it does not show what evidence produces that recommendation or how ambiguity is surfaced when more than one unmerged range could plausibly own the event. The design should not imply more attribution certainty than the system can actually provide.

## UX Checklist

| Criterion | Result |
|-----------|--------|
| Goal clarity | Pass — the operator goal is visible in both variants |
| Progressive disclosure | Pass — queue scan first, detail second |
| Information hierarchy | Pass — severity, provenance, and route dominate |
| No repeated information | Partial — the two variants overlap intentionally, but the queue-to-detail relationship should be made more explicit |
| Flow grouping | Pass — event evidence, route choice, and action buttons stay grouped |
| State legibility | Pass — selected event, severity, and suggested route are all obvious |
| Action locality | Pass — create/suppress/route controls sit beside the selected event details |
| Reversibility | Partial — suppression and queue decisions do not yet show undo/audit affordances |
| Empty and error states | Partial — missing collector/empty queue states are not shown |
| Performance feel | Pass — the primary review path stays within two steps |
| Keyboard and pointer ergonomics | Pass — scanning and single-selection review look practical |
| Consistency | Pass — both variants use the same provenance and privacy language |

## User-Story Goal Coverage

| Story | Coverage |
|-------|----------|
| 1. Collect runtime log evidence | Partial — assumes a collector exists; source selection remains out of scope |
| 2. Convert logs into structured events | Covered — event fields and typed evidence are visible |
| 3. Collapse duplicate events | Covered — fingerprints and occurrence counts are explicit |
| 4. Separate issues from observations | Covered — create issue vs observation vs suppress is clear |
| 5. Attach honest commit provenance | Covered — "observed in" vs "introduced by" is the core strength |
| 6. Route work to the right queue | Covered — active worker, sweeper, and human triage all appear |
| 7. Preserve useful reproduction context | Covered — evidence excerpts, timestamps, and environment cues are visible |
| 8. Protect private user data | Covered — redaction and privacy review are first-class steps |

## Recommended Direction

Accept the queue-first direction in `01-log-inbox-routing.html` as the primary prototype for human review. It gives the clearest answer to the main workflow question: how a maintainer moves from repeated runtime fingerprints to a routed issue without flooding the queue or blaming the wrong commit.

Carry forward the strongest detail-level elements from `02-issue-draft-review.html` into that direction, especially the explicit release gate checklist and the "kept vs removed vs deferred" privacy summary. Those should become the second-step review state after the queue selection rather than a separate competing prototype track.

## Questions For Human Review And Architecture

1. Should the intended primary flow be explicitly two-step: queue triage first, draft review second?
2. When build metadata is missing, should the UI default to human triage immediately or allow issue creation with a weaker provenance label?
3. What minimum audit trail is required for suppression decisions: reason, expiry, reviewer, and regression reopen rules?
4. What evidence should justify an "active worker" recommendation when several unmerged worktrees exist at once?
5. Does the first implementation need an explicit empty-state and collector-failure screen before architecture can proceed, or are those acceptable to defer to spec?
