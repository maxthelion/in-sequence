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

## Implemented In Fifth Slice

- `PhraseModel` now carries an optional `PhraseSceneState` for scene A, scene B,
  and crossfader.
- `PhrasePerformOverlayState` can stage phrase scene state alongside normal
  layer cells.
- Setup-mode scene changes write to the phrase baseline; Perform-mode scene
  changes stage into the live phrase copy.
- Capture, save-back, and revert now include staged scene state.
- The phrase Scenes tab reads through `resolvedPhraseSceneState`, so staged
  scene changes are visible before capture.
- Scene A/B/crossfader values compile into `PhrasePlaybackBuffer`.
- Phrase playback applies phrase scene state to the master bus host on phrase
  entry/switch without mutating the global master-bus defaults.
- Focused tests cover setup write, perform staging, save-back, and capture for
  phrase scene state.

## Implemented In Sixth Slice

- The transport phrase control now exposes Current and Next as separate readable
  elements rather than hiding queued state inside one compact pill.
- Stopped transport shows the selected phrase as the current phrase instead of
  replacing phrase context with "Stopped".
- Free mode shows no next phrase until a phrase is queued.
- Song mode previews the arrangement-proposed next phrase when there is no
  explicit queued override.
- Queued phrases still use the existing phrase launch grid and cue/switch
  semantics.
- A small phrase progress bar and bar readout are visible in the transport
  control, using the existing `PhrasePlayhead` rather than a second timing
  model.
- Transport current/next/progress presentation is factored into pure helpers so
  stopped, Free, Song, queued override, looped phrase, and progress cases have
  focused regression coverage without requiring visual automation.

## Implemented In Seventh Slice

- Phrase-local Layers and Global Apply now use the existing quantised mute
  scheduler when the phrase shell is in Latch mode, Q:BAR is active, the
  transport is running, and the selected layer is Mute.
- Moment mode never arms quantised mute from the phrase surfaces.
- Pattern, scalar, scene, and fill-flag phrase edits still land immediately;
  Fill's existing runtime cue is not reused here because it does not capture
  back into the phrase perform overlay.
- The timing decision is covered by `PhrasePerformTimingPolicyTests`, including
  the explicit non-goal that fill/pattern do not use the mute scheduler.

## Implemented In Eighth Slice

- The visible top-bar Setup/Perform switch has been removed from
  `StudioTopBar`.
- The underlying session `WorkspaceMode` remains in place for tracks/scenes
  behavior and visual-scenario command compatibility.
- This resolves the visible anti-hybrid issue where phrase-local Perform/Capture
  coexisted with a global top-level Perform affordance.

## Implemented In Ninth Slice

- Phrase-local Latch now has a `LEN: HOLD` / `LEN: 1B` control in the phrase
  header.
- A one-bar length-limited Mute uses the quantised toggle scheduler, commits at
  the bar boundary, and stages a bar-shaped phrase cell in the perform overlay.
- The scheduler records the committed boundary tick so the session can compute
  which phrase bar receives the temporary mute value.

## Implemented In Tenth Slice

- A session-level playback agreement test now proves perform-overlay phrase
  values reach the engine-visible playback snapshot.
- The covered fields are pattern slot, mute, fill flag, repeat count, loop flag,
  and phrase scene state.
- This narrows the previous acceptance gap where tests proved overlay reads but
  not that the installed playback snapshot used the overlay-applied phrase.

## Implemented In Eleventh Slice

- The phrase-local Latch length chip now cycles through `LEN: HOLD`, `LEN: 1B`,
  `LEN: 2B`, `LEN: 4B`, and `LEN: 8B`.
- Multi-bar length-limited Mute staging is covered at the session boundary: a
  committed two-bar latch writes a bar-shaped phrase cell for the two bars
  beginning at the committed boundary.
- This keeps the surface matrix-like and avoids adding another modal or detail
  panel for latch length.

## Implemented In Twelfth Slice

