# iPad Portability Plan

**Parent context:** `wiki/pages/project-layout.md`, `wiki/pages/build-system.md`, and the current macOS-only target audit.
**Status:** Not started. Tag `v0.0.NN-ipad-portability` at completion.

## Summary

Make SequencerAI build and run as an iPad app without weakening the macOS app or regressing the recent live-store performance work.

This is a moderate port, not a rewrite. The document model, live store, sequencer engine, generator evaluation, snapshot compiler, and much of the audio graph are already platform-neutral enough to share. The main work is around the app shell, platform services, AU UI presentation, desktop-only debug hooks, and touch-responsive layout.

The first useful milestone is an iPad proof of concept that opens a document, edits clips, runs transport, and plays through internal audio. AUv3 hosting, MIDI behavior, and polished touch layout come after the shared app compiles.

## Current Findings

### Portable or mostly portable

- `Sources/Document/` is pure model and document serialization.
- `Sources/Engine/` is mostly platform-neutral sequencing/runtime logic.
- `Sources/Musical/` is pure lookup/data logic.
- Most SwiftUI views can compile for iPad once AppKit-only dependencies are conditionalized.
- `AVAudioEngine`, `AVAudioUnit`, CoreMIDI, and AUv3 hosting exist on iPadOS, but behavior and availability differ from macOS.

### macOS-only today

- The Xcode project is macOS-only: `SDKROOT = macosx`, `MACOSX_DEPLOYMENT_TARGET = 14.0`.
- `SequencerAIApp` uses `@NSApplicationDelegateAdaptor`, `Settings`, and macOS `DocumentGroup` defaults.
- `SequencerAIAppDelegate` imports AppKit and implements `NSApplicationDelegate`.
- `AUWindowHost` imports AppKit and presents plug-in views in `NSWindow`.
- `StepGridView` imports AppKit for the debug-only mouse-down probe (`NSViewRepresentable`, `NSEvent`, `NSView`).
- Some UI is desktop-density and assumes wide windows, hover/pointer affordances, and inspector columns.

### Product constraints

- iPad AU hosting means AUv3 only. macOS-only installed Audio Units do not carry over.
- iPad plug-in UI should be presented as a sheet or popover using a view controller host, not a detached AppKit window.
- External MIDI may exist through CoreMIDI-compatible devices or network sessions, but UX and permissions need iPad-specific testing.
- Touch targets, scroll behavior, grid density, and sidebar/detail navigation need an iPad layout pass.

## Guardrails

- Preserve the resident live-store architecture. Do not reintroduce `Project` as a hot UI or playback model.
- Do not fork document, clip, phrase, macro-lane, or snapshot data structures for iPad.
- Keep iPad-specific code behind narrow platform seams or `#if os(iOS)` / `#if os(macOS)` blocks.
- Keep macOS behavior and AU window hosting intact.
- Do not remove macOS tests to make the iPad target compile.
- Avoid a separate "iPad engine." Shared engine code should remain the default.
- Any unavailable platform feature should degrade explicitly in UI, not fail silently.

## Desired Architecture

```
Sources/App/
  SequencerAIApp.swift                    # shared scene composition where possible
  SequencerMacAppDelegate.swift           # macOS-only lifecycle bridge
  SequencerIOSAppDelegate.swift           # optional, only if iPad lifecycle needs it
  PlatformLifecycle.swift                 # small protocol/facade if useful

Sources/Audio/
  AUPluginPresenter.swift                 # platform-neutral protocol
  AUWindowHost.swift                      # macOS implementation
  AUViewControllerHost.swift              # iPadOS implementation

Sources/UI/
  Track/TrackWorkspaceView.swift          # adaptive source/destination layout
  TrackSource/Clip/ClipContentPreview.swift # touch-sized layer/grid variants if needed
  Platform/PlatformInteraction.swift      # optional hover/context-menu fallbacks

SequencerAI.xcodeproj/
  SequencerAI iPad target                 # shares source files with macOS target
```

## Task 1 — Add an iPad target that shares source files

**Goal:** Create an iPadOS app target that compiles as much shared code as possible before behavior changes begin.

- [ ] Add an iPadOS target to `SequencerAI.xcodeproj`.
- [ ] Set deployment target deliberately, likely current iPadOS minus one major version unless framework availability forces newer.
- [ ] Share `Sources/Document`, `Sources/Engine`, `Sources/Musical`, most `Sources/Audio`, and most `Sources/UI`.
- [ ] Add iPad app icon/bundle metadata only as needed for buildability.
- [ ] Keep the macOS target unchanged and building.
- [ ] Document target setup in `wiki/pages/build-system.md`.

Acceptance:

- macOS app still builds.
- iPad target reaches the first compile errors that are genuine platform API issues, not project registration issues.

## Task 2 — Split platform lifecycle from the app shell

**Goal:** Replace AppKit-only lifecycle wiring with platform-specific adapters.

