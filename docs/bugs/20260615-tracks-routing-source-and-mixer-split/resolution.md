# Resolution

Status: RESOLVED 2026-07-04 process closeout on main `9062180d`

The old `feature/routing-source-mixer-split` branch was preserved but not
merged by ancestry. Current `main` resolves the owner intent through the later
Track detail structure instead:

- the Sound tab uses `TrackDestinationEditor` for source selection/editing;
- the empty source action is `Add Sound Source`;
- the Mixer tab uses `TrackRoutingTabContent(mode: .mixer)` for output, scene
  membership, and sends;
- source and mixer routing are no longer collapsed into one ambiguous
  destination flow on the working surface.

The earlier feature branch still contains a stale side-by-side two-well
implementation, tests, and capture fixture rows. It is retained as historical
evidence, but the build loop is closed as superseded by current main rather than
continued or merged.

Evidence:

- `.meta/multipass/runtime/loops/project/act/2026-07-04T17-35Z-routing-source-mixer-split-reconciled.md`
