# Launchpad Mini MK3 Control Surface Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class support for a Novation Launchpad Mini MK3 as an optional hardware control surface. The device is selected in Settings, attaches to the currently focused document window, mirrors the active workspace when that workspace is Phrase or Live, accepts pad presses as editing / navigation input, and drives the Launchpad LEDs so the hardware reflects project state clearly.

**User-facing scope:**
- Settings can enable or disable a Launchpad control surface and bind its MIDI input/output endpoints.
- The app uses the Launchpad Mini MK3 in **Programmer mode** on the device's regular MIDI interface, not DAW mode.
- **Phrase** workspace gets a direct 8x8 hardware matrix.
- **Live** workspace gets a hardware-native 8x8 performance grid derived from the same project state as the on-screen Live workspace.
- Pads and edge buttons light to show selection, page, current values, and playback position.

**Out of scope for v1:**
- Launchpad Pro / Launchpad X / non-Novation surfaces.
- Clip editor note-grid editing.
- Mixer / Routes / Library / Track editor hardware mappings.
- Custom-mode editing through Novation Components.
- Multiple simultaneous active control surfaces.

**Tech stack:** Swift 5.9+, SwiftUI, CoreMIDI, XCTest, xcodegen.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`

**Status:** Not started.

---

## Manual Anchors

This plan is based on the local manuals:

- `Launchpad Mini - Programmers Reference Manual.pdf`
- `Novation-Launchpad-Mini-MK3-User-Manual.pdf`

Relevant facts to lock in:

- The Launchpad Mini MK3 exposes **two USB MIDI interfaces**: a DAW pair and a regular MIDI pair. The programmer reference says the regular **MIDI In / Out** interface is the one intended for Custom modes and Programmer mode. We should use that, not the DAW interface, for this feature.
- The programmer reference explicitly recommends **Programmer mode** for scripts and interactive surfaces, because it provides a clean slate and full surface control.
- Programmer mode can be entered with SysEx command `0Eh` (`<mode> = 1`) and left with the same command (`<mode> = 0`).
- In Programmer mode, the surface is effectively a **full 9x9 map**:
  - 8x8 main grid is addressed by note numbers `11...88` in decade rows.
  - top row uses CC `91...99`.
  - right column uses CC `19...89`.
- The Launchpad accepts lighting either by MIDI events on channels 1/2/3 (static / flashing / pulsing) or by the **LED lighting SysEx** command `03h`, which can update up to 81 LEDs in one message.
- The user manual confirms the default 8x8 note maps for Drum / Keys / User and shows that Programmer mode is the only mode that exposes the full edge buttons plus the addressable logo.
- The user manual also states that the device always boots into Live mode, so the app should deliberately enter Programmer mode when attaching and return to Live mode when detaching.

These facts are architectural inputs, not optional implementation details.

---

## Why Programmer Mode

We should intentionally **not** build this on DAW mode.

Reasons:

- DAW mode is designed around Ableton-like session semantics and the separate DAW MIDI interface.
- The app needs a generic control-surface protocol that can represent Phrase and Live workspaces, not Ableton Session state.
- Programmer mode gives us:
  - the full 8x8 grid
  - the top row
  - the right column
  - explicit LED control
  - predictable MIDI note / CC indices

For a custom sequencer surface, Programmer mode is the right abstraction.

---

## Current-Code Constraints

The plan must account for the current app architecture:

- `PreferencesView` is still simple and does not yet persist arbitrary settings.
- `MIDISession` currently enumerates endpoints and creates virtual endpoints, but it does **not** yet subscribe to arbitrary external MIDI sources.
- `ContentView` owns workspace switching locally and currently drives playback updates from `document.project`.
- `WorkspaceDetailView` owns `liveLayerID` as local `@State`.
- `PhraseWorkspaceView` already pages visible tracks in groups of **8**, which fits Launchpad naturally.
- The app is document-based, so a hardware surface must attach to the **focused document window**, not to all windows at once.

Because of that, this plan introduces a shared control-surface context and a new MIDI input-subscription path instead of trying to read ad hoc SwiftUI local state from the hardware layer.

---

## Architecture

### App-scoped pieces

- `ControlSurfacePreferences`
  - persisted app preference for whether a control surface is enabled
  - selected surface kind (`none`, `launchpadMiniMK3`)
  - selected MIDI input endpoint id
  - selected MIDI output endpoint id
  - optional brightness override / test action

- `ControlSurfaceCoordinator`
  - singleton-like app service created in `SequencerAIApp`
  - watches preferences and available MIDI endpoints
  - owns the active Launchpad session if enabled
  - routes input/output only for the currently focused document scene

- `WorkspaceControlSurfaceContext`
  - shared, observable UI/hardware context for the focused scene
  - active workspace section
  - selected live layer id
  - phrase track page
  - phrase row page
  - live scope page
  - live step/bar page

### Device-specific pieces

- `LaunchpadMiniMK3Session`
  - owns the selected MIDI source/destination connection
  - verifies the device shape if possible
  - enters Programmer mode when activated
  - restores Live mode on detach / shutdown
  - receives hardware note/CC input
  - sends LED frames

- `LaunchpadMiniMK3InputMapper`
  - converts programmer-mode note/CC indices into semantic actions

- `LaunchpadMiniMK3Renderer`
  - converts a workspace surface model into LED commands
  - owns the Launchpad palette mapping
  - diffs frames so we do not blindly repaint all 81 LEDs every time

### Workspace adapters

- `PhraseControlSurfaceAdapter`
  - derives an 8x8 phrase matrix model from `Project` + `WorkspaceControlSurfaceContext`
  - handles pad presses by mutating phrase cells, selection, and paging

- `LiveControlSurfaceAdapter`
  - derives an 8x8 live-performance model from `Project` + `WorkspaceControlSurfaceContext`
  - handles pad presses for the current Live editing behavior

These adapters should be view-agnostic. They must not depend on SwiftUI view structs.

---

## File Structure

Expected additions / modifications:

```text
Sources/App/
  SequencerAIApp.swift                         MODIFIED

