# Roadmap Next Actions

Generated: 2026-04-29T13:52:41Z
Repo HEAD: 1ae6385
Branch:    codex/tracks-perform-scenes-workspace

This is an experimental deterministic project-management scan. It does not build anything; it only infers the likely next planning action from files under `docs/roadmap/<feature-slug>/`.

Each roadmap item has front matter in its feature `README.md`: `id`, `title`, `status`, `priority`, `blocked_by`, `stage`, `owner`, and `updated`.

Planning actions after `clarify-feature` are intended for the `pm-assistant` role, except `review-prototypes` and `review-architecture`, which require user judgment. `clarify-feature`, `blocked`, `review-prototypes`, and `review-architecture` require user input.

## Selector

For each feature, blocked metadata or open questions win first; otherwise the first missing artifact wins:

1. `status: blocked`, non-empty `blocked_by`, or `open-questions.md` -> blocked
2. `notes.md` -> clarify-feature
3. `user-stories.md` -> draft-user-stories
4. `existing-state.md` -> inspect-existing-state
5. `prototypes/*` -> build-prototypes
6. `ux-review.md` -> review-prototypes
7. `architecture.md` -> write-architecture
8. `architecture-review.md` -> review-architecture
9. `spec.md` -> write-spec
10. `plan.md` -> write-plan
11. `implementation-handoff.md` -> write-implementation-handoff
12. all present -> ready-for-build-queue

## Next User Item

- **Item:** 17
- **Feature:** Fill A Clip From Current Generator
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `clarify-feature`
- **Role:** `user`
- **Why:** No `notes.md` yet.
- **Output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

## Next Agent Item

- **Item:** 1
- **Feature:** Clip History
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `write-spec`
- **Role:** `pm-assistant`
- **Why:** Architecture review exists, but `spec.md` is missing.
- **Output:** Write the feature specification from the selected prototype direction and reviewed architecture guardrails.

## Feature Actions

### 1. Clip History

- **Directory:** `docs/roadmap/clip-history/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `write-spec`
- **Role:** `pm-assistant`
- **Reason:** Architecture review exists, but `spec.md` is missing.
- **Suggested output:** Write the feature specification from the selected prototype direction and reviewed architecture guardrails.

### 2. Scene Perform

- **Directory:** `docs/roadmap/scene-perform/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 3. Step Sequencer

- **Directory:** `docs/roadmap/step-sequencer/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `inspect-existing-state`
- **Role:** `pm-assistant`
- **Reason:** User stories exist, but `existing-state.md` is missing.
- **Suggested output:** Inspect code, docs, tests, screenshots, and prototypes; report model/UI gaps with file references.

### 4. Mixer Main Out

- **Directory:** `docs/roadmap/mixer-main-out/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 5. Mixer Busses

- **Directory:** `docs/roadmap/mixer-busses/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

### 6. Send Effects

- **Directory:** `docs/roadmap/send-effects/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `draft-user-stories`
- **Role:** `pm-assistant`
- **Reason:** `notes.md` exists, but `user-stories.md` is missing.
- **Suggested output:** Run a background PM pass. Write `user-stories.md`, or create `open-questions.md` and mark the feature blocked if the notes are too thin.

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
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### 18. Toggle Fill On A Track To Hear It

- **Directory:** `docs/roadmap/track-fill-toggle/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### 19. Drum Kit Group View

- **Directory:** `docs/roadmap/drum-kit-group-view/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### 20. Fill Applied To Whole Kit

- **Directory:** `docs/roadmap/whole-kit-fill/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

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
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### 23. Phrase Cells

- **Directory:** `docs/roadmap/phrase-cells/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### 24. Track Perform Multi-Select And Latch

- **Directory:** `docs/roadmap/track-perform-multiselect-latch/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