- The automation sheet now has an explicit Clear Automation action.
- Clearing automation collapses bars/steps/curve cells to a single phrase-cell
  value resolved at the current phrase playhead position.
- The underlying deterministic helper is covered by phrase policy tests so
  clearing bar and curve automation preserves the currently heard value rather
  than snapping to a default.

## Implemented In Thirteenth Slice

- A focused acceptance-style test now proves direct Perform-layer writes are
  immediate for pattern, mute, and fill.
- The test runs without transport, confirms the engine-visible playback
  snapshot updates after each write, and confirms no quantized arm remains
  pending.

## Implemented In Fourteenth Slice

- Phrase navigation tests now explicitly cover runtime application of phrase
  scene state, not just phrase-scene persistence in the playback snapshot.
- Playback start applies the current phrase's scene A, scene B, and crossfader
  selection to the master bus.
- A queued phrase boundary applies the promoted phrase's scene A, scene B, and
  crossfader selection to the master bus.
- This closes a stale evidence gap around whether the phrase Scenes surface is
  merely stored or actually reaches runtime playback state.

## Implemented In Fifteenth Slice

- Phrase-local Latch/Q:BAR now treats Fill Flag as a capturable phrase-layer
  change rather than only a runtime one-bar cue.
- The quantised scheduler carries live fill-flag overrides so the boundary tick
  hears the new Fill value immediately, then the session stages the overlay cell
  and retires the override.
- Length-limited Fill Flag commits stage bar-shaped phrase cells, matching the
  existing length-limited Mute behavior.
- Layers and Global Apply route both Mute and Fill through the quantised boolean
  latch path; Pattern and scalar layers remain immediate pending an explicit
  product decision about scheduled non-boolean layer semantics.

## Verified

- `docs/roadmap/perform-mode-phrase-layer-capture/acceptance-verification.md`
  now maps the spec acceptance criteria to current code/test evidence and
  explicitly marks partial, missing, and anti-hybrid concerns.
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
- After the fifth slice, `xcodebuild build` passed for the app target with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the fifth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests` passed with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the sixth slice, `xcodebuild build` passed for the app target with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After transport presentation hardening, `xcodebuild test
  -only-testing:SequencerAITests/TransportPhraseNavigationPresentationTests`
  passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After transport presentation hardening, `xcodebuild build` passed for the app
  target with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the seventh slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformTimingPolicyTests` passed with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the seventh slice, `xcodebuild build` passed for the app target with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the eighth slice, `xcodebuild build` passed for the app target with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After the eighth slice, `xcodebuild test
  -only-testing:SequencerAITests/WorkspaceModeTests` passed with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when rerun outside
  the sandbox after the sandboxed runner could not reach Xcode's helper
  services.
- After the ninth slice, the app target built with direct `xcodebuild` using
  `/tmp/seqai-phrase-perform-build`.
- After the ninth slice, `xcodebuild test
  -only-testing:SequencerAITests/QuantisedToggleSchedulerTests` passed with
  direct `xcodebuild`.
- After the ninth slice, `xcodebuild test
  -only-testing:SequencerAITests/SequencerDocumentSessionQuantisedToggleTests/test_committedLengthLimitedMuteStagesBarCellForTheCommittedBar`
  passed with direct `xcodebuild`.
- After the tenth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests/test_performOverlayPublishesEngineVisiblePhrasePlaybackState`
  passed with direct `xcodebuild`.
- After the tenth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests` passed with
  direct `xcodebuild`.
- After the tenth slice, the app target built with direct `xcodebuild` using
  `/tmp/seqai-phrase-perform-build`.
- After the eleventh slice, `xcodebuild test
  -only-testing:SequencerAITests/SequencerDocumentSessionQuantisedToggleTests/test_committedLengthLimitedMuteCanSpanMultiplePhraseBars`
  passed with direct `xcodebuild`.