Sources/MIDI/
  MIDIClient.swift                            MODIFIED
  MIDISession.swift                           MODIFIED
  MIDIInputConnection.swift                   NEW

Sources/Platform/
  ControlSurfacePreferences.swift             NEW

Sources/ControlSurface/
  ControlSurfaceCoordinator.swift             NEW
  WorkspaceControlSurfaceContext.swift        NEW
  LaunchpadMiniMK3Session.swift               NEW
  LaunchpadMiniMK3InputMapper.swift           NEW
  LaunchpadMiniMK3Renderer.swift              NEW
  LaunchpadMiniMK3Palette.swift               NEW
  PhraseControlSurfaceAdapter.swift           NEW
  LiveControlSurfaceAdapter.swift             NEW

Sources/UI/
  PreferencesView.swift                       MODIFIED
  ContentView.swift                           MODIFIED
  WorkspaceDetailView.swift                   MODIFIED
  PhraseWorkspaceView.swift                   MODIFIED
  LiveWorkspaceView.swift                     MODIFIED

Tests/SequencerAITests/
  MIDI/MIDIInputConnectionTests.swift         NEW
  Platform/ControlSurfacePreferencesTests.swift NEW
  ControlSurface/LaunchpadMiniInputMapperTests.swift NEW
  ControlSurface/LaunchpadMiniRendererTests.swift NEW
  ControlSurface/PhraseControlSurfaceAdapterTests.swift NEW
  ControlSurface/LiveControlSurfaceAdapterTests.swift NEW
