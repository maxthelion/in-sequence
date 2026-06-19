---
feature: perform-mode-phrase-layer-capture
created: 2026-06-18
status: partial-verification
sources:
  - docs/roadmap/perform-mode-phrase-layer-capture/spec.md
  - docs/roadmap/perform-mode-phrase-layer-capture/implementation-audit.md
  - Sources/UI/PhraseWorkspaceView.swift
  - Sources/UI/TransportBar.swift
  - Sources/App/PhrasePerformOverlayState.swift
  - Sources/App/SequencerDocumentSession+Mutations.swift
  - Tests/SequencerAITests/App/PhrasePerformOverlaySessionTests.swift
  - Tests/SequencerAITests/UI/TransportPhraseNavigationPresentationTests.swift
  - Tests/SequencerAITests/UI/PhrasePerformTimingPolicyTests.swift
---

# Acceptance Verification

This is a strict check against `spec.md`. It records what is proven by current
code/tests, what is only partially supported, and what still needs visual or
runtime evidence. A partial result means "do not call the whole feature done".

## Summary

- Verified enough to keep building: phrase overlay state, capture/discard model,
  transport phrase presentation, phrase scene single-value state, scoped Global
  Apply writes, the first quantized Mute latch policy, and length-limited Mute
  staging across one or more bars. Engine-visible playback snapshot
  coverage now proves phrase overlay values reach pattern, mute, fill,
  repeat/loop, and scene state buffers.
- Not yet verified enough to ship as the full feature: visual match to the V3
  wireframes, general latch length/expiry semantics beyond Mute, scene
  macro/per-bar/continuous automation, and interactive runtime evidence for the
  phrase surfaces while playback is running.

