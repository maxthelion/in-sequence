# Mixer Main Out - Implementation Handoff

## Feature

- **ID:** 4
- **Title:** Mixer Main Out
- **Status:** `inventory`
- **Stage:** `ready-for-build-queue`
- **Source directory:** `docs/roadmap/mixer-main-out/`

---

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [plan.md](plan.md) | First build document to read. It sequences the work into verification, persisted gain, metering, mixer UI extraction, and coverage. |
| [spec.md](spec.md) | Primary product contract. Use this when there is any ambiguity about behaviour, acceptance criteria, or non-goals. |
| [architecture.md](architecture.md) | Guardrails around document ownership, realtime metering, graph mutation, and mixer composition. |
| [architecture-review.md](architecture-review.md) | Accepted review. Locks the post-fader metering requirement and calls out migration and duplicate-affordance risks. |
| [existing-state.md](existing-state.md) | Current code reality: scene-scoped inserts already exist, the mixer has no master section, and metering is absent. |
| [user-stories.md](user-stories.md) | User intent and acceptance signals for the master section, inserts, metering, and crossfader. |
| [ux-review.md](ux-review.md) | Accepted UX direction. Explains why Variant A beat the top-band alternative. |
| [prototype-approval.md](prototype-approval.md) | User approval and the three locked product decisions for v1. |
| [prototypes/mixer-main-out-variant-a.html](prototypes/mixer-main-out-variant-a.html) | Selected prototype for layout, control grouping, and visual hierarchy. |
| [decisions.md](decisions.md) | The settled product decisions that the implementation must not reopen. |
| [notes.md](notes.md) | Original product framing and cross-links to busses, sends, and Scene Perform. |

The implementation loop should consume this handoff first, then follow the
links above in the order shown unless a plan phase points somewhere more
specific.

---

## Goal

Add a dedicated master-output lane to the mixer workspace so the user can
manage the final output without leaving the mixer. In v1 that means:

- one fixed right-side master column in the mixer
- one global post-blend master fader
- scene-scoped master inserts surfaced in the mixer instead of only in Scenes
- one shared Scene A/B crossfader control reused from Scene Perform
- one new transient dBFS meter plus manual clip latch clear

This is a narrow extension of the existing master-bus path, not a mixer routing
rewrite.

---

## Chosen Product Direction

The approved direction is Variant A: a fixed right-side master column inside
the mixer workspace. The master fader is global and applied after the A/B
crossfade blend. The insert panel remains scene-scoped and shows whichever scene
has the higher current crossfader weight. The clip indicator is manual-clear
only in v1.

Do not add a second prototype pass, a per-scene master fader, or a new global
master insert model unless later user feedback explicitly invalidates the
approved lane.

---

## Guardrails The Implementer Must Preserve

1. `Project.masterBus` remains the single persisted owner of authored master-bus
   state. Meter peaks, clip latch state, and live crossfader overrides remain
   transient runtime state only.
2. The global master gain and the meter tap must stay on the same audible
   post-fader point. If `finalOutputMixer.outputVolume` is the master fader,
   meter `finalOutputMixer`. Do not ship pre-fader metering by accident.
3. Scene-scoped inserts are the v1 boundary. Reuse `MasterBusScene.inserts` and
   the existing mutation helpers; do not invent a second insert-chain model.
4. The mixer master column must read and write the same
   `masterBusPerformanceOverlay.crossfaderOverride` path used by Scene Perform
   today. No duplicate local crossfader state.
5. Audio-graph writes still flow through the existing `performOnMain` /
   `MainAudioGraph` discipline. Views must not mutate AVAudioEngine nodes
   directly.
6. Metering callbacks run on a realtime thread. Observable publication must
   cross to the main thread explicitly, and clip/meter state must never be
   persisted into the document.
7. `MasterBusScene.outputGain` stays out of scope for this feature. Do not
   repurpose it as the global master fader.

---

## Implementation Read Order

