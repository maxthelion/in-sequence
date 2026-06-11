# Resolution: Live Buffer, Audition, Save Arm

- date: 2026-06-11
- branch: `feature/clip-history-corrections`
- status: implemented; visual verification pending (no QA captures run on this pass)

## Correction 1 — step-region division, time alignment, vertical pitch

The preview is a compact piano-roll driven by `ClipHistoryPreviewLayout`
(`Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift`), extracted
from the view so the math is unit-testable:

- The grid divides horizontally by `previewGridSteps`: the selection's step
  count while auditioning (16 regions for one bar, 32 for two bars), and a
  stable single bar for the live rolling view, so longer selections divide
  into more regions instead of stretching fewer oversized blocks.
- Step boundaries render as explicit divider lines with bar/beat/step
  emphasis (`stepDivision(at:)`) — the previous uniform per-step wash read
  as one continuous block.
- Notes place pitch vertically via `rowIndex(forPitch:)` (row 0 = highest
  pitch in range, two-semitone padding around the played material), with
  octave (C) lanes shaded, so contour reads musically.
- Note x-position and width come from `startStep`/`lengthSteps` against the
  same grid, giving explicit time alignment.

## Correction 2 — pattern slots indicate pressability only while armed

Save-arm is now a state machine on `ClipHistoryTransferViewModel`
(`armSave()` / `disarmSave()` / `isSaveArmed`):

- Pressing `Save Clip` calls `armSave()`, which requires a selected history
  segment.
- `TrackPatternSlotPalette` receives a `DestinationMode` (and its pulse
  animation) only while `isSaveArmed`; otherwise the row is plain pattern
  selection/navigation with no pulsing.
- Deselecting the history segment, changing the selection length such that
  the selection is invalidated, switching pattern slot/track, cancelling,
  or completing a save all disarm.
- Replace confirmation (`pendingReplaceSlotIndex`) is derived from the
  armed state, so the amber "occupied" affordance can only appear while
  armed.

## Correction 3 — Refresh button

Removed before this pass: the History tab has no manual Refresh control on
`main` (`82ba0289`). Its replacement is the automatic mechanism this pass
builds on — a 250 ms `.task` poll (`refreshClipHistoryWhileVisible` in
`TrackSourceEditorView.swift`) that updates the model's capture snapshot
while the tab is visible. This pass added an equality guard in
`updateLiveSnapshot` so unchanged snapshots (stopped transport) do not
invalidate observation. No manual-refresh mental model remains.

## Correction 4 — circular buffer, live bar, audition enter/exit

- Capture always writes to the engine's rolling buffer
  (`ClipCaptureService` via `TickStateBuffer`); the UI polls
  `EngineController.captureSnapshot(trackID:)`, which reads the runtime
  tick path — no per-note document writes. The snapshot is read out from
  under the tick-state lock and the `@Observable` model is mutated on the
  main actor afterwards, never while a lock is held.
- No selection: the preview shows the currently filling live bar
  (`liveFillStepIndex` drives a fill region and playhead edge), labelled
  "Rolling".
- Selecting a segment enters audition (`setAuditionOverride`), freezes the
  preview on the selected material, and labels it "Auditioning".
- Deselecting (or selecting an invalid cell) stops audition and returns to
  the live rolling view.
- History works for clip sources as well as generators:
  `TrackSourceHistoryDisplayState` maps `.occupiedClip` to `.liveCapture`.
  This is truthful at the engine level — tick prepare appends resolved
  notes to the capture service for both `.generator` and `.clip` slot
  programs (`EngineController.resolvedStepNotes`).

## Tests

`Tests/SequencerAITests/UI/TrackSourceSourceDisplayStateTests.swift` pins:

- step-region division (`previewGridSteps` live vs audition) and the live
  fill index hiding during audition,
- pitch row mapping, range padding, clamping, and bar/beat/step divider
  emphasis (`ClipHistoryPreviewLayout`),
- the save-arm state machine: arm requires a selection, disarm on
  deselection and on selection-invalidating length changes, replace
  confirmation flow, disarm preserving audition,
- live/audition transitions including snapshot freezing while selected,
- clip sources reporting `Live` availability.

## Outstanding

- Visual verification of the preview at the review window size is pending
  (QA capture scripts intentionally not run on this pass).
