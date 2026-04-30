---
feature: midi-interfaces
created: 2026-04-30
---

# MIDI Interfaces — Architecture

Sources consulted: `docs/roadmap/midi-interfaces/existing-state.md`,
`docs/roadmap/midi-interfaces/ux-review.md`,
`docs/roadmap/midi-interfaces/user-stories.md`,
`docs/plans/2026-04-23-launchpad-mini-control-surface.md`,
`wiki/pages/engine-architecture.md`,
`wiki/pages/routing.md`,
`wiki/pages/architecture-guardrails.md`.

---

## Application Invariants This Feature Must Preserve

1. **Document truth vs. runtime state.** The `.seqai` document must not gain
   any hardware-surface state. `ControlSurfacePreferences` is app-scoped
   (`UserDefaults` / `@AppStorage`), never per-document. Pad state and LED
   frames are runtime-only; they must not enter the project model.

2. **Playback snapshot hot path is untouched.** LED rendering and pad-input
   dispatch operate on the UI thread against `document.project` data already
   presented to the UI. They must never reach into the engine's `PlaybackSnapshot`
   internals, nor compete with the `TickClock` callback. Playhead position for LED
   display is obtained from `EngineController`'s transport state exposed to SwiftUI,
   not by observing the snapshot directly.

3. **No lock on the engine tick.** `ControlSurfaceCoordinator` is UI-thread
   owned. If the engine exposes a playhead column index for LED rendering, it
   must do so via a `@Published` or `@Observable` property on `EngineController`
   that SwiftUI already reads safely — no new shared mutable state between the
   timer callback and the control-surface path.

4. **Document-based windowing is unaffected.** `DocumentGroup` scene semantics
   must not change. Each document window continues to own its own
   `EngineController` and project. The coordinator attaches to the key window's
   context by observation; no document is aware of the coordinator.

5. **Phrase and Live views continue to work without hardware.** All state
   lifting required by the control-surface context must be additive — the views
   must not regress when no surface is configured.

6. **CoreMIDI send path is unchanged for sequencer output.** `MidiOut` and
   `MIDIRouter` continue to drive note output exactly as today. The control
   surface uses an independent MIDI output port for LED SysEx; it does not share
   the existing send path.

---

## Data / Runtime Model

### Persisted state (app-scoped, `UserDefaults`)

`ControlSurfacePreferences` holds exactly:

- `enabled: Bool`
- `surfaceKind: SurfaceKind` (enum; v1 only `.launchpadMiniMK3`)
- `inputEndpointUID: MIDIUniqueID?`
- `outputEndpointUID: MIDIUniqueID?`

Nothing else belongs in persistence. Selection, page indices, layer IDs, LED
frames — none of these are persisted.

### Transient runtime state

`WorkspaceControlSurfaceContext` is an `@Observable` class owned per document
scene, injected via the SwiftUI environment. It holds:

- `activeSection: WorkspaceSection` — lifted from `ContentView` (currently
  `@State private`); must become an environment or binding-driven value.
- `liveLayerID: String` — already a `@Binding` path from `WorkspaceDetailView`;
  confirm it can be passed through to the context without a separate copy.
- `phraseTrackPage: Int` — lifted from `PhraseWorkspaceView.trackPage`.
- `phrasePage: Int` — new; introduced alongside `phraseTrackPage`.
- `scopePage: Int` — new; lifted from `LiveWorkspaceView` (does not exist today).
- `colPage: Int` — new; lifted from `LiveWorkspaceView` (does not exist today).
- `selectedPhraseID: String?` — currently local to phrase row-select logic;
  needs to be observable here.

`WorkspaceControlSurfaceContext` is read by both the workspace views (to drive
on-screen paging UI) and by the adapters (to produce LED frames and route pad
presses). It is the single source of truth for surface-visible workspace state;
it does not duplicate document model data.

### Device session (app-scoped singleton path)

`ControlSurfaceCoordinator` is created in `SequencerAIApp` and injected as an
environment object or singleton. It holds:

- a reference to the current `LaunchpadMiniMK3Session` (or nil)
- a weak reference to the currently active `WorkspaceControlSurfaceContext`

`LaunchpadMiniMK3Session` owns:

- `MIDIInputConnection` — subscribes to the selected hardware source
- an output port for SysEx LED commands
- the last-sent `ControlSurfaceFrame` for diffing

`LaunchpadMiniMK3Renderer` is stateless (or minimally stateful for diff); it
does not hold document or workspace state.

### LED frame model (transient, ephemeral)

`ControlSurfaceFrame` is a flat structure:

```
struct ControlSurfaceFrame {
    var leds: [ControlSurfaceLEDID: ControlSurfaceLEDState]
}

enum ControlSurfaceLEDState {
    case off
    case palette(UInt8)
    case rgb(r: UInt8, g: UInt8, b: UInt8)
    // future: .flashing, .pulsing — deferred to v2
}
```

