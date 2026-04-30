---
feature: midi-interfaces
created: 2026-04-30
---

# MIDI Interfaces — Specification

Sources: `user-stories.md`, `existing-state.md`, `ux-review.md` (accepted),
`architecture.md`, `architecture-review.md` (accepted, risks M1–M3, questions Q1–Q3).

---

## 1. Scope and Non-Goals

### In scope (v1)

- One device: Novation Launchpad Mini MK3 (regular MIDI interface, Programmer
  mode).
- Control Surfaces section in MIDI Settings: enable toggle, input/output endpoint
  pickers, status row, "Test LEDs" button.
- Automatic Programmer-mode entry on connect; restore to device-default Live mode
  on disable or quit.
- Context-aware routing: the same physical pads operate the active workspace
  without any Settings reconfiguration.
- Phrase workspace hardware grid: 8×8 phrase-by-track matrix with edge buttons
  for paging and layer switching.
- Live workspace hardware grid: scope rows × step/bar columns with edge buttons
  for layer, scope, and column paging, workspace switching, and transport.
- Focused-window ownership: hardware follows the frontmost document window.
- Test LEDs: brief full-surface pattern to verify endpoint selection.

### Explicitly out of scope (v1)

- Modifier-chord / long-press gestures on the hardware (deferred to v2).
- Hardware LED pulsing and flashing (static colors only; deferred until MIDI
  clock is intentionally emitted).
- Additional control surface devices beyond the Launchpad Mini MK3.
- Renaming `WorkspaceSection.tracks` to `.live` (see Section 6.1).
- Multi-surface support (architecture must not prevent it, but v1 supports one
  surface at a time).
- Per-document control surface configuration (all preferences are app-scoped).

---

## 2. Persisted State

`ControlSurfacePreferences` is app-scoped, stored in `UserDefaults` (via
`@AppStorage`). It contains exactly:

| Field | Type | Default |
|---|---|---|
| `enabled` | `Bool` | `false` |
| `surfaceKind` | `SurfaceKind` (enum; v1: `.launchpadMiniMK3` only) | `.launchpadMiniMK3` |
| `inputEndpointUID` | `MIDIUniqueID?` | `nil` |
| `outputEndpointUID` | `MIDIUniqueID?` | `nil` |

Nothing else is persisted. Pad state, LED frames, page indices, layer IDs, and
selection state are all transient runtime values. They must not enter the `.seqai`
document model.

---

## 3. Transient Runtime State

`WorkspaceControlSurfaceContext` is an `@Observable` class, one instance per
active document scene. It is the single source of truth for all surface-visible
workspace state.

| Property | Type | Source / Lifting |
|---|---|---|
| `activeSection` | `WorkspaceSection` | Lifted from `ContentView.section` (currently `@State private`). Must become a `@Binding` or `@Environment`-injectable value. |
| `liveLayerID` | `String` | `WorkspaceControlSurfaceContext` becomes the single source; `WorkspaceDetailView` receives a `@Binding` into it (see M2 resolution, Section 5.2). |
| `phraseTrackPage` | `Int` | Lifted from `PhraseWorkspaceView.trackPage`. |
| `phrasePage` | `Int` | New; introduced alongside `phraseTrackPage` in the view. |
| `scopePage` | `Int` | New; introduced in `LiveWorkspaceView`. |
| `colPage` | `Int` | New; introduced in `LiveWorkspaceView`. |
| `selectedPhraseID` | `String?` | Lifted from local phrase row-select logic. |

Views and adapters both read from this context. There must be no parallel copy
of any of these values. The context does not duplicate document model data.

---

## 4. Device Session and Coordinator

### 4.1 Coordinator injection (M1 resolution)

`ControlSurfaceCoordinator` is created in `SequencerAIApp` as a `@StateObject`
and injected via `.environmentObject(coordinator)` on the `DocumentGroup`. This
matches the singleton-warmup pattern used by `MIDISession.shared` and is the
required approach. A true static `shared` singleton is not used; the SwiftUI
environment is the access path.

The coordinator holds:

- A reference to the current `LaunchpadMiniMK3Session` (or `nil`).
- A weak reference to the currently active `WorkspaceControlSurfaceContext`.

