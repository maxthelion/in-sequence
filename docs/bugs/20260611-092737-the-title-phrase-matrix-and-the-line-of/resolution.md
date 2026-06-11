# Resolution

Fixed, as a component pattern: page-level panels no longer restate what the
selected top-nav pill already says, and the explainer sentence under such
titles is gone (ux-canon rules 1/3).

- `Sources/UI/PhraseWorkspaceView.swift` — "PHRASE MATRIX" title + "Project-
  scoped layers across the top…" eyebrow removed (`showsHeader: false`).
  Also removed the "Phrase rows return after a layer or inline variant is
  selected." sentence from the layer-selection surface (the rule-3 example).
- `Sources/UI/TracksMatrixView.swift` — "TRACKS" panel title removed; the
  matching "Track cards return after a layer…" sentence removed from its
  layer-selection surface.
- `Sources/UI/Mixer/MixerWorkspaceView.swift` — "MIXER / Track strips active
  now" header removed.
- `Sources/UI/Library/LibraryWorkspaceView.swift` — "LIBRARY / App-support
  folders and future browsing surface" header removed.
- Scenes ("Scene Library" / "Scenes Perform" headers) handled together with
  the wrapper-nesting report
  (`20260611-093048-there-s-wasted-space-in-the-outer-wrappe`).
- `Sources/UI/Theme/StudioPanel.swift` — documents the rule ("title names a
  section, never the page") and gains an optional header `accessory` so a
  panel can carry a trailing control without a page title.

Deliberately not done: section-level panel titles that name something the nav
does not (Destination, Pattern, Slice Clip, Step Layers, Sample Player, Kit
Matrix, Voice Routes) are kept — they label sections inside a page, which is
the legitimate use of the panel header.
