---
status: fold-recommended
updated: 2026-06-08
owner: pm
related:
  - docs/roadmap/clip-history/README.md
  - docs/roadmap/clip-history/spec.md
  - docs/roadmap/clip-history/existing-state.md
  - docs/roadmap/clip-history/prototype-approval.md
  - docs/roadmap/clip-history/feedback/2026-06-02-inline-history-tab-feedback.md
  - docs/roadmap/clip-history/feedback/2026-06-02-live-buffer-save-arm-feedback.md
---

# Fill Clip From Generator Overlap Disposition

## Disposition

Recommendation: fold this deferred lane into Clip History / History and close it
as a separate build candidate.

The original lane intent is only "Commit current generator output into a clip."
That intent is now covered by the accepted generator-capture direction in Clip
History: recent generated or played output is kept in live history, a user can
choose a captured region, audition it as a virtual clip without mutating the
document, then explicitly save it into a pattern slot with replace protection.

The latest product-owner feedback strengthens the fold rather than creating a
separate lane. History should be an inline tab, work for generator and clip
sources, show the current live rolling bar when nothing is selected, enter
audition when a history segment is selected, and use `Save Clip` to arm the
existing pattern row as the destination picker. That makes "fill the clip from
the current generator" a state inside History, not a standalone workflow.

## Comparison

| Question | Deferred lane | Accepted History direction |
| --- | --- | --- |
| Source | "current generator output" is undefined: current rules, current bar, latest buffer, or what just played | live circular history of what played, including current filling bar when no segment is selected |
| Selection | no source-window semantics | explicit history selection, with no selection showing live rolling/current-bar state |
| Audition | unspecified | selected history becomes temporary virtual-clip audition; clearing selection exits audition |
| Destination | unspecified clip/pattern-slot behavior | `Save Clip` arms the existing pattern row as the destination picker |
| Overwrite | unspecified | occupied destinations require explicit replace behavior |
| Persistence | unspecified immediate write risk | document mutation happens only on explicit save; capture/history state remains live/session state |

## Distinct V1 Question Set

No distinct v1 question set remains after Clip History for this lane.

If future evidence shows History cannot satisfy a one-action capture need, reopen
that as Clip History follow-up scope, not as this old lane. The only questions
worth asking then would be:

- whether a shortcut should save the current live rolling bar without first
  selecting a history segment;
- whether that shortcut should bypass audition or merely preselect the current
  live bar inside History;
- how replace confirmation attaches to the already accepted pattern-row save
  arm.

Those are interaction refinements to History. They do not justify promoting
`fill-clip-from-generator` as an independent product lane.

## Promotion Recommendation

Do not promote this lane to a build loop. Treat item 17 as folded into Clip
History / History unless the product owner later asks for a separate one-shot
capture command after seeing the landed History workflow.
