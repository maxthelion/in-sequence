# Clip History Build Resume Handoff

Status: ready for promotion when a build slot opens.

## Build Target

Build the approved v4 Clip History flow:
[`prototypes/clip-history-dual-grid-v4.html`](prototypes/clip-history-dual-grid-v4.html).

The feature is not "save the latest buffer." It is a transfer workflow:

1. Open Clip History from the track-source/generator context.
2. Freeze a capture snapshot at modal open.
3. Choose a source region from a 4x4 recent-history matrix.
4. Preview/audition the selected virtual clip without document mutation.
5. Choose a destination from a matching 4x4 pattern-slot matrix.
6. Save only after source and destination are explicit.
7. Require `Replace` confirmation for occupied destinations.

## Existing Implementation Evidence

Current `main` contains an earlier Clip History modal from commit `9ae658d`.
That modal is not accepted as complete. It saved the latest capture length and
performed live capture reads from the modal render path.

The old branch `auto/roadmap-1-clip-history` contains useful salvage:

- `Sources/Engine/CaptureSnapshot.swift`
- `Sources/Engine/PseudoClipState.swift`
- frozen-snapshot modal/view-model work in `Sources/UI/TrackSource/ClipHistoryCaptureSheet.swift`
- capture and pseudo-clip tests
- overwrite confirmation behavior

Do not merge that branch as-is. It is stale relative to `main`, includes legacy
`.claude` build-loop artifacts, and still has unresolved branch hygiene.

## Fresh Build Loop Instructions

Start from current `main` in a new v2 build loop/worktree. Harvest the old
branch deliberately by reading its implementation and tests, then reapply the
pieces that still fit the current track-source architecture.

Required checks before calling the feature ready:

- architecture review confirms no document mutation during audition and no
  live engine polling from SwiftUI render paths;
- testing review covers snapshot stability, pseudo-clip materialization,
  save-to-slot from selected content, occupied-slot replacement, and empty
  history;
- UX/IA review compares the built modal against v4 screenshots/prototype;
- visual-economy review checks the modal uses space clearly and keeps source,
  preview, and destination priority obvious.

## Promotion Note

Build capacity is currently governed by `multipass.yaml` with two active build
slots. Promote Clip History after an active build loop completes or if the
project decider intentionally swaps priorities.
