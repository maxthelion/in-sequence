# Resolution

Fixed.

- `Sources/UI/Mixer/ScenesWorkspaceView.swift` — the outer wrapper row
  holding the big "Scenes" display title and the Perform button is gone. The
  Perform toggle now lives inside the nested panel's header row, and the
  "Scene Library" / "Scenes Perform / Runtime scene macro overrides" titles
  are removed too (the SCENES nav pill already says where we are).
- `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` — same panel-header
  treatment for perform mode; the Perform toggle (lit amber while active) is
  the header accessory.
- `Sources/UI/Theme/StudioPanel.swift` — gained the `accessory` slot used for
  this, so any panel can host a trailing control in its header instead of
  needing an extra wrapper row above it.

General nesting review requested by the note: the same outer-wrapper pattern
was removed on Phrase (single-child VStack around the panel plus the page
title header) and Tracks/Mixer/Library page titles in
`20260611-092737-the-title-phrase-matrix-and-the-line-of`. The remaining
page paddings come from one shared scale (`StudioMetrics.Spacing`).
