# MIDI Interfaces — Implementation Handoff

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [spec.md](spec.md) | Primary build reference. Defines persisted state, runtime context, coordinator/session ownership, pad mappings, LED states, Settings behavior, acceptance criteria, and test requirements. |
| [plan.md](plan.md) | Phase sequence and per-task details. Read this first when starting each phase; it contains the required order and gates. |
| [architecture.md](architecture.md) | Guardrails and invariants the implementation must preserve. Use with the architecture review where ambiguity remains. |
| [architecture-review.md](architecture-review.md) | Accepted verdict. Identifies risks M1-M3 and confirms they are resolved in the spec. |
| [ux-review.md](ux-review.md) | Accepted UX direction and prototype caveats. Explains the top-row pad-budget conflict that the architecture/spec resolved. |
| [prototypes/01-control-surface-settings.html](prototypes/01-control-surface-settings.html) | Settings Control Surfaces prototype for stories 1 and 7. |
| [prototypes/02-phrase-workspace-grid.html](prototypes/02-phrase-workspace-grid.html) | Phrase workspace hardware grid prototype for story 4. |
| [prototypes/03-live-workspace-grid.html](prototypes/03-live-workspace-grid.html) | Live workspace hardware grid prototype for story 5. |
| [existing-state.md](existing-state.md) | Current code reality: missing MIDI input path, missing SysEx, private workspace state, no control-surface tests. |
| [user-stories.md](user-stories.md) | Story-level intent and acceptance signals. |
| [notes.md](notes.md) | Raw user language and link to the older Launchpad Mini plan. |

---

## Goal

MIDI Interfaces v1 adds one app-scoped control surface: Novation Launchpad Mini
MK3 in regular MIDI Programmer mode. The same physical hardware events must be
routed to different workspace behavior based on the frontmost document window
and active workspace, without changing the controller configuration. In Phrase,
the 8x8 grid mirrors the visible phrase-by-track matrix. In Live, the grid
mirrors scope rows and step/bar columns, with track colors, toggle states,
playhead position, workspace switching, and transport.

This is not a general MIDI-learn system. It is a focused Launchpad Mini MK3
control-surface integration with Settings, lifecycle, focused-window ownership,
workspace adapters, LED rendering, and test coverage.

---

## Chosen UX Direction

The accepted direction is a composite of three prototypes:

- Control Surfaces section inside the existing MIDI tab, with a Launchpad Mini
  MK3 toggle, input/output endpoint pickers, five status states, and "Test LEDs".
- Phrase hardware grid: 8x8 phrase rows by track columns, top-row controls for
  layer/page/workspace actions, and right-column row-select.
- Live hardware grid: scope rows by step/bar columns, top-row controls for
  layer/page/workspace/transport actions, right-column scope-select, and a
  playhead column rendered as a full green override.

The Mini MK3 has only eight top-row CC pads. The spec resolves the prototype's
pad-budget conflict with exact CC 91-98 mappings for Phrase and Live. Do not
revive the prototype's fictional ninth pad or add modifier chords in v1.

---

## Guardrails and Invariants

These are hard constraints from `architecture.md`, `architecture-review.md`, and
`spec.md`.

**1. No control-surface runtime state in the document.**
`ControlSurfacePreferences` is app-scoped in `UserDefaults` / `@AppStorage`.
Pad state, LED frames, page indices, layer IDs, and selected phrase state are
transient. They must not enter `.seqai` or any Codable document model.

**2. Do not touch the playback hot path for LED rendering or pad dispatch.**
Adapters read UI-safe state and `document.project`. They must not observe
`PlaybackSnapshot` internals or add locks/shared mutable state around
`TickClock`.

**3. MIDI sequencer output remains separate.**
The existing `MidiOut` / `MIDIRouter` path continues to handle note output. The
control surface uses an independent SysEx output path for LED commands.

**4. `WorkspaceControlSurfaceContext` is the single source of surface-visible state.**
It owns `activeSection`, `liveLayerID`, `phraseTrackPage`, `phrasePage`,
`scopePage`, `colPage`, and `selectedPhraseID`. Views and adapters both read it.
Do not keep a second `liveLayerID` or page state in sync by observation.

**5. Pad input callbacks do not mutate documents.**
CoreMIDI callbacks translate raw messages into `HardwarePadEvent` value types,
then use `DispatchQueue.main.async` for semantic handling. Document mutations
happen only on the main queue through the same helpers the SwiftUI views use.