`ControlSurfaceLEDID` addresses the full 9×9 Launchpad surface: grid cells by
(row, col) and edge pads by their Programmer-mode CC number.

Frames are produced on the UI thread, diffed, and dispatched as SysEx from
`LaunchpadMiniMK3Renderer`. They are never persisted and are always
reconstructible from the current `WorkspaceControlSurfaceContext` +
`document.project`.

### Pad-state model

Input from hardware arrives as CoreMIDI packets on the `MIDIInputConnection`
callback (background thread). The callback must be minimal: translate the raw
note/CC byte pair into a `HardwarePadEvent` value type and dispatch it to the
main queue for semantic handling by the active adapter. No document mutation
happens on the MIDI callback thread.

```
struct HardwarePadEvent {
    enum Kind { case down, up }
    var kind: Kind
    var ledID: ControlSurfaceLEDID
    var velocity: UInt8
}
```

The active workspace adapter receives `HardwarePadEvent` on the main queue,
interprets it against `WorkspaceControlSurfaceContext` + `document.project`,
and calls existing document-mutation helpers. The adapters must not introduce
new mutation paths; they call the same functions the SwiftUI views call.

---

## Resolving the Five UX-Review Open Issues

### 1. Edge-pad budget for workspace-switch + transport (Launchpad Mini MK3 top CC row has 8 pads)

The Phrase workspace uses all 8 top-row pads: 2 layer-nav, 2 track-page, 2
phrase-page, 1 jump-to-selected-page, 1 workspace-switch. That fills the row
for Phrase.

The Live workspace uses 8 top-row pads: 2 layer-nav, 2 scope-page, 2 col-page,
1 workspace-switch, 1 transport play/stop. That also fills the row exactly.

The architecture recommends the following assignment:

**Phrase top-row mapping (CC 91–98, left to right):**
- prev-layer / next-layer / prev-track-page / next-track-page /
  prev-phrase-page / next-phrase-page / jump-to-active-phrase-page /
  workspace-switch-to-Live

**Live top-row mapping (CC 91–98, left to right):**
- prev-layer / next-layer / prev-scope-page / next-scope-page /
  prev-col-page / next-col-page / workspace-switch-to-Phrase /
  transport-play-stop

This eliminates the "9th pad" fiction in Prototype 3. Transport play/stop
occupies CC 98 (the rightmost top-row pad). Workspace-switch occupies CC 97.
This is the only layout that fits all seven required functions in each workspace
into 8 physical pads without a modifier chord or long-press.

**Trade-off accepted:** Neither workspace has a free pad for future functions on
the top row in v1. A modifier-chord mechanism (hold a layer pad, then press
another pad) is deferred to v2. The spec should document the exact CC assignment
table and state that modifier chords are explicitly out of scope for v1.

**This is a product decision the architecture can make** because it is a
direct consequence of the hardware constraint (8 pads) and the settled list of
v1 functions (7 per workspace). No user input is needed unless the user wants
to deprioritize one of the 7 functions.

### 2. `WorkspaceSection.tracks` rename vs. alias for Live workspace

The existing enum is:

```swift
enum WorkspaceSection { case phrase, tracks, track, mixer, scenes, library }
```

The `.tracks` case renders `TracksWorkspaceView`, which the product calls "Live"
workspace.

**Guardrail:** Do not rename `.tracks` to `.live` in v1. A rename touches every
switch statement in the codebase (`ContentView`, `WorkspaceDetailView`,
`WorkspaceDetailView`, routing) and risks regressions outside the
control-surface feature. The control-surface code should internally map
`.tracks` to a `LiveControlSurfaceAdapter` using a local alias:

```swift
// In ControlSurfaceCoordinator or adapter dispatch:
case .tracks: return liveAdapter.handleEvent(event)
```

A comment block at the top of `WorkspaceControlSurfaceContext` should document
that `.tracks` is the current code name for the Live/tracks workspace. If the
enum gains a `.live` case in a future refactor, the mapping comment is the
single update point.

**This is an architecture decision the PM pass can make.** No user input needed.

### 3. Playhead column override rule (full override vs. blend)

The prototype shows the playhead column as a solid green override of all cell
state. This architecture recommends **full override** for v1:

- Rationale: the primary live-performance signal is "where are we in the
  sequence right now." Blending would require hardware to simultaneously
  communicate two distinct state dimensions (current value + position) with one
  LED color, which reduces legibility on small hardware. Full override keeps the
  playhead unambiguous.
- Spec consequence: `LiveControlSurfaceAdapter.buildFrame()` should apply
  playhead color last, after all cell states are resolved. Any LED in the
  playhead column is set to the playhead green regardless of its computed cell
  state.
