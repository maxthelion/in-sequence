---
verdict: accepted
reviewed: 2026-04-30
---

# MIDI Interfaces — Architecture Review

Sources consulted: `docs/roadmap/midi-interfaces/architecture.md`,
`docs/roadmap/midi-interfaces/ux-review.md`,
`docs/roadmap/midi-interfaces/user-stories.md`,
`docs/roadmap/midi-interfaces/existing-state.md`,
`wiki/pages/architecture-guardrails.md`,
`wiki/pages/engine-architecture.md`,
`wiki/pages/routing.md`.

---

## Summary

The architecture document is coherent, internally consistent, and respects the
project's guardrails. The five UX-review open issues are resolved with credible,
well-scoped decisions. The three remaining architecture questions are genuinely
implementer-resolvable by reading the codebase — they do not require user input
or a second architecture pass. The verdict is **accepted**; the feature may
advance to `write-spec`.

---

## Approved Guardrails

### 1. Document truth versus runtime state — fully respected

`ControlSurfacePreferences` is correctly scoped to `UserDefaults` / `@AppStorage`
(app-scoped, not per-document). Pad state, LED frames, and `ControlSurfaceFrame`
are correctly classified as transient and ephemeral. Nothing in the proposed
`WorkspaceControlSurfaceContext` should enter the `.seqai` document. This is
exactly the split the guardrails page demands.

### 2. Playback hot path untouched — correctly isolated

The architecture explicitly states that LED rendering and pad-input dispatch
operate on the UI thread against `document.project` data, and must never reach
into `PlaybackSnapshot` internals or compete with the `TickClock` callback.
The routing wiki confirms `MIDIRouter` and `EngineController` own the hot path;
the control-surface path is additive on the UI side and has no intersection with
`Sources/Engine/`. This guardrail is honored.

### 3. No new shared mutable state between timer callback and control-surface path — credible

Invariant 3 states that `EngineController`'s playhead exposure must be
`@Published` or `@Observable`, the same property SwiftUI already reads.
The engine-architecture wiki confirms `EngineController` already exposes
transport state to SwiftUI. As long as the implementation uses that existing
published property (or adds one with the same thread model), no lock on the
engine tick is introduced. The guardrail is correct; the spec should name the
exact property to prevent implementers from reaching past it.

### 4. CoreMIDI send path isolation — correct and complete

Invariant 6 states that the control surface uses an independent MIDI output
port for SysEx and does not share the existing `MidiOut` / `MIDIRouter` send
path. The routing wiki confirms `MidiOut` is a block in the engine DAG; the
control surface sits entirely outside that DAG. This is correctly scoped.

### 5. `WorkspaceControlSurfaceContext` as single source of truth — sound

The proposed `@Observable` context is the only owner of surface-visible workspace
state (`activeSection`, `liveLayerID`, `phraseTrackPage`, `phrasePage`,
`scopePage`, `colPage`, `selectedPhraseID`). Views and adapters both read from
it. This avoids duplicated truth while keeping the document model unchanged.
The `@Observable` pattern matches the app's existing approach.

### 6. Adapter mutations via existing document helpers only — correct

Both mutation tables (Phrase and Live) route through the same helpers the
SwiftUI views call. No new public mutation API is introduced. This is the right
discipline: the adapter is view-logic equivalent, not a new mutation layer.

---

## Rejected or Revised Guardrails

None. No guardrail in the architecture document conflicts with the project's
architecture or the user stories.

---

## Assessment of the Five UX-Review Resolutions

### 1. Edge-pad budget (top CC row has 8 pads)

**Sound.** The architecture makes the only assignment that fits all seven
required v1 functions in each workspace without a modifier chord:

- Phrase: prev-layer / next-layer / prev-track-page / next-track-page /
  prev-phrase-page / next-phrase-page / jump-to-active-phrase-page /
  workspace-switch-to-Live
- Live: prev-layer / next-layer / prev-scope-page / next-scope-page /
  prev-col-page / next-col-page / workspace-switch-to-Phrase / transport-play-stop

The architecture correctly documents that this exhausts the top row in v1 and
defers modifier chords to v2. This is not a product decision that requires
user input — it is a hardware-capacity conclusion. The spec should publish the
exact CC assignment table (CC 91–98, left to right) and mark modifier chords
as explicitly out of scope.

One implicit assumption to verify at spec time: "jump-to-active-phrase-page"
(Phrase top row, CC 97) must be defined precisely. If the phrase is already on
the current page, this is a no-op; if it is on a different page, it sets
`phrasePage` to the page containing `selectedPhraseID`. The adapter must handle
the degenerate case where no phrase is selected.