## Acceptance Criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Current phrase, next phrase, and progress are visible in transport. | Pass, needs visual review | `TransportPhraseNavigationPresentation` and `TransportPhraseProgressPresentation` drive separate current/next/progress UI in `Sources/UI/TransportBar.swift`. Covered by `TransportPhraseNavigationPresentationTests`. |
| 2 | Song mode proposes next phrase and Free mode starts with no next phrase. | Pass | Tests cover Free stopped with no next phrase and Song running with arrangement next phrase. |
| 3 | The user can cue/override the next phrase. | Partial | Presentation tests cover queued phrase overriding Song arrangement next. Existing phrase launch grid remains the interaction path, but this needs runtime/visual verification in the built app. |
| 4 | Phrase page has Layers, Scenes, and Global Apply tabs. | Pass, needs visual review | `PhraseWorkspaceTab` defines `layers`, `scenes`, and `globalApply`; `PhraseWorkspaceView` switches between those surfaces. |
| 5 | Perform Off edits phrase baseline directly. | Pass | `PhrasePerformOverlaySessionTests.test_setPhraseCellInSetupModeMutatesCanonicalPhrase` and scene setup tests prove setup-mode writes canonical phrase state. |
| 6 | Perform On edits a live phrase copy/overlay. | Pass | `PhrasePerformOverlayState` stores staged cells/scene state. Overlay tests prove perform-mode writes do not mutate canonical phrase and are read through `phraseWithPerformOverlay`. |
| 7 | Capture/Discard are visible but disabled when Perform is off. | Partial | `PhraseWorkspaceView` renders Capture/Discard in the phrase shell and gates actions from overlay state. This still needs visual review to prove disabled/off-state presentation is clear. |
| 8 | Dirty/changed state is visible when Perform is on and changes exist. | Pass, needs visual review | Overlay staged counts and dirty lookups are covered by `PhrasePerformOverlaySessionTests`. Built visual clarity is not yet reviewed. |
| 9 | Latch timing controls are phrase-local and inactive in Moment mode. | Partial | UI state and `PhrasePerformTimingPolicyTests` prove Moment does not arm quantized Mute. `PhraseWorkspaceView` now exposes phrase-local `LEN: HOLD`, `1B`, `2B`, `4B`, and `8B` only for Latch. Visual state remains unverified. |
| 10 | Layers uses an eight-column matrix and direct cell click changes values. | Partial | `PhraseWorkspaceView` uses eight-column grids and value-mode clicks route through direct `setPhraseCell` paths. Needs visual evidence against V3. |
| 11 | Automation mode changes layer-cell click behavior to open automation editing. | Partial | `PhraseCellTool.automation` routes cell clicks to the deeper editor. The editor is still the existing modal shape and needs UX review. |
| 12 | Global Apply applies a chosen layer/value to the current track scope. | Pass | `PhrasePerformOverlaySessionTests.test_scopedGlobalApplyInPerformModeStagesEveryRecipientTrack` proves scoped multi-track writes through the phrase overlay path. |
| 13 | Global Apply track scope selection uses an eight-column matrix. | Partial | Implemented in `PhraseWorkspaceView`, but needs visual evidence. |
| 14 | Scenes keeps the current scene A/B/crossfader shape. | Partial | `phraseScenesSurface` uses Slot A, crossfader, Slot B and stores `PhraseSceneState`. It needs visual comparison with the current scenes surface and V3 intent. |
| 15 | Capture Phrase only chooses a phrase destination. | Pass | `PhrasePerformCaptureSheet` is reused for destination-only capture paths. No changed-cell review or Capture Clip option is in this phrase capture surface. |
| 16 | Capture writes the perform copy to the chosen phrase destination. | Pass | Overlay tests cover capture to existing phrase and new phrase, including staged cells and scene state. |
| 17 | Discard removes the perform copy without saving it. | Pass | Overlay tests cover `revertPhrasePerformOverlay` clearing staged cells while preserving canonical phrase state. |
| 18 | Playback and UI agree about phrase mute/fill/pattern/repeat values. | Pass for compiled playback snapshot, needs runtime exercise | `PhrasePerformOverlaySessionTests.test_performOverlayPublishesEngineVisiblePhrasePlaybackState` proves perform-overlay pattern, mute, fill, repeat/loop, and scene state are installed into the engine-visible playback snapshot. Interactive heard/runtime evidence is still required. |
| 19 | Moment changes are immediate. | Partial | Policy tests prove Moment bypasses quantized Mute arming. Direct value paths are immediate, but this is not covered end-to-end for every layer. |
| 20 | Latch changes can be quantized to next bar and length-limited. | Partial | Quantized Mute arming exists for phrase Layers and Global Apply when Latch + Q:BAR is active. One-bar and multi-bar length-limited Mute commits at the boundary and stages a bar-shaped phrase cell. General length-limited semantics for other layers are not implemented. |
| 21 | No deferred performance-group UI is implemented. | Pass | The current phrase workspace does not add performance-group UI. |
| 22 | No Capture Clip redesign is implemented. | Pass | This build keeps phrase capture separate from clip history/capture clip work. |
| 23 | No generic Cell Detail page remains in this flow. | Partial | Normal layer clicks no longer open the generic editor. Automation mode still opens the deeper cell editor, so this needs UX review against "automation modal" intent. |
| 24 | Visual review evidence shows built surfaces compared with V3 wireframe intent. | Missing | Peekaboo/visual automation was not run in this unattended context. No screenshot evidence is attached yet. |

## Anti-Hybrid Review

- Pass for visible UI: the top bar no longer exposes the old global
  Setup/Perform switch, so the phrase-local Perform/Capture shell is the only
  visible Perform/Capture affordance in the main chrome. The underlying
  `WorkspaceMode` session state still exists for tracks/scenes behavior and
  visual-scenario compatibility.
- Pass: Capture Phrase no longer contains Capture Clip and no longer asks for a
  changed-cell review.
- Partial: Layers and Global Apply use matrix grammar in code, but visual
  evidence is still required before declaring they avoided a workflow-form feel.

## Required Next Evidence

1. Run an interactive visual review with screenshots for Transport, Layers,
   Scenes, Global Apply, Capture, and Automation mode against
   `prototypes/05-phrase-value-cell-system-v3.html`.
2. Exercise a running phrase in Free and Song modes to prove the displayed
   current/next phrase and heard phrase agree.
3. Exercise a running phrase to confirm the compiled pattern/mute/fill/repeat
   agreement is audible/runtime-visible, not only present in the installed
   playback snapshot.
4. Decide whether the remaining internal `WorkspaceMode.perform` name should be
   renamed later; it is no longer exposed as top-level app chrome, but tests and
   scenario commands still use the legacy name.
5. Extend and test latch length semantics beyond one-bar Mute before marking
   criterion 20 complete.