- V2 option: a blend rule (e.g., playhead column uses a tinted version of the
  cell color) can be introduced when the hardware palette mapping is revisited.

**This is an architecture decision the PM pass can make.**

### 4. Empty-pad partial-page rendering (rows/columns outside data bounds)

When fewer than 8 phrases fill a phrase page, or fewer than 8 scopes fill a
scope page, the hardware pads beyond the data bounds must be:

- **LED state: `.off`** — fully dark, no palette color.
- **Input behavior: no-op** — pad-down events for out-of-bounds pads are
  discarded by the adapter before any document mutation occurs.

The adapters must guard against out-of-bounds access with explicit range checks
against the current page slice length. This is not a "defensive coding nice-to-
have" — it is a hard requirement because the hardware will always send input for
all 64 main-grid pads regardless of data population.

The spec should enumerate the guard points: `PhraseControlSurfaceAdapter`
checks phrase-slice bounds and track-slice bounds; `LiveControlSurfaceAdapter`
checks scope-slice bounds and column-slice bounds.

### 5. Fallback LED color for uncolored scopes

When a scope row in the Live workspace has no assigned color (e.g., the scope
is an ungrouped individual track without a group color), the row falls back to a
fixed neutral palette entry defined in `LaunchpadMiniMK3Palette`. The
architecture recommends:

- A dedicated `uncolored` semantic in `LaunchpadMiniMK3Palette`, mapping to a
  dim white / light gray palette index (Launchpad Mini MK3 palette entry ~1–3,
  which are dim white tones).
- The fallback must not be transparent or `.off`. An unlit row would be
  indistinguishable from an empty-pad (out-of-bounds) row, breaking the
  user's ability to know a scope exists but has no color.
- `LiveControlSurfaceAdapter` queries a `scopeColor(for:)` helper that returns
  either the scope's assigned RGB or the `uncolored` palette entry.

---

## Mutation Paths

All pad-press mutations must go through the same document-editing helpers the
SwiftUI views use. No new public mutation API is introduced.

### Phrase adapter mutations

| Pad type | Mutation |
|---|---|
| Grid pad (in-bounds) | Toggle / set phrase cell value for active layer at (phraseRow, trackCol) — same helper as phrase grid tap |
| Top-row layer nav | Increment / decrement layer index in `WorkspaceControlSurfaceContext.activeLayerID` |
| Top-row track-page nav | Increment / decrement `phraseTrackPage` in context |
| Top-row phrase-page nav | Increment / decrement `phrasePage` in context |
| Top-row workspace-switch | Set `activeSection = .tracks` in context (same as clicking the Live tab) |
| Right-column row-select | Set `selectedPhraseID` to the phrase at the visible row index |
| Out-of-bounds pad | No-op |

### Live adapter mutations

| Pad type | Mutation |
|---|---|
| Grid pad (in-bounds) | Toggle / set step or bar cell value for active scope row + column — same helper as live grid tap |
| Top-row layer nav | Increment / decrement `liveLayerID` in context |
| Top-row scope-page nav | Increment / decrement `scopePage` in context |
| Top-row col-page nav | Increment / decrement `colPage` in context |
| Top-row workspace-switch | Set `activeSection = .phrase` in context |
| Top-row transport | Call `EngineController.toggleTransport()` — same as the on-screen play/stop button |
| Right-column scope-select | Update active scope selection (mirrors on-screen row selection) |
| Out-of-bounds pad | No-op |

---

## Existing Code Patterns to Follow

1. **Singleton initialization in `SequencerAIApp`.** Follow the pattern of
   `_ = MIDISession.shared`. The coordinator can be created as a `@StateObject`
   or app-level `let` and injected via `.environmentObject`.

2. **Shutdown in `SequencerAIAppDelegate`.** Insert
   `ControlSurfaceCoordinator.shared.detachAll()` before
   `SequencerDocumentSessionRegistry.flushAll()` in `applicationWillTerminate`.
   This preserves the existing ordered teardown sequence.

3. **CoreMIDI send via `MIDIClient.send`.** `LaunchpadMiniMK3Session` obtains
   a MIDI output port through `MIDIClient` and sends SysEx via `MIDISend`.
   The existing `MIDIClient.send` method handles both virtual source injection
   and real destination sends; the control surface should use the destination
   path.

4. **SysEx support must be added to `MIDIPacketBuilder` or a parallel builder.**
   The existing builder covers note-on, note-off, and CC only (confirmed gap in
   `existing-state.md`). A new `MIDISysExBuilder` value type should be
   introduced in `Sources/MIDI/` following the same stateless builder pattern.
   This is a MIDI-layer concern, not a control-surface concern; keep it in
   `Sources/MIDI/`.

