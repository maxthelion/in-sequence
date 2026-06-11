---
status: open
source:
  - docs/roadmap/song-mode-phrase-looping/user-stories.md
  - docs/roadmap/song-mode-phrase-looping/existing-state.md
  - docs/roadmap/song-mode-phrase-looping/artifacts.md
  - docs/roadmap/song-mode-phrase-looping/ux-review.md
updated: 2026-06-04
---

# Song Mode And Phrase Looping Open Questions

This document packages the remaining PM questions from the accepted UX review,
the existing-state architecture decision points, and the Tracks UI screenshot
note. It does not answer architecture or implementation details.

## Product And UX Questions

| ID | Question | Source | Recommended handling |
|----|----------|--------|----------------------|
| Q1 | Does the `Now` immediate-switch action dismiss the phrase dropdown? | UX review, prototype 01 | Decide in spec. Recommendation from review: dismiss after switch to avoid stale open state during playback. |
| Q2 | Can the performer clear a queued phrase without substituting another phrase? | UX review, prototype 01 | Product decision needed before final spec, or explicitly accept re-queue-only cancellation for MVP. This is a live-performance recovery risk. |
| Q3 | Does tapping outside the phrase dropdown dismiss it? | UX review, prototype 01 | Decide in spec. Recommendation from review: yes, with the SwiftUI equivalent of outside-tap dismissal. |
| Q4 | Should cycle progress be shown per bar or per step? | UX review, prototype 01 | Decide in spec. Recommendation from review: per-bar for MVP; per-step can be a refinement. |
| Q5 | How should long queued-phrase names appear in the crowded transport bar? | UX review, prototype 01 | Decide in spec. Recommendation from review: use a compact icon plus short name, or a fixed truncation rule. |
| Q6 | What is the stopped-state treatment for the phrase queue button? | UX review, prototype 01 | Define disabled SwiftUI treatment in spec, including why the queue action is unavailable when no phrase is playing. |
| Q7 | How should the transport phrase controls behave on narrow or crowded layouts? | UX review, prototype 01 | Add spec constraints for truncation, minimum readable labels, and whether secondary state collapses. |
| Q8 | If a queued phrase becomes the Tracks UI basis phrase and the performer edits it, what happens if the queue is later cancelled? | UX review, prototype 02 | Product decision needed before final spec, or explicitly accept "edits land immediately in the queued phrase" as MVP semantics. This is the highest data-surprise risk. |
| Q9 | Is the existing top-right `Basis Phrase` panel the canonical UI placement, or should the prototype's inline basis label be introduced? | artifacts.md, UX review, prototype 02 | Resolve in spec against the screenshot. The feature must update the existing basis phrase context even if an additional inline cue is added. |
| Q10 | What should the Tracks UI basis phrase show when playback is stopped while a phrase is queued? | UX review, prototype 02 | Decide in spec. Likely candidates are selected phrase, last active phrase, or queued preview until cleared. |
| Q11 | How should the Tracks UI grid resize or scroll when the basis phrase changes to a phrase with a different bar count? | UX review, prototype 02 | Declare an MVP constraint or define resize/scroll behavior in spec. Review recommended same-bar-count as an MVP constraint. |
| Q12 | Should the basis phrase banner behavior apply to the current `.song` auto-cycle mode? | UX review, existing-state.md | Defer for this feature unless architecture/spec explicitly keeps the behavior within free-play phrase navigation. |

## Architecture Decision Points To Carry Forward

| ID | Decision point | Why it matters |
|----|----------------|----------------|
| A1 | Where do `currentPhraseID`, `queuedPhraseID`, and `basisPhraseID` live and how are they published? | The transport bar and Tracks UI both need coherent phrase state, but the existing model only exposes `selectedPhraseID`. |
| A2 | Should queued/basis phrase state be live performance state on `EngineController`, persisted document state, or a mutation of `session.store.selectedPhraseID`? | This decides whether cueing a phrase changes saved project selection or only live playback/editing context. |
| A3 | What emits the phrase-boundary event that promotes `queuedPhraseID` to `currentPhraseID`? | End-of-cycle switching requires a reliable musical boundary signal; the current tick engine has no callback for it. |
| A4 | Should `PlaybackSnapshot` include queued phrase state? | The current snapshot carries only `selectedPhraseID`; queued switching may need snapshot participation depending on the chosen engine design. |
| A5 | How should the three duplicated view-side `playbackPhraseIndex` derivations be consolidated or bypassed? | Current phrase identity is derived independently in three views and is not tested, which is risky once transport state becomes performer-facing. |
| A6 | How narrowly should this feature treat "Song Mode"? | Existing `.song` mode is a stub/auto-cycle behavior. This feature should not accidentally expand into a full scripted arrangement feature. |

## Already Answered By Approved Prototypes

- Queuing a phrase should immediately update the Tracks UI basis phrase for
  preview/editing context.
- End-of-cycle switching and immediate switching should both update the
  transport current-phrase indicator and the Tracks UI basis phrase as one
  coherent state transition.
- Prototype 01 and prototype 02 are complementary design bases, not competing
  alternatives.

## Product-Owner Attention

No product-owner question is required merely to package this PM artifact layer.
If the next PM pass cannot choose safe MVP defaults, the most useful compact
owner questions are Q2 and Q8.
