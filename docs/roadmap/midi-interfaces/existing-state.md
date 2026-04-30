# MIDI Interfaces — Existing State

Inspected on 2026-04-29. Source files examined are listed per finding.

---

## What Exists Today

### MIDI Layer

**`Sources/MIDI/MIDISession.swift`**

- App-wide singleton (`MIDISession.shared`) that owns a single `MIDIClient`.
- Creates one virtual output endpoint ("SequencerAI Out") and one virtual input endpoint ("SequencerAI In") at launch.
- Exposes `sources: [MIDIEndpoint]` and `destinations: [MIDIEndpoint]` (live CoreMIDI enumeration) for UI display.
- The virtual input handler has a `TODO(phase 2)` comment that explicitly acknowledges incoming MIDI from external hardware is dropped: "route incoming MIDI into the engine".
- There is no concept of connecting to an external hardware source; the virtual input only receives messages that other apps forward to "SequencerAI In".

**`Sources/MIDI/MIDIClient.swift`**

- Wraps CoreMIDI and provides `send(_:to:)` which handles both virtual source injection (`MIDIReceived`) and real destination sends (`MIDISend` via a lazy output port).
- `createVirtualInput` and `createVirtualOutput` cover the app's own endpoints.
- **No `MIDIInputPortCreateWithBlock` / `MIDIPortConnectSource` path exists.** The only comment referencing input ports is in `clientRefForTesting`, which exposes the client ref specifically so tests can create input ports externally. There is no production subscription capability for subscribing to an arbitrary hardware source.
- `MIDIClientCreateWithBlock` notification closure is a no-op: "MIDI system notifications — handled in a later task."
- No hot-plug (device connect/disconnect) tracking.

**`Sources/MIDI/MIDIEndpoint.swift`**

- Plain value type wrapping `MIDIEndpointRef`, `MIDIUniqueID`, `displayName`, and `role`. No filtering, badging, or manufacturer metadata.

**`Sources/MIDI/MIDIPacketBuilder.swift`**

- Supports note-on, note-off, and CC messages only.
- **No SysEx support.** Programmer-mode entry/exit and LED lighting on the Launchpad Mini MK3 both require SysEx messages (`0xF0 … 0xF7`). This is a hard gap.

---

### Settings / Preferences

**`Sources/UI/PreferencesView.swift`**

