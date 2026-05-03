---
feature: mixer-main-out
created: 2026-04-30
based_on:
  - docs/roadmap/mixer-main-out/user-stories.md
  - docs/roadmap/mixer-main-out/existing-state.md
  - docs/roadmap/mixer-main-out/ux-review.md
  - docs/roadmap/mixer-main-out/prototypes/mixer-main-out-variant-a.html
  - wiki/pages/engine-architecture.md
  - wiki/pages/routing.md
  - wiki/pages/track-destinations.md
  - wiki/pages/architecture-guardrails.md
---

# Mixer Main Out — Architecture

Written: 2026-04-30
UX direction: Variant A (right-side fixed master column, accepted in `ux-review.md`).

Decision update: the previously blocking product questions were resolved on
2026-05-03 in `decisions.md`. Where Section 5 or Section 9 says user input is
required, `decisions.md` is now authoritative.

---

## 1. Design Constraints Carried Forward

The following findings from `existing-state.md` and `ux-review.md` constrain every architectural
decision below.

1. **`MasterBusScene.normalized()` clobbers `outputGain` to 1.0 unconditionally.**
   `MasterBus.swift:301` resets the field on every engine apply call. Any user-controllable master
   fader field that lives on `MasterBusScene` must be accompanied by a change to the normalization
   path, or the field must live on `MasterBusState` (global, not per-scene) where `normalized()`
   does not touch it.

2. **Metering is entirely absent from the codebase.** No tap, no dBFS conversion, no
   `@Observable` meter property, no clip latch state. This is a net-new subsystem with real-time
   thread implications.

3. **Audio tap callbacks fire on a non-main real-time thread.** Any `installTap` on
   `finalOutputMixer` or `mainMixerNode` receives its buffer callback on AVAudioEngine's private
   I/O thread. UI state updates must be dispatched to the main thread (see
   `EngineController.publishToMain`, EngineController.swift:163). Writing to `@Observable`
   properties without dispatch would be a thread-safety violation.

4. **`installMasterChains` stops and restarts the AVAudioEngine.** MainAudioGraph.swift:88–145
   tears down and rebuilds the master insert chain. A metering tap installed on `finalOutputMixer`
   is invalidated on every such stop. The tap must be removed before the stop and reinstalled after
   restart, or it must be installed on `mainMixerNode` which survives graph rebuilds.

5. **Crossfader widget state is already shared and observable.** `EngineController.
   masterBusPerformanceOverlay.crossfaderOverride` is `@Observable` and the existing crossfader
   widget reads from it directly. The mixer's master column re-uses the same state; it does not
   own a copy.

6. **Inserts are per-scene, not global.** `MasterBusScene.inserts` stores the insert chain for
   each scene. There is no global post-crossfade insert chain in the current model. The mixer
   master column must surface one scene's insert list, not a new chain kind. Which scene's list to
   show when the crossfader is mid-blend is an unresolved product decision (see Section 5).

7. **Mixer and scenes live in separate workspace sections today.** `WorkspaceSection.mixer` routes
   to `MixerWorkspaceView`; `WorkspaceSection.scenes` routes to `ScenesWorkspaceView`. The master
   column, crossfader widget, and insert list are all currently rendered only in
   `ScenesWorkspaceView`. Merging them into the mixer requires either extracting shared components
   or accepting that the crossfader widget lives in two places with shared backing state.

---

## 2. Application Invariants the Feature Must Preserve

### 2a. Document Is the Single Persisted Truth

The `.seqai` document is the only truth for authored state. The following fields must live in
the document if they are to survive across sessions:

- Master output gain level (if a user-controllable fader is in scope).
- Insert chains (already on `MasterBusScene.inserts` — must remain there).
- Crossfader authored position (already on `MasterBusABSelection.crossfader` — must remain there).

The following fields must not be persisted:

- Real-time meter levels (peak amplitudes from the audio tap).
- Clip indicator latch state (see Section 5, question 6 — policy is unresolved, but the latch
  should be a session-scoped runtime flag, not a document field, unless a user explicitly
  chooses to save the clear action).
