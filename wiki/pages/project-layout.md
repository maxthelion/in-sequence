---
title: "Project Layout"
category: "architecture"
tags: [structure, files, modules, boundaries, organization]
summary: The on-disk layout of the sequencer-ai app, how folders map to responsibility boundaries, and the file-per-responsibility pattern enforced by the code review checklist.
last-modified-by: user
---

## Top-level layout

```
sequencer-ai/
├── project.yml                        # xcodegen config — see [[build-system]]
├── .gitignore                         # excludes xcodeproj, DerivedData, .claude/, wiki/.meta/
├── Sources/                           # all Swift sources (one Xcode target)
│   ├── App/
│   ├── Document/
│   ├── UI/
│   ├── Engine/
│   ├── Platform/
│   ├── MIDI/
│   ├── Audio/
│   └── Resources/
├── Tests/
│   └── SequencerAITests/              # XCTest bundle
├── docs/
│   ├── specs/                         # time-stamped design specs
│   └── plans/                         # time-stamped implementation plans
└── wiki/
    └── pages/                         # evergreen reference docs (you're reading one)
```

`Sources/` subdirectories are **responsibility boundaries**, not technical layers. Each holds one kind of concern; a file belongs to exactly one of them.

## Responsibility boundaries

### `Sources/App/`

App lifecycle and composition root. SwiftUI `App` conformance, `DocumentGroup`, `Settings` scene, any top-level scenes. Also the place to wire together app-scoped singletons on launch (e.g. `MIDISession.shared` is touched here, not in view code).

Currently: `SequencerAIApp.swift`.

### `Sources/Document/`

Everything about the `.seqai` document. `FileDocument` conformance, the `Codable` model that's serialized, UTType declarations. **No UI, no engine, no platform concerns.** This module should remain importable into a hypothetical CLI tool that only processes documents.

Currently: `SeqAIDocument.swift`, `SeqAIDocumentModel.swift`. See [[document-model]].

### `Sources/UI/`

SwiftUI views only. Each view in its own file. Composed into `ContentView` (NavigationSplitView) via `SequencerAIApp`. Views read from `MIDISession.shared` and the document binding; they never own business logic or talk to platform APIs directly.

Currently: `ContentView`, `SidebarView`, `DetailView`, `InspectorView`, `TransportBar`, `PreferencesView`.

### `Sources/Engine/`

The pipeline runtime and app-facing playback controller. This boundary owns typed streams, the block contract, block registry, DAG executor, tick clock, command queue, and the engine controller that wires those pieces into track playback. It may depend on `MIDI/` for transport to virtual endpoints and on the audio sink protocol used by `Audio/`, but it does not depend on SwiftUI views or document serialization details.

Currently: `Block.swift`, `Stream.swift`, `Executor.swift`, `BlockRegistry.swift`, `TickClock.swift`, `CommandQueue.swift`, `EngineController.swift`, `Blocks/NoteGenerator.swift`, `Blocks/MidiOut.swift`. See [[engine-architecture]].

### `Sources/Platform/`

macOS-specific glue that isn't specific to any one subsystem — filesystem paths, app-support bootstrap, permissions prompts, document pickers. Code here uses `FileManager`, `URL`, `NSUserDefaults`, etc.

Currently: `AppSupportBootstrap.swift`. See [[app-support-layout]].

### `Sources/MIDI/`

CoreMIDI wrapping and app-level MIDI session. See [[midi-layer]]. Never imported from `Document/`. Imported from `UI/` (for the preferences display) and `App/` (for session boot).

Currently: `MIDIClient.swift`, `MIDIEndpoint.swift`, `MIDISession.swift`.

### `Sources/Audio/`

Native audio output and AU instrument hosting. This layer owns `AVAudioEngine`, built-in or hosted instrument nodes, and mixer routing for tracks that play sound inside the app instead of emitting only CoreMIDI. It does not know about SwiftUI or document bindings directly; the controller layer feeds it note events.

Currently: `AudioInstrumentHost.swift`.

### `Sources/Resources/`

Non-code artifacts bundled into the app: `Info.plist`, `SequencerAI.entitlements`. Managed by `project.yml`; xcodegen writes these during generation.

### `Tests/SequencerAITests/`

XCTest bundle mirroring the `Sources/` layout. One test file per subject; naming convention: `FooTests.swift` corresponds to `Foo.swift`. Tests import the app via `@testable import SequencerAI`.

## File-per-responsibility

The reason for many small files over few large ones is spelled out in [[code-review-checklist]] §2 "No god files." Summary:

- One concept per file — not "one class per file," *one concept* (which may be a type + its small supporting types)
- ~200 lines is fine, ~500 lines is a smell, ~1000 lines means split
- Utility dumping grounds (`Utils.swift`, `Helpers.swift`) are forbidden; every helper belongs somewhere with a real name

Current `Sources/` exemplifies this: `MIDIEndpoint.swift` is ~30 lines (value type only), `MIDIClient.swift` is ~90 lines (client wrapper), `MIDISession.swift` is ~45 lines (app-level composition). None of these would be improved by merging.

## Dependency direction

Dependencies flow **inward** toward `Document/`:

```
App   → UI → Engine / Audio / MIDI / Platform / Document
              Engine          → MIDI / Audio
              Audio           → Engine (playback sink protocol only)
              Platform        → Document
              MIDI            → (nothing from this project)
              Document        → (nothing from this project)
```

Rules this encodes:

- `Document/` depends on nothing project-internal. It stays pure-Codable.
- `Engine/` owns playback/runtime logic and may talk to MIDI and audio sinks, but not SwiftUI.
- `Audio/`, `MIDI/`, and `Platform/` don't import `UI/` or `Document/`.
- `UI/` can use anything below it but doesn't own business logic.
- `App/` wires everything together.

Breaking this ordering (e.g., `Document/` importing `UI/`) is a review-blocking violation.

## Adding new subdirectories

As later plans land, additional boundaries will appear:

- `Sources/Coordinator/` — macro coordinator + phrase model (Plan 2)
- `Sources/Song/` — song model / phrase-refs (Plan 3)
- `Sources/Chord/` — chord generator (Plan 4)
- `Sources/Drums/` — drum tagged-stream support (Plan 5)
- `Sources/Audio/` — AVAudioEngine + AU hosting + sample playback
- `Sources/Library/` — the template / voice-preset / take / etc library loader (later plan)

Each new directory comes with a wiki page like this one describing what it contains and what depends on what.

## Related pages

- [[build-system]] — how the project is generated and built
- [[document-model]] — what lives in a `.seqai`
- [[midi-layer]] — the MIDI module in detail
- [[app-support-layout]] — filesystem layout under `~/Library`
- [[code-review-checklist]] — the rules this layout is designed to satisfy
