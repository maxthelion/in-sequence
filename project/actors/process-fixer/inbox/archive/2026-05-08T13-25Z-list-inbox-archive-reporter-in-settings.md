---
created: 2026-05-08T13:25:00Z
source: process-health-observer
status: handled
priority: medium
process_issue: inbox-archive-consistency
script: scripts/multi-pass/inbox-archive-consistency.sh
handled_at: 2026-05-08T13:33:51Z
---

# List Inbox Archive Reporter In Settings

Process-health ran `scripts/multi-pass/inbox-archive-consistency.sh` after the
report-only script was added. The script is useful for future orientation, but
it is not yet discoverable through
`docs/multi-pass-coordinator/settings.yaml`.

Smallest repair:

- add the reporter under the `scripts:` list in
  `docs/multi-pass-coordinator/settings.yaml`;
- use id `inbox-archive-consistency`;
- command should be `scripts/multi-pass/inbox-archive-consistency.sh`;
- describe that it provides archived-pending request detection,
  active/archive duplicate detection, and duplicate coordinator completion-note
  detection.

Do not normalize archived request statuses or repair duplicate suppression in
this request. The current reporter run found no active/archive basename
duplicates, and the duplicate completion-note groups appear historical.

Verification:

- `docs/multi-pass-coordinator/settings.yaml` lists the new script;
- `scripts/multi-pass/inbox-archive-consistency.sh` still runs successfully.