### 4.2 Session ownership

`LaunchpadMiniMK3Session` is owned by the coordinator. It holds:

- `MIDIInputConnection` — subscribes to the selected hardware source.
- An independent output port for SysEx LED commands (does not share `MidiOut`
  or `MIDIRouter`).
- The last-sent `ControlSurfaceFrame` for diffing.

`LaunchpadMiniMK3Renderer` is stateless (or minimal for diff). It never holds
document or workspace state.

### 4.3 App lifecycle

**Startup:** `ControlSurfaceCoordinator` is created in `SequencerAIApp.body`
as `@StateObject`. On creation, it reads `ControlSurfacePreferences` and, if
`enabled == true` and both endpoint UIDs are set and the endpoints are present
in CoreMIDI, it creates a `LaunchpadMiniMK3Session` and sends the Programmer-mode
SysEx.

**Shutdown:** `ControlSurfaceCoordinator.detachAll()` is inserted in
`SequencerAIAppDelegate.applicationWillTerminate`, before the existing
`SequencerDocumentSessionRegistry.flushAll()` call. `detachAll()` sends the
restore-to-Live-mode SysEx and closes the input/output MIDI ports. No
Programmer-mode lock survives process exit.

**Window focus (Story 6):** The coordinator must bind the active
`WorkspaceControlSurfaceContext` to the frontmost document window. Bringing a
different document window to the front rebinds the surface, immediately repaints
all 81 pads, and stops delivering pad events to the previously active window.

**Implementer finding Q1 — Minimum macOS deployment target:** Look up
`MACOSX_DEPLOYMENT_TARGET` in the project build settings or `Package.swift`.

- If macOS 14+: use `.onWindowFocusChange` for focus tracking.
- If macOS 13 or earlier: use `NSWindowDelegate` via AppKit interop. This
  requires wrapping each `DocumentGroup` window in an `NSWindowController`
  subclass or using a `SwiftUI.Application.delegate` shim. This is
  implementation-non-trivial and must not be treated as a one-liner; allocate
  accordingly.

The spec does not hardcode the approach because the deployment target is a
project build setting.

---

## 5. Resolved Architecture Risks

### 5.1 M1 — Coordinator injection: resolved

Use `@StateObject` in `SequencerAIApp` body + `.environmentObject(coordinator)`
on the `DocumentGroup`. See Section 4.1.

### 5.2 M2 — `liveLayerID` binding path: resolved

`WorkspaceControlSurfaceContext.liveLayerID` is the single source of truth for
the live layer selection. `WorkspaceDetailView` must receive a `@Binding` into
this property rather than owning a separate `@State private var liveLayerID`.
The lifting strategy: when the context is injected into the view tree,
`WorkspaceDetailView` reads `liveLayerID` from the context and passes it down as
a binding to `LiveWorkspaceView`. There must be no separate copy. If this
cannot be achieved without a copy (e.g., because of SwiftUI's initialization
rules for `@State`), the implementation loop must resolve the structural
conflict and record the chosen approach before shipping. Do not leave two
independent values in sync via observation.

### 5.3 M3 — `HardwarePadEvent` dispatch mechanism: resolved

The CoreMIDI input callback on `MIDIInputConnection` runs on a background
thread. The callback must:

1. Translate the raw note/CC byte pair into a `HardwarePadEvent` value type
   (struct, no references to document or context).
2. Dispatch to the main queue via `DispatchQueue.main.async { adapter.handle(event) }`.

`@MainActor`-annotated methods are not the required mechanism; explicit
`DispatchQueue.main.async` is, because the CoreMIDI callback is not
`@MainActor`-aware and bridging would require an `assumeIsolated` pattern that
is error-prone. Use `DispatchQueue.main.async`.

**Back-pressure:** If events arrive faster than the main queue drains (e.g., a
user holding a pad), the events queue in the main dispatch queue. No additional
back-pressure mechanism is required for v1; pad events are small and infrequent
compared to audio callbacks. If pad-hold bursts cause observable UI stutter in
practice, the implementation loop may add a debounce at the callback boundary
without a spec revision.

---

## 6. Implementation Findings (Q1–Q3)

These questions are resolvable by reading the codebase. The implementer must
resolve them before building the affected component and record the finding in a
code comment or PR description.