5. **Input port via `MIDIClient`.** `MIDIClient` currently exposes
   `clientRefForTesting` to let tests create input ports. Production code needs
   a proper `createInputPort(handler:)` method in `MIDIClient`. The
   implementation loop must add that method; the control surface does not bypass
   the client boundary.

6. **`@Observable` for shared context.** Follow the app's existing approach to
   observable model objects. `WorkspaceControlSurfaceContext` should be
   `@Observable` (Swift 5.9 Observation framework) and injected via
   `.environment(context)`, matching how other shared state is propagated in
   the app.

7. **Adapters read from `document.project`, not from the engine snapshot.**
   Follow the existing pattern where SwiftUI views read from the document model.
   Adapters are view-logic equivalents; they belong in the UI dependency graph,
   not in the engine runtime.

---

## Risks and Dependencies

### Risk 1: `MIDIClient` production input-port gap

There is no production `createInputPort` method in `MIDIClient`. The
implementation loop must add this before `MIDIInputConnection` can be built.
This is the most structurally blocking gap; it touches `Sources/MIDI/` and
requires tests.

**Mitigation:** Task 2 in the existing plan (`docs/plans/...`) is exactly this
task. It must be implemented and tested before the coordinator or session can
receive pad input.

### Risk 2: SwiftUI window-focus tracking on macOS

The app uses `DocumentGroup`, which creates one scene per document. Tracking
which scene is key/frontmost to rebind hardware requires either
`.focusedSceneValue` / `.onWindowFocusChange` (if available on the target OS) or
an `NSWindowDelegate` hook. Neither exists today. The implementation loop must
evaluate the available API surface for the minimum deployment target and choose
an approach that does not require bypassing SwiftUI scene lifecycle.

**Mitigation:** This is deferred to the coordinator task (Task 3 in the plan).
The architecture should note that `NSWindowDelegate` via `AppKit` interop is the
likely fallback, since `onWindowFocusChange` is available only from macOS 14+.
The spec should state the minimum deployment target requirement for this feature.

### Risk 3: `WorkspaceSection.tracks` private state lifting

`ContentView.section` is `@State private`. Lifting it to be observable by the
control-surface context requires either converting it to an
`@Environment`-injected value or adding a `@Binding` propagation path down to
the context. This is a UI-tree refactor that could introduce regressions in
workspace switching. The implementation loop should add tests covering workspace
switching before making this change.

**Mitigation:** The state lift should be isolated to a dedicated commit / PR. It
should not be bundled with the control-surface feature build.

### Risk 4: SysEx absent from `MIDIPacketBuilder`

`MIDIPacketBuilder` is a value type and does not support SysEx. Adding a
`MIDISysExBuilder` in `Sources/MIDI/` is straightforward, but it requires
production code changes in a tested boundary. The implementation loop must add
tests for SysEx construction before the LED renderer can rely on it.

### Risk 5: Frame repaint performance

The LED frame covers 81 pads. A full repaint on every SwiftUI view update could
trigger excessive SysEx traffic. `LaunchpadMiniMK3Renderer` must diff the
previous frame and only send changed LEDs. The diffing logic must be tested with
unit tests covering full-frame, single-changed-LED, and no-change scenarios.

### Risk 6: Playhead column index source

The `LiveControlSurfaceAdapter` needs the current playhead step index to
determine which column to paint green. `EngineController` owns transport state
and exposes a `currentStep: Int` or equivalent to SwiftUI today. The adapter
should read this from the same source the on-screen playhead indicator uses.
If no such exposed property exists, the implementation loop must add it to
`EngineController` — this is a small addition but it must not expose engine
internals that break the `Engine → UI` dependency direction.

### Risk 7: No `Tests/SequencerAITests/ControlSurface/` directory

The entire control-surface test boundary is new. The implementation loop must
create this directory and ensure all new types have test coverage before the
feature is considered shippable.

---

## Architecture Questions Remaining Before Spec

1. **Minimum macOS deployment target.** Window-focus tracking options depend on
   this. The spec writer needs to know whether `onWindowFocusChange` (macOS 14+)
   or `NSWindowDelegate` is the required path.

2. **`EngineController` playhead exposure.** Does the current `EngineController`
   already expose a `currentStep: Int` or equivalent `@Published` property that
   the live adapter can read safely from the UI thread? If not, what is the
   right property to add without violating the engine's existing thread model?

3. **`scopeColor(for:)` data source.** Scope colors come from track group color
   data in the project model. The spec should identify the exact model path
   (e.g., `TrackGroup.color`) and confirm that the fallback for ungrouped tracks
   is also modeled in the document (or is a hardcoded fallback in the palette).

These three questions are answerable by an implementer reading the codebase
directly. They do not require user input. They should be resolved as findings
in the spec rather than blocking the architecture-review stage.
