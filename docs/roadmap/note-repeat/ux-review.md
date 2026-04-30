---
verdict: accepted
selected_prototype: perform-page-toggle.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/perform-page-toggle.html
  - prototypes/layer-interval-and-substep.html
feedback_applied: []
---

# Note Repeat — UX Review

## What Works

### perform-page-toggle.html (Stories 1 and 2)

The three-scenario flow (Idle / Engaged / Released) covers the full engage-disengage round-trip without ambiguity. The visual language is well-differentiated: the dashed border on the idle Repeat button clearly signals "proposed new UI"; the amber pulsing state signals "hold active"; the immediate return to dashed-idle on release communicates disengage precisely. The per-track column alignment between the action row and the track card grid is correct — a performer can read which track is repeating without hunting.

The captured-step overlay ("CAPTURED: step 9 — Firing at 1/16 interval — hold to sustain") gives the performer just enough feedback to confirm what was locked. Scenario C shows that Kick rejoins at step 12 (the live transport position at release) rather than step 9, which directly validates the "no drift back to captured step" requirement in Story 2.

Multi-track independence is shown: while Kick is frozen, Snare, HH, and Bass advance normally. This resolves what could have been an ambiguous moment in the user story.

### layer-interval-and-substep.html (Stories 3 and 4)

The segmented 1/16 / 1/32 / 1/64 control is clear and cognitive-load-free. Three options, one tap, no numeric entry. The step-ruler diagrams accurately illustrate the intra-step firing count for each interval, making the sub-step concept legible to anyone reading the architecture later.

The amber "sub" badge on 1/32 and 1/64 is a useful prototype-only annotation — it marks the engine boundary without requiring the performer to understand it. The gate-length clamping callout on the 1/64 tab is the only place in either prototype where a non-obvious engine constraint is surfaced at the UX layer, which is appropriate because it has a perceptible outcome (notes truncated mid-sustain).

## What Fails or Is Missing

### 1. No "latch vs. momentary" disambiguation (Story 1)

The user notes say "like fill." The existing-state report confirms Fill is not a runtime toggle at all today — it is phrase-authored. The prototype shows both Fill and Repeat as tap-to-toggle buttons, but the user story assumption says "momentary-hold-or-latch model." The prototype does not show how latch mode vs. momentary mode is selected or indicated. If the intent is that a short tap latches and a long press is momentary (or vice versa), this needs a scenario. This is a design question, not a prototype failure, but architecture cannot be written without knowing which interaction model must be supported.

### 2. Generator-track behaviour is unaddressed

Existing-state confirms that Fill is not applied to generator-backed sources. The prototype shows "Bass-Seq" advancing normally while Kick repeats, but does not address what happens if a generator-backed track has Repeat engaged. The captured step for a generator track may not be a deterministic event sequence the way a clip step is. This edge case should be stated, even if the first implementation simply does not support generator tracks.

### 3. No empty-step capture scenario

Story 2 says the captured step is "the step that was quantized at engage time." The prototype shows Kick being captured on a step that has a note (step 9, orange in the grid). There is no scenario where the performer engages Repeat on an empty step (no note). Should that be a no-op? Should it capture silence and fire nothing? The prototype does not cover it.

### 4. Interval selector location requires navigation away from perform mode

The interval selector lives in "Track Layer Settings" (layer-interval-and-substep.html), which is the edit-mode layer detail view. A performer who wants to change the repeat interval must exit perform mode, enter edit mode, navigate to layer settings, adjust the interval, and return. This is not surfaced as a gap in the prototype annotations. Architecture should note whether a quick-access shortcut from perform mode is needed or if the current navigation depth is acceptable for a pre-performance setting.

### 5. Stuck-note risk on rapid re-engage is not shown

Scenario C shows a clean release followed by idle. It does not show the edge case where the performer immediately re-engages Repeat within the same step after releasing it. The flush-then-capture sequence could produce a doubled note or a missed note-off. This is an engine concern but a scenario worth capturing in the spec.

## UX Checklist

| Criterion | Result |
|-----------|--------|
| All user-story goals reachable from the prototype | Partial — Stories 1, 2, 3, 4 shown; latch/momentary model unresolved |
| Happy path completable in <= 2 taps | Pass — engage: 1 tap; release: 1 tap |
| Active states visually unambiguous | Pass — amber pulsing vs. idle dashed vs. blue active |
| Off-path / error states shown | Partial — no empty-step capture, no rapid re-engage shown |
| Adversarial fixture data used consistently | Pass — same 4 tracks, same step pattern across scenarios |
| No hidden state that the performer cannot observe | Pass — capture overlay on card makes captured step explicit |
| Interaction budget <= 3 taps for primary paths | Pass |

## User-Story Goal Coverage

| Story | Coverage |
|-------|----------|
| 1 — Note Repeat toggle on perform page | Covered in all three perform-page scenarios |
| 2 — Capture step, loop until released | Covered in Scenarios B and C; latch/momentary gap |
| 3 — Per-layer repeat interval | Covered in layer-interval-and-substep.html |
| 4 — Sub-step intervals within a step | Visualised; engine approach unresolved |

## Recommended Direction

Accept both prototypes as complementary: `perform-page-toggle.html` for Stories 1 and 2, and `layer-interval-and-substep.html` for Stories 3 and 4. No rework is needed before architecture; the gaps identified above are architecture and spec questions, not UX failures.

The selected prototype for implementation handoff is `perform-page-toggle.html` as the primary surface (the user's interaction point). The layer-interval prototype informs the data model and interval-setting placement.

## Open Questions for Architecture

1. **Latch vs. momentary:** Does the Repeat button follow a latch-on-tap / release-on-second-tap model, a momentary-hold model, or both (e.g. short tap = latch, long press = momentary)? The perform page has no dedicated long-press affordance today. Architecture cannot define the engage/disengage API without knowing which model is required.

2. **Generator track support:** Should Note Repeat be suppressed (button disabled) for generator-backed tracks in the first implementation, or must it capture the generator's most recent output step? The RollingCaptureBuffer exists but only accumulates clip steps deterministically.

3. **Empty-step capture:** If Repeat is engaged when the transport is on a step with no note event, should the engine do nothing (no retrigger), capture silence (audible gap pulses), or snap forward to the nearest active step?

4. **Interval change while repeating:** If the performer changes the repeat interval in layer settings while Repeat is actively engaged on that track, should the change take effect on the next retrigger or only when Repeat is next engaged?

5. **Sub-step scheduling approach:** Which of the three approaches identified in existing-state should be adopted? (Higher-resolution TickClock, secondary intra-step timer, or multi-event dispatch from within a single Executor.tick.) This is the highest-risk architecture decision and must be answered before the spec can include sub-step intervals.

6. **Navigation depth for interval setting:** Is it acceptable that interval configuration requires navigating out of perform mode to layer settings, or does the first implementation need a quick-access control reachable from perform mode?