- Any UI-only selection or hover state.

### 2b. No UI-Only Playback Truth

Per the architecture guardrails: "view-local state becoming the source of playback truth" is a
red flag. Specifically:

- The crossfader position visible in the master column must read from the same
  `masterBusPerformanceOverlay.crossfaderOverride` that drives the audio graph. The column must
  not maintain a local copy.
- The master fader (however scoped) must drive the audio graph through the same mutation path as
  all other audio-graph parameters (`performOnMain` → `MasterBusHost.apply`), not through a
  local `AVAudioMixerNode.outputVolume` write in the view.

### 2c. Audio Thread Isolation

The metering subsystem introduces the first explicit real-time thread callback in the product.
The rules from `architecture-guardrails.md` and `existing-state.md` section 6 apply:

- No allocation inside the tap callback.
- No locks inside the tap callback (use atomics or lock-free ring buffers for peak value transfer).
- The UI polling mechanism (e.g. `CADisplayLink`, `Timer`) must read from a thread-safe buffer
  owned by `MasterMeterPublisher` or an equivalent type, and dispatch only to the main thread
  before any `@Observable` write.

### 2d. Graph Mutation Via `performOnMain`

All audio graph topology changes (insert chain installs, master fader gain writes) must go
through the `performOnMain` dispatch path used by `MainAudioGraph`. Direct writes to
`AVAudioMixerNode.outputVolume` from a view gesture handler would bypass this contract.

---

## 3. Data and Runtime Shape: Persisted vs. Transient

### 3a. Persisted Document State

| Field | Location | Status | Notes |
|---|---|---|---|
| `MasterBusScene.inserts` | `MasterBus.swift` | Exists and working | No change required |
| `MasterBusABSelection.crossfader` | `MasterBus.swift:686` | Exists and working | No change required |
| `MasterBusScene.outputGain` | `MasterBus.swift:280` | Exists but always normalized to 1 | See question 2 below |
| `MasterBusState.masterOutputGain` (proposed) | `MasterBus.swift` | Does not exist | Required if global fader is in scope |

Whether the master fader is per-scene (`MasterBusScene.outputGain` repaired) or global
(`MasterBusState.masterOutputGain` added) is the most consequential architectural decision for
this feature (UX review question 2). It must be resolved before spec. See Section 5.

### 3b. Transient Runtime State

| Field | Owner | Notes |
|---|---|---|
| `crossfaderOverride: Double?` | `MasterBusPerformanceOverlayState` (on `EngineController`) | Already @Observable; drives live audio graph. The master column reads this, it does not own it. |
| Peak meter values (L, R): `Double` | `MasterMeterPublisher` (proposed) | Populated by audio tap callback via atomic store; polled by UI display link. NOT document state. |
| Clip latch flag: `Bool` | `MasterMeterPublisher` (proposed) | Set when peak > 0 dBFS; cleared by user action. NOT document state (policy unresolved — see question 6). |
| Active-scene-for-insert-display: `MasterBusSceneID?` | Computed from `masterBus.abSelection` + crossfader position | Derived, not stored. Rule to be specified. |

### 3c. Proposed `MasterMeterPublisher`

A new `@Observable` class (`MasterMeterPublisher` or equivalent, owned by `MasterBusHost` or
`EngineController`) is required for metering. Its responsibilities:

- Owns the `AVAudioNode` tap lifecycle (install after engine start, remove before engine stop).
- Receives the buffer callback on the audio I/O thread.
- Updates an atomic peak-value pair (left, right) inside the callback with no allocation and no
  lock.
- Exposes `@MainActor`-isolated properties (`peakL: Double`, `peakR: Double`, `isClipped: Bool`)
  that are updated by the main-thread polling loop.
- Exposes a `clearClip()` action callable from the UI to reset `isClipped`.

The tap must be installed on `finalOutputMixer` (after the per-branch gain mixing, before
`mainMixerNode`), as `existing-state.md` section 8 question 3 recommends. This placement measures
what the master insert chain and crossfader produce, which is what the user needs to monitor.

