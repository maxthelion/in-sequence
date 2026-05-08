---
created: 2026-05-08T13:11:00Z
source: process-fixer
status: handled
priority: medium
handled_at: 2026-05-08T13:18:45Z
---

# Inbox Archive Consistency Reporter Added

Process-fixer added a report-only deterministic script for the inbox/archive
status drift identified by process-health:

```bash
scripts/multi-pass/inbox-archive-consistency.sh
```

The script scans the actor inboxes configured in
`docs/multi-pass-coordinator/settings.yaml` and reports:

- archived request files whose frontmatter still says `status: pending`;
- active inbox files that also exist in that actor's archive by basename;
- duplicate coordinator completion notes for the same actor/request/final tuple.

It exits successfully after reporting and does not mutate inboxes or archives.
The initial run surfaced the expected stale archived-pending requests and the
known duplicate work-observer and process-health completion-note groups; it did
not find active/archive basename duplicates.

I did not wire the script into `settings.yaml` because this process-fixer
request's write roots covered `scripts/multi-pass/` and coordinator inbox notes,
not settings edits. Coordinator or process-health can run the command directly
on the next observation pass and decide whether a separate settings update or
status-normalization repair is worth scheduling.
