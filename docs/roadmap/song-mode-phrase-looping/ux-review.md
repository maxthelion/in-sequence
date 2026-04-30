---
verdict: accepted
selected_prototype: 01-transport-phrase-indicator.html (primary) + 02-tracks-basis-phrase-tracking.html (Story 5 companion)
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/01-transport-phrase-indicator.html
  - prototypes/02-tracks-basis-phrase-tracking.html
feedback_applied: []
---

# UX Review — Song Mode And Phrase Looping

## Summary

Both prototypes are coherent, focused, and address all five user stories without producing an over-polished artifact. The interaction design is sound for the stated MVP scope. The open questions they surface are well-formed and appropriate for clarification at spec time. The two prototypes are complementary rather than competing — prototype 01 owns Stories 1–4 (transport bar) and prototype 02 owns Story 5 (Tracks UI basis phrase). The recommended direction is to adopt both as the design basis.

---

## Per-Prototype Evaluation

### Prototype 01 — `01-transport-phrase-indicator.html` (Stories 1–4)

#### What works

**Story 1 — Current-phrase indicator.** The "Now / Phrase B (Verse Drop)" group with a cycle-progress bar is clear and immediately readable. The progress bar uses the same blue as the active-phrase name, so the visual relationship between "which phrase" and "how far through" is natural. The empty/stopped state (Scenario A) correctly disables the queue button and shows "— none —" — this is the right empty-state treatment.

**Story 2 — Queue next phrase via dropdown.** The two-interaction budget is delivered: tap "Queue" button, tap "Queue" in a row. The dropdown header is explicit ("Choose next phrase — queue or switch immediately"). The amber colour on queued rows is distinct from the blue active state. Replacing the "Queue" button text with "Queued ✓" on the queued row is an effective confirmation affordance that does not add a separate status element.

**Story 3 — End-of-cycle switch.** Scenario C (static reference) correctly shows the full concurrent state: current phrase in blue, queued phrase in amber on the button, end-of-cycle annotation inline ("at end of cycle"). The cycle-animation in Scenario B demonstrates the automatic end-of-cycle transition, including queue clearing and label update. The transport bar button name change from "Queue ↓" to "Phrase C (Chorus) ↓" (with truncation) gives persistent visibility of the queued state without requiring the dropdown to be open.

**Story 4 — Immediate switch.** The "Now" button column in the dropdown is clearly distinct from the "Queue" column using red (`#cc3300`) against the default neutral tone. The `switchNow()` JS handler correctly resets the cycle bar and clears any pending queue, demonstrating that an immediate switch cancels an in-flight queue.

**Fixture data.** "Phrase D (Outro / Bridge Reprise)" is the adversarial long-name fixture. The prototype exercises truncation in the queue button and overflow in the dropdown name cell — the prototype acknowledges this as open question 5 rather than silently ignoring it.

**Stub treatment.** REC button, BPM slider, transport-position readout, and mode toggle are all stubbed and unmistakably greyed/labeled. The reviewer cannot mistake them for interactive.

#### What fails or is unclear

**No "cancel queue" path.** Open question 2 in the prototype notes that there is no explicit cancel: re-queuing a different phrase is the only cancellation. During a live performance this is acceptable, but if the performer changes their mind and wants to cancel without substituting another phrase, they have no affordance. The prototype explicitly acknowledges this; it should be resolved at spec time.

**Dropdown dismiss behaviour on "Now" is unresolved.** The prototype closes the dropdown on "Now" (immediately). Open question 1 flags this for confirmation. Both approaches — close immediately vs. stay open to show the updated state — have merit. This is the right question to escalate rather than guess.

**Long queued-phrase name in transport button.** The truncation logic (22 characters) is a reasonable heuristic but arbitrary. The alternative (show only a count or icon when queued) is worth exploring at spec time, especially as the transport bar is already crowded. The prototype flags this correctly.

**Queue button crowding.** The transport bar already holds: play, REC stub, BPM, mode toggle, phrase indicator (Now), queue segment (Next + button + EOC annotation), position, and activity dot. Adding a queued-phrase name inline in the Next button may overflow small display widths. The prototype does not provide a narrow-viewport test scenario. This should be addressed in the spec.

**Stopped-state queue button interaction.** Scenario A shows the queue button as `opacity:.4;cursor:default` — visually disabled but without explicit ARIA or a tooltip explaining why. The tooltip title attribute is present in HTML but would not render in production SwiftUI. The spec should define the disabled treatment.

