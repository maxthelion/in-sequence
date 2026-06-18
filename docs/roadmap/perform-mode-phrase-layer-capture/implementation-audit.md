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

## Implemented In Third Slice

- Phrase page now has phrase-local tabs for Layers, Scenes, and Global Apply.
- Global Apply is phrase-local and scoped to the selected phrase.
- Empty Global Apply scope means all tracks; explicit scope can be selected from
  an eight-column track matrix.
- Global Apply action choices are matrix cells using the existing performance
  layer grammar rather than form controls.
- Global Apply applies one cycled layer value to the whole scope through
  `setPhraseCell`, so Perform mode stages the change in the overlay and setup
  mode writes baseline.
- Focused tests cover multi-track scoped writes in Perform mode.

## Implemented In Fourth Slice

- The Scenes tab is now a concrete phrase workspace surface rather than a
  placeholder.
- It uses the existing scene grammar: Slot A, crossfader, and Slot B.
- Slot A/B cards use the existing `MasterBusScene` and `MasterBusABSelection`
  model instead of inventing a parallel phrase-scene model.
- Slot picking uses the existing scene picker semantics and writes through
  `setMasterABMode`.
- Crossfader moves use the existing live master crossfader overlay.
- Scene macro wells reuse the existing `MacroSlotKnob` primitive and existing
  master scene macro override plumbing.
- The new wrapper is phrase-local in the IA, but phrase-specific persistence of
  scene selection/crossfader/macro automation remains explicit model work.
- A small phrase-local crossfader track view was copied because the existing
  scene perform crossfader is private to `ScenesWorkspaceView+Perform`; this
  should be extracted to a shared component in a cleanup pass.

## Verified

- `xcodebuild test -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests`
  passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild build` passed for the app target.
- After the second slice, the same focused test target passed again with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the third slice, `xcodebuild build` passed for the app target and
  `xcodebuild test -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests`
  passed again with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the fourth slice, `xcodebuild build` passed for the app target with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the fourth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests` passed with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Still Not Done

- Transport still needs the full current phrase / next phrase / boundary
  progress treatment from the spec.
- Scenes is now in the phrase-local A/B/crossfader tab, but the values are not
  yet stored as phrase-cell/phrase-scene data, and per-bar/continuous scene
  values have not been implemented.
- Moment and Latch behavior is currently represented in the shell; quantized
  latch execution and length-limited expiry still need engine-level handling.
- Visual review evidence against the V3 prototype has not yet been captured for
  the built app.
- The automation modal is still visually the existing editor restyled as
  "Automation"; it needs a UX review against the V3 intent before the full
  feature can be called done.
- Global Apply needs visual review and likely refinement against the V3 matrix
  intent, especially scope default semantics.

## Next Build-Loop Action

Add phrase-scene persistence behind the production Scenes tab:

- define the minimal phrase-local data for A scene, crossfader, and B scene;
- preserve the current Slot A / crossfader / Slot B UI shape;
- keep macro wells tied to the scene currently selected in each slot;
- make scene choices/crossfader capture with the phrase perform overlay;
- defer full continuous scene automation until the phrase-scene value model is
  in place.
