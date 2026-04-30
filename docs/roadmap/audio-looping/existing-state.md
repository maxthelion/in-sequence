# Audio Looping — Existing State

Inspected on 2026-04-29 against branch `codex/tracks-perform-scenes-workspace`.

Scope: the **macro live-looping performance page** described in `user-stories.md`. Track-level audio capture is covered by `docs/roadmap/input-audio/existing-state.md` and is a prerequisite; findings here are limited to the five page-level stories (open page, arm, simultaneous record, playback toggle, clear).

---

## 1. Navigation / Workspace Architecture

**What exists**

`WorkspaceSection` (`Sources/UI/WorkspaceSection.swift`) is an exhaustive enum with six cases: `.phrase`, `.tracks`, `.track`, `.mixer`, `.scenes`, `.library`. It drives both the sidebar (`SidebarView`) and the main content switch in `WorkspaceDetailView`.

`SidebarView` (`Sources/UI/SidebarView.swift`) renders all sections via a `globalRow(title:systemImage:sectionValue:)` helper. Adding a new section is a two-file change: a new case in `WorkspaceSection` and a new `globalRow` call in `SidebarView`. Both files are otherwise well-structured for this kind of extension.

`WorkspaceDetailView` (`Sources/UI/WorkspaceDetailView.swift`) dispatches on `WorkspaceSection` in a `switch` inside a `@ViewBuilder`. Each section resolves to a dedicated workspace view (e.g., `ScenesWorkspaceView`, `MixerWorkspaceView`). A `looping` section would need a matching case here.

**Gaps vs. user stories**

- Story 1 (open the live-looping page): There is no `WorkspaceSection.looping` case, no sidebar entry for it, and no workspace view backing it. The structural pattern to add one is clear and already precedented, but the code does not yet exist.

---

## 2. Track Arm State

**What exists**

`StepSequenceTrack` (`Sources/Document/StepSequenceTrack.swift`) has no `isArmed`, `pendingArm`, or any recording-readiness field. The document model has no per-track or session-level concept of "armed tracks."

`Project` (`Sources/Document/Project.swift` and its extensions) has no `armedTrackIDs: Set<UUID>` or equivalent. The session mutation layer (`Sources/App/SequencerDocumentSession+Mutations.swift`) has no `armTrack`, `disarmTrack`, or `setArmed` function.

**Gaps vs. user stories**

- Story 2 (arm a track): No arm state exists anywhere — not on the track model, not on the project, not on the session. Arm/disarm controls and state transitions (empty → armed → armed-again-to-clear) have no foundation.

---

## 3. Simultaneous Record Trigger (Quantized Global Start)

**What exists**

`TransportBar` (`Sources/UI/TransportBar.swift`) has a record button (`record.circle.fill` icon) that is rendered but **permanently disabled** (`disabled(true)`) with an empty action closure. It is a visual stub only.

`EngineController` (`Sources/Engine/EngineController.swift`) exposes `start()` / `stop()` for the playback clock but has no `startRecordingArmedTracks()` or equivalent method. The `CommandQueue` / `EventQueue` system carries MIDI note and AU events; there is no record-trigger command kind.

`TickClock` (`Sources/Engine/TickClock.swift`) fires step-boundary callbacks via a software timer. Bar boundaries are detectable as `transportTickIndex % stepsPerBar == 0`, which is the natural hook point for a quantized record start. However no code uses this to trigger record arming; the mechanism exists but is unharvested.

`LayerSnapshot` (`Sources/Engine/LayerSnapshot.swift`) carries per-track mute and fill state — it does not carry arm or recording state.

**Gaps vs. user stories**

- Story 3 (trigger recording across armed tracks simultaneously): No global record trigger is wired. The transport record button is a non-functional stub. No quantized-start logic exists in the engine or clock layer.

---

## 4. Per-Track Playback Toggle (Loop Mute / Unmute)

**What exists**

Track mute is fully implemented at both the document and engine levels:

- `TrackMixSettings.isMuted: Bool` (`Sources/Document/TrackMixSettings.swift`) persists per-track mute in the document.
- `LayerSnapshot.mute: [UUID: Bool]` (`Sources/Engine/LayerSnapshot.swift`) carries live mute state for the render tick.
- `EngineController` checks `isMuted` in `syncAudioOutputs`, `processTick`, and MIDI dispatch paths; a muted track produces no output.
- `SequencerDocumentSession+Mutations.swift` exposes `toggleTrackMute(trackID:)` and `setTrackMuted(_:trackID:)`.

This infrastructure is the closest analogue to the story-4 playback toggle. However:

- Mute operates on the overall track, not specifically on a recorded audio loop. Muting a step-sequencer track silences its MIDI/AU output, but a live-looping playback toggle conceptually controls whether the recorded audio loop is audible, independently of step-sequencer output.
- If the looping page targets tracks that are solely playing back a recorded audio loop (no concurrent step output), the existing `toggleTrackMute` mutation could be reused as the playback-on/off mechanism, provided the underlying audio-input track model is in place. That model does not yet exist (see `input-audio/existing-state.md`).