- [ ] Move `NSApplicationDelegate` code behind `#if os(macOS)` or into `SequencerMacAppDelegate.swift`.
- [ ] Keep app termination behavior on macOS: flush sessions, close AU windows, shutdown engines, drain run loop.
- [ ] Define iPad lifecycle handling for scene background/resign-active: flush documents and stop/continue audio according to product choice.
- [ ] Keep `DocumentGroup` if it works cleanly on iPad; otherwise add a minimal iPad document/browser scene and defer polish.
- [ ] Gate `Settings` scene to macOS or replace with iPad settings UI.

Acceptance:

- macOS lifecycle tests continue to pass.
- iPad target no longer imports AppKit from `Sources/App`.

## Task 3 — Conditionalize desktop-only UI/debug hooks

**Goal:** Remove AppKit dependencies from shared UI files.

- [ ] Move the debug mouse-down probe in `StepGridView` behind `#if os(macOS)`.
- [ ] Provide an empty iPad implementation or remove the probe from iPad builds.
- [ ] Audit context menus, hover-only affordances, keyboard shortcuts, and pointer assumptions.
- [ ] Add touch alternatives where a context menu is the only discoverable path.

Acceptance:

- iPad target no longer imports AppKit from `Sources/UI`.
- macOS debug diagnostics still work in debug builds.

## Task 4 — Introduce a platform AU UI presenter

**Goal:** Preserve macOS `NSWindow` plug-in UI while adding an iPad presentation path.

- [ ] Extract a small `AUPluginPresenter` protocol from `AUWindowHost`.
- [ ] Keep `AUWindowHost` as the macOS implementation using `NSWindow`.
- [ ] Add an iPad implementation that presents `auAudioUnit.requestViewController` in a sheet/popover.
- [ ] Update `TrackDestinationEditor` and mixer AU effect UI to request presentation through the protocol.
- [ ] Keep AU state capture/writeback behavior consistent across platforms.
- [ ] Show a clear unavailable state when a plug-in has no iPad-compatible view controller.

Acceptance:

- macOS AU windows still open and write back state on close.
- iPad can present AUv3 UI for compatible units, or reports unavailable UI cleanly.

## Task 5 — Audit AU and MIDI feature availability on iPad

**Goal:** Decide which destination features are supported in iPad v1 and make unsupported paths explicit.

- [ ] Verify Apple DLS synth / default internal instrument availability on iPad.
- [ ] Verify `AVAudioUnitComponentManager` component discovery on iPadOS for instruments and effects.
- [ ] Verify factory/user preset APIs for hosted AUv3 units.
- [ ] Verify CoreMIDI endpoint enumeration and sending on physical/network MIDI setups.
- [ ] Add UI copy/states for unavailable AU/MIDI features.

Acceptance:

- Supported destination matrix is documented in `wiki/pages/track-destinations.md`.
- Unsupported iPad features are hidden or disabled with clear text, not broken controls.

## Task 6 — Make the track workspace touch-responsive

**Goal:** Keep the core workflow usable on iPad screens.

- [ ] Add size-class or geometry-driven layout rules for source/destination panels.
- [ ] Ensure clip layer controls, step grids, macro grids, and AU destination cards meet touch target expectations.
- [ ] Replace hover-dependent cues with persistent visual state.
- [ ] Review sidebars/navigation for split-view and full-screen iPad use.
- [ ] Keep desktop density on macOS; do not make macOS sparse just to satisfy iPad.

Acceptance:

- A 12.9-inch iPad layout can edit clips, choose layers, assign macros, and edit destinations without clipped controls.
- A narrower iPad layout stacks panels intentionally rather than accidentally.
- macOS screenshots/layout remain equivalent to pre-port behavior.

## Task 7 — iPad smoke tests and build checks

**Goal:** Add a minimal verification loop that keeps the iPad target alive.

- [ ] Add an iPad simulator build command to `wiki/pages/build-system.md`.
- [ ] Add CI/script support if the project has a build script path for it.
- [ ] Build the iPad target for simulator.
- [ ] Run shared pure tests where possible.
- [ ] Manually smoke: create/open document, edit clip steps, edit velocity/chance, select macro layer, press Play/Stop, hear internal audio, save/reopen.
- [ ] Manually smoke AUv3 only if compatible test units are available.

Acceptance:

- macOS tests pass.
- iPad simulator build passes.
- Manual smoke notes are recorded in the closing commit or wiki update.

## Risks

- AUv3 behavior is the largest unknown. macOS AU assumptions may not map perfectly to iPadOS, especially preset/state UI behavior.
- iPad file/document UX may require more product design than the compile port suggests.
- Touch layout may uncover workflow decisions, not just responsive CSS-style fixes.
- Audio session behavior on iPad may need explicit handling for backgrounding, interruptions, and route changes.
- MIDI behavior depends on physical devices, network sessions, and permissions that simulator testing cannot fully cover.

## Estimated Effort

- Proof-of-concept build with AU UI disabled or minimal: 2-4 days.
- Playable iPad version with documents, sequencer, internal audio, basic MIDI: 1-2 weeks.
- Polished iPad app with AUv3 UI, touch-first layout, file handling, MIDI verification, and tests: 3-6 weeks.