The tap lifecycle must be tied to engine start/stop events. `MasterBusHost.installMasterChains`
already stops and restarts the engine; that method (or its caller) must also coordinate tap
removal and reinstall.

---

## 4. Mutation Paths and Ownership

### 4a. Master Fader

The master fader drives one gain value: either `MasterBusScene.outputGain` (per-scene path) or
`MasterBusState.masterOutputGain` (global path). The mutation path in either case:

1. View gesture → `session.mutateMasterBus(...)` (document mutation, same pattern as
   `session.reorderInserts`).
2. Session mutation triggers `EngineController.applyMasterBusState(...)` (or equivalent).
3. `MasterBusHost.apply(...)` sets `managedMasterGainMixer.outputVolume` for the relevant branch.

If the global path is chosen, `managedMasterGainMixer` (or a new post-blend gain node) is written
directly in one call. If the per-scene path is chosen, `outputGain` must be read at the correct
scene index and applied to the corresponding branch gain mixer. The `normalized()` call must not
reset it afterward.

### 4b. Insert Chain (Mixer Panel Re-exposure)

Insert add, remove, bypass, and reorder mutations already exist via
`SequencerDocumentSession+Mutations.swift:297–324`. The mixer master column re-exposes these same
mutations; it does not introduce new mutation paths. The view binds to `masterBus.scenes[i].inserts`
for the active scene (determined by the display rule resolved in Section 5, question 1).

### 4c. Crossfader

The crossfader position is owned by `ScenesWorkspaceView+Perform.swift`. The master column reads
and writes the same `engineController.masterBusPerformanceOverlay.crossfaderOverride` via
`engineController.setLiveMasterCrossfader(_:)`. The crossfader widget must be extracted from its
private `crossfader(...)` function in `ScenesWorkspaceView+Perform.swift` and made reusable as a
standalone `MasterCrossfaderView` (or equivalent) that both the scenes view and the mixer column
can embed. This is a presentation-side refactor with no model changes.

### 4d. Clip Indicator Clear

`MasterMeterPublisher.clearClip()` is called from a "CLR" button in the master column. This
resets the `isClipped` flag from the main thread. No document mutation is involved (the flag is
transient). If automatic hold-and-reset is added later, it must also go through this method rather
than through a document field.

---

## 5. Open Questions: Resolved vs. Requiring User Input

The six open questions from `ux-review.md` are addressed below.

### Question 1 — Active scene inserts during mid-blend (RESOLVED)

**Which scene's insert chain does the master out panel display when the crossfader is mid-blend?**

Options:
- Always the A-slot scene (simple; predictable; A is conventionally dominant).
- Always the scene with higher crossfader weight (dynamic; more complex display logic).
- Show both with a separator (highest information density; unclear layout at scale).

Architecture can implement any of these, but the correct policy is a product decision. The
display rule determines the view binding and the label ("Inserts (Scene: X)"). This must be
resolved before spec. The question is recorded in `open-questions.md`.

**Architectural implication:** All three options bind to existing `MasterBusScene.inserts` data.
No new model field is required for any option. The only difference is the index computation in
the view or view model.

### Question 2 — Master fader scope: per-scene vs. global (RESOLVED)

**Should the master output fader be per-scene (`MasterBusScene.outputGain`, repaired) or
global (`MasterBusState.masterOutputGain`, new field)?**

Architecture analysis:
- **Per-scene:** The field already exists. Repair requires removing the unconditional reset in
  `normalized()` and updating `MasterBusHost` to read and apply it per branch. The mixer column
  shows a different fader position for each active scene, which may be surprising if the user
  expects "one master level."
- **Global:** A new `masterOutputGain: Double` field on `MasterBusState` is added. It is applied
  to a single gain node after the A/B crossfade blend. This is the conventional DAW behavior —
  one master fader, independent of scenes. Requires adding a new gain node after
  `finalOutputMixer` in `MainAudioGraph`, or repurposing an existing one.