**6. Out-of-bounds hardware pads are dark and no-op.**
Hardware always sends all pad positions. Adapters must range-check phrase,
track, scope, and column slices before any mutation. Out-of-bounds LEDs are
`.off`, not dim.

**7. The app must restore the hardware on disable and quit.**
Enabling sends Programmer-mode SysEx. Disabling or terminating sends
restore-to-Live-mode SysEx before document-session shutdown completes.

**8. `WorkspaceSection.tracks` remains the Live workspace in v1.**
Do not rename the enum case. Map `.tracks` to the Live adapter at the dispatch
boundary and document the naming mismatch near `WorkspaceControlSurfaceContext`.

---

## Sequencing and Gates

Follow `plan.md`. The feature is intentionally split so low-level MIDI and state
lifting land before Settings or adapters depend on them.

### Phase 0 — Pre-Build Verification (read-only)

Resolve the three implementer findings before coding affected components:

- Confirm the minimum macOS deployment target and choose the focus tracking
  approach (`.onWindowFocusChange` for macOS 14+, AppKit interop otherwise).
- Confirm whether `EngineController` already exposes a UI-safe playhead column;
  if not, plan `@Published var currentPlayheadColumn: Int` updated through
  `DispatchQueue.main.async` from the tick callback.
- Confirm the exact model path for Live scope colors and the non-zero uncolored
  fallback.

Record findings in the implementation PR description or a short build note.

### Phase 1 — MIDI Infrastructure

Add production external input subscription and SysEx construction before any
device session or adapter work:

- `MIDIClient.createInputPort(handler:)` / `MIDIInputConnection` using
  `MIDIInputPortCreateWithBlock` and `MIDIPortConnectSource`.
- `MIDISysExBuilder` for Programmer-mode entry, restore, and LED lighting
  commands.

### Phase 2 — Control-Surface Context and State Lifting

Introduce `WorkspaceControlSurfaceContext` and lift section, layer, phrase page,
track page, scope page, column page, and selected phrase state into it. This
must preserve existing workspace behavior when no hardware is configured.

State lifting, especially `ContentView.section` and `liveLayerID`, should be
isolated and tested because it touches core navigation.

### Phase 3 — Launchpad Device Layer

Build the device-specific but document-free layer:

- `ControlSurfaceFrame`, `ControlSurfaceLEDID`, `ControlSurfaceLEDState`.
- `LaunchpadMiniMK3Palette` with non-zero `uncolored`.
- `LaunchpadMiniMK3InputMapper` covering all 9x9 positions.
- `LaunchpadMiniMK3Renderer` with frame diffing.
- `LaunchpadMiniMK3Session` owning input connection, SysEx output, renderer,
  Programmer-mode attach, restore detach, and main-queue event dispatch.

### Phase 4 — Workspace Adapters

Build `PhraseControlSurfaceAdapter` and `LiveControlSurfaceAdapter` after the
relevant context state is lifted. Both adapters must derive frames from context
plus `document.project`, route in-bounds presses through existing SwiftUI
mutation helpers, and no-op before mutation when pads are out of bounds.

### Phase 5 — Settings, Preferences, Coordinator, Lifecycle

Add app-scoped preferences, the Control Surfaces Settings section, coordinator
injection through `SequencerAIApp`, attach/detach and hot-plug behavior,
focused-window ownership, full-surface repaint on rebind, and Test LEDs.

Use `@StateObject` plus `.environmentObject(coordinator)`. Do not introduce a
competing static singleton.

### Phase 6 — Integration Review and Acceptance

Run component tests and the manual hardware checklist from `plan.md`. A real
Launchpad Mini MK3 is required before shipping because Programmer mode, LED
palette behavior, hot-plug behavior, and hardware routing cannot be fully
validated by unit tests.

---

## Files and Modules Expected to Change

| Area | Expected files |
|---|---|
| MIDI infrastructure | `Sources/MIDI/MIDIClient.swift`, new `MIDIInputConnection`, new `MIDISysExBuilder` |
| App bootstrap/lifecycle | `Sources/App/SequencerAIApp.swift`, `Sources/App/SequencerAIAppDelegate.swift` |
| Preferences | `Sources/UI/PreferencesView.swift`, new preferences support type |
| Control surface core | New frame, LED ID, LED state, palette, mapper, renderer, session, coordinator, context, and adapter files |
| Workspace UI state | `ContentView`, `WorkspaceDetailView`, `PhraseWorkspaceView`, `LiveWorkspaceView` or focused subviews |
| Engine exposure | `EngineController` only if Phase 0 confirms no safe playhead property exists |
| Tests | New `Tests/SequencerAITests/ControlSurface/`, plus focused MIDI and preference tests |