**Gaps vs. user stories**

- Story 4 (toggle loop playback): The mute toggle primitives exist and are wired through the engine, but they target the general track output, not a discrete loop-playback state. Whether the mute primitive can be repurposed directly depends on how the Input Audio track model defines the relationship between step output and loop playback. That model is not yet built.

---

## 5. Clear a Loop

**What exists**

No "clear loop" concept exists anywhere in the codebase. There is no record buffer to clear, no `clearLoop(trackID:)` mutation, and no engine-side buffer reset path.

**Gaps vs. user stories**

- Story 5 (clear a loop): Entirely absent at every layer (model, engine, UI).

---

## 6. "Loop-Capable Track" Filter

**What exists**

`TrackType` (`Sources/Document/TrackType.swift`) has three cases: `.monoMelodic`, `.polyMelodic`, `.slice`. None of these represents a track that can record live audio input. There is no `isLoopCapable` computed property, no protocol, and no query in `LiveSequencerStore` or `Project` that would let a workspace filter for audio-input-capable tracks.

**Gaps vs. user stories**

- Story 1 requires the looping page to show only "tracks capable of looping." That capability check depends on a new `TrackType` case or `Destination` variant for audio input, which is the Input Audio feature's job to define. Until that is done, the filter predicate for this page cannot be written.

---

## 7. Related: Input Audio Prerequisite

The `input-audio/existing-state.md` report confirms that no audio-input track type, no record buffer, no `AVAudioEngine.inputNode` tap, no arm state, and no quantized-record mechanism exist anywhere in the codebase. The Audio Looping performance page is a consumer of the Input Audio track model; it cannot be built independently.

---

## 8. Architecture Constraints

**Navigation extension is straightforward.** Adding a `.looping` case to `WorkspaceSection` and the corresponding sidebar row and workspace view switch arm follows a precedented, low-risk pattern. This part of the work can be prototyped without waiting for Input Audio to be complete (using a placeholder content view that expects the loop model to be injected).

**Arm state belongs at the session level, not the track level.** The current `StepSequenceTrack` model treats all state as document-persisted. Arm state is transient (it should not survive a save/reload). The cleanest placement is a `@State` or `@Observable` property on `SequencerDocumentSession` (not `Project`), analogous to how `selectedTrackID` is already stored in `Project` but arm state would be more naturally session-only. This is a design decision to record in the spec.

**Global record trigger needs an engine hook.** The transport record button stub in `TransportBar` gives an existing UI anchor. Wiring it requires: (a) a session-level set of armed track IDs, (b) an engine method that inspects those IDs and starts capture on the next bar boundary, (c) the `TickClock` bar-boundary hook described in `input-audio/existing-state.md`.

**Mute primitives are a usable starting point for the playback toggle.** `toggleTrackMute` and the `LayerSnapshot.mute` path are already tested and wired through the engine. If the Input Audio feature models loop playback as a track whose only audible output is the loop buffer, then mute becomes equivalent to "silence the loop." This would need to be confirmed in the Input Audio spec before the looping page relies on it.

---

## 9. Relevant Tests

No test file in `Tests/` references looping, arm state, or a loop performance page. The mute toggle is exercised indirectly via engine snapshot tests, but there are no dedicated tests for:

- a looping workspace section
- arm/disarm state transitions
- global record trigger
- loop-capable track filtering
- clear-loop state transitions

---

## 10. Summary of Gaps by Story

| Story | Model gap | Engine gap | UI gap |
|---|---|---|---|
| 1. Open looping page | No loop-capable track type (blocks filter) | — | No `WorkspaceSection.looping`, no workspace view |
| 2. Arm a track | No arm state on track or session | No arm command kind | No arm control |
| 3. Global record trigger | No armed-tracks set | Record button is a disabled stub; no bar-boundary hook | No global trigger UI |
| 4. Playback toggle | Mute primitive exists but is not loop-specific | Mute engine path works; applicability depends on Input Audio model | No loop-page playback toggle |
| 5. Clear a loop | No loop buffer to clear | No buffer-reset path | No clear control |

---

## 11. Dependency on Input Audio

This feature cannot be specced or built until `input-audio` delivers:

1. A `TrackType` or `Destination` variant for audio input (defines "loop-capable").
2. A per-track record buffer and arm mechanism (stories 2, 3, 5 all write to / read from this buffer).
3. A quantized-record-start hook in `EngineController` (story 3).

The navigation shell (story 1) and the playback-toggle wiring (story 4, using the existing mute path) could be prototyped independently, but those prototypes would be placeholder-only until the Input Audio model stabilises.

---

## Next Action

Build a prototype of the looping page navigation shell and per-track card layout under `docs/roadmap/audio-looping/prototypes/`. This can be done in HTML per the prototype guidelines without waiting for Input Audio, using placeholder data to validate the card-based performance UI.
