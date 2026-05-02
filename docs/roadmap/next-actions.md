# Roadmap Next Actions

Generated: 2026-05-02T17:47:43Z
Repo HEAD: f2089a4
Branch:    codex/tracks-perform-scenes-workspace

This is an experimental deterministic project-management scan. It does not build anything; it only infers the likely next planning action from files under `docs/roadmap/<feature-slug>/`.

Each roadmap item has front matter in its feature `README.md`: `id`, `title`, `status`, `priority`, `blocked_by`, `stage`, `owner`, and `updated`.

Planning actions after `clarify-feature` are intended for the `pm-assistant` role, except `review-concerns`, which requires user judgment. `clarify-feature`, `blocked`, and `review-concerns` require user input. `review-prototypes`, `review-architecture`, and `address-feedback` are PM-assistant actions. The global "Next Agent Item" prioritises unresolved feedback and review rework before ordinary artifact creation.

## Selector

For each feature, deferred status wins first, then unresolved feedback, then open concerns, then blocked metadata or open questions, then review-document verdicts requesting rework; otherwise the first missing artifact wins:

1. `status: deferred` -> deferred
2. unresolved `feedback/*.md` -> address-feedback
3. open `concerns.md` -> review-concerns
4. `status: blocked`, non-empty `blocked_by`, or `open-questions.md` -> blocked
5. `ux-review.md` with `verdict: needs-rework`/`rejected` -> `redirect_to` (default `build-prototypes`)
6. `architecture-review.md` with `verdict: needs-rework`/`rejected` -> `redirect_to` (default `write-architecture`)
7. `notes.md` -> clarify-feature
8. `user-stories.md` -> draft-user-stories
9. `existing-state.md` -> inspect-existing-state
10. `prototypes/*` -> build-prototypes
11. `ux-review.md` -> review-prototypes
12. `architecture.md` -> write-architecture
13. `architecture-review.md` -> review-architecture
14. `spec.md` -> write-spec
15. `plan.md` -> write-plan
16. `implementation-handoff.md` -> write-implementation-handoff
17. all present -> ready-for-build-queue

## Next User Item

- **Item:** 4
- **Feature:** Mixer Main Out
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `blocked`
- **Role:** `user`
- **Why:** Status is `inventory`, blocked_by is `[]`, or `open-questions.md` exists.
- **Output:** Answer the open questions or resolve the blocker before advancing this item.

## Next Agent Item

- **Item:** 8
- **Feature:** MIDI Interfaces
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `write-implementation-handoff`
- **Role:** `pm-assistant`
- **Why:** Plan exists, but `implementation-handoff.md` is missing.
- **Output:** Bundle the PM artifacts into a build-loop handoff that links authoritative context, guardrails, spec, plan, non-goals, and open questions.

## Feature Actions

### 1. Clip History

- **Directory:** `docs/roadmap/clip-history/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Planning artifacts are present.
- **Suggested output:** Promote the implementation handoff into the normal build queue when the user chooses.

### 2. Scene Perform

- **Directory:** `docs/roadmap/scene-perform/`
- **Status:** `ready-for-build`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Planning artifacts are present.
- **Suggested output:** Promote the implementation handoff into the normal build queue when the user chooses.

### 3. Step Sequencer

- **Directory:** `docs/roadmap/step-sequencer/`
- **Status:** `ready-for-build`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Planning artifacts are present.
- **Suggested output:** Promote the implementation handoff into the normal build queue when the user chooses.

### 4. Mixer Main Out

- **Directory:** `docs/roadmap/mixer-main-out/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `blocked`
- **Role:** `user`
- **Reason:** Status is `inventory`, blocked_by is `[]`, or `open-questions.md` exists.
- **Suggested output:** Answer the open questions or resolve the blocker before advancing this item.

### 5. Mixer Busses

- **Directory:** `docs/roadmap/mixer-busses/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `blocked`
- **Role:** `user`
- **Reason:** Status is `inventory`, blocked_by is `[]`, or `open-questions.md` exists.
- **Suggested output:** Answer the open questions or resolve the blocker before advancing this item.

### 6. Send Effects

- **Directory:** `docs/roadmap/send-effects/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `blocked`
- **Role:** `user`
- **Reason:** Status is `inventory`, blocked_by is `[]`, or `open-questions.md` exists.
- **Suggested output:** Answer the open questions or resolve the blocker before advancing this item.

