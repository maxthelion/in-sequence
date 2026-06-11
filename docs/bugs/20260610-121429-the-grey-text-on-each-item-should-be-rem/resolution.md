# Resolution

Fixed. The "Choose AU Instrument" list repeated the same grey line — "Host
this Audio Unit inside the app." — under every row, while the modal subtitle
already states exactly that (ux-canon rule 1: one fact, one place; rule 3: no
explainer prose).

What changed:

- `Sources/UI/TrackDestination/AddDestinationSheet.swift` — AU rows now render
  only the instrument name.
- `Sources/UI/Theme/StudioCards.swift` — `StudioOptionButton.detail` is now
  optional (default empty) and the detail line is only rendered when present,
  so any picker whose header already names the shared context can drop the
  per-row caption.

Deliberately not done: the other option lists in the same sheet (Virtual MIDI
Out / AU Instrument / Sampler / Slicer) keep their detail lines — each row
there says something different about *that* option, which is the legitimate
use of the detail slot.
