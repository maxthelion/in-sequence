# Tracks Matrix Crashes On Unhandled Phrase Layer Accent

Status: Open  
Reported: 2026-04-28  
Observed in: `codex/slicer-track-mvp` worktree while testing the slicer UI  
Crash report: `/Users/maxwilliams/Library/Logs/DiagnosticReports/SequencerAI-2026-04-28-113121.ips`

## Summary

The app crashed with `EXC_BREAKPOINT / SIGTRAP` on the main thread while rendering the Tracks matrix action bar. The crash comes from `layerAccent(_:)` asserting on an unhandled phrase layer id.

This is likely not an audio/WAV decoding crash. The top frames are all SwiftUI presentation:

```text
_assertionFailure
assertionFailure(_:file:line:)
layerAccent(_:) at Sources/UI/PhraseLayerPresentation.swift:16
TracksMatrixView.layerControl.getter at Sources/UI/TracksMatrixView.swift:237-260
```

## Current Evidence

`Sources/UI/PhraseLayerPresentation.swift` currently recognizes only these built-in ids:

- `pattern`
- `brightness`
- `register`
- `mute`
- `fill-flag`
- `tension`
- `transpose`

It also handles ids with the `macro-` prefix. Other default phrase layers created by `PhraseLayerDefinition.defaultSet(for:)`, such as `volume`, `intensity`, `density`, `variance`, and `swing`, fall through to:

```swift
assertionFailure("Unhandled phrase layer accent id: \(layerID)")
return StudioTheme.cyan
```

The Tracks matrix layer selector can render any phrase layer. Cycling to or restoring selection on one of the unhandled built-in layers can therefore crash during SwiftUI layout before the fallback color is useful.

## Build Identification Note

The macOS `.ips` report does not appear to include a git SHA for the app build. It includes binary image UUIDs and source file paths/line numbers, which can identify a local build artifact or dSYM, but not the source commit unless the app embeds the git SHA at build time.

The observed slicer worktree HEAD at investigation time was `bad48ff`, but that worktree also had uncommitted changes. Treat that as context, not a definitive build identifier.

## Expected Behavior

UI rendering should never crash because a phrase layer has no explicit accent mapping. Unknown or newly added phrase layer ids should receive a stable fallback accent without triggering an assertion in app runtime.

## Suggested Fix

- Add explicit accent mappings for all built-in `PhraseLayerDefinition.defaultSet(for:)` ids.
- Remove the `assertionFailure` from the production rendering path, or gate it behind a non-crashing debug-only diagnostic.
- Add a small test that iterates every default phrase layer and calls the presentation helper, so adding a new built-in layer cannot reintroduce this crash.

