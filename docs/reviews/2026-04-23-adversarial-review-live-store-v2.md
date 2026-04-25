# Adversarial Review: Live-Store V2 Commits

Reviewed commits:
- `b312e01` `docs(plan): archive live-store v1 and refine canonical v2`
- `ac11a2f` `feat(sequencer): implement live-store v2 core`
- `5b6df6f` `feat(mixer): route mix controls through live session`

Plan under review:
- `docs/plans/2026-04-23-live-sequencer-store-v2.md`

## Findings

### Critical

1. `LiveSequencerStore` is still a thin `Project` wrapper, which violates the central V2 guardrail that the first migrated version must be "a real authored-state owner, not a thin wrapper around `document.project`."

Evidence:
- `Sources/Engine/LiveSequencerStore.swift:12-49` stores only `private(set) var project: Project`
- every mutation clones and rewrites the full `Project` value with `var next = project`
- `Sources/App/SequencerDocumentSession.swift:24` constructs the store directly from `document.wrappedValue.project`

Why this matters:
- the implementation did not actually introduce separate resident authored state for clips, track programs, phrase data, macros, sampler filter state, or destination state
- the "live store" is therefore still paying full-`Project` copy / equality / replacement costs on every mutation
- the new ownership tests pass because Swift value semantics already detach the copied `Project`, not because the branch established the new architectural boundary the plan demanded

### Critical

2. The hot tick path still traverses `Project` and ignores the compiled clip buffers for note resolution, so the core plan goal "tick path reads snapshots, not `Project` traversal helpers" is not met.

Evidence:
- `Sources/Engine/PlaybackSnapshot.swift:11` embeds the entire `Project` in the snapshot
- `Sources/Engine/EngineController.swift:651-677` still derives playback context from `playbackSnapshot.project.selectedPhraseID` and iterates `documentModel.tracks`
- `Sources/Engine/EngineController.swift:1263-1317` resolves generator and clip steps by calling `playbackSnapshot.project.generatorEntry(...)`, `playbackSnapshot.project.clipEntry(...)`, and `playbackSnapshot.project.clipPool`
- `Sources/Engine/SequencerSnapshotCompiler.swift:25-66` compiles `ClipBuffer`, but the tick path never uses that buffer for actual clip-note playback

Why this matters:
- the compiled buffers are currently only partial metadata carriers, not the actual runtime playback source
- note-grid clip reads, generator lookups, and clip-pool traversal are still document-driven on the hot path
- this is the main performance and authority risk the plan was written to eliminate

### Critical

3. The reviewed branch still crashes when the AU macro picker reads parameters from plug-ins that do not expose a KVC-compliant `ancestors` property.

Evidence:
- `Sources/UI/TrackDestinationEditor.swift:573-585` builds the macro picker by calling `host.parameterReadout()`
- `Sources/Audio/AudioInstrumentHost.swift:527-551` calls `param.value(forKeyPath: "ancestors")`
- this exact path crashed earlier today with `valueForUndefinedKey:` on `AUParameter`

Why this matters:
- this is a hard crash in a UI surface that the recent work actively routes users into
- even though a fix now exists in a separate worktree, the branch under review still contains the crash
- the current branch is therefore not safe to hand off for AU-track testing in its present state

### Important

4. The app still uses one shared `EngineController` for every `DocumentGroup` window, so the new per-document session boundary is not actually isolated at runtime.

Evidence:
- `Sources/App/SequencerAIApp.swift:6-9` creates a single `@State private var engineController`
- `Sources/App/SequencerAIApp.swift:33-50` passes that same controller into every document root
- `Sources/App/SequencerDocumentRootView.swift:21-25` activates each session against that shared controller

Why this matters:
- opening a second document can overwrite the first document's live engine state, prepared snapshot, transport state, macro dispatch state, and audio routing
- the plan framed the session/store boundary as per-document, but the runtime owner below it is still global
- this is exactly the kind of subsystem-boundary leak the adversarial review is supposed to catch

### Important

5. Sampler filter controls still force `fullEngineApply` on every UI change, even though the plan explicitly called for live filter updates without broad document reapply.

Evidence:
- `Sources/UI/SamplerDestinationWidget.swift:109-110` says filter controls call `sampleEngine.applyFilter` on each change for immediate feedback
- `Sources/UI/SamplerDestinationWidget.swift:187-209` mutates filter settings continuously as the UI changes
- `Sources/UI/TrackDestinationEditor.swift:262-269` wraps every `filterSettings` write in `session.mutateProject(impact: .fullEngineApply)`

Why this matters:
- every cutoff / resonance / drive drag now both updates the live sampler filter and triggers a full engine apply path
- that defeats the plan’s "runtime-adjacent hot controls go through focused live mutation paths" requirement
- it is likely to show up as jitter, over-application, or state churn under active performance use

## Notes

- The guardrail tests added in this series are useful, but they currently encode the implemented shape rather than the plan’s stricter architecture. In particular, `Tests/SequencerAITests/Engine/LiveSequencerStoreOwnershipTests.swift` only proves that mutating a copied `Project` value does not mutate the original value.
- Non-hot UI surfaces still write to `document.project` directly in places like `SidebarView`, `TracksMatrixView`, `RoutesListView`, and parts of `TrackWorkspaceView`. The V2 plan allows some of that temporarily, so I am not calling those out as primary findings here. The deeper problems above are blockers first.
