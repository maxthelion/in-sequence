# Roadmap Next Actions

Generated: 2026-05-03T11:33:40Z
Repo HEAD: a3bd630
Branch:    codex/tracks-perform-scenes-workspace

This is an experimental deterministic project-management scan. It does not build anything; it only infers the likely next planning action from files under `docs/roadmap/<feature-slug>/`.

Each roadmap item has front matter in its feature `README.md`: `id`, `title`, `status`, `priority`, `blocked_by`, `stage`, `owner`, and `updated`.

Planning actions after `clarify-feature` are intended for the `pm-assistant` role, except `review-concerns` and `human-review-prototypes`, which require user judgment. `clarify-feature`, `blocked`, `review-concerns`, and `human-review-prototypes` require user input. `review-prototypes`, `review-architecture`, and `address-feedback` are PM-assistant actions. The global "Next Agent Item" prioritises unresolved feedback and review rework before ordinary artifact creation.

## Selector

For each feature, deferred status wins first, then unresolved feedback, then open concerns, then blocked metadata or open questions, then review-document verdicts requesting rework, then human prototype approval; otherwise the first missing artifact wins:

1. `status: deferred` -> deferred
2. unresolved `feedback/*.md` -> address-feedback
3. open `concerns.md` -> review-concerns
4. `status: blocked`, non-empty `blocked_by`, or `open-questions.md` -> blocked
5. `ux-review.md` with `verdict: needs-rework`/`rejected` -> `redirect_to` (default `build-prototypes`)
6. accepted `ux-review.md` without approved `prototype-approval.md` -> human-review-prototypes
7. `prototype-approval.md` with `status: changes-requested`/`rejected` -> build-prototypes
8. `architecture-review.md` with `verdict: needs-rework`/`rejected` -> `redirect_to` (default `write-architecture`)
9. `notes.md` -> clarify-feature
10. `user-stories.md` -> draft-user-stories
11. `existing-state.md` -> inspect-existing-state
12. `prototypes/*` -> build-prototypes
13. `ux-review.md` -> review-prototypes
14. `architecture.md` -> write-architecture
15. `architecture-review.md` -> review-architecture
16. `spec.md` -> write-spec
17. `plan.md` -> write-plan
18. `implementation-handoff.md` -> write-implementation-handoff
19. all present -> ready-for-build-queue

## Next User Item

- **Item:** 1
- **Feature:** Clip History
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `human-review-prototypes`
- **Role:** `user`
- **Why:** `ux-review.md` exists, but human prototype approval is missing.
- **Output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

## Next Agent Item

- **Item:** 18
- **Feature:** Toggle Fill On A Track To Hear It
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `review-prototypes`
- **Role:** `pm-assistant`
- **Why:** Prototype artifacts exist, but `ux-review.md` is missing.
- **Output:** Review variants against the UX checklist and choose or reject a direction.

## Feature Actions

### 1. Clip History

- **Directory:** `docs/roadmap/clip-history/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 2. Scene Perform

- **Directory:** `docs/roadmap/scene-perform/`
- **Status:** `ready-for-build`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 3. Step Sequencer

- **Directory:** `docs/roadmap/step-sequencer/`
- **Status:** `ready-for-build`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 4. Mixer Main Out

- **Directory:** `docs/roadmap/mixer-main-out/`
- **Status:** `blocked`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `blocked`
- **Role:** `user`
- **Reason:** Status is `blocked`, blocked_by is `[]`, or `open-questions.md` exists.
- **Suggested output:** Answer the open questions or resolve the blocker before advancing this item.

### 5. Mixer Busses

- **Directory:** `docs/roadmap/mixer-busses/`
- **Status:** `blocked`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `blocked`
- **Role:** `user`
- **Reason:** Status is `blocked`, blocked_by is `[]`, or `open-questions.md` exists.
- **Suggested output:** Answer the open questions or resolve the blocker before advancing this item.

### 6. Send Effects

- **Directory:** `docs/roadmap/send-effects/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 7. Input Audio

- **Directory:** `docs/roadmap/input-audio/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 8. MIDI Interfaces

- **Directory:** `docs/roadmap/midi-interfaces/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 9. Modifier Chain Placement

- **Directory:** `docs/roadmap/modifier-chain-placement/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 10. Phrase Features

- **Directory:** `docs/roadmap/phrase-features/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 11. Song Mode And Phrase Looping

- **Directory:** `docs/roadmap/song-mode-phrase-looping/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 12. Drum Parts As A Group

- **Directory:** `docs/roadmap/drum-parts-as-group/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 13. Autoslice Algorithm

- **Directory:** `docs/roadmap/autoslice-algorithm/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 14. Audio Looping

- **Directory:** `docs/roadmap/audio-looping/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 15. Note Repeat

- **Directory:** `docs/roadmap/note-repeat/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 16. Step Order

- **Directory:** `docs/roadmap/step-order/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

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
- **Next action:** `review-prototypes`
- **Role:** `pm-assistant`
- **Reason:** Prototype artifacts exist, but `ux-review.md` is missing.
- **Suggested output:** Review variants against the UX checklist and choose or reject a direction.

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
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 25. Selective Scene Inputs

- **Directory:** `docs/roadmap/selective-scene-inputs/`
- **Status:** `deferred`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `deferred`
- **Role:** `pm`
- **Reason:** Status is `deferred`; this item is intentionally skipped for now.
- **Suggested output:** No action until the user reactivates this item.