- Three-tab form: General (placeholder), MIDI, Audio (placeholder).
- MIDI tab shows three read-only sections: Inputs (lists `sources`), Outputs (lists `destinations`), Virtual (shows this app's virtual endpoints).
- Lists are populated via `@State` snapshots refreshed by a "Refresh" button; no reactive observation or hot-plug updates.
- **No Control Surfaces section.** No toggle, endpoint picker, status row, or Test LEDs button.
- **No persistence of any MIDI setting.** No `@AppStorage`, `UserDefaults`, or `ControlSurfacePreferences` type anywhere in the codebase.

---

### App Bootstrap and Lifecycle

**`Sources/App/SequencerAIApp.swift`**

- `_ = MIDISession.shared` warms the MIDI singleton at launch.
- No `ControlSurfaceCoordinator` instantiation. No app-scoped control-surface context.
- `DocumentGroup` scene creates one `SequencerDocumentRootView` per document; no focus-tracking hook to rebind hardware between windows.

**`Sources/App/SequencerAIAppDelegate.swift`**

- `applicationWillTerminate` calls `SequencerDocumentSessionRegistry.flushAll()` then `shutdownAll()` then drains the run loop.
- **No detach / restore-to-Live-mode path for a Launchpad.** If the device were in Programmer mode at termination, it would remain locked there.

---

### Workspace State

**`Sources/UI/ContentView.swift`**

- Owns `section: WorkspaceSection` as `@State private`. Not exposed to any shared context.

**`Sources/UI/WorkspaceSection.swift`**

- Six cases: `.phrase`, `.tracks`, `.track`, `.mixer`, `.scenes`, `.library`.
- The "Live" workspace from the user stories is represented by the `.tracks` case (which renders `TracksWorkspaceView`). There is no `.live` case; the plan refers to "Live workspace" but the enum uses `.tracks`.

**`Sources/UI/WorkspaceDetailView.swift`**

- `liveLayerID: String` is `@State private`, defaulting to `"pattern"`. Not lifted to any shared observable.
- `tracksMode: TracksWorkspaceMode` is also `@State private`.
- Routes `.phrase` to `PhraseWorkspaceView` and `.tracks` to `TracksWorkspaceView`. No `.live` routing yet.

**`Sources/UI/PhraseWorkspaceView.swift`**

- Has `trackPage: Int` as `@State private` (paging tracks in groups of 8 — a direct natural fit for the Launchpad grid).
- `selectedLayerID` is also `@State private`.
- No `phrasePage` concept exists; phrases are not yet paged.
- State is entirely local to the view; nothing is externally observable.

**`Sources/UI/LiveWorkspaceView.swift`**

- `selectedLayerID` is passed in as `@Binding` (from `WorkspaceDetailView.liveLayerID`).
- `visibleScopes` is computed from track groups and tracks; not paged in groups of 8.
- `collapseGroups: Bool` is `@State private`.
- No hardware-addressable paging state; no scope page, step page, or bar page concept.

---

## Where Current Experience Diverges from User Stories

| Story | Gap |
|---|---|
| 1. Configure control surface in Settings | No Control Surfaces section in MIDI prefs; no endpoint pickers; no persistence |
| 2. Automatic Programmer-mode management | No SysEx in `MIDIPacketBuilder`; no `LaunchpadMiniMK3Session`; no attach/detach lifecycle |
| 3. Stable controller routing to active workspace | No external input subscription (`MIDIInputConnection` missing); no `ControlSurfaceCoordinator`; no `WorkspaceControlSurfaceContext` |
| 4. Phrase workspace hardware editing | `trackPage` is private state; no `phrasePage`; no `ControlSurfaceFrame`; no `PhraseControlSurfaceAdapter` |
| 5. Live workspace hardware performance | Scope, step/bar paging all private local state; no `LiveControlSurfaceAdapter` |
| 6. Focused-window ownership | No window-focus tracking hook; `ContentView` section state is not shared |
| 7. Test LEDs | No Test LEDs button; no SysEx path for LED lighting SysEx (`03h`) |

---

## Model Gaps vs. UX / Workflow Gaps

### Model gaps (no code exists)

- `MIDIInputConnection` — input port subscription to external hardware source.
- `ControlSurfacePreferences` — persistence of enabled state, surface kind, selected endpoint IDs.
- `ControlSurfaceCoordinator` — app singleton routing surface to focused document window.
- `WorkspaceControlSurfaceContext` — shared observable for active workspace section, layer ID, phrase page, scope page, step/bar page.
- SysEx builder support in `MIDIPacketBuilder` or a parallel `MIDISysExBuilder`.
- `LaunchpadMiniMK3Session` — Programmer-mode entry/exit, LED frame sends.
- `LaunchpadMiniMK3InputMapper` — note/CC index → semantic action translation.
- `LaunchpadMiniMK3Renderer` — frame diff and SysEx LED lighting (`03h`) output.
- `LaunchpadMiniMK3Palette` — semantic colour → Launchpad palette/RGB mapping.
- `PhraseControlSurfaceAdapter` — phrase matrix model from project + context.
- `LiveControlSurfaceAdapter` — live scope/step model from project + context.
- `ControlSurfaceFrame` / `ControlSurfaceLEDState` — device-agnostic frame model.

### UX / Workflow state gaps (private state must be lifted or mirrored)

- `ContentView.section` must be observable to `WorkspaceControlSurfaceContext`.
- `WorkspaceDetailView.liveLayerID` must be lifted out of local `@State`.
- `PhraseWorkspaceView.trackPage` must be lifted or mirrored into shared context.
- A new `phrasePage` concept must be introduced in `PhraseWorkspaceView` (and shared context).
- `LiveWorkspaceView` needs scope page and step/bar page state in shared context.

---

## Architecture Constraints

- `MIDISession` is a singleton but `MIDIClient` is not `open` and has no public input-port creation method (only `clientRefForTesting` for tests). A new `MIDIInputConnection` class will need to use `clientRefForTesting` or the client must gain a proper production `createInputConnection` method.
- The app is document-based with `DocumentGroup`. Focus tracking for "key window" in SwiftUI on macOS requires explicit `NSWindowDelegate` hooks or the `.focusedSceneValue` / `.onWindowFocusChange` modifier chain; neither is present.
- `applicationWillTerminate` in `SequencerAIAppDelegate` already has a structured shutdown sequence (`SequencerDocumentSessionRegistry.flushAll()` → `shutdownAll()` → drain). The detach/restore path for the Launchpad must be wired into this sequence — likely by adding `ControlSurfaceCoordinator.detachAll()` before the drain step.
- `MIDIPacketBuilder` is a value type with a fixed event type set. SysEx requires either a new `addSysEx(bytes: [UInt8], timestamp:)` method or a separate builder; it cannot be retrofitted by the control-surface work without modifying `Sources/MIDI/`.
- The `.tracks` workspace case in `WorkspaceSection` serves as "Live"; there is no `.live` case. The plan and stories refer to "Live workspace" — whether to rename `.tracks` or add `.live` should be clarified before the spec is written, as it affects how `ControlSurfaceCoordinator` maps section state.

---

## Relevant Tests and Missing Coverage

### Existing tests that touch the MIDI boundary

- `Tests/SequencerAITests/MIDI/MIDIClientSendTests.swift` — covers `MIDIClient.send`.
- `Tests/SequencerAITests/MIDI/MIDIPacketBuilderTests.swift` — covers note-on, note-off, CC construction.
- `Tests/SequencerAITests/MIDIClientTests.swift` — covers client creation and virtual endpoint lifecycle.

### No tests exist for any of the following (all new work)

- `MIDIInputConnection` connect/disconnect/callback lifecycle.
- `ControlSurfacePreferences` persistence roundtrip and missing-endpoint fallback.
- `LaunchpadMiniMK3InputMapper` note/CC index → coordinate mapping.
- `LaunchpadMiniMK3Renderer` frame-to-SysEx translation, palette mapping, diff behavior.
- `PhraseControlSurfaceAdapter` 8×8 matrix derivation, paging, colour decisions.
- `LiveControlSurfaceAdapter` scope/step mapping, playhead highlighting, row action routing.
- No `Tests/SequencerAITests/ControlSurface/` directory exists.
- No `Tests/SequencerAITests/Platform/ControlSurfacePreferencesTests.swift` exists.