```

`Sources/ControlSurface/` is justified here as a new responsibility boundary. This is not just CoreMIDI wrapping and not just UI. It is app-specific hardware-surface logic that sits between MIDI, document state, and workspace interaction.

---

## Settings UX

The settings surface should live under the existing **MIDI** tab, not as a separate top-level settings tab.

Add a `Control Surfaces` section with:

- `Enable Launchpad Mini MK3` toggle
- `Input` picker
  - sourced from CoreMIDI **sources**
  - filtered / badged to help the user pick the Launchpad MIDI input
- `Output` picker
  - sourced from CoreMIDI **destinations**
  - filtered / badged the same way
- `Status` row
  - disconnected / connected / wrong interface / verification failed
- `Test LEDs` button
- optional `Brightness` slider if we choose to send brightness SysEx

Persistence should be app-scoped, not document-scoped.

The first version should bind exactly one Launchpad at a time.

---

## Workspace Mapping

### Phrase workspace mapping

Phrase is the simplest and most literal mapping because the app already pages tracks in groups of 8.

#### Main 8x8 grid

- columns = visible track page (`0..<8`)
- rows = phrase page (`0..<8`)
- each pad represents one phrase-row / track-column cell for the selected layer

This implies adding a **phrase page** concept alongside the existing track page so the hardware can address phrases in banks of 8 without fighting the scroll view.

#### Edge buttons

Top row (`CC 91...99`):

- previous layer
- next layer
- previous track page
- next track page
- previous phrase page
- next phrase page
- jump to selected phrase page
- switch to Live workspace
- optional transport / refresh / clear action

Right column (`CC 19...89`, bottom to top aligned to rows):

- row-select buttons for the 8 visible phrases
- selecting a row should update `selectedPhraseID`
- optionally, a modified press can insert / duplicate later, but not in v1

#### Phrase colours

The grid should be legible first, pretty second.

Suggested v1 colour rules:

- empty / inherit-default cell: dim neutral
- selected cell: bright white or bright accent
- currently selected phrase row: subtle row emphasis
- currently playing phrase row: bright green accent
- boolean layers:
  - `on` = bright green
  - `off` = dim neutral
- pattern-index layers:
  - stable slot colour by slot index
- scalar layers:
  - gradient from dim to bright within a fixed hue family

We should keep the palette small and consistent across the app.

### Live workspace mapping

Live should be **hardware-native**, not a literal copy of the on-screen card grid.

The Launchpad grid should show:

- rows = visible scopes / tracks (paged in groups of 8)
- columns = visible steps or bars (paged in groups of 8)

Interpretation depends on the selected phrase cell mode:

- `.steps` => 8 visible steps
- `.bars` => 8 visible bars
- `.single` / `.inheritDefault` => row acts like a one-value lane; first column is the primary toggle/cycle target, remaining columns can be reserved / duplicated / dimmed
- `.curve` => v1 treats curve lanes as scalar previews plus a simple set/cycle interaction, not full curve editing

This is intentionally more useful on hardware than trying to mirror the current SwiftUI cards.

#### Live edge buttons

Top row:

- previous layer
- next layer
- previous scope page
- next scope page
- previous step/bar page
- next step/bar page
- switch to Phrase workspace
- transport play / stop
- optional follow-current-phrase toggle

Right column:

- row select for visible scopes
- optional group expand/collapse follow-up later

#### Live colours

- current playhead column: bright transport colour
- active row selection: white accent
- boolean true: bright green
- boolean false: dim
- pattern slot colours: slot palette
- scalar values: gradient
- mixed grouped rows: striped / alternating / neutral mixed marker

V1 should use **static lighting only** for correctness. We should not rely on the Launchpad's own pulsing/flashing timing until the app is also intentionally feeding it MIDI clock.

---

## MIDI and Session Ownership

This feature needs new MIDI capabilities the app does not currently have.

### Input subscription

The app must be able to subscribe to an arbitrary external MIDI source.

Add a dedicated input-port abstraction, for example:

```swift
final class MIDIInputConnection {
    init(client: MIDIClient, source: MIDIEndpoint, handler: @escaping (UnsafePointer<MIDIPacketList>) -> Void) throws
    func disconnect()
}
```

This should:

- create a CoreMIDI input port
- connect it to the selected source endpoint
- forward packet lists to a handler
- clean up deterministically

### Focus ownership

Only the **focused document scene** may own the Launchpad at a given time.

That means:

- `ControlSurfaceCoordinator` is app-scoped
- each document scene registers a `WorkspaceControlSurfaceContext`
- the coordinator attaches the active Launchpad session to whichever scene is key / frontmost
- when focus changes, the device is rebound and the LED frame is refreshed

Without this, multiple document windows will race to drive the same hardware.

### Attach / detach lifecycle

When attaching:

- verify endpoints exist
- optionally send Device Inquiry
- send Programmer-mode SysEx
- clear / redraw the surface

When detaching:

- disconnect MIDI input
- optionally blank LEDs
- send Live-mode SysEx so the device is usable standalone again

The app must also perform the detach path on termination.

---

## Rendering Strategy

Use a frame-based renderer, not scattered ad hoc LED writes.

### Surface model

Both workspace adapters should produce a simple device-agnostic frame model:

```swift
struct ControlSurfaceFrame {
    var leds: [ControlSurfaceLEDID: ControlSurfaceLEDState]
}
```

Where `ControlSurfaceLEDState` captures:

- off
- static palette colour
- static RGB colour
- reserved future cases for pulse / flash

### Launchpad output

`LaunchpadMiniMK3Renderer` then converts the frame into Launchpad commands.

V1 recommendation:

- use **LED lighting SysEx (`03h`)** for full-frame and large diff updates
- allow small direct note/CC palette writes as an implementation optimization later

Reasons:

- one message can update the whole surface
- palette and RGB are both available
- the renderer stays in one place

### Palette policy

Introduce a fixed mapping layer:

- app semantic colours -> Launchpad palette / RGB
- avoid hard-coding palette indices throughout adapters

This keeps Phrase and Live colour logic readable and testable.

---

## UI Integration

The hardware layer needs shared state, so a few pieces of local `@State` should be lifted.

- `ContentView` / `WorkspaceDetailView` should expose current `WorkspaceSection` to the control-surface context.
- `WorkspaceDetailView.liveLayerID` should move into shared context rather than staying local-only.
- Phrase view should add a shared `phrasePage` concept so the hardware can move through phrase rows deterministically.
- Phrase / Live views should continue to work normally without a Launchpad attached.

This is not a live-store refactor. Keep the data path as small as possible:

- read from current `document.project`
- mutate through the same project-editing helpers the views already use

If the future live-store work lands, the control-surface adapters can later switch to the live session as their read/write authority.

---

## Task Breakdown

## Task 1: Settings and preference persistence

- [ ] Add `ControlSurfacePreferences`.
- [ ] Persist enabled state, surface kind, selected input id, selected output id.
- [ ] Extend `MIDIPreferences` with a `Control Surfaces` section.
- [ ] Show connection / verification status.

**Acceptance:**
- Settings survive relaunch.
- The user can explicitly choose Launchpad input and output endpoints.

## Task 2: MIDI input subscription support

- [ ] Add a way to subscribe to arbitrary external MIDI sources.
- [ ] Add tests for connect / disconnect / callback forwarding.
- [ ] Keep this logic inside the MIDI boundary, not in views.

**Acceptance:**
- The app can receive pad presses from a selected hardware MIDI source.

## Task 3: App coordinator and focused-scene binding

- [ ] Add `ControlSurfaceCoordinator`.
- [ ] Add `WorkspaceControlSurfaceContext`.
- [ ] Register / unregister scene contexts from document windows.
- [ ] Ensure only the key window drives the hardware.

**Acceptance:**
- Switching frontmost document windows switches Launchpad ownership cleanly.

## Task 4: Launchpad Mini MK3 session and renderer

- [ ] Add Programmer-mode attach / detach logic.
- [ ] Add Launchpad input mapper from note/CC indices to semantic actions.
- [ ] Add frame renderer using LED lighting SysEx.
- [ ] Add palette mapping and diffing.

**Acceptance:**
- Enabling the surface switches the device to Programmer mode and lights a test frame.
- Disabling restores Live mode.

## Task 5: Phrase workspace adapter

- [ ] Add phrase page state.
- [ ] Map 8x8 grid to visible phrase x track cells.
- [ ] Map top/right buttons to layer / page / selection actions.
- [ ] Add phrase colour rules.

**Acceptance:**
- Pressing Launchpad pads edits phrase cells in the selected layer.
- Paging and row selection work from hardware.
- LEDs reflect current phrase matrix state.

## Task 6: Live workspace adapter

- [ ] Add scope page and step/bar page state.
- [ ] Map 8x8 grid to scope rows and step/bar columns.
- [ ] Map edge buttons to workspace navigation and selection.
- [ ] Add live playback / playhead lighting.

**Acceptance:**
- Live edits can be performed from Launchpad.
- LEDs show the current live page and playhead clearly.

## Task 7: Polish and safe detach behavior

- [ ] Repaint on workspace switches, layer switches, and document selection changes.
- [ ] Clear or restore on app termination.
- [ ] Add a manual test checklist for disconnect / reconnect / sleep / wrong endpoint selection.

**Acceptance:**
- No stuck Programmer-mode device after quitting the app.
- Reconnect is predictable.

---

## Test Plan

### Unit

- `ControlSurfacePreferencesTests`
  - roundtrip persistence
  - missing endpoint fallback behavior

- `MIDIInputConnectionTests`
  - connection lifecycle
  - packet forwarding

- `LaunchpadMiniInputMapperTests`
  - programmer note/CC indices map to expected hardware coordinates
  - edge buttons map correctly

- `LaunchpadMiniRendererTests`
  - full-frame to SysEx translation
  - palette mapping
  - diff behavior only emits changed LEDs

- `PhraseControlSurfaceAdapterTests`
  - 8x8 phrase cell mapping
  - page calculations
  - selected / playing / boolean / scalar / pattern colour decisions

- `LiveControlSurfaceAdapterTests`
  - scope/step page mapping
  - playhead highlighting
  - row action routing

### Integration

- Settings enable Launchpad -> coordinator attaches -> Programmer mode command sent.
- Disabling settings sends detach / restore command.
- Active window switch changes which document the hardware edits.

### Manual

1. Open Settings, enable Launchpad Mini MK3, choose the Launchpad MIDI input/output pair.
2. Confirm the device switches into Programmer mode and a test frame lights.
3. Switch to Phrase workspace. Confirm 8x8 hardware grid mirrors the visible phrase x track page.
4. Press pads to toggle / set phrase cells. Confirm both app and hardware update.
5. Page tracks and phrases from the hardware. Confirm app selection moves with it.
6. Switch to Live workspace. Confirm hardware remaps to live row/column behavior.
7. Start transport. Confirm playhead indication updates.
8. Disable the surface or quit the app. Confirm the Launchpad returns to Live mode.

---

## Assumptions and Defaults

- V1 supports exactly one control surface model: Launchpad Mini MK3.
- V1 uses the Launchpad's **MIDI** interface, not the DAW interface.
- V1 uses **Programmer mode**.
- V1 supports **Phrase** and **Live** workspaces only.
- V1 uses static LED rendering; tempo-accurate hardware pulsing/flashing is deferred until we intentionally emit MIDI clock.
- Preferences are app-scoped, not document-scoped.
- The active key document window owns the surface.
- Hardware integration should not block future migration to a live-store runtime; it should sit behind adapters that can later read from a session/store instead of directly from `document.project`.
