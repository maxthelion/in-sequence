---
id: 1
title: Clip History
status: inventory
priority: unset
blocked_by: []
stage: ready-for-build
owner: pm
updated: 2026-05-21
ux_review_archived: docs/roadmap/clip-history/ux-reviews/ux-review-2026-05-04-needs-rework.md
---

# Clip History

Status: ready for a fresh build-loop pass. The authoritative UI target is
[`prototypes/clip-history-dual-grid-v4.html`](./prototypes/clip-history-dual-grid-v4.html),
approved in [`prototype-approval.md`](./prototype-approval.md).

The earlier merged modal on `main` is not accepted as the finished feature. It
implemented a "save latest capture" flow and caused the UX review in
[`feedback/2026-05-04-built-modal-ux-review.md`](./feedback/2026-05-04-built-modal-ux-review.md).
Future work should preserve any useful engine/model pieces, but it must build
the v4 source-to-destination transfer model: frozen 16-bar history as a 4x4
source matrix, pattern slots as a matching 4x4 destination matrix, explicit
history-region selection, temporary virtual-clip preview/audition, save disabled
until source and destination are selected, and occupied-slot replacement gated
by confirmation.

An older branch, `auto/roadmap-1-clip-history`, contains salvageable work
(`CaptureSnapshot`, `PseudoClipState`, frozen-snapshot modal pieces, and tests)
but is stale relative to current `main`. Treat it as implementation reference,
not as build authority.
