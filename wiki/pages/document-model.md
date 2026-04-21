---
title: "Document Model"
category: "data-model"
tags: [document, seqai, codable, persistence, versioning, filedocument]
summary: The .seqai file format, the Codable Project that backs it, and the forward-compatible versioning approach.
last-modified-by: user
---

## What a `.seqai` file is

A `.seqai` document is a pretty-printed JSON file produced by serializing `Project` through `JSONEncoder`. It's the user's project. One song per document (decision recorded in the north-star spec's Open Questions).

Current scaffold content (the model grows with each later plan):

```json
{
  "version": 1
}
```

Fields will be added as plans 1 through 12 land (macro grid, song, tracks, clips, etc.). Every addition must preserve forward read-compatibility with older documents.

## UTType

Declared in `project.yml` and re-exported in Swift:

- Identifier: `ai.sequencer.document`
- Extension: `.seqai`
- Conforms to: `public.data`, `public.content`
- Role in Info.plist: `Editor` (this app creates and edits them)

```swift
// Sources/Document/SeqAIDocument.swift
extension UTType {
    static let seqAIDocument = UTType(exportedAs: "ai.sequencer.document")
}
```

## `FileDocument` conformance

`SeqAIDocument` is a `FileDocument` value type that holds a `Project` and handles read/write to `FileWrapper`:

```swift
struct SeqAIDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.seqAIDocument] }
    static var writableContentTypes: [UTType] { [.seqAIDocument] }

    var model: Project

    init(model: Project = .empty) { … }
    init(configuration: ReadConfiguration) throws { … }           // JSONDecoder
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { … }  // JSONEncoder, pretty + sorted
}
```

Output formatting uses `[.prettyPrinted, .sortedKeys]` so diffs are stable and merges are tractable. Documents can be version-controlled by users if they want.

## Model shape

```swift
// Sources/Document/Project.swift
struct Project: Codable, Equatable {
    var version: Int

    static let empty = Project(version: 1)
}
```

Intentionally tiny. Additions arrive via subsequent plans, always keeping `version` as the first field and bumping it when breaking schema changes land.

## Versioning

### Rule

Every schema change to `Project` that could cause an older reader to misinterpret a newer file must increment `version`. Additive changes that an older reader could safely ignore (new optional fields) should keep `version` stable — `JSONDecoder` drops unknown keys.

### Reading old documents

When we need to read a file with a lower `version`, a migration path will be introduced via a `Codable` shim that reads the old shape and constructs the new one. The plan (added in a future sub-spec) is:

- `ProjectV1`, `ProjectV2`, … as separate Codable types
- A top-level decoder that peeks at `version`, dispatches to the right Vn decoder, and then lifts to current
- A single `upgrade(_:)` pipeline for the lift chain

For the current scaffold there is only `v1`, so this infrastructure isn't built yet. Noting the plan here so the version field isn't treated as decoration.

### Refusing to read newer documents

If a file's `version` is greater than the current code supports, `init(configuration:)` should throw rather than attempt to read it and produce silently-corrupt state. Not yet implemented — will land alongside the migration infrastructure.

## Round-trip correctness

A document saved and reopened must be byte-exact when re-serialized (barring whitespace from `.prettyPrinted`, which `sortedKeys` neutralizes). Tests in `Tests/SequencerAITests/SeqAIDocumentTests.swift` verify this on the empty model; every time a field is added, a new round-trip test asserts its preservation.

## TrackPatternBank and SourceRef

### TrackPatternBank

`TrackPatternBank` owns the pattern slots for one track and now carries an optional reference to an attached AI generator:

```swift
struct TrackPatternBank: Codable, Equatable, Identifiable, Sendable {
    var trackID: UUID
    var slots: [TrackPatternSlot]
    var attachedGeneratorID: UUID?
}
```

`attachedGeneratorID` is `nil` by default — no generator is attached to any track at creation time. The user attaches one explicitly via `Project.attachNewGenerator(to:)`. Removing it calls `Project.removeAttachedGenerator(from:)`.

`attachedGeneratorID` is serialised with `encodeIfPresent`, so older documents that omit the key decode cleanly with `nil` via `decodeIfPresent`.

`TrackPatternBank.synced(track:generatorPool:clipPool:)` validates `attachedGeneratorID` against the pool on every sync: if the referenced entry no longer exists or no longer matches the track type, the field is set back to `nil`.

### SourceRef — both IDs always present

`SourceRef` carries a `generatorID` and a `clipID` simultaneously. The `mode` field (`TrackSourceMode`) picks which one drives playback for that slot — either `.generator` or `.clip`. Both IDs are preserved across mode switches.

```
mode = .generator → generatorID drives playback; clipID is retained for bypass fallback
mode = .clip      → clipID drives playback; generatorID is retained to re-engage if bypass is reversed
```

The **preserve-opposite-ID invariant**: `SourceRef.normalized(trackType:generatorPool:clipPool:)` resolves each ID to the nearest compatible pool entry but does not zero out the ID that is not currently active. This means a slot can round-trip through attach → bypass → un-bypass without losing either reference.

`setPatternClipID(_:for:slotIndex:)` merges the new clip ID with the existing `generatorID` so a clip change while bypassed does not discard the generator link.

### Per-slot bypass (when a generator is attached)

When `attachedGeneratorID != nil`, each slot independently chooses whether its generator is engaged or bypassed to the clip:

- `setSlotBypassed(true, trackID:slotIndex:)` sets that slot's `mode` to `.clip` while preserving both IDs.
- `setSlotBypassed(false, …)` restores `mode` to `.generator`.
- Slots for tracks with no attached generator always use `.clip` mode; bypass is not applicable.

### Default constructor

`TrackPatternBank.default(for:initialClipID:)` creates a bank with all slots pointing to the supplied clip ID in `.clip` mode and `attachedGeneratorID = nil`. The old two-pool constructor (`default(for:generatorPool:clipPool:)`) no longer exists.

## What a document does *not* contain

To keep `.seqai` portable:

- **No sample audio data.** Sample files are referenced by path / bookmark; the document holds only the metadata.
- **No library content.** Drum templates, voice presets, fill presets, takes — all live in [[app-support-layout|the user library]] or the app bundle, referenced by name / id.
- **No hosted AU state that requires out-of-process restore.** AU `fullState` is serialized into the document as `Data`, but the AU binaries themselves are referenced by identifier and must be installed on the reading machine.
- **No window state.** UI layout is restored from `NSUserDefaults` / `UserDefaults` per-machine, not travelled with the document.

## Related pages

- [[project-layout]] — where `Document/` sits in the module graph
- [[app-support-layout]] — where library content and preferences live (outside the document)
- [[code-review-checklist]] — the invariants any document-related change must satisfy
- [[drum-track-mvp]] — how drum kit creation seeds per-part clips in the pool