### 2. `WorkspaceSection.tracks` rename vs. alias

**Sound.** The no-rename decision is correct. A rename touches every switch
statement in the codebase and risks regressions unrelated to this feature.
The local alias (`case .tracks: return liveAdapter.handleEvent(event)`) is the
minimal, safe, reviewable change. The comment-block documentation at the top of
`WorkspaceControlSurfaceContext` is an appropriate single update point. This
decision is PM-resolvable and the architecture makes it correctly.

### 3. Playhead column full override

**Sound.** Full override (playhead color applied last, overriding all cell
state) is the right v1 choice. The rationale — single LED cannot simultaneously
convey position and content on a small 3-color surface — is correct for the
Launchpad Mini MK3's palette system. The spec should state this explicitly and
note that the LED set loop order matters: cell state first, playhead override
last.

### 4. Empty-pad partial-page rendering (`.off` + no-op)

**Sound.** Requiring `.off` (fully dark) and a no-op for out-of-bounds pad
presses is the correct approach. It distinguishes empty-page pads from assigned
pads and prevents inadvertent document mutation. The architecture correctly
characterizes this as a hard requirement, not a defensive-coding nice-to-have.
The spec must enumerate the guard points as stated: `PhraseControlSurfaceAdapter`
checks phrase-slice and track-slice bounds; `LiveControlSurfaceAdapter` checks
scope-slice and column-slice bounds.

### 5. Uncolored scope fallback

**Sound.** A dedicated `uncolored` semantic in `LaunchpadMiniMK3Palette` mapping
to a dim white / light gray palette entry is correct. The rationale — an unlit
row is indistinguishable from an empty-pad row — is a real usability constraint.
The spec should name the specific palette entries (MK3 palette indices 1–3,
dim white) and require the fallback to be non-zero.

---

## Assessment of the Three Architecture-Internal Open Questions

### Q1: Minimum macOS deployment target

**Implementer-resolvable.** The architecture correctly identifies this as a
lookup in the project configuration (`MACOSX_DEPLOYMENT_TARGET` in the xcodeproj
or `Package.swift`). The consequence is deterministic: if the target is macOS
14+, `onWindowFocusChange` is available; if it is macOS 13 or earlier,
`NSWindowDelegate` via AppKit interop is required. An implementer reading
`SequencerAIApp.swift` and the project build settings can resolve this in
minutes. The spec should state which path is required once the implementer
checks, and should not hardcode the assumption.

**One concern to carry into the spec:** if the current target is macOS 13,
`NSWindowDelegate` requires wrapping each `DocumentGroup` window in an
`NSWindowController` subclass or using a `SwiftUI.Application.delegate` shim.
This is not architecturally novel but it is implementation-non-trivial. The spec
should call this out explicitly so the implementer does not treat it as a
one-liner.

### Q2: `EngineController` playhead exposure

**Implementer-resolvable.** The engine-architecture wiki confirms
`EngineController` already exposes transport state to SwiftUI. An implementer
reading `Sources/Engine/EngineController.swift` can confirm whether a
`currentStep: Int` or step-index equivalent is already `@Published`. If it
exists, the spec names it. If it does not, the spec describes what property to
add (a `@Published var currentPlayheadColumn: Int` on the main thread, updated
at the start of `dispatchTick()` from the same tick index already in scope).
The architecture's guardrail — must not expose engine internals that break the
`Engine → UI` dependency direction — is the right constraint. The spec should
enforce it.

**One concern:** `EngineController.dispatchTick()` runs in the `TickClock`
callback. Updating a `@Published` property there without a `DispatchQueue.main`
hop could cause SwiftUI update-from-background-thread warnings in debug builds
even if it is technically safe. The spec should note this threading detail so
the implementation uses `DispatchQueue.main.async` if the property update
happens off the main thread.

### Q3: `scopeColor(for:)` data source

**Implementer-resolvable.** The existing-state document and routing wiki confirm
that groups and tracks live on the document model. An implementer reading
`Sources/Document/` can locate whether `TrackGroup` or a similar model carries
a color field. The hardcoded fallback for ungrouped tracks is also a code-lookup
rather than a user question. The architecture's recommendation (a `scopeColor(for:)`
helper on `LiveControlSurfaceAdapter`) is the right abstraction boundary. The
spec should require the helper to be a pure function of `document.project` with
a defined fallback value; the implementer confirms the exact model path.

---

## Risks the Architecture Pass Identified Correctly