### Q1 — Minimum macOS deployment target

See Section 4.3. Determines which window-focus tracking API is available.

### Q2 — `EngineController` playhead exposure

The `LiveControlSurfaceAdapter` needs the current playhead step (column) index.
Read `Sources/Engine/EngineController.swift`:

- If a `@Published var currentPlayheadColumn: Int` or equivalent already exists
  and is updated on the main thread, use it directly.
- If no such property exists, add `@Published var currentPlayheadColumn: Int`
  to `EngineController`. Update it at the start of `dispatchTick()`. Because
  `dispatchTick()` runs in the `TickClock` callback (background thread), the
  update must be wrapped: `DispatchQueue.main.async { self.currentPlayheadColumn = column }`.
  This is the same threading pattern used for any other `@Published` property
  updated from the tick callback.
- The property must not expose engine internals that break the `Engine → UI`
  dependency direction. A plain step index is sufficient; do not pass
  `PlaybackSnapshot` or internal engine state into the property.

### Q3 — `scopeColor(for:)` data source

Read `Sources/Document/` to locate the model path for scope colors:

- If `TrackGroup` (or an equivalent type) carries a color field, `scopeColor(for:)`
  on `LiveControlSurfaceAdapter` returns that color for grouped tracks, mapped
  through `LaunchpadMiniMK3Palette`.
- For ungrouped individual tracks (no group color), `scopeColor(for:)` returns
  the `uncolored` palette entry (Launchpad Mini MK3 palette index 1–3, dim
  white). This fallback must be non-zero (see Section 9).
- `scopeColor(for:)` must be a pure function of `document.project`; it must not
  hold state.
- Record the exact model path (e.g., `TrackGroup.color: Color?`) in a code
  comment on the helper.

---

## 7. Pad Assignment Tables

### 7.1 Phrase workspace — top CC row (CC 91–98, left to right)

| CC | Label | Action |
|---|---|---|
| 91 | prev-layer | Decrement active layer index in `WorkspaceControlSurfaceContext` |
| 92 | next-layer | Increment active layer index |
| 93 | prev-track-page | Decrement `phraseTrackPage` (clamp at 0) |
| 94 | next-track-page | Increment `phraseTrackPage` (clamp at max) |
| 95 | prev-phrase-page | Decrement `phrasePage` (clamp at 0) |
| 96 | next-phrase-page | Increment `phrasePage` (clamp at max) |
| 97 | jump-to-active-phrase-page | Set `phrasePage` to the page containing `selectedPhraseID`. No-op if `selectedPhraseID` is nil. No-op if the selected phrase is already on the current page. |
| 98 | workspace-switch-to-Live | Set `activeSection = .tracks` in context |

### 7.2 Live workspace — top CC row (CC 91–98, left to right)

| CC | Label | Action |
|---|---|---|
| 91 | prev-layer | Decrement `liveLayerID` index in context |
| 92 | next-layer | Increment `liveLayerID` index |
| 93 | prev-scope-page | Decrement `scopePage` (clamp at 0) |
| 94 | next-scope-page | Increment `scopePage` (clamp at max) |
| 95 | prev-col-page | Decrement `colPage` (clamp at 0) |
| 96 | next-col-page | Increment `colPage` (clamp at max) |
| 97 | workspace-switch-to-Phrase | Set `activeSection = .phrase` in context |
| 98 | transport-play-stop | Call `EngineController.toggleTransport()` (same as the on-screen play/stop button) |

Both tables exhaust the 8-pad top CC row. No pad is available for additional
functions in v1. Modifier chords are explicitly out of scope.

### 7.3 Phrase workspace — right column (row-select)

Right-column pads map to the 8 phrase rows visible on the current page. Pressing
pad row N sets `selectedPhraseID` to the phrase at visible row N. Out-of-bounds
pads (when the page has fewer than 8 phrases) are `.off` and deliver no-op on
press.

### 7.4 Live workspace — right column (scope-select)

Right-column pads map to the 8 scope rows visible on the current scope page.
Pressing pad row N updates the active scope selection (mirrors on-screen row
selection). Out-of-bounds pads are `.off` and deliver no-op on press.

---