1. Read this handoff.
2. Read [plan.md](plan.md) and execute in phase order.
3. Use [spec.md](spec.md) as the product contract for behaviour and acceptance
   criteria.
4. Use [architecture.md](architecture.md) and
   [architecture-review.md](architecture-review.md) as hard guardrails for
   state ownership, tap placement, and UI extraction boundaries.
5. Read [existing-state.md](existing-state.md) before changing master-bus
   document helpers, audio graph code, or mixer/scenes UI.

Do not reopen decisions already settled in [decisions.md](decisions.md) or
[prototype-approval.md](prototype-approval.md). If code reality conflicts with
those decisions, capture it as an implementation finding and stay inside the
documented guardrails.

---

## Build Sequence

Follow the plan's phases in order:

1. **Phase 0 - verification**
   Confirm the post-fader seam on `finalOutputMixer`, the extraction seams for
   the shared crossfader and insert controls, and the exact test landing zones.
2. **Phase 1 - persisted master gain**
   Add `masterOutputGain` to `MasterBusState`, wire a focused session mutation,
   and apply the gain on the final output path.
3. **Phase 2 - transient master metering**
   Add the runtime-only meter owner, clip latch, and tap lifecycle without
   leaking state into the document.
4. **Phase 3 - mixer master column**
   Extract the shared crossfader, surface scene-scoped inserts in the mixer,
   add the master fader, and add the meter/clip UI.
5. **Phase 4 - verification and polish**
   Add the document, session, engine, and UI coverage called out in the plan and
   confirm the accepted behaviour against the spec.

---

## Files And Modules Expected To Change

| Area | Expected work |
|---|---|
| `Sources/Document/MasterBus.swift` | Add `masterOutputGain` with legacy-safe decoding and normalization rules |
| `Sources/App/SequencerDocumentSession+Mutations.swift` | Add a focused master-output gain mutation path |
| `Sources/Audio/MainAudioGraph.swift` and `Sources/Audio/MasterBusHost.swift` | Apply the global gain and own the meter tap lifecycle |
| `Sources/Engine/EngineController.swift` | Publish transient meter state and clip clear actions safely to SwiftUI |
| `Sources/UI/Mixer/MixerWorkspaceView.swift` and related mixer/scenes views | Add the master column and extract/reuse the crossfader and insert UI |
| `Tests/SequencerAITests/Document/`, `App/`, `Audio/`, and UI-focused tests | Add coverage for decode defaults, session mutation, post-fader metering, and master-column behaviour |

No `docs/specs/**`, `docs/plans/**`, wiki, or unrelated roadmap items belong in
this build.

---

## Acceptance Focus

The implementation is ready to ship to review only when these outcomes are
observable:

- The mixer renders a dedicated right-side master section distinct from tracks
  and busses.
- The master fader writes one global persisted output gain and affects only the
  final output level.
- The meter reflects the same post-fader signal the user hears.
- The clip indicator latches on overload and clears only when the user presses
  clear.
- The insert panel reuses scene-scoped master inserts and follows the dominant
  crossfader side.
- The mixer crossfader stays in sync with Scene Perform because both surfaces
  share the same live override path.

See [spec.md](spec.md) Section 8 for the full acceptance criteria and
[plan.md](plan.md) for the exact verification sequence.

---

## Non-Goals And Deferred Follow-Ups

- No per-scene master output gain in v1.
- No new global master insert chain after the A/B blend.
- No auto-clear timer for clip state.
- No Reset / Save Blend / Save to Scene controls in the mixer master column.
- No new effect types, AU hosting rules, or mixer-busses redesign.
- No second visual prototype pass unless later feedback invalidates the approved
  lane.

---

## Open Questions

There are no user-blocking product questions left for this item.

The remaining checks are implementation findings already called out in
[plan.md](plan.md):

- confirm the exact post-fader tap and rebuild seam around `finalOutputMixer`
- confirm the lightest extraction path for the shared crossfader and insert UI
- confirm the precise test files to extend for document, session, engine, and
  mixer coverage

These are implementation checks, not reasons to relitigate the PM direction.
