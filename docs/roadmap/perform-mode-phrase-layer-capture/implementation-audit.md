---
feature: perform-mode-phrase-layer-capture
created: 2026-06-18
status: partial-first-slice
sources:
  - docs/roadmap/perform-mode-phrase-layer-capture/spec.md
  - docs/roadmap/perform-mode-phrase-layer-capture/implementation-handoff.md
---

# Implementation Audit

This records the state after the first direct implementation slice. It is not a
done declaration for the whole feature.

## Implemented In This Slice

- Phrase page now has a phrase shell with Perform Off/On, changed summary,
  Capture, Discard, Moment/Latch, and phrase-local quantize control.
- Capture Phrase uses the existing phrase destination chooser copy and no
  longer presents itself as a changed-cell review.
- The old top-bar quantize pill has been removed; quantize is controlled from
  the phrase shell and is disabled/de-emphasized when Moment is selected.
- `SequencerDocumentSession.setPhraseCell` now routes phrase cell writes to the
  perform overlay while workspace mode is Perform.
- Phrase matrix display reads through `phraseWithPerformOverlay`, so staged
  perform values are visible before capture.
- Phrase matrix scalar drag and boolean toggle paths use `setPhraseCell`, so
  normal value changes follow the baseline-versus-perform-copy boundary.
- Focused tests cover setup-mode canonical writes and perform-mode overlay
  writes without mutating the canonical phrase.
- A Foreman build loop config has been added for the remaining feature work and
  review gates.

## Implemented In Second Slice

- Phrase layer toolbar now has explicit Value and Automation tools.
- Normal phrase matrix cell clicks no longer open the old hidden double-click
  editor path.
- Boolean layer cells still toggle directly through `setPhraseCell`.
- Pattern layer cells now cycle pattern index directly through `setPhraseCell`.
- Automation tool clicks open the deeper cell editor/modal for the selected
  track/layer.
- The deeper cell editor now reads the effective phrase state through
  `phraseWithPerformOverlay`.
- Deeper cell edits now write through `setPhraseCell`, so Perform mode stages
  those edits into the overlay instead of mutating the canonical phrase.
- Focused tests cover bar/automation-shaped cell replacement in Perform mode.

## Verified

- `xcodebuild test -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests`
  passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild build` passed for the app target.
- After the second slice, the same focused test target passed again with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Still Not Done

- Transport still needs the full current phrase / next phrase / boundary
  progress treatment from the spec.
- Phrase page does not yet have final Layers, Scenes, and Global Apply tabs as
  separate production surfaces.
- Global Apply is not yet implemented as a phrase-local scoped matrix surface.
- Scenes has not yet been moved into the phrase-local A/B/crossfader tab.
- Moment and Latch behavior is currently represented in the shell; quantized
  latch execution and length-limited expiry still need engine-level handling.
- Visual review evidence against the V3 prototype has not yet been captured for
  the built app.
- The automation modal is still visually the existing editor restyled as
  "Automation"; it needs a UX review against the V3 intent before the full
  feature can be called done.

## Next Build-Loop Action

Build the production Phrase Global Apply tab around the existing matrix grammar:

- phrase-local, not top-level;
- show the current scope count;
- use an eight-column matrix for track scope selection;
- apply one chosen layer/value action to the whole scope through
  `setPhraseCell`;
- reuse the same Moment/Latch gesture model as the phrase shell.
