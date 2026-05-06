---
status: ready-for-build-planning
created: 2026-05-06T20:18:00+01:00
source_pass: docs/roadmap/agentic-loop/passes/prepare-production-cherry-pick-candidates.md
source_decisions: docs/roadmap/agentic-loop/decisions/inferred-defaults.md
product_shape_source: docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md
---

# Production Cherry-Pick Candidates

## Summary

Do not merge or cherry-pick any broad probe branch wholesale.

The next build round should port only narrow model/test seeds, then map them
onto current production ownership before any UI integration. The strongest
near-term candidate is the transient performance override layer because it is a
pure `Engine` value model with focused tests. The other lane learnings are
valuable, but most need an architecture plan first because the probe code owns
state in SwiftUI, uses synthetic data, or invents document/audio-graph identity
that production does not yet have.

Reject all probe-local UI panels, seeded fixtures, and broad
`SequencerAI.xcodeproj/project.pbxproj` churn from the overnight branches.

## Evidence Checked

- `README.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/roadmap/agentic-loop/synthesis/current-product-shape.md`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.js`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js`
- `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-morning-harvest.md`
- `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-postmortem.md`
- `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-summary.md`
- `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`
- `docs/roadmap/lanes/mixer-routing-and-sends.md`
- Probe commit artifacts from `0e3ba5c`, `3a1d15d`, `99834b3`,
  `6991918`, and `a9bdbc4`, inspected read-only with `git show`.
- Current production ownership references in `Project`, `Project+TrackSources`,
  `Project+CapturedClips`, `PlaybackSnapshot`, `EngineController`,
  `MainAudioGraph`, `document-model`, and `routing`.

## Production-Safe Model/Test Candidates

These can be scheduled as narrow porting work, provided the implementer keeps
them pure and does not bring along probe UI or project-file churn.

| Priority | Candidate | Source artifact | Production target | Porting rule | Minimum tests |
|---|---|---|---|---|---|
| P0 | Transient track performance override value layer | `3a1d15d:Sources/Engine/TrackPerformanceOverrideLayer.swift` and `3a1d15d:Tests/SequencerAITests/Engine/TrackPerformanceOverrideLayerTests.swift` | `Sources/Engine/` runtime/session model, likely adjacent to `EngineController` performance overlay concepts | Port the pure `Equatable`/`Sendable` layer and focused tests only. Keep UI, `TracksMatrixView` tap changes, and local `@State` ownership out. Treat 16-step preset maps as seed data, not final step-length policy. | Preserve authored fill fallback, multi-track batch updates, note-repeat priority over step-order, clear/clearAll behavior, and inactive-state compaction. Add a guard that the layer never mutates phrase/document state. |
| P1 | Developer observability event model | `a9bdbc4:Sources/Diagnostics/ObservabilityProbeModels.swift` and `a9bdbc4:Tests/SequencerAITests/Diagnostics/ObservabilityProbeModelsTests.swift` | New `Sources/Diagnostics/` developer-tooling model, behind a diagnostics/debug pathway | Rename away from `Probe`, remove seeded samples, and keep this explicitly developer tooling. Do not add a top-level musician-facing Automation workspace. | Fingerprint normalization, path/email redaction, route policy, issue draft wording, and separation of "Observed in" from "Introduced by". |

## Requires-Plan Candidates

These should not be cherry-picked directly. Each needs a build plan that maps
the concept to current `Project`, `LiveSequencerStoreState`,
`PlaybackSnapshot`, routing, session/runtime, and audio-graph ownership.

