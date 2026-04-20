---
name: adversarial-review-model-consistency
description: Adversarial review focused on hybrid-state drift after the reshape + TrackType + destination + phrase-layer migrations. Hunt: parallel representations, legacy accessors held alive by tests, stub types, non-exhaustive switches.
type: review
base_ref: v0.0.6-midi-routing
head_sha: 7d3f707745d270fd691277c128eb28ec4384be20
date: 2026-04-20
scope: Sources/Document/** + cross-module readers (UI, Engine); compared against docs/specs/2026-04-18-north-star-design.md and track-group-reshape plan
active_plan: docs/plans/2026-04-19-cleanup-post-reshape.md (drafted to receive these findings)
---

# Adversarial Review — Post-Reshape Drift Hunt

Base: `v0.0.6-midi-routing` → HEAD `7d3f707`. Focus: model/type drift residue.

## 🔴 Critical

### C1. `TrackType` legacy decoder silently deleted — old `.seqai` documents fail to open
`Sources/Document/SeqAIDocumentModel.swift:1139-1165`. The commit `99baf52` ("TrackType rename to 3-case with legacy decoder") added a custom `init(from decoder:)` that mapped `"instrument"`/`"drumRack"` → `.monoMelodic` and `"sliceLoop"` → `.slice`. The subsequent commit `1bc2593` ("align phrase ui") stripped the decoder and `LegacyTrackSource` out — its diff shows `-    init(from decoder: Decoder) throws`, `-        case "instrument":`, `-        case "drumRack":`, `-        case "sliceLoop":`, `-private enum LegacyTrackSource`. The current `TrackType` is a plain raw-value enum. Any document saved before `1bc2593` throws `DecodingError` on open. `Tests/SequencerAITests/Document/TrackTypeMigrationTests.swift` was also quietly rewritten to stop testing legacy values — *no test caught the regression because the contract it asserted was deleted alongside the code.* Fix: restore the legacy decoder, restore a migration test that decodes a captured pre-reshape fixture document (not a synthetic `"instrument"` string).

### C2. `InspectorView` Picker destroys `.inheritGroup` the instant it renders
`Sources/UI/InspectorView.swift:35`. `Picker("Output", selection: $document.model.selectedTrack.output)` binds directly to the legacy `track.output` bridge. `StepSequenceTrack.output` getter (`SeqAIDocumentModel.swift:1014-1026`) maps `.inheritGroup` → `.none`, so the Picker displays "No Default Output" for a grouped drum-kit member. The setter (1027-1054) has no `.inheritGroup` case and always writes a concrete destination. Selecting the same displayed value (`.none`) normalises `.inheritGroup` → `.none`, silently detaching the track from its group's shared sink. Drum-kit members opened in the Inspector lose inheritance on any interaction. Same pattern in `TrackDestinationEditor.swift:30-39` (destructive on selector click) and `MixerView.swift:40` (display only, but misleads the user into thinking the track is silent). Fix: either add `.inheritGroup` to `TrackOutputDestination`, or delete `track.output` entirely and have UIs bind to `track.destination` with a dedicated `.inheritGroup` button.

## 🟡 Important

### I1. `DrumKitPreset.Member.defaultGeneratorKindID` is authored but never read
`SeqAIDocumentModel.swift:37, 56-72`. Each member carries a hard-coded `"mono-generator"` string. `addDrumKit(_:)` (483-523) never reads it; no grep hit outside the preset declarations. Stub of a plan-not-yet-executed. Either remove the field or wire `addDrumKit` to select the matching generator pool entry.

### I2. `BusRef` is a pure stub with zero consumers
`Sources/Document/TrackGroup.swift:5-11, 22, 45, 68`. Only use: one stored property on `TrackGroup`, decoded for round-trip. No engine, no UI, no tests touch it. Commit `c2d3670` called it a "stub" — it still is. Either delete until the bus-routing plan lands, or add a TODO comment referencing the plan that will consume it. Carrying dead types invites future mis-adoption.

### I3. `GeneratorKind.drumKit` / `.templateGenerator` are retired-model residue
`Sources/Document/PhraseModel.swift:611-668, 715-720`. The spec (line 51) is explicit: "there is no `drum-kit` kind in the flat-track model — drum parts are individual `monoMelodic` tracks." Yet `GeneratorKind` still carries `.drumKit` (compatible with `.monoMelodic`) and `.templateGenerator` (compatible with all TrackTypes) and the default generator pool instantiates a `Drum Pattern` entry with `kind: .drumKit`. Parallel representation with the new "drum parts are grouped mono tracks" model. Either delete these cases or document why they remain.

### I4. Legacy `output:` / `audioInstrument:` init params still load-bearing for tests
`SeqAIDocumentModel.swift:916-918` (init), 1116-1136 (`defaultDestination(output:...)`). Five test files still construct tracks via `output: .midiOut` / `output: .auInstrument`. The convenience bridge exists only because tests rely on it; this cements the pre-reshape API into the next N plans. Fix during cleanup: migrate tests to pass `destination:` directly and drop the initializer's `output:` / `audioInstrument:` params plus `Self.defaultDestination(output:...)`.

### I5. `track.output` getter conflates `.inheritGroup` and `.none`
`SeqAIDocumentModel.swift:1014-1026`. Beyond C2's direct bug: any reader using this accessor (Mixer strip label, Inspector row, TrackDestinationEditor switch) cannot distinguish "inheriting from group" from "silent". The type itself has no room to grow. Deleting the getter is the right move once C2 is fixed.

### I6. Non-exhaustive `switch` vs `Destination` — no `@unknown default` on an `enum` the spec says will grow
Every concrete `switch destination` (EngineController 231/427/469/1067, AudioInstrumentHost 173, TrackDestinationEditor 17/304, the internal `defaultDestination(for:)` at SeqAIDocumentModel 772, and `track.output`/`.audioInstrument` getters) lists all five cases by hand. The `sample-pool` plan (`docs/plans/2026-04-19-sample-pool.md:243`) explicitly adds `Destination.sample(...)`. Every one of these switches will silently miscompile (or worse, skip routing) when that case lands. Since `Destination` is in-module, `@unknown default` isn't required — but without it the next case is an N-site migration. Add a `/// Adding a case? Audit these N sites` marker near the enum, or introduce a protocol extension with a single dispatch.

## 🔵 Minor

### M1. Dead `audioOutputKey.group` condition order
`EngineController.swift:1053-1064`. `audioOutputKey` first checks `case .auInstrument = destination` on the resolved destination, then checks `case .inheritGroup = track.destination`. Works today but the two branches could diverge. Extract a `groupIDForInheritingAU(track:documentModel:) -> TrackGroupID?` helper.

### M2. Wiki / plan stray `drumKit` references
`wiki/pages/track-groups.md` and plan docs still sprinkle "drumKit" as a first-class concept despite the spec retiring it. Low priority; feeds wiki-drift class from cleanup plan.

## Meta-assessment

**The dominant residue pattern is *new cases added without exhausting the compatibility bridge, and old bridges retained because tests still hit them.*** The reshape added `Destination.inheritGroup`, `TrackGroup`, and `TrackType` 3-case — but left `TrackOutputDestination` (4-case), `track.output` / `track.audioInstrument` (pre-reshape convenience accessors), `GeneratorKind.drumKit/.templateGenerator`, and `DrumKitPreset.Member.defaultGeneratorKindID` (stub field) intact. Then when the test suite held the bridge in place, the "legacy decoder" that justified the bridge was deleted (commit `1bc2593`) without anyone noticing — because no test owned the legacy wire format contract. This is the duplicate-code-path class compounded with test-coverage-gap: the migration path exists on paper but nothing verifies end-to-end that a v0.0.6 document opens in HEAD.

For `cleanup-post-reshape.md`'s TODO section: enumerate the six bridges above (TrackOutputDestination, `track.output`, `track.audioInstrument`, `DrumKitPreset.Member.defaultGeneratorKindID`, `BusRef`, `GeneratorKind.drumKit`), add a golden test that opens a captured pre-reshape `.seqai` fixture, and gate reshape-class plans on "no old shape has more than one reader" before tagging.

Files referenced: `Sources/Document/SeqAIDocumentModel.swift`, `Sources/Document/Destination.swift`, `Sources/Document/TrackGroup.swift`, `Sources/Document/PhraseModel.swift`, `Sources/UI/InspectorView.swift`, `Sources/UI/TrackDestinationEditor.swift`, `Sources/UI/MixerView.swift`, `Sources/Engine/EngineController.swift`, `Tests/SequencerAITests/Document/TrackTypeMigrationTests.swift`.
