---
feature: midi-interfaces
created: 2026-05-02
---

# MIDI Interfaces Plan

## Status

PM plan — ready for build queue. No production code has been written.

---

## Overview

MIDI Interfaces v1 adds one supported control surface, the Novation Launchpad
Mini MK3, as an app-scoped MIDI control surface for the Phrase and Live
workspaces. The implementation must keep hardware configuration out of the
document model, keep LED rendering and pad handling off the audio hot path, and
use the same document mutation helpers as the SwiftUI views.

The plan runs in seven phases:

1. read-only verification of build-time questions from the spec;
2. MIDI infrastructure needed for input subscription and SysEx output;
3. transient control-surface context and state lifting;
4. Launchpad session, mapper, renderer, and frame model;
5. Phrase and Live workspace adapters;
6. Settings UI, lifecycle, window focus, and coordinator wiring;
7. integration review and acceptance testing.

Phases 1 and 2 are structural prerequisites. Do not build the Settings UI or
workspace adapters before the MIDI input and SysEx boundaries are tested.

---

## Phase 0 — Pre-Build Verification (read-only)

Phase 0 resolves the spec's implementer-findings before coding starts. Record
each finding in the implementation PR description or a short build note.

### 0-A. Confirm macOS deployment target and focus API

**Files to read.**

- Project build settings / `Package.swift` if present.
- `Sources/App/SequencerAIApp.swift`
- `Sources/App/SequencerAIAppDelegate.swift`

**Tasks.**

1. Locate `MACOSX_DEPLOYMENT_TARGET`.
2. If the target is macOS 14 or newer, plan to use `.onWindowFocusChange`.
3. If the target is macOS 13 or earlier, plan an `NSWindowDelegate` or
   `SwiftUI.Application.delegate` interop path for key-window detection.
4. Record the selected focus approach before Phase 6 starts.

**Acceptance signals.**

- The focus approach is known before coordinator wiring begins.
- The implementation does not assume a macOS 14-only API on an older target.

### 0-B. Confirm playhead exposure in `EngineController`

**Files to read.**

- `Sources/Engine/EngineController.swift`
- Existing Live workspace playhead rendering files.

**Tasks.**

1. Confirm whether a published current-step/current-column property already
   exists.
2. If it exists, record its name and thread contract.
3. If it does not exist, plan to add
   `@Published var currentPlayheadColumn: Int`, updated from `dispatchTick()`
   through `DispatchQueue.main.async`.
4. Confirm the adapter can read only a plain step index, not engine internals.

**Acceptance signals.**

- The playhead LED source is known before `LiveControlSurfaceAdapter` is built.
- No adapter reads `PlaybackSnapshot` or any audio hot-path structure.

### 0-C. Confirm scope color model path

**Files to read.**

- `Sources/Document/`
- Live workspace scope/group rendering files.

**Tasks.**

1. Locate whether group or track scope color is stored on `TrackGroup` or an
   equivalent model.
2. Record the exact path used by `LiveControlSurfaceAdapter.scopeColor(for:)`.
3. Confirm ungrouped/uncolored scopes fall back to a non-zero dim-white
   `LaunchpadMiniMK3Palette.uncolored` value.

**Acceptance signals.**

- `scopeColor(for:)` can be a pure function of `document.project`.
- Empty/out-of-bounds rows remain `.off`; uncolored real scopes remain visible.

---

## Phase 1 — MIDI Infrastructure

Phase 1 creates the tested low-level MIDI pieces that all later phases depend
on. It must not touch workspace UI.

### 1-A. Add production MIDI input port support

**What it is.** `MIDIClient` gains a production input subscription API instead
of relying on `clientRefForTesting`.

**Tasks.**

1. Add a `createInputPort(handler:)` / connection method that uses
   `MIDIInputPortCreateWithBlock` and `MIDIPortConnectSource`.
2. Introduce a small `MIDIInputConnection` owner that can disconnect cleanly.
3. Ensure the CoreMIDI callback translates packets without touching document
   state.
4. Add tests for port creation, callback dispatch, and disconnect.

**Artifacts touched.**

- `Sources/MIDI/MIDIClient.swift`
- New MIDI input connection type under `Sources/MIDI/`
- `Tests/SequencerAITests/MIDI/`

**Acceptance signals.**

- External hardware sources can be subscribed to through `MIDIClient`.
- Tests do not use `clientRefForTesting` as the production path.

### 1-B. Add SysEx builder and send coverage

**What it is.** A new stateless `MIDISysExBuilder` supports Launchpad
Programmer-mode and LED SysEx frames.

**Tasks.**

1. Add `MIDISysExBuilder` as a separate value type; do not overload
   `MIDIPacketBuilder` with SysEx concerns.
