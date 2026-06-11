# Resolution

Fixed.

- `Sources/UI/TrackDestinationEditor.swift` — the empty destination state is
  now a single dashed plus card ("Add Destination", the shared
  `StudioAddCard`) that opens the destination chooser. The "OUTPUT" eyebrow,
  "No destination" headline, and "Set a destination to route notes for this
  track." sentence are gone (ux-canon rules 1/3); the guidance lives in the
  card's tooltip. This also replaces the stock white `.borderedProminent`
  button (rule 6).
- `Sources/UI/Track/TrackWorkspaceView.swift` — the panel's "Current sink and
  routing target" eyebrow is removed; "Destination" alone names the section.