## 8. Adapter Behavior Requirements

### 8.1 Phrase adapter — grid mutations

| Pad area | Condition | Mutation |
|---|---|---|
| 8×8 main grid, in-bounds | Pad (row, col) maps to a valid phrase row and track column for the current page | Toggle / set phrase cell value for the active layer at (phraseRow, trackCol) — same helper the SwiftUI phrase grid uses |
| 8×8 main grid, out-of-bounds | Pad row exceeds phrase-slice length or pad col exceeds track-slice length | No-op; no document mutation |
| Top CC row | CC 91–98 | Actions per Section 7.1 |
| Right column | In-bounds | Set `selectedPhraseID` |
| Right column | Out-of-bounds | No-op |

### 8.2 Live adapter — grid mutations

| Pad area | Condition | Mutation |
|---|---|---|
| 8×8 main grid, in-bounds | Pad (row, col) maps to a valid scope row and step/bar column | Toggle / set step or bar cell value for the active scope row + column — same helper the SwiftUI live grid uses |
| 8×8 main grid, out-of-bounds | Pad row exceeds scope-slice length or pad col exceeds column-slice length | No-op; no document mutation |
| Top CC row | CC 91–98 | Actions per Section 7.2 |
| Right column | In-bounds | Update active scope selection |
| Right column | Out-of-bounds | No-op |

### 8.3 Out-of-bounds guard points (both adapters)

Adapters must guard against out-of-bounds access with explicit range checks
before any document mutation. Hardware always sends input for all 64 main-grid
pads and all 8+1 edge pads regardless of data population. This is a hard
requirement.

Enumerated guard points:

- `PhraseControlSurfaceAdapter`: check phrase-slice bounds (current page index ×
  8 to min(count, (page+1)×8)); check track-slice bounds (current track page).
- `LiveControlSurfaceAdapter`: check scope-slice bounds (current scope page);
  check column-slice bounds (current col page, respecting steps vs. bars mode).

---

## 9. LED Frame Model

### 9.1 Frame structure

```
struct ControlSurfaceFrame {
    var leds: [ControlSurfaceLEDID: ControlSurfaceLEDState]
}

enum ControlSurfaceLEDState {
    case off
    case palette(UInt8)
    case rgb(r: UInt8, g: UInt8, b: UInt8)
    // .flashing, .pulsing — deferred to v2
}
```

`ControlSurfaceLEDID` addresses the full 9×9 surface: grid cells by (row, col)
and edge pads by their Programmer-mode CC number.

Frames are produced on the UI thread, diffed against the last-sent frame, and
dispatched as SysEx by `LaunchpadMiniMK3Renderer`. They are never persisted and
are always reconstructible from the current context + `document.project`.

### 9.2 Semantic LED states — Phrase workspace

| State | LED encoding |
|---|---|
| Empty cell | `.off` |
| Filled (boolean true) | `.palette` — mid-green |
| Scalar / velocity value | `.palette` — mid-blue |
| Pattern-slot | `.palette` — mid-purple |
| Selected row (any cell in selected phrase row) | `.palette` — amber (same amber as active layer edge pad) |
| Playing phrase (cells in the currently playing phrase row) | `.palette` — bright green |
| Out-of-bounds pad | `.off` |

Precedence when a cell matches multiple states: playing > selected > filled /
scalar / pattern-slot > empty. The implementer must apply states in ascending
precedence order so the last write wins.

### 9.3 Semantic LED states — Live workspace

| State | LED encoding |
|---|---|
| Empty step/bar | `.off` |
| Filled (boolean true) | `.palette` — mid-green |
| Scalar / velocity value | `.palette` — mid-blue |
| Pattern-slot | `.palette` — mid-purple |
| Selected row (any cell in the selected scope row) | `.palette` — amber |
| Playhead column (during playback) | Full override: `.palette` — bright green. Applied last, after all cell states are resolved. Any LED in the playhead column is set to playhead-green regardless of its computed cell state. |
| Out-of-bounds pad | `.off` |

### 9.4 Edge pad LED states