No document model file should gain persisted control-surface state. No schema
migration is expected.

---

## Non-Goals (First Version)

Do not build any of the following:

- Additional control surfaces beyond Novation Launchpad Mini MK3.
- Multi-surface support.
- MIDI learn or arbitrary user remapping.
- Per-document control-surface preferences.
- Modifier-chord or long-press gestures.
- LED pulsing, flashing, or MIDI-clock-driven animation.
- Renaming `WorkspaceSection.tracks` to `.live`.
- Persisting pad state, LED frames, page indices, layer IDs, or selected phrase
  state in `.seqai`.
- Reworking existing sequencer MIDI note output through `MidiOut` or
  `MIDIRouter`.

---

## Open Questions and Risks

**No user-blocking open questions.** The remaining questions are implementer
findings from Phase 0 and must be resolved by reading the codebase:

| Finding | Blocks | Owner |
|---|---|---|
| Minimum macOS deployment target and focus API | Phase 5-E focused-window ownership | Implementation team |
| Existing or new `EngineController` playhead column property | Phase 4-B Live adapter | Implementation team |
| Exact scope color model path and uncolored fallback | Phase 4-B Live adapter | Implementation team |

**Known risks to watch:**

- Production MIDI input support is currently missing and is the structural
  prerequisite for the whole feature.
- SysEx is absent from `MIDIPacketBuilder`; keep it in a separate
  `MIDISysExBuilder`.
- State lifting can regress workspace navigation if context and view state are
  duplicated.
- Frame repaint performance depends on renderer diffing; no-change renders must
  send zero SysEx.
- Manual hardware validation is required before claiming the feature is done.

---

## Acceptance Criteria

Condensed from `spec.md`.

- [ ] MIDI Settings contains a Control Surfaces section, not a new top-level tab.
- [ ] Launchpad Mini MK3 toggle, input picker, output picker, status row, and
  Test LEDs button behave as specified.
- [ ] Endpoint selections persist app-wide across relaunch.
- [ ] Enabling sends Programmer-mode SysEx; disabling and quitting restore Live
  mode.
- [ ] Missing-device and hot-plug states do not crash or send to stale endpoints.
- [ ] Switching workspaces reroutes pad events and repaints all 81 LEDs without
  Settings changes.
- [ ] Phrase grid pads map to the correct visible phrase/track cells and mutate
  through existing helpers.
- [ ] Phrase top-row CC 91-98 and right-column row-select behavior match the
  spec.
- [ ] Live grid pads map to the correct visible scope/step or scope/bar cells
  and mutate through existing helpers.
- [ ] Live top-row CC 91-98, right-column scope-select, transport, workspace
  switch, and playhead override match the spec.
- [ ] Partial pages render out-of-bounds pads as `.off` and pressing them is a
  no-op.
- [ ] Bringing another document window to the front repaints and reroutes the
  Launchpad to that document only.
- [ ] The app still works normally when no hardware is configured.
- [ ] No control-surface runtime state is persisted in the document model.

---

## Testing Expectations

Minimum required test coverage before the feature is shippable:

| Component | Required coverage |
|---|---|
| `MIDISysExBuilder` | Programmer-mode entry, Programmer-mode restore, LED lighting command |
| `MIDIClient` input path | Port creation, source connection, callback dispatch, disconnect |
| `ControlSurfacePreferences` | Persistence roundtrip, missing-endpoint fallback |
| `LaunchpadMiniMK3InputMapper` | Note/CC mapping for all 9x9 positions |
| `LaunchpadMiniMK3Renderer` | Full-frame repaint, single changed LED, no-change sends zero SysEx |
| `PhraseControlSurfaceAdapter` | Matrix derivation, partial pages, page clamping, jump-to-selected no-op when no phrase selected |
| `LiveControlSurfaceAdapter` | Scope/step mapping, playhead full override, uncolored fallback, out-of-bounds no-op |

Run the normal test suite after each phase that changes production behavior.
Phase 6 also requires the manual Launchpad checklist in `plan.md`.
