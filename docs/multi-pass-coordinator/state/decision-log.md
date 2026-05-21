# Decision Log

Compact current-shape decision notes. Legacy coordinator logs are historical
context only.

## 2026-05-21T06:58Z

Accepted refreshed orientation that supersedes the older dirty Mixer Busses UI
merge snapshot: builder continuation completed clean commit `6622bc9` in
`.worktrees/roadmap-5-mixer-busses-ui-finish` with focused mixer/session tests
passing. Sent the build-loop decider an exact-state gate request for visual
economy, UX/IA, architecture, and testing review; did not reopen the stale
partial-work read. Scene Perform and Step Sequencer remain P1 PM-ready
follow-ons after Mixer Busses gates.

## 2026-05-21T07:44Z

Promoted `scene-perform` into `build/scene-perform` using the available v2
build-capacity slot. Mixer Busses remains active with routine builder and
visual-evidence follow-ups already pending inside `build/mixer-busses`; no
top-level micromanagement needed. Chose Scene Perform over Step Sequencer for
this slot because it is the lower-numbered P1 PM-ready item and advances the
scenes/live-performance workflow. Recorded the known clean-but-behind branch
and merge-tree conflict risk in the build-decider request.

## 2026-05-21T08:22Z

Accepted fresh work and feature-readiness observations over the older
orientation where they differ: both build slots are now occupied by
`build/mixer-busses` and `build/scene-perform`, each with current builder
requests already pending. The v2 capacity CLI reports zero available build
slots and `step-sequencer` as the only unpromoted ready candidate, so no new
promotion or top-level follow-up was scheduled. `step-sequencer` remains the
next clear ready candidate once a build slot opens; `clip-history` remains
PM-ambiguous.

## 2026-05-21T09:55Z

Reconciled Clip History PM artifacts after discovering the split state: `main`
contains the rejected save-latest modal, while `auto/roadmap-1-clip-history`
contains useful but stale repair work. Updated the roadmap artifacts so
`clip-history-dual-grid-v4.html` is build authority, added
`docs/roadmap/clip-history/build-resume-handoff.md`, and moved Clip History into
ready-for-promotion evidence. Do not merge the old branch as-is; when capacity
opens, create a fresh v2 build loop on current `main` and harvest the branch
deliberately.

## 2026-05-21T08:48Z

Accepted refreshed orientation that `build/scene-perform` is blocked on a
builder continuation after `usage_rate_limit`, not ready for review. Sent a
continuation request to `builder` for `build/scene-perform` to verify/resolve
the merge state, preserve the approved three-column Scene Perform intent, run
focused checks, capture feasible UI evidence, and report exact commit/check
state before any gates are routed. Mixer Busses remains blocked on its existing
visual-correction continuation, capacity remains full, and no product-owner
attention is needed.