| Edge area | Active/current state | Inactive / at-limit state |
|---|---|---|
| Layer nav pads (prev/next) | Amber (`.palette` — amber) | Dark gray (dim, reachable but not current) |
| Page nav pads (all types) | Dim color when navigation is possible; fully `.off` (not dim) when at the boundary in that direction and no further paging is possible | Fully `.off` |
| Workspace-switch pad | Dim white or fixed neutral color | — |
| Transport play/stop (CC 98, Live) | Bright green when playing; dim red when stopped | — |
| Row-select / scope-select right column | Amber for the selected row; dark blue for all other in-bounds rows; `.off` for out-of-bounds rows | — |

### 9.5 Uncolored scope fallback (Q3 consequence)

When a scope row in the Live workspace has no assigned color (ungrouped
individual track with no group color), `LiveControlSurfaceAdapter` returns the
`uncolored` palette entry from `LaunchpadMiniMK3Palette`. The `uncolored` entry
maps to Launchpad Mini MK3 palette index 1–3 (dim white). The fallback must be
non-zero; a fully dark row is indistinguishable from an empty-pad row and would
prevent the user from knowing the scope exists.

### 9.6 Frame diff and SysEx

`LaunchpadMiniMK3Renderer` compares the new frame to the last-sent frame and
sends SysEx only for changed LEDs. It must not send a full-frame repaint on
every SwiftUI view update. The diff must handle three scenarios: full-frame
change (all 81 LEDs differ), single-LED change, and no change (zero SysEx
sends). All three must be covered by unit tests.

---

## 10. MIDI Layer Requirements

### 10.1 MIDIClient production input port

`MIDIClient` must gain a proper production `createInputPort(handler:)` method
that calls `MIDIInputPortCreateWithBlock` / `MIDIPortConnectSource`. The existing
`clientRefForTesting` exposure is for tests only and must not be used in
production code. This method must be implemented and tested before
`MIDIInputConnection` can be built. It is the most structurally blocking gap.

### 10.2 SysEx builder

A new `MIDISysExBuilder` value type must be introduced in `Sources/MIDI/`. It
follows the same stateless builder pattern as the existing `MIDIPacketBuilder`.
It must support SysEx frame construction (`0xF0 … 0xF7`) for:

- Programmer-mode entry SysEx (Launchpad Mini MK3 format).
- Programmer-mode restore-to-Live-mode SysEx.
- LED lighting SysEx (`0x03` command in the Launchpad Mini MK3 SysEx protocol).

`MIDIPacketBuilder` must not be modified for SysEx. The control surface uses
`MIDISysExBuilder` exclusively. Production `MIDISend` for SysEx must be tested
with unit tests before the LED renderer relies on it.

### 10.3 Pad event type

```
struct HardwarePadEvent {
    enum Kind { case down, up }
    var kind: Kind
    var ledID: ControlSurfaceLEDID
    var velocity: UInt8
}
```

This is a value type with no document or context references. It is constructed
on the CoreMIDI callback thread and dispatched to the main queue. See M3
resolution (Section 5.3).

---

## 11. Settings UI Requirements (Story 1, Story 7)

### 11.1 Control Surfaces section in MIDI tab

The Control Surfaces section appears within the existing MIDI tab of Preferences.
No new top-level tab is added.

**Layout (top to bottom):**

1. Section header: "Control Surfaces"
2. Toggle: "Launchpad Mini MK3" — enables/disables the surface.
   Sub-label when disabled: "Enable to configure and use a hardware control
   surface."
3. When toggle is on: input endpoint picker and output endpoint picker appear.
   Pickers are disabled when the toggle is off.
4. Status row: shows one of five states (see Section 11.2).
5. "Test LEDs" button: visible when toggle is on; active only when status is
   "Connected". Triggers a brief full-surface LED test pattern and shows an
   ephemeral feedback label for 2.5 seconds. Button has a 2.5-second cooldown.

Persistence is automatic via `@AppStorage` / `UserDefaults`. No Save button.
On first open after relaunch with saved preferences, endpoint pickers show the
previously selected endpoint names.

### 11.2 Five Control Surface states

