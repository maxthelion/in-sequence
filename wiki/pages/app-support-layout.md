---
title: "App Support Layout"
category: "data-model"
tags: [app-support, library, filesystem, bootstrap, sandbox]
summary: The on-disk directory tree the app maintains under ~/Library/Application Support, how it's created on first launch, and what category of content lives where.
last-modified-by: user
---

## Root path

Under macOS App Sandbox the app's Application Support directory resolves to:

```
~/Library/Containers/ai.sequencer.SequencerAI/Data/Library/Application Support/sequencer-ai/
```

Outside the sandbox (e.g., if entitlements are ever relaxed), it would be:

```
~/Library/Application Support/sequencer-ai/
```

Access is always via `FileManager.default.url(for: .applicationSupportDirectory, …)` — the actual path is OS-managed; code never hard-codes `/Users/…`. `AppSupportBootstrap.appSupportRoot()` returns the right URL and creates the parent directory if missing.

## Tree

```
~/Library/.../sequencer-ai/
└── library/
    ├── templates/            # drum-kit rhythmic templates (tagged clips)
    ├── voice-presets/        # per-track voice config + interpretation map
    ├── fill-presets/         # named abstract-vector static overlays
    ├── takes/                # captured time-varying macros (see spec §5b)
    ├── chord-gen-presets/    # chord-generator configs
    ├── slice-sets/           # sliced-loop metadata (boundaries, per-slice tags)
    └── phrases/              # reusable phrase definitions (shared across projects)
```

Created on first launch by `AppSupportBootstrap.ensureLibraryStructure(root:)`. The operation is idempotent — calling it on every launch is cheap and guaranteed safe.

## Content authority

Per the north-star spec's Library resolution (Q4, option C — hybrid):

- **Bundled defaults** ship read-only inside the app bundle (at `SequencerAI.app/Contents/Resources/library/...`).
- **User content** lives under `~/Library/.../sequencer-ai/library/...`.
- At runtime, the Library view merges both, showing a "source" flag per entry so the user can distinguish "ships with app" from "their own."

The bundled content doesn't live in this directory; only the user's content does. Library loaders know how to read from both.

## Why this sits outside the document

A `.seqai` project references library items by name / id; it doesn't embed them. This means:

- Multiple projects can share the same drum templates and voice presets
- Editing a voice preset once updates every project that uses it (by design — library items are meant to be sharable assets)
- Projects stay small even with rich arrangements

The trade-off is that a `.seqai` file isn't fully self-contained. If the user wants portability they can export a "bundle" that copies referenced library items alongside the document — that's a later feature, not MVP.

## Permissions

With the app sandbox active (see [[build-system]] entitlements), this directory is fully writable by the app without any user interaction. Sandbox path redirection is transparent to the app's code because `FileManager.url(for: .applicationSupportDirectory, …)` returns the sandboxed path.

## Bootstrap behavior

```swift
// Sources/Platform/AppSupportBootstrap.swift
enum AppSupportBootstrap {
    static let librarySubfolders: [String] = [
        "library/templates",
        "library/voice-presets",
        "library/fill-presets",
        "library/takes",
        "library/chord-gen-presets",
        "library/slice-sets",
        "library/phrases",
    ]

    static func ensureLibraryStructure(root: URL) throws { … }
    static func appSupportRoot() throws -> URL { … }
}
```

Called from `SequencerAIApp.init`. Failures log via `NSLog` and do not crash the app — the user can still work on documents, they just won't find library content. A follow-up Library-view plan should surface bootstrap failures visibly so the user can act on them.

## What is *not* under this path

- `UserDefaults` (preferences) — lives in the standard `Preferences/ai.sequencer.SequencerAI.plist` managed by `UserDefaults.standard`
- Caches — would go under `~/Library/Caches/ai.sequencer.SequencerAI/` (not used yet)
- Recent-file bookmarks — persisted via `UserDefaults` using security-scoped bookmarks (requires the `files.bookmarks.app-scope` entitlement already granted in [[build-system]])
- Logs — currently `NSLog` only, no per-file log rotation yet

## Related pages

- [[document-model]] — what lives in a `.seqai` (and what doesn't)
- [[build-system]] — entitlements controlling sandbox behavior
- [[project-layout]] — where `Platform/` sits in the module graph