### 7. Input Audio

- **Directory:** `docs/roadmap/input-audio/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `blocked`
- **Role:** `user`
- **Reason:** Status is `inventory`, blocked_by is `[]`, or `open-questions.md` exists.
- **Suggested output:** Answer the open questions or resolve the blocker before advancing this item.

### 8. MIDI Interfaces

- **Directory:** `docs/roadmap/midi-interfaces/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-implementation-handoff`
- **Role:** `pm-assistant`
- **Reason:** Plan exists, but `implementation-handoff.md` is missing.
- **Suggested output:** Bundle the PM artifacts into a build-loop handoff that links authoritative context, guardrails, spec, plan, non-goals, and open questions.

### 9. Modifier Chain Placement

- **Directory:** `docs/roadmap/modifier-chain-placement/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 10. Phrase Features

- **Directory:** `docs/roadmap/phrase-features/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 11. Song Mode And Phrase Looping

- **Directory:** `docs/roadmap/song-mode-phrase-looping/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 12. Drum Parts As A Group

- **Directory:** `docs/roadmap/drum-parts-as-group/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 13. Autoslice Algorithm

- **Directory:** `docs/roadmap/autoslice-algorithm/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 14. Audio Looping

- **Directory:** `docs/roadmap/audio-looping/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 15. Note Repeat

- **Directory:** `docs/roadmap/note-repeat/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 16. Step Order

- **Directory:** `docs/roadmap/step-order/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-architecture`
- **Role:** `pm-assistant`
- **Reason:** UX review exists, but `architecture.md` is missing.
- **Suggested output:** Write architecture guardrails before the feature spec: invariants, lightweight data/runtime shape, persistence boundaries, and risks.

### 17. Fill A Clip From Current Generator

- **Directory:** `docs/roadmap/fill-clip-from-generator/`
- **Status:** `deferred`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `deferred`
- **Role:** `pm`
- **Reason:** Status is `deferred`; this item is intentionally skipped for now.
- **Suggested output:** No action until the user reactivates this item.

### 18. Toggle Fill On A Track To Hear It

- **Directory:** `docs/roadmap/track-fill-toggle/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `review-concerns`
- **Role:** `user`
- **Reason:** `concerns.md` exists and is not resolved or archived.
- **Suggested output:** Review the concerns, decide whether they are accepted guardrails, open questions, or non-blocking notes, then update `concerns.md` before PM work continues.

### 19. Drum Kit Group View

- **Directory:** `docs/roadmap/drum-kit-group-view/`
- **Status:** `deferred`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `deferred`
- **Role:** `pm`
- **Reason:** Status is `deferred`; this item is intentionally skipped for now.
- **Suggested output:** No action until the user reactivates this item.

### 20. Fill Applied To Whole Kit

- **Directory:** `docs/roadmap/whole-kit-fill/`
- **Status:** `deferred`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `deferred`
- **Role:** `pm`
- **Reason:** Status is `deferred`; this item is intentionally skipped for now.
- **Suggested output:** No action until the user reactivates this item.

### 21. Observability From Application Logs

- **Directory:** `docs/roadmap/observability-log-issues/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `inspect-existing-state`
- **Role:** `pm-assistant`
- **Reason:** User stories exist, but `existing-state.md` is missing.
- **Suggested output:** Inspect code, docs, tests, screenshots, and prototypes; report model/UI gaps with file references.

### 22. Scenes In Phrases

- **Directory:** `docs/roadmap/scenes-in-phrases/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 23. Phrase Cells

- **Directory:** `docs/roadmap/phrase-cells/`
- **Status:** `deferred`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `deferred`
- **Role:** `pm`
- **Reason:** Status is `deferred`; this item is intentionally skipped for now.
- **Suggested output:** No action until the user reactivates this item.

### 24. Track Perform Multi-Select And Latch

- **Directory:** `docs/roadmap/track-perform-multiselect-latch/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