2. Support frame construction with `0xF0 ... 0xF7`.
3. Add helpers or fixtures for Programmer-mode entry, Programmer-mode restore,
   and Launchpad LED lighting command (`0x03`).
4. Add tests for all three message families.

**Artifacts touched.**

- New `Sources/MIDI/MIDISysExBuilder.swift`
- `Tests/SequencerAITests/MIDI/`

**Acceptance signals.**

- SysEx byte sequences are deterministic and tested.
- Later renderer code can consume a tested builder instead of hand-assembling
  bytes.

---

## Phase 2 — Control-Surface Context and State Lifting

Phase 2 establishes the transient state shared by SwiftUI views and hardware
adapters. It must not add document fields or Codable state.

### 2-A. Introduce `WorkspaceControlSurfaceContext`

**What it is.** A per-document-scene `@Observable` context for hardware-visible
workspace state.

**State owned.**

- `activeSection: WorkspaceSection`
- `liveLayerID: String`
- `phraseTrackPage: Int`
- `phrasePage: Int`
- `scopePage: Int`
- `colPage: Int`
- `selectedPhraseID: String?`

**Tasks.**

1. Add the context in the UI/control-surface boundary.
2. Document that `.tracks` is the current code name for the Live workspace.
3. Keep the context transient and non-Codable.
4. Add unit tests for page clamping and simple state transitions where useful.

**Acceptance signals.**

- No `.seqai` document model changes.
- Views and adapters have one shared source for surface-visible state.

### 2-B. Isolate workspace section and layer lifting

**What it is.** Lift private view state into the shared context without changing
the workspace navigation contract.

**Tasks.**

1. Lift `ContentView.section` into a binding/environment path that updates
   `WorkspaceControlSurfaceContext.activeSection`.
2. Make `WorkspaceControlSurfaceContext.liveLayerID` the single source for the
   Live layer selection; `WorkspaceDetailView` receives a binding into it.
3. Add or update tests for workspace switching before and after the lift.
4. Do not rename `WorkspaceSection.tracks`.

**Acceptance signals.**

- On-screen workspace switching still works with no hardware attached.
- There is no second `liveLayerID` copy kept in sync by observation.

### 2-C. Lift workspace paging state

**Tasks.**

1. Lift `PhraseWorkspaceView.trackPage` into the context.
2. Add `phrasePage` to Phrase workspace behavior and bind it to the context.
3. Add `scopePage` and `colPage` to Live workspace behavior and bind them to
   the context.
4. Clamp all pages to available data.

**Acceptance signals.**

- Phrase and Live views still work without a configured Launchpad.
- Page changes from view controls and future hardware adapters use the same
  state path.

---

## Phase 3 — Launchpad Device Layer

Phase 3 builds the device-specific session, mapper, renderer, palette, and
frame model. It may begin after Phase 1 is complete.

### 3-A. Define frame, LED ID, and palette types

**Tasks.**

1. Add `ControlSurfaceFrame`, `ControlSurfaceLEDID`, and
   `ControlSurfaceLEDState`.
2. Address the full 9x9 surface: 8x8 grid plus top row and right column.
3. Add `LaunchpadMiniMK3Palette` with semantic colors, including non-zero
   `uncolored`.
4. Add tests for LED ID equality/addressing and palette fallback values.

**Acceptance signals.**

- Frame objects are reconstructible from context and project state.
- Frame objects are never persisted.

### 3-B. Add Launchpad input mapper

**Tasks.**

1. Map Programmer-mode note/CC messages to `ControlSurfaceLEDID`.
2. Translate raw messages into `HardwarePadEvent` value types.
3. Distinguish pad down/up events by velocity.
4. Cover all 9x9 positions in tests.

**Acceptance signals.**

- The mapper has no document or context references.
- All physical positions are covered by deterministic tests.

### 3-C. Add Launchpad renderer

**Tasks.**

1. Convert `ControlSurfaceFrame` diffs into LED SysEx messages.
2. Send only changed LEDs after the initial full repaint.
3. Cover full-frame repaint, single-LED change, and no-change behavior with
   tests.
4. Keep renderer state limited to the previous frame used for diffing.

**Acceptance signals.**

- No full-frame repaint is emitted on every SwiftUI update.
- Zero-change renders send zero SysEx messages.

### 3-D. Add `LaunchpadMiniMK3Session`

**Tasks.**

1. Own the `MIDIInputConnection`, independent SysEx output path, and renderer.
2. Send Programmer-mode SysEx on attach.
3. Send restore-to-Live-mode SysEx on detach.
4. Dispatch `HardwarePadEvent` to the main queue with
   `DispatchQueue.main.async`.

**Acceptance signals.**

- No document mutation occurs on the CoreMIDI callback thread.
- Detach is idempotent and closes input/output resources cleanly.

---

## Phase 4 — Workspace Adapters

