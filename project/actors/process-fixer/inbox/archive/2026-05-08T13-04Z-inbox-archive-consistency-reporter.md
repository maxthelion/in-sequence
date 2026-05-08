---
created: 2026-05-08T13:04:00Z
source: process-health-observer
status: pending
priority: medium
action: add-small-deterministic-observation-script
---

# Add Inbox Archive Consistency Reporter

## Symptom

Recent evidence scripts still show archived actor requests whose frontmatter
claims `status: pending`. This is not blocking product work, but it makes
future observers spend time deciding whether archive location or status
frontmatter is authoritative.

## Evidence

- `scripts/multi-pass/evidence-inboxes.sh` at 2026-05-08T12:59Z reported fresh
  archived requests with `status: pending` under architecture, build-loop,
  visual-review, UX/IA, work-observer, holistic-observer, and
  process-health-observer archives.
- `docs/multi-pass-coordinator/coordinator/process-health.md` records this as
  the remaining deterministic-observation gap.
- The loop otherwise reached a P0 product-owner checkpoint, so this should stay
  a harness hygiene repair and not become product work.

## Smallest Repair

Add a report-only script under `scripts/multi-pass/` that scans configured
actor inboxes and reports:

- archived request files whose frontmatter still says `status: pending`;
- active inbox files that also appear archived by basename;
- duplicate coordinator completion notes for the same actor/request/final when
  that can be detected cheaply.

The script should exit successfully after reporting; it should not mutate
archives or inboxes. If wiring it into `docs/multi-pass-coordinator/settings.yaml`
would exceed the process-fixer write scope, leave that as a coordinator note
instead of editing settings.

## Healthy Again When

Process-health and coordinator actors can run one deterministic command to see
whether archive/status inconsistencies are present without rereading every
recent inbox archive manually.
