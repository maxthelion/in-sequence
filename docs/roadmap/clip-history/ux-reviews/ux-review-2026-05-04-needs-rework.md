---
verdict: needs-rework
redirect_to: build-prototypes
updated: 2026-05-04
---

# Clip History UX Review

> Superseded as the active roadmap gate on 2026-05-04 by the replacement prototype pass in `prototypes/clip-history-dual-grid-v4.html`. Keep this review as the critique that drove the rework; the next PM-loop action should write a fresh `ux-review.md` against the replacement pass.

## User Feedback

The modal version is the stronger direction.

The prototypes did not fully understand the production application's current visual language, which is acceptable for rough Balsamiq-style exploration, but the next pass should better respect the app's structure.

## Direction To Keep

Use the modal pattern as the basis for the next design pass.

The current accepted interaction model is:

- recent history clips as a 4x4 matrix on one side;
- the 16 pattern slots as a similar 4x4 element on the other side;
- a lower preview and audition area for the selected virtual clip;
- explicit source selection, destination selection, and overwrite confirmation before save.

## What Failed Or Needs Another Pass

- The built modal regressed from "choose a musical moment from history" to "save the latest capture length," so the source-selection concept must be rebuilt.
- The next prototype must make source history and destination pattern slots symmetrical 4x4 matrices with equal visual weight.
- The preview area must clearly separate temporary audition state from committed pattern-slot state.
- Save must stay disabled until the user explicitly picks both a history cell and a destination slot, and occupied slots must require a visible overwrite-confirmation step.
- The modal layout needs a stable minimum size that does not crop its title or main content.
- The build path must not poll engine capture state from `body`; opening the modal freezes one snapshot and subsequent slot clicks stay on cheap local UI state.

## Rework Trigger

See [feedback/2026-05-04-built-modal-ux-review.md](feedback/2026-05-04-built-modal-ux-review.md). That review supersedes the previous build-ready interpretation of this feature and sends the roadmap back to `build-prototypes`.

## Architecture Questions To Resolve Before Spec

- How is recent step history stored in a lightweight way?
- How does scrubbing through history create a pseudo clip for audition?
- Where does pseudo-clip playback live so it does not become accidental document truth?
- At what exact action does the pseudo clip become a real persisted clip?
- How does this fit existing sequencer data patterns rather than forcing broad document rewrites?