| Priority | Candidate | Useful source | Why it needs a plan first | Agent-actionable next plan |
|---|---|---|---|---|
| P0 | Performance override integration into playback | `TrackPerformanceOverrideLayer` plus Happy Accident Workbench Keep/Discard transaction labels | The pure layer is safe, but production still needs a runtime owner, UI command API, tick-path read point, Keep destination, and Discard restore owner. Note repeat also needs sub-step scheduling before audible 1/32 or 1/64 promises. | Write a plan for a session/engine-owned `trackPerformanceOverlay` that resolves `fillEnabled` and step index above `PlaybackSnapshot.resolvedStep` without writing phrase cells. Include Keep to active phrase cells and Discard to authored snapshot restoration. |
| P0 | Source-slot capture/history identity | Track editor probe composition; `Project+CapturedClips`; `SourceRef` preserve-opposite-ID invariant; workbench generated clip history | The existing document model already preserves generator and clip IDs, so probe UI code is not the artifact. The missing work is a production history/capture shell around selected pattern slots. | Write a Track Editor plan that adds focused tests for capturing generated output into `clipPool` while retaining `sourceGeneratorID`/`SourceRef.generatorID`, selected slot context, and modifier identity. History should live beside the selected slot, not as copied probe `@State`. |
| P1 | Runtime audio buffer and document buffer-reference vocabulary | `99834b3:Sources/UI/Inputs/AudioInputLoopingAutosliceProbeModel.swift`, `99834b3:Tests/SequencerAITests/UI/AudioInputLoopingAutosliceProbeModelTests.swift`, and workbench `runtime-audio-buffer` / `document-buffer-reference` labels | The probe stores synthetic buckets and UI-owned runtime state. Production needs a PCM/file owner, derived waveform caches, loop range, slice cue metadata, record scheduling, monitor mode, and document references without persisting sample memory. | Write an Audio Input/Looping plan that introduces typed IDs and tests for one captured buffer being referenced by input track, loop deck, waveform, slice cues, and buffer users. Explicitly separate runtime sample memory from document metadata. |
| P1 | Return-send mixer reducer semantics | `6991918:Sources/UI/Mixer/MixerRoutingProbeModel.swift`, `6991918:Tests/SequencerAITests/UI/MixerRoutingProbeModelTests.swift`, Lane C note, and workbench mixer route summary | The reducer semantics are useful, but production lacks a document mixer graph and `MainAudioGraph` bus/send ownership. Probe bus IDs are regenerated view-local state. | Write a Mixer Routing plan for return-style sends feeding post-blend master, with document-owned bus/return IDs, additive solo, delete-confirm affected route enumeration, reroute-to-master, global inserts, and manual clip clear. |
| P2 | Queued phrase staging and scene/phrase performance read model | Phrase/scene probe and inferred default for queued staging | The phrase probe uses local queued state and does not solve authored vs staged phrase mutation. | Fold this into the performance override/phrase plan only after the P0 overlay owner exists. Require visible states for selected, staged, committed, and restored queued phrase edits. |

## Reject / Do Not Cherry-Pick

| Reject | Source | Reason |
|---|---|---|
| Probe UI panels and top-level workspaces | `TrackEditorFoundationProbeView`, `TrackPerformanceOverrideProbePanel`, `AudioInputLoopingAutosliceProbeView`, `MixerRoutingProbePanel`, `ObservabilityProbeWorkspaceView`, `PhraseScenePerformanceProbeView` | They are visual evidence and interaction pressure, not production architecture. Most own state locally in SwiftUI or duplicate existing workspaces. |
| Local `@State` and seeded fixture models | Broad SwiftUI probes and local HTML workbench fixture | Accepted defaults explicitly reject probe-local UI state as production truth. Production needs document/session/runtime/audio-graph owners. |
| Synthetic audio recording and bucket autoslice behavior | Audio input probe | Useful for UI pressure only. It is not PCM capture, not render-adjacent recording, and not sample-level onset detection. |
| Hard-coded 16-step performance presets as final semantics | Performance override probe | Good seed for tests, but final step-order policy must follow clip/phrase length. |
| Top-level Automation tab as musician-facing control | External control probe | Observability is developer tooling until a separate external-control product plan exists. |
| Broad `SequencerAI.xcodeproj/project.pbxproj` diffs | All broad probe implementation commits | Multiple probes regenerated project files. Add production files through the normal project-maintenance path in narrow branches. |
| Whole-branch cherry-picks | All `codex/probe-overnight-broad-probe-2026-05-05-*` branches | Each branch mixes useful model ideas with probe UI, project-file churn, seeded data, and lane-local assumptions. |

## Build Round Sequence

1. **Plan and port the pure track performance override value layer.**
   Start with `TrackPerformanceOverrideLayer` and tests, then add the build plan
   for runtime ownership and playback resolution before wiring UI.
2. **Plan source-slot capture/history identity.**
   Use existing `SourceRef` and `saveCapturedClip` behavior as the production
   base; add tests before UI work.
3. **Plan audio buffer references and mixer returns separately.**
   These touch runtime audio and audio graph ownership, so they should not be
   hidden inside a broad UI pass.
4. **Keep observability as optional developer tooling.**
   It can proceed independently after the music-making P0/P1 work is scheduled,
   provided it does not appear as a normal instrument workspace.

## User Attention

No immediate user attention is required. The current inferred default is still
to treat Happy Accident Workbench as the integrated source-of-truth shape until
later evidence contradicts it.

The next high-leverage user checkpoint should be after the P0 build plans are
written: confirm whether the proposed production build sequence still preserves
the Happy Accident Workbench flow.