Phase 4 translates context plus project data into frames and document mutations.
Adapters must call the same mutation helpers as the SwiftUI views.

### 4-A. Build `PhraseControlSurfaceAdapter`

**Tasks.**

1. Build the 8x8 phrase-by-track frame from `document.project` and
   `WorkspaceControlSurfaceContext`.
2. Implement top-row CC actions exactly as specified for CC 91-98.
3. Implement right-column row-select, updating `selectedPhraseID`.
4. Route in-bounds grid pad presses through the existing phrase-grid mutation
   helper.
5. Guard phrase-slice and track-slice bounds before every mutation.
6. Apply LED precedence: playing > selected > filled/scalar/pattern-slot >
   empty.

**Tests.**

- 8x8 matrix derivation.
- Track and phrase page clamping.
- Partial-page pads render `.off` and press as no-op.
- `jump-to-active-phrase-page` no-ops when no phrase is selected.

**Acceptance signals.**

- Hardware and screen mutate the same cells.
- Out-of-bounds pads never mutate the document.

### 4-B. Build `LiveControlSurfaceAdapter`

**Tasks.**

1. Build the scope-row by step/bar-column frame from `document.project`,
   context, and the playhead source confirmed in Phase 0-B.
2. Implement top-row CC actions exactly as specified for CC 91-98.
3. Implement right-column scope select.
4. Route in-bounds grid pad presses through the existing Live workspace mutation
   helper.
5. Guard scope-slice and column-slice bounds before every mutation.
6. Apply playhead column as a full override after other LED states.
7. Use pure `scopeColor(for:)` with non-zero uncolored fallback.

**Tests.**

- Scope/step mapping.
- Scope and column page clamping.
- Playhead full override.
- Uncolored scope fallback.
- Partial-page pads render `.off` and press as no-op.

**Acceptance signals.**

- The Live workspace can be performed from hardware without changing Settings.
- Playhead rendering does not read engine snapshots or touch the audio hot path.

---

## Phase 5 — Settings, Preferences, Coordinator, and Lifecycle

Phase 5 wires the user-facing configuration and app-scoped ownership model.

### 5-A. Add app-scoped control-surface preferences

**Tasks.**

1. Add `ControlSurfacePreferences` backed by `UserDefaults` / `@AppStorage`.
2. Persist only `enabled`, `surfaceKind`, `inputEndpointUID`, and
   `outputEndpointUID`.
3. Add tests for persistence roundtrip and missing-endpoint fallback.

**Acceptance signals.**

- Preferences are app-scoped, not document-scoped.
- No page, selection, LED, or workspace state is persisted.

### 5-B. Add Control Surfaces section to MIDI Settings

**Tasks.**

1. Add the section inside the existing MIDI tab; do not create a new top-level
   Preferences tab.
2. Add the Launchpad Mini MK3 enable toggle.
3. Add input and output endpoint pickers, disabled when the toggle is off.
4. Add the endpoint note: "Select the regular MIDI (not DAW) endpoints for
   Programmer mode."
5. Add the five status states from the spec.
6. Add "Test LEDs" with connected-only availability, 2.5-second feedback, and
   2.5-second cooldown.

**Acceptance signals.**

- Endpoint selection survives relaunch.
- Device-missing state is clear and non-crashing.
- Test LEDs sends a full-surface pattern only when connected.

### 5-C. Add `ControlSurfaceCoordinator`

**Tasks.**

1. Create the coordinator in `SequencerAIApp` as a `@StateObject`.
2. Inject it through `.environmentObject`.
3. Attach/detach `LaunchpadMiniMK3Session` based on preferences and live
   CoreMIDI endpoint availability.
4. Hold a weak/current reference to the active
   `WorkspaceControlSurfaceContext`.
5. Repaint all 81 pads on attach, workspace switch, page change, or focused
   document change.

**Acceptance signals.**

- There is one app-scoped coordinator, not a static singleton plus an
  environment object competing for ownership.
- Switching workspaces routes pad events to the active adapter and repaints the
  full surface.

### 5-D. Wire lifecycle and hot-plug behavior

**Tasks.**

1. Insert `ControlSurfaceCoordinator.detachAll()` in app termination before
   document session flush/shutdown completes.
2. Handle endpoint disappearance by detaching the session and moving Settings
   to "Device not found".
3. Handle endpoint reappearance by reattaching automatically when preferences
   are still enabled.
4. Ensure disabling the toggle sends restore-to-Live-mode SysEx.

**Acceptance signals.**

- The Launchpad is not left in Programmer mode after disable or quit.
- Removing the device does not crash or send to stale endpoint refs.

### 5-E. Wire focused-window ownership

**Tasks.**

1. Use the Phase 0-A focus approach to bind the frontmost document's context to
   the coordinator.
