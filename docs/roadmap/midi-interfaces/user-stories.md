# MIDI Interfaces User Stories

## Stories

### 1. Enable and configure a hardware control surface

- **As a:** producer who owns a Novation Launchpad Mini MK3
- **I want:** a Control Surfaces section in MIDI Settings where I can toggle the Launchpad on, pick its MIDI input and output endpoints, and see whether it is connected
- **So that:** I can attach hardware once and have the app remember my setup across relaunches
- **Done when:** the toggle, input picker, output picker, and status row are all present and survive app restart; the selected endpoints are persisted app-wide, not per-document

### 2. Automatic mode management on connect and disconnect

- **As a:** producer
- **I want:** the app to switch the Launchpad into Programmer mode when I enable it and return it to the device's default Live mode when I disable it or quit
- **So that:** I never have to manually reset the hardware after an app session, and the device remains usable as a standalone controller when disconnected
- **Done when:** enabling the surface sends the Programmer-mode SysEx, disabling or quitting sends the restore SysEx, and no Programmer-mode lock persists after the app exits

### 3. Stable controller routing to context-aware workspace behavior

- **As a:** producer performing a set
- **I want:** pad presses and knob/button messages from the hardware to be routed to whichever workspace is active, without the controller needing reconfiguration
- **So that:** I can switch between Phrase and Live workspaces and the same physical pads immediately do the right thing for each context
- **Done when:** the app intercepts the same incoming hardware events and routes them through the active workspace adapter; switching workspaces re-renders the surface without touching controller settings

### 4. Phrase workspace editing from hardware

- **As a:** producer editing sequence data
- **I want:** the Launchpad's 8x8 grid to mirror the visible phrase-by-track matrix in the Phrase workspace, with edge buttons for paging and layer switching
- **So that:** I can toggle, set, and page through phrase cells entirely from hardware without reaching for the mouse
- **Done when:**
  - each pad in the 8x8 grid maps to a visible phrase-row / track-column cell for the selected layer
  - pad presses mutate the correct cell in the project
  - top-row and right-column edge buttons navigate layers, track pages, and phrase pages
  - row-select buttons update `selectedPhraseID`
  - hardware LED colours reflect empty, selected, playing, boolean, pattern-slot, and scalar states

### 5. Live workspace performance from hardware

- **As a:** producer running a live performance
- **I want:** the Launchpad grid to show scopes as rows and steps or bars as columns for the current Live workspace state, with edge buttons for layer, scope, and step/bar page navigation
- **So that:** I can trigger and edit live performance cells from hardware without interrupting focus on the screen
- **Done when:**
  - rows map to visible scopes paged in groups of eight
  - columns map to visible steps or bars depending on the active phrase cell mode
  - edge buttons handle layer switching, scope paging, step/bar paging, workspace switching, and transport play/stop
  - playhead column is visually distinct during playback
  - static LED colours represent boolean, pattern-slot, scalar, and selection states without relying on hardware pulsing

### 6. Focused-window ownership of the control surface

- **As a:** producer working with multiple document windows open simultaneously
- **I want:** the Launchpad to follow whichever document window is currently frontmost
- **So that:** I never accidentally edit the wrong document from hardware
- **Done when:** bringing a different document window to the front re-binds the hardware to that window's project state, immediately repaints the surface, and the previously active window no longer receives hardware input

### 7. Test LED feedback for initial setup

- **As a:** producer completing the first-time setup
- **I want:** a "Test LEDs" button in Settings that lights up a recognizable pattern on the Launchpad
- **So that:** I can verify I have selected the correct MIDI output endpoint before relying on the surface during a session
- **Done when:** pressing "Test LEDs" sends a brief full-surface lighting pattern and the status row reflects a connected state

---

## Acceptance Signals

- Opening Settings shows a Control Surfaces section under the MIDI tab; no separate top-level tab.
- After selecting endpoints and relaunching the app, the previous endpoint selection is restored.
- When the Launchpad is enabled in Settings, the hardware LED surface updates within one render cycle to reflect the current workspace state.
- Switching from Phrase to Live workspace updates all 81 pads and edge buttons without any additional Settings interaction.
- Pressing a pad in Phrase workspace edits the expected cell; the on-screen view updates to match.
- Pressing a pad in Live workspace edits the expected step, bar, or row; the on-screen view updates to match.
- Closing or quitting the app causes the Launchpad LEDs to reset (blank or Live-mode default) within the same process lifecycle.
- Bringing a second document window to the front causes the Launchpad to immediately repaint for the new document.

---

## Assumptions

- V1 supports exactly one device: the Novation Launchpad Mini MK3.
- The app uses the device's regular MIDI interface (not the DAW interface) and Programmer mode, as established by the existing plan.
- Preferences and surface ownership are app-scoped; individual documents are not responsible for surface configuration.
- The hardware routing layer sits behind workspace adapters so future workspaces can be added without re-architecting the MIDI layer.
- V1 uses static LED rendering only; hardware pulsing and flashing are deferred until MIDI clock is intentionally emitted.
- A full surface-agnostic frame model (`ControlSurfaceFrame`) sits between workspace adapters and the device-specific renderer, keeping Launchpad details out of workspace logic.
- The existing Launchpad Mini plan (`docs/plans/2026-04-23-launchpad-mini-control-surface.md`) is the authoritative technical reference and these stories are aligned to it.
- This roadmap item may grow to cover additional MIDI controller types in future phases; the v1 architecture should not hard-code assumptions that prevent that.