| State ID | Status label | When shown |
|---|---|---|
| A: Disabled | (status row hidden) | Toggle is off |
| B: Enabled, no endpoints | "Not configured — select input and output endpoints" | Toggle is on, one or both endpoint UIDs are nil |
| C: Input only | "Input selected — output required for LED feedback" | Toggle is on, input UID set, output UID nil |
| D: Connected | "Connected — Programmer mode active" | Toggle is on, both UIDs set, both endpoints present in CoreMIDI, Programmer mode SysEx sent successfully |
| E: Device missing | "Device not found — check USB connection" | Toggle is on, a saved UID is no longer present in CoreMIDI device list |

On transition from State D to State E (endpoint disappears), the app must not
crash and must not attempt to send MIDI to a stale endpoint reference. The
coordinator detaches the session and updates the status to E. When the device
reappears (CoreMIDI notification), the coordinator automatically reattaches and
transitions back to D.

### 11.3 Endpoint pickers

The pickers enumerate CoreMIDI sources (for input) and destinations (for output)
from the live CoreMIDI device list. The picker annotation note reads: "Select
the regular MIDI (not DAW) endpoints for Programmer mode." This note is visible
adjacent to the pickers whenever the toggle is on.

---

## 12. WorkspaceSection alias

The existing `WorkspaceSection` enum must not be renamed in v1. The `.tracks`
case continues to represent what the product calls "Live workspace". The control
surface code uses a local alias at the dispatch boundary:

```swift
// In ControlSurfaceCoordinator / adapter dispatch:
// Note: .tracks is the current code name for the Live/tracks workspace.
case .tracks: return liveAdapter.handleEvent(event)
```

A comment block at the top of `WorkspaceControlSurfaceContext` documents this
mapping. If the enum gains a `.live` case in a future refactor, that comment is
the single update point.

---

## 13. State Lifting Isolation

The `ContentView.section` state lift (from `@State private` to an environment-
injectable or binding-driven value) must be isolated to a dedicated commit / PR.
It must not be bundled with the control-surface feature build. The implementation
loop should add tests covering workspace switching before making this change, to
avoid regressions in the existing workspace navigation.

---

## 14. Test Requirements

The implementation loop must create `Tests/SequencerAITests/ControlSurface/`
before the feature is considered shippable. All new types require test coverage.
Minimum required test cases per component:

| Component | Required coverage |
|---|---|
| `MIDISysExBuilder` | SysEx construction: Programmer-mode entry, Programmer-mode exit, LED lighting command |
| `MIDIClient.createInputPort` | Port creation, successful connection, callback dispatch, disconnect |
| `ControlSurfacePreferences` | Persistence roundtrip; missing-endpoint fallback |
| `LaunchpadMiniMK3InputMapper` | Note/CC index → `ControlSurfaceLEDID` mapping for all 9×9 positions |
| `LaunchpadMiniMK3Renderer` | Frame-to-SysEx: full-frame repaint, single-changed-LED, no-change (zero sends) |
| `PhraseControlSurfaceAdapter` | 8×8 matrix derivation; partial-page empty-pad handling; page boundary clamping |
| `LiveControlSurfaceAdapter` | Scope/step mapping; playhead column full-override; uncolored scope fallback; out-of-bounds no-op |

---

## 15. Acceptance Criteria (mapped to stories)

| Story | Criterion |
|---|---|
| 1. Configure control surface | Control Surfaces section present in MIDI tab; toggle, pickers, status row visible; endpoint selection survives app restart. |
| 2. Programmer mode management | Enabling the surface sends Programmer-mode SysEx; disabling or quitting sends restore SysEx; no Programmer-mode lock after app exits. |
| 3. Context-aware routing | Switching workspaces re-renders all 81 pads without Settings interaction; pad events route to the active adapter. |
| 4. Phrase workspace hardware editing | Each of the 64 main-grid pads maps to the correct phrase-by-track cell; mutations are reflected on-screen; edge buttons navigate layers, track pages, phrase pages, row-select; partial pages render correctly (dark, no-op). |
| 5. Live workspace hardware performance | Scope rows, step/bar columns, paging, layer switching, playhead column, workspace switch, and transport all work from hardware; partial pages render correctly. |
| 6. Focused-window ownership | Bringing a second document window to the front causes the surface to repaint immediately for the new document; the previous window no longer receives hardware input. |
| 7. Test LEDs | "Test LEDs" button in Settings sends a full-surface LED pattern; button is active only when status is "Connected". |