2. On focus change, stop delivering events to the old context.
3. Repaint immediately for the new document.

**Acceptance signals.**

- Two open document windows do not share hardware input.
- Bringing a different document forward makes the Launchpad follow it.

---

## Phase 6 — Integration Review and Acceptance

Phase 6 is the shippability pass after Phases 1-5 are complete.

### 6-A. Run component tests

Required coverage:

| Component | Required tests |
|---|---|
| `MIDISysExBuilder` | Programmer entry, Programmer restore, LED command |
| `MIDIClient` input path | Port creation, connection, callback dispatch, disconnect |
| `ControlSurfacePreferences` | Persistence roundtrip, missing-endpoint fallback |
| `LaunchpadMiniMK3InputMapper` | All 9x9 note/CC mappings |
| `LaunchpadMiniMK3Renderer` | Full repaint, single change, no change |
| `PhraseControlSurfaceAdapter` | Matrix derivation, partial pages, page clamping |
| `LiveControlSurfaceAdapter` | Scope/step mapping, playhead override, uncolored fallback |

### 6-B. Run manual hardware checklist

Manual acceptance requires a real Launchpad Mini MK3 connected through its
regular MIDI endpoints.

- [ ] Enabling the surface sends Programmer-mode SysEx.
- [ ] Disabling the surface restores Live mode.
- [ ] Quitting the app restores Live mode.
- [ ] Settings endpoint selection survives relaunch.
- [ ] Test LEDs lights the full surface and respects cooldown.
- [ ] Phrase grid pad edits the matching on-screen cell.
- [ ] Phrase top-row paging and layer buttons match CC 91-98.
- [ ] Phrase partial pages show dark, no-op pads.
- [ ] Live grid pad edits the matching scope/step or scope/bar cell.
- [ ] Live top-row paging, workspace switch, and transport match CC 91-98.
- [ ] Live playhead column overrides cell colors while playing.
- [ ] Switching Phrase/Live workspaces repaints all pads.
- [ ] Focusing a second document repaints and reroutes hardware input.
- [ ] Unplugging the device moves Settings to the missing-device state without
      crashing.

### 6-C. Final review gate

Before marking the build complete:

1. Confirm no control-surface runtime state was added to the document model.
2. Confirm pad input callbacks dispatch to the main queue before semantic
   handling.
3. Confirm LED rendering does not touch the engine hot path.
4. Confirm all out-of-bounds pad guards run before document mutation.
5. Confirm the feature still works with no hardware configured.

---

## Files and Modules Expected to Change

| Area | Expected files |
|---|---|
| MIDI infrastructure | `Sources/MIDI/MIDIClient.swift`, new `MIDIInputConnection`, new `MIDISysExBuilder` |
| App bootstrap/lifecycle | `Sources/App/SequencerAIApp.swift`, `Sources/App/SequencerAIAppDelegate.swift` |
| Preferences | `Sources/UI/PreferencesView.swift`, new preferences support type |
| Control surface core | New frame, LED ID, palette, mapper, renderer, session, coordinator, context, and adapter files |
| Workspace UI state | `ContentView`, `WorkspaceDetailView`, `PhraseWorkspaceView`, `LiveWorkspaceView` or their focused subviews |
| Engine exposure | `EngineController` only if Phase 0-B confirms no safe playhead property exists |
| Tests | New `Tests/SequencerAITests/ControlSurface/`, plus focused MIDI and preference tests |

No document model files should gain persisted control-surface state. No schema
migration is expected.

---

## Sequencing Notes

1. Phase 0 is read-only and should be completed first.
2. Phase 1 must land before any device session or adapter depends on input or
   SysEx output.
3. Phase 2-B state lifting should be isolated in its own commit because it
   touches core workspace navigation.
4. Phase 3 can proceed in parallel with Phase 2 after Phase 1 is complete, as
   long as frame/model tests do not depend on lifted UI state.
5. Phrase and Live adapters should be built after their relevant context fields
   are lifted.
6. Settings can be built before adapters, but the toggle must not claim
   "Connected" until the coordinator/session path exists.
7. Hardware manual testing is required before shipping because SysEx mode
   changes and LED colors cannot be fully trusted from unit tests alone.

---

## Non-Goals and Deferred Work

The following must not be built as part of this plan:

- Additional control surfaces beyond Novation Launchpad Mini MK3.
- Multi-surface support.
- Per-document control-surface preferences.
- Modifier-chord or long-press gestures.
- LED pulsing/flashing or MIDI-clock-driven animation.
- Renaming `WorkspaceSection.tracks` to `.live`.
- Persisting pad state, LED frames, page indices, layer IDs, or selected phrase
  state in `.seqai`.
- Reworking the existing sequencer MIDI note-output path through `MidiOut` or
  `MIDIRouter`.