#### Checklist

- [ ] Empty / stopped state covered: YES (Scenario A)
- [ ] Primary happy path covered: YES (Scenario B interactive)
- [ ] Concurrent-state reference: YES (Scenario C static)
- [ ] Adversarial fixture data used: YES (long phrase name, 4 phrases)
- [ ] Stubs clearly marked: YES
- [ ] Interaction budget stated and verified: YES (2 interactions for queue, 2 for immediate)
- [ ] Open questions documented in the artifact: YES (5 questions)
- [ ] Color used semantically only: YES
- [ ] Single primary action per affordance: YES (Queue and Now are clearly separated)

#### Story coverage

| Story | Covered | Notes |
|-------|---------|-------|
| 1. Current-phrase indicator | Yes | Scenario A (stopped), B (playing) |
| 2. Queue next phrase via dropdown | Yes | Scenario B interactive |
| 3. End-of-cycle switch | Yes | Scenario B animation + Scenario C static |
| 4. Immediate switch from dropdown | Yes | Scenario B "Now" button |
| 5. Tracks UI basis phrase follows free-play | Stubbed | Prototype 02 owns this |

---

### Prototype 02 — `02-tracks-basis-phrase-tracking.html` (Story 5)

#### What works

**Story 5 — Basis phrase follows cue and switch.** The demo is driven by explicit control buttons ("Queue: Phrase B", "Switch now: Phrase C", "Simulate end-of-cycle", "Reset") which makes every state reachable without depending on a tick clock. The basis-phrase banner updates visually on queue (amber, "queued preview" pill) and on switch (blue, confirmed). The grid step-data re-renders per phrase using distinct patterns — the reviewer can see that edits would land in the correct phrase.

**Three-state static reference.** State 1 (playing, no queue), State 2 (playing A, queued C — preview), and State 3 (after switch to C) are rendered side by side. This answers the core product question: queuing immediately updates the Tracks UI to the queued phrase so the performer can preview or edit it before it plays.

**Architecture note in prototype.** The annotation box at the bottom of the three-state reference documents the two implementation options (new `basisPhraseID` on `EngineController` vs. mutating `selectedPhraseID`). This is exactly the right place to surface this: as a visible decision point for the architecture pass, not as an implementation detail buried in a spec.

**Flash animation on basis-phrase change.** The yellow row-flash on grid rows when the basis phrase changes communicates "something updated" without being distracting. This is a good lightweight signal that the grid re-loaded.

**Transport stub shows queued state.** The transport bar stub in the interactive demo shows the "Next: [pill]" queue indicator when a phrase is queued, keeping the cross-prototype story coherent.

#### What fails or is unclear

**Open question 2 — edits to the queued basis phrase before cancel.** If the performer queues Phrase C, the Tracks UI switches to show Phrase C's pattern, and the performer edits steps there — then cancels the queue — those edits are already written to Phrase C (there is no staging layer). The prototype raises this correctly as open question 2, referencing the Phrase Features story-4 staging gap. This is a genuine product risk that should be addressed explicitly in the spec: either the UI must warn before allowing edits on a queued-but-not-yet-active phrase, or the spec must accept the edit-lands-immediately semantics.

**Open question 4 — grid scroll/resize when basis phrase changes.** The prototype assumes all phrases have the same bar count. A real project where Phrase D has 16 bars and Phrase A has 4 bars would require the grid to resize or scroll. The prototype explicitly defers this. The spec should either handle multi-bar-count phrases or declare same-length as an MVP constraint.

**"Basis" label vs. the existing "Basis Phrase" panel.** The artifacts.md screenshot mentions an existing top-right "Basis Phrase" panel with a "Perform" button. The prototype renders the basis label as a row inside the track-labels column. These two placements will need to be reconciled: the spec should decide whether this feature updates the existing top-right panel, or introduces a new inline label. The prototype's left-column placement does not match the artifact screenshot, but neither is wrong — they are different layout hypotheses that should be resolved.

**No explicit "what happens when playback is stopped" state for the basis phrase.** The demo starts playing. If playback stops while a phrase is queued, the basis phrase should presumably revert to the selected phrase. This state is not demonstrated.

#### Checklist

- [ ] Story 5 happy path covered: YES (interactive demo drives all transitions)
- [ ] Three distinct states covered: YES (static reference)
- [ ] Cross-prototype coherence with prototype 01: YES (transport stub mirrors prototype 01 design)
- [ ] Architecture decision surfaced: YES (basisPhraseID option documented)
- [ ] Adversarial fixture data: PARTIAL (long phrase name present; same-bar-count assumption not stressed)
- [ ] Stubs clearly marked: YES (step-grid content explicitly labeled as "... (8 bars)")
- [ ] Open questions documented: YES (4 questions)