The conventional behavior (global, post-blend) is strongly implied by the user story
("a clearly separated master out section... control the final output independently of individual
tracks or busses") and the prototype label "MASTER OUT." However, this is a model change with
migration implications for existing documents that rely on `MasterBusScene.outputGain` being 1.0.
The decision is recorded in `open-questions.md`.

**Architectural recommendation (advisory, not decided):** The global field is more correct for the
user story intent. Per-scene outputGain repair is a dead end because it produces
per-scene master levels, which is not what Story 1 describes. If the user confirms the global
interpretation, the implementation adds `MasterBusState.masterOutputGain: Double` (default 1.0,
persisted) and connects it to a new or repurposed gain node after the crossfade blend.

### Question 3 — Unity (0 dB) position and default fader value (RESOLVABLE IN SPEC)

**Where is Unity on the fader scale, and what is the default value at document creation?**

Architecture position: The fader scale should place 0 dBFS at approximately 75–80 % from the
bottom of the throw (matching the Variant A prototype's visual intent and standard DAW convention,
where headroom above unity is available for the +6 dB region). The default value at document
creation is 1.0 (Unity, 0 dB). This is consistent with `MasterBusScene.outputGain`'s current
hard-coded value and with how new documents initialize all other gain fields.

This is a spec-level decision that does not require user input. It can be set as a default in the
spec with a note that the dB display scale is a UI/implementation concern.

### Question 4 — Empty insert chain affordance (RESOLVABLE IN SPEC)

**What is shown when a scene's insert chain is empty?**

Architecture position: The two dashed-border empty-slot rows shown in Variant A are the correct
pattern. They are consistent with the existing `ScenesWorkspaceView` insert list behavior and with
the prototype's empty-slot rendering. The spec should confirm the slot count (2 visible empty
slots) and the label ("— empty slot —" as shown in the prototype). No model change is required;
the view renders empty dashed rows when `scene.inserts.count` is below the visible slot count.

This is a spec-level decision.

### Question 5 — Minimum workspace width / collapse policy (RESOLVABLE IN SPEC)

**At narrow viewport widths (iPad split-screen ~540–700 pt), how does the 190 px master column
behave?**

Architecture analysis: The master column occupies a fixed 190 pt right side of the mixer
workspace. The minimum practical width for the track strip area (with at least 3–4 visible
channel strips at ~72 pt each) is approximately 288–360 pt. Adding 190 pt gives a minimum
workspace width of approximately 478–550 pt. This is tight but achievable on a standard iPad
12.9" split-screen (768 pt available, giving ~578 pt after split).

Architecture recommendation: Define a minimum workspace width of 540 pt. Below this threshold,
collapse the master column to a compact 44 pt icon strip (fader hidden, meter visible as a narrow
bar, no insert chain). Expand on tap. This is consistent with how the existing mixer workspace
handles narrow windows. The collapse policy is a spec decision, not a model decision.

No model changes required for any collapse policy.

### Question 6 — Clip indicator latch policy (RESOLVED)

**Does the clip latch reset only on user action ("CLR" button), or also after an automatic hold
period?**

Architecture analysis: User story 3 explicitly states "stays latched until manually cleared."
The acceptance signal repeats this: "it does not reset on its own until the user clears it."
This strongly implies user-action-only reset, which is also the conventional DAW behavior
(Pro Tools, Logic, Ableton all require a user click to clear clip indicators).

Architecture recommendation: Implement user-action-only reset as the default. Auto-hold-and-reset
is explicitly not required by the story. If the user wants auto-reset as an option, it is additive
and can be handled in a follow-up. The question is noted in `open-questions.md` only to confirm
that no automatic reset timer is required, rather than to seek an alternative answer.

**This question is likely resolvable as "user-action-only" based on the user story text.** It is
included in `open-questions.md` as a confirmation request rather than a blocking unknown.

---

## 6. Relationship to Mixer Busses (Item 5)