All seven risks in the architecture document are real and correctly scoped:

- **Risk 1** (`MIDIClient` production input-port gap): the most structurally
  blocking gap. It touches `Sources/MIDI/` and must be resolved before any
  pad input can be received. Confirmed by `existing-state.md`.
- **Risk 2** (SwiftUI window-focus tracking on macOS): real API uncertainty
  dependent on deployment target. Architecture correctly defers to the
  coordinator task.
- **Risk 3** (`WorkspaceSection.tracks` private state lifting): a UI-tree
  refactor risk. Architecture correctly recommends isolating it to a dedicated
  commit / PR with tests before the change.
- **Risk 4** (SysEx absent from `MIDIPacketBuilder`): confirmed hard gap in
  existing-state. A separate `MIDISysExBuilder` in `Sources/MIDI/` is the
  right boundary.
- **Risk 5** (frame repaint performance): diff logic must be tested with full-frame,
  single-changed-LED, and no-change scenarios. Correctly called out.
- **Risk 6** (playhead column index source): correctly identified as a potential
  gap in `EngineController`; resolution is implementer-resolvable (see Q2 above).
- **Risk 7** (no `Tests/ControlSurface/` directory): the implementation loop
  must create this directory and provide test coverage for all new types.

---

## Risks the Architecture Pass Missed

### M1: `ControlSurfaceCoordinator` singleton vs. environment injection ambiguity

The architecture states the coordinator is "created in `SequencerAIApp` and
injected as an environment object or singleton." These are architecturally
distinct choices. A true app-level singleton (a static `shared` property) and an
`@StateObject` injected via `.environmentObject` have different lifecycle
semantics. On macOS with `DocumentGroup`, there is only one `SequencerAIApp`
instance, so either approach works at the app level. However, the spec should
settle this definitively so the implementation does not produce two code paths
that are later refactored. Recommended resolution: use `@StateObject` in
`SequencerAIApp` body + `.environmentObject(coordinator)` on the `DocumentGroup`,
matching the singleton-warmup pattern used by `MIDISession.shared`.

### M2: `liveLayerID` binding path ambiguity

The architecture states that `liveLayerID: String` is "already a `@Binding`
path from `WorkspaceDetailView`; confirm it can be passed through to the context
without a separate copy." This is stated as a confirmation task but left open.
If `liveLayerID` cannot be bridged without a copy, the context and
`WorkspaceDetailView` hold separate values and must be kept in sync, which
is a dual-source-of-truth problem. The spec must resolve this: either
`WorkspaceControlSurfaceContext.liveLayerID` becomes the single source and
`WorkspaceDetailView` receives a binding into it, or the architecture is wrong
and this needs a different lifting strategy. Do not leave this as a confirmation
task for the implementer.

### M3: `HardwarePadEvent` dispatch to main queue — missing implementation detail

The architecture states the CoreMIDI input callback must dispatch a
`HardwarePadEvent` to the main queue for semantic handling. The mechanism for
doing so is not specified. Two options exist: `DispatchQueue.main.async` (simple
but no back-pressure) or a `@MainActor`-annotated handler. The architecture
should also state what happens if events arrive faster than the main queue can
drain (e.g., a user holding down a pad). The spec should address this; it is
not blocking the architecture verdict but the implementer needs explicit guidance.

---

## Open Architecture Questions Remaining

None that block the spec. The three implementer-resolvable questions (Q1–Q3
above) should be resolved as named findings in the spec rather than open
questions. The three missed risks (M1–M3 above) should be resolved in the spec
with definitive choices before the implementation loop begins.

---

## Recommendation

**Advance to `write-spec`.** The architecture is coherent enough for a spec
writer to rely on. No user input is needed. The spec writer should:

1. Publish the CC assignment table (CC 91–98) for both workspace top-row
   mappings as a normative table.
2. Resolve the coordinator injection pattern (M1) definitively.
3. Resolve the `liveLayerID` binding path (M2) definitively.
4. Specify the main-queue dispatch mechanism for `HardwarePadEvent` (M3).
5. Name the exact `EngineController` property used for playhead exposure (Q2),
   noting the threading requirement.
6. State the minimum macOS deployment target and which window-focus API follows
   from it (Q1).
7. Confirm the `TrackGroup.color` (or equivalent) model path for `scopeColor` (Q3).
8. Enumerate the explicit out-of-bounds guard points in both adapters.
9. Define the "jump-to-active-phrase-page" no-selection edge case.
10. Mark modifier chords as explicitly out of scope for v1.
