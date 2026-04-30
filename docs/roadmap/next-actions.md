# Roadmap Next Actions

Generated: 2026-04-29T18:26:27Z
Repo HEAD: 39aafb1
Branch:    codex/tracks-perform-scenes-workspace

This is an experimental deterministic project-management scan. It does not build anything; it only infers the likely next planning action from files under `docs/roadmap/<feature-slug>/`.

Each roadmap item has front matter in its feature `README.md`: `id`, `title`, `status`, `priority`, `blocked_by`, `stage`, `owner`, and `updated`.

Planning actions after `clarify-feature` are intended for the `pm-assistant` role, except `review-prototypes` and `review-architecture`, which require user judgment. `clarify-feature`, `blocked`, `review-prototypes`, and `review-architecture` require user input.

## Selector

For each feature, deferred status wins first, then blocked metadata or open questions; otherwise the first missing artifact wins:

1. `status: deferred` -> deferred
2. `status: blocked`, non-empty `blocked_by`, or `open-questions.md` -> blocked
3. `notes.md` -> clarify-feature
4. `user-stories.md` -> draft-user-stories
5. `existing-state.md` -> inspect-existing-state
6. `prototypes/*` -> build-prototypes
7. `ux-review.md` -> review-prototypes
8. `architecture.md` -> write-architecture
9. `architecture-review.md` -> review-architecture
10. `spec.md` -> write-spec
11. `plan.md` -> write-plan
12. `implementation-handoff.md` -> write-implementation-handoff
13. all present -> ready-for-build-queue

## Next User Item

- **Item:** 2
- **Feature:** Scene Perform
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `review-prototypes`
- **Role:** `user`
- **Why:** Prototype artifacts exist, but `ux-review.md` is missing.
- **Output:** Review variants against the UX checklist and choose or reject a direction.

## Next Agent Item

- **Item:** 6
- **Feature:** Send Effects
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `build-prototypes`
- **Role:** `pm-assistant`
- **Why:** Existing-state report exists, but no prototype artifact was found in `prototypes/`.
- **Output:** Create focused Balsamiq-style HTML prototypes under this feature directory.

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
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `review-prototypes`
- **Role:** `user`
- **Reason:** Prototype artifacts exist, but `ux-review.md` is missing.
- **Suggested output:** Review variants against the UX checklist and choose or reject a direction.

### 3. Step Sequencer

- **Directory:** `docs/roadmap/step-sequencer/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `review-prototypes`
- **Role:** `user`
- **Reason:** Prototype artifacts exist, but `ux-review.md` is missing.
- **Suggested output:** Review variants against the UX checklist and choose or reject a direction.

### 4. Mixer Main Out

- **Directory:** `docs/roadmap/mixer-main-out/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `review-prototypes`
- **Role:** `user`
- **Reason:** Prototype artifacts exist, but `ux-review.md` is missing.
- **Suggested output:** Review variants against the UX checklist and choose or reject a direction.

### 5. Mixer Busses

- **Directory:** `docs/roadmap/mixer-busses/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `review-prototypes`
- **Role:** `user`
- **Reason:** Prototype artifacts exist, but `ux-review.md` is missing.
- **Suggested output:** Review variants against the UX checklist and choose or reject a direction.

### 6. Send Effects

- **Directory:** `docs/roadmap/send-effects/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `build-prototypes`
- **Role:** `pm-assistant`
- **Reason:** Existing-state report exists, but no prototype artifact was found in `prototypes/`.
- **Suggested output:** Create focused Balsamiq-style HTML prototypes under this feature directory.

### 7. Input Audio

- **Directory:** `docs/roadmap/input-audio/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 8. MIDI Interfaces

- **Directory:** `docs/roadmap/midi-interfaces/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 9. Modifier Chain Placement

- **Directory:** `docs/roadmap/modifier-chain-placement/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 10. Phrase Features

- **Directory:** `docs/roadmap/phrase-features/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 11. Song Mode And Phrase Looping

- **Directory:** `docs/roadmap/song-mode-phrase-looping/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 12. Drum Parts As A Group

- **Directory:** `docs/roadmap/drum-parts-as-group/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 13. Autoslice Algorithm

- **Directory:** `docs/roadmap/autoslice-algorithm/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 14. Audio Looping

- **Directory:** `docs/roadmap/audio-looping/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 15. Note Repeat

- **Directory:** `docs/roadmap/note-repeat/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 16. Step Order

- **Directory:** `docs/roadmap/step-order/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

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
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

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

