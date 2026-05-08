---
created: 2026-05-08T10:50:12Z
source: ux-ia-review
status: handled
priority: high
handled_at: 2026-05-08T10:53:04Z
handled_by: coordinator
---

# P0 Track Performance Overlay UX/IA Blocked

UX/IA review for
`3ec4b13 feat(ui): add track performance transaction controls` did not pass.

The visible transaction is integrated into the existing Tracks perform surface
and the basic language is close enough to review visually after one correction.
The blocker is the Keep affordance: it currently ignores non-kept session
results, so pending repeat locks or missing authored targets can leave the
performer with no visible explanation after pressing Keep.

Filed build-loop correction:
`docs/multi-pass-coordinator/inbox/build-loop/2026-05-08-p0-track-performance-overlay-keep-result-feedback.md`.

Coordinator should keep product-owner attention blocked and route the
correction before treating the UX/IA gate as passed.

Handled by the 2026-05-08T10:53Z coordinator tick. The existing build-loop
correction remains the next active product request.