- After the eleventh slice, `xcodebuild test
  -only-testing:SequencerAITests/SequencerDocumentSessionQuantisedToggleTests`
  passed with direct `xcodebuild`.
- After the eleventh slice, the app target built with direct `xcodebuild` using
  `/tmp/seqai-phrase-perform-build`.
- After the twelfth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePolicySessionTests` passed with direct
  `xcodebuild`.
- After the twelfth slice, the app target built with direct `xcodebuild` using
  `/tmp/seqai-phrase-perform-build`.
- After the thirteenth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests/test_performModeDirectLayerChangesPublishImmediatelyWithoutTransport`
  passed with direct `xcodebuild`.
- After the thirteenth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformOverlaySessionTests` produced the
  normal completion footer and exited after the wrapper cleared; no
  `xcodebuild`/`xctest` process remained.
- After the thirteenth slice, the app target built with direct `xcodebuild`
  using `/tmp/seqai-phrase-perform-build`.
- After the fourteenth slice, `xcodebuild test
  -only-testing:SequencerAITests/EngineControllerPhraseNavigationTests` passed
  with direct `xcodebuild`.
- After the fifteenth slice, `xcodebuild test
  -only-testing:SequencerAITests/PhrasePerformTimingPolicyTests` passed with
  direct `xcodebuild`.
- After the fifteenth slice, `xcodebuild test
  -only-testing:SequencerAITests/QuantisedToggleSchedulerTests` passed with
  direct `xcodebuild`.
- After the fifteenth slice, `xcodebuild test
  -only-testing:SequencerAITests/EngineControllerQuantisedToggleTests` passed
  with direct `xcodebuild`.
- After the fifteenth slice, `xcodebuild test
  -only-testing:SequencerAITests/SequencerDocumentSessionQuantisedToggleTests`
  passed with direct `xcodebuild`.
- After the fifteenth slice, the app target built with direct `xcodebuild`
  using `/tmp/seqai-phrase-perform-build`.

## Still Not Done

- Transport now has current phrase, next phrase, and cycle progress visible, but
  it still needs visual review against the V3 prototype and runtime checking in
  both Song and Free playback.
- Scenes is now in the phrase-local A/B/crossfader tab and stores single phrase
  values for scene A, scene B, and crossfader. Per-bar/continuous scene values
  and macro automation have not been implemented.
- Moment and Latch behavior is partially engine-backed for phrase-local Mute
  changes. Length-limited Mute now commits at the bar boundary and stages a
  bar-shaped phrase cell across the configured bar span. General phrase-cell
  quantized execution and length-limited behavior for other layers still need
  engine-level handling.
- Playback snapshot agreement is proven for pattern, mute, fill, repeat/loop,
  and scene state, but it still needs interactive runtime evidence while the app
  is playing.
- Direct Moment-style pattern, mute, and fill writes are proven to publish
  immediately into the engine-visible snapshot, but they still need interactive
  runtime evidence on the built surface.
- The visible top-level Perform affordance is gone, but the internal
  `WorkspaceMode.perform` naming still exists and may need a later rename if it
  keeps confusing the phrase-local Perform model.
- Visual review evidence against the V3 prototype has not yet been captured for
  the built app.
- The automation modal now has a Clear Automation action, but its visual shape
  still needs review against the V3 intent before the full feature can be
  called done.
- Global Apply needs visual review and likely refinement against the V3 matrix
  intent, especially scope default semantics.

## Next Build-Loop Action

Review and harden the built phrase perform surface before more feature growth:

- resolve or explicitly accept the remaining partial/missing items in
  `acceptance-verification.md`;
- run visual review against the V3 prototype for Layers, Scenes, and Global
  Apply, and the transport current/next/progress control;
- extract the duplicated scene crossfader view into a shared component if the
  visual shape survives review;
- decide whether scene macro moves become phrase-cell automation or a separate
  phrase-scene event lane;
- then extend Moment/Latch engine semantics beyond one-bar Mute and implement
  the remaining scene automation model.