#### Story coverage

| Story | Covered | Notes |
|-------|---------|-------|
| 5. Tracks UI basis phrase follows free-play | Yes | Queue → preview, switch → confirm, end-of-cycle → confirm |

---

## Cross-Prototype Issues

**Prototype 01 does not show the basis-phrase update.** When a "Now" switch or end-of-cycle event fires in Prototype 01's Scenario B, the log updates but there is no indication that the Tracks UI below has also changed. For a reviewer who has not seen Prototype 02, this connection is invisible. The spec should explicitly link the two events (phrase switch → basis-phrase update) so implementers wire them as a single atomic event, not two separate side-effects.

**Color palette is consistent across both prototypes.** Blue (`#0060df`) = currently playing, Amber (`#e8a000`) = queued/preview, Red (`#cc3300`) = immediate switch. This three-color vocabulary should be carried into the spec as the semantic encoding for phrase-state.

**The interaction budget is only stated in Prototype 01.** Prototype 02 states "zero extra interactions required" correctly for Story 5 (it is automatic), but the interaction budget box is absent in Prototype 02. This is acceptable since Story 5 has no user-initiated interactions; noting it here for the spec author.

---

## Open Questions From Prototypes — Recommended Handling

These should be transferred to `open-questions.md` or resolved in the spec.

| # | Question | Recommended action |
|---|----------|--------------------|
| 1 | Does "Now" dismiss the dropdown? | Decide at spec: recommend yes (simpler, avoids stale open dropdown during playback) |
| 2 | Can the performer cancel a queue without substituting another phrase? | Decide at spec: add a dedicated clear/cancel affordance or accept re-queue-only |
| 3 | Does tapping outside the dropdown dismiss it? | Decide at spec: recommend yes with swiftUI equivalent gesture handling |
| 4 | Cycle-progress granularity: per-bar or per-step? | Recommend per-bar for MVP; per-step is a refinement |
| 5 | Long queued-phrase name in queue button | Decide at spec: recommend icon + short name or truncate at ~16 chars |
| P02-1 | Does queuing immediately update the Tracks UI basis phrase? | Yes — prototypes answer this; carry into spec |
| P02-2 | Edits to queued basis phrase before cancel | Must be addressed in spec; risk is data loss if performer cancels queue |
| P02-3 | Basis-phrase banner in song mode (auto-cycle)? | Defer to song-mode scripted-arrangement feature; note in spec as out of scope for this item |
| P02-4 | Grid resize when phrases have different bar counts | Declare as MVP constraint: phrases assumed same bar count; revisit post-MVP |

---

## Recommended Direction

**Adopt both prototypes as the design basis.** There is no competing direction — the two prototypes address different stories and are designed to be complementary.

**Prototype 01** defines the transport-bar layout: Now label + cycle-bar + Next queue button with inline queued-phrase name, dropdown with Queue and Now columns per row.

**Prototype 02** defines the Tracks UI basis-phrase update rule: queuing a phrase immediately previews it in the Tracks UI; switching confirms it. The left-column "Basis:" banner placement should be reconciled against the existing top-right "Basis Phrase" panel (from artifacts.md) at spec time.

**Architecture decision required before spec is final.** The spec must resolve whether the basis-phrase state flows through a new `EngineController.basisPhraseID` observable or through a mutation to `session.store.selectedPhraseID`. Prototype 02 correctly identifies this as the pivotal question. The architecture pass should answer it.

**Do not enter the architecture pass with open questions 2 (cancel queue) and P02-2 (edits to queued phrase) unresolved.** Both carry product risk. They should either be answered by the user or explicitly declared as deferred with the simplest safe default (re-queue-only cancel; no staging layer warning in MVP).

---

## Next Action

Proceed to `write-architecture`. The architecture pass should focus on:

1. Where `currentPhraseID` and `queuedPhraseID` live (EngineController vs. document model).
2. How `basisPhraseID` is derived and published to views.
3. The phrase-boundary event mechanism (`prepareTick` hook vs. observer callback).
4. Whether the Tracks UI basis phrase update should be a separate observable or the same mutation path as `selectedPhraseID`.
5. Deduplication of the three-view `playbackPhraseIndex` derivation (existing-state gap).
