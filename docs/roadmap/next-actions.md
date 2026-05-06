# Roadmap Next Actions

Generated: 2026-05-06T18:53:37Z
Repo HEAD: 3d9f266
Branch:    codex/tracks-perform-scenes-workspace

This is an experimental deterministic project-management scan. It does not build anything; it only infers the likely next planning action from files under `docs/roadmap/<feature-slug>/`.

Each roadmap item has front matter in its feature `README.md`: `id`, `title`, `status`, `priority`, `blocked_by`, `stage`, `owner`, and `updated`.

Planning actions after `clarify-feature` are intended for the `pm-assistant` role, except `review-concerns` and `human-review-prototypes`, which require user judgment. `clarify-feature`, `blocked`, `review-concerns`, and `human-review-prototypes` require user input. `review-prototypes`, `review-architecture`, and `address-feedback` are PM-assistant actions. The global "Next Agent Item" prioritises unresolved feedback and review rework before ordinary artifact creation.

## Selector

For each feature, deferred status wins first, then unresolved feedback, then open concerns, then blocked metadata or open questions, then review-document verdicts requesting rework, then ready-for-build state, then human prototype approval; otherwise the first missing artifact wins:

1. `status: deferred` -> deferred
2. unresolved `feedback/*.md` -> address-feedback
3. open `concerns.md` -> review-concerns
4. `status: blocked`, non-empty `blocked_by`, or `open-questions.md` -> blocked
5. `ux-review.md` with `verdict: needs-rework`/`rejected` -> `redirect_to` (default `build-prototypes`)
6. `status: ready-for-build` or `stage: ready-for-build(-queue)` -> ready-for-build-queue
7. accepted `ux-review.md` without approved `prototype-approval.md` -> human-review-prototypes
8. `prototype-approval.md` with `status: changes-requested`/`rejected` -> build-prototypes
9. `architecture-review.md` with `verdict: needs-rework`/`rejected` -> `redirect_to` (default `write-architecture`)
10. `notes.md` -> clarify-feature
11. `user-stories.md` -> draft-user-stories
12. `existing-state.md` -> inspect-existing-state
13. `prototypes/*` -> build-prototypes
14. `ux-review.md` -> review-prototypes
15. `architecture.md` -> write-architecture
16. `architecture-review.md` -> review-architecture
17. `spec.md` -> write-spec
18. `plan.md` -> write-plan
19. `implementation-handoff.md` -> write-implementation-handoff
20. all present -> ready-for-build-queue

## Next User Item

- **Item:** 7
- **Feature:** Input Audio
- **Priority:** `unset`
- **Status:** `inventory`
- **Action:** `human-review-prototypes`
- **Role:** `user`
- **Why:** `ux-review.md` exists, but human prototype approval is missing.
- **Output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

## Next Agent Item

- No roadmap items currently have an autonomous PM-assistant action.

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
- **Reason:** Feature is already marked `ready-for-build`/`ready-for-build`; PM artifacts have been handed off or are ready to hand off.
- **Suggested output:** Do not reopen PM prototype approval unless new feedback invalidates the approved direction. Let the build loop or promotion flow own this item.

### 3. Step Sequencer

- **Directory:** `docs/roadmap/step-sequencer/`
- **Status:** `ready-for-build`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Feature is already marked `ready-for-build`/`ready-for-build`; PM artifacts have been handed off or are ready to hand off.
- **Suggested output:** Do not reopen PM prototype approval unless new feedback invalidates the approved direction. Let the build loop or promotion flow own this item.

### 4. Mixer Main Out

- **Directory:** `docs/roadmap/mixer-main-out/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Feature is already marked `ready-for-build-queue`/`inventory`; PM artifacts have been handed off or are ready to hand off.
- **Suggested output:** Do not reopen PM prototype approval unless new feedback invalidates the approved direction. Let the build loop or promotion flow own this item.

### 5. Mixer Busses

- **Directory:** `docs/roadmap/mixer-busses/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Feature is already marked `ready-for-build-queue`/`inventory`; PM artifacts have been handed off or are ready to hand off.
- **Suggested output:** Do not reopen PM prototype approval unless new feedback invalidates the approved direction. Let the build loop or promotion flow own this item.

### 6. Send Effects

- **Directory:** `docs/roadmap/send-effects/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Planning artifacts are present.
- **Suggested output:** Promote the implementation handoff into the normal build queue when the user chooses.

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
- **Next action:** `ready-for-build-queue`
- **Role:** `pm`
- **Reason:** Feature is already marked `ready-for-build-queue`/`inventory`; PM artifacts have been handed off or are ready to hand off.
- **Suggested output:** Do not reopen PM prototype approval unless new feedback invalidates the approved direction. Let the build loop or promotion flow own this item.

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
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

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
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 22. Scenes In Phrases

- **Directory:** `docs/roadmap/scenes-in-phrases/`
- **Status:** `inventory`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

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
- **Next action:** `human-review-prototypes`
- **Role:** `user`
- **Reason:** `ux-review.md` exists, but human prototype approval is missing.
- **Suggested output:** Review the prototypes with `ux-review.md` as the PM pre-flight critique. Write `prototype-approval.md` with `status: approved` or capture feedback for another prototype pass.

### 25. Selective Scene Inputs

- **Directory:** `docs/roadmap/selective-scene-inputs/`
- **Status:** `deferred`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `deferred`
- **Role:** `pm`
- **Reason:** Status is `deferred`; this item is intentionally skipped for now.
- **Suggested output:** No action until the user reactivates this item.

### ?. agentic-loop

- **Directory:** `docs/roadmap/agentic-loop/`
- **Status:** `unknown`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### ?. lanes

- **Directory:** `docs/roadmap/lanes/`
- **Status:** `unknown`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### ?. probe-results

- **Directory:** `docs/roadmap/probe-results/`
- **Status:** `unknown`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

### ?. probes

- **Directory:** `docs/roadmap/probes/`
- **Status:** `unknown`
- **Priority:** `unset`
- **Blocked by:** `[]`
- **Next action:** `clarify-feature`
- **Role:** `user`
- **Reason:** No `notes.md` yet.
- **Suggested output:** Capture the brief user clarification: what feels wrong, what users are trying to achieve, what the model already gets right, and any constraints.

