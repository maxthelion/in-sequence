# Resolution

Fixed, and the "how do we get here" question has a concrete answer.

How the state is reached (diagnosis, not a state-machine bug): the
destination chooser's "Slicer" option commits
`.slicer(sliceSetID: SliceSet.emptyID, …)`
(`Sources/UI/TrackDestination/AddDestinationSheet.swift:52`), i.e. a slicer
destination with no slice set, and the same shape survives clearing/reloading
a document. So any track given a Slicer destination outside the
"New Slice Track" flow lands on this page with no loop attached. It is a
legal, reachable state — the page just handled it with prose.

What changed in `Sources/UI/Slicer/SliceTrackWorkspaceView.swift`:

- The "No loop assigned / Create a new slice track from Tracks to attach a
  loop." text is replaced by a dashed plus card ("Add Loop") that opens a
  break-loop picker; choosing a loop installs it on this track in place via
  `session.setSlicerDestination` (ux-canon rules 3/4).
- The "Step Layers" panel is hidden while no loop is attached — there is
  nothing to slice or sequence yet.
- The Sample Player panel is also hidden in this state (tracked separately in
  `20260611-095915-also-the-sample-player-has-lots-of-unnec`).

Needs-repro note: none required — the state was reproduced statically from
the code path above; no runtime-only trigger was involved.