`existing-state.md` section 8 and the notes cross-reference note that mixer-busses (item 5) has
its own Q4 about whether insert state is scene-scoped or global. That question is closely related
to this feature's question 2 (master fader scope) and question 1 (active scene insert display).

**Guardrail:** The mixer-main-out feature must not unilaterally change `MasterBusScene.inserts`
from per-scene to global without coordinating with the mixer-busses roadmap item. The current
architecture assumes that inserts remain per-scene for this feature. If mixer-busses resolves its
Q4 in favor of a global chain, the master column's insert display rule (question 1) may change.

The spec should note this dependency explicitly and flag that a global insert chain refactor, if
it lands as part of mixer-busses, would supersede the active-scene display rule adopted here.

---

## 7. Existing Patterns to Follow

| Concern | Existing Pattern | Source |
|---|---|---|
| Insert list UI (add, bypass, reorder, remove) | `ScenesWorkspaceView` insert list view | Sources/UI/Mixer/ScenesWorkspaceView.swift |
| Crossfader widget | `ScenesWorkspaceView+Perform.swift:28` — extract to reusable component | Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift |
| Audio graph mutation dispatch | `performOnMain` in `MainAudioGraph` | Sources/Audio/MainAudioGraph.swift:164 |
| Document-level master bus mutations | `SequencerDocumentSession+Mutations.swift:297–324` | Sources/Document/SequencerDocumentSession+Mutations.swift |
| Observable state update from non-main thread | `EngineController.publishToMain` dispatch pattern | Sources/Engine/EngineController.swift:163 |
| Engine stop/start coordination | `installMasterChains` stop/restart pattern | Sources/Audio/MainAudioGraph.swift:88–145 |

The metering tap and `MasterMeterPublisher` are net-new; no direct existing pattern covers them.
The `publishToMain` dispatch pattern is the closest analog for the main-thread publishing step.

---

## 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Tap invalidation on graph rebuild | High | Must explicitly uninstall tap before `installMasterChains` stop and reinstall after restart. If not handled, clip indicators will stop updating silently after any insert-chain edit. |
| `normalized()` clobbering a repaired `outputGain` | High | If per-scene path is chosen, `normalized()` must be changed in the same commit as the UI. Any call path that triggers `normalized()` without the UI guard will silently reset the fader. |
| Duplicate crossfader widget state | Medium | Extracting the widget to a shared component and ensuring both call sites read from `masterBusPerformanceOverlay.crossfaderOverride` is required. A local copy would desync from the scenes view. |
| Audio thread dBFS conversion cost | Low | Peak detection (absolute value scan over a buffer) is trivially inexpensive. Risk is negligible. |
| Narrow viewport layout at 540 pt | Medium | Test on actual iPad split-screen dimensions. The collapse policy (question 5) must be decided before spec to avoid a late layout regression. |
| Mixer-busses global-chain refactor superseding this design | Medium | The per-scene insert assumption in this architecture could be invalidated if mixer-busses (item 5) adopts a global post-blend chain. The spec should note the dependency and the condition under which the active-scene display rule becomes moot. |

---

## 9. Architecture Questions Gating Spec

Questions 1, 2, and 6 from Section 5 were resolved on 2026-05-03 in `decisions.md`.
Questions 3, 4, and 5 are resolvable within the spec.

| # | Question | Resolution path |
|---|---|---|
| 1 | Which scene's inserts show during mid-blend? | Resolved: show the scene with higher crossfader weight |
| 2 | Master fader: global `masterOutputGain` or repaired per-scene `outputGain`? | Resolved: global post-blend master output gain |
| 3 | Unity position and default fader value at document creation | Resolvable in spec (default: 0 dB = 1.0, ~75–80 % up the throw) |
| 4 | Empty insert chain affordance | Resolvable in spec (dashed empty slots matching prototype) |
| 5 | Minimum workspace width / collapse policy | Resolvable in spec (540 pt minimum, compact strip below) |
| 6 | Clip indicator: user-action-only vs auto-hold? | Resolved: manual clear only |
