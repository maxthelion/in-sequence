---
verdict: accepted
selected_prototype: prototypes/clip-history-dual-grid-v4.html
reviewed: 2026-05-04
prototypes_reviewed:
  - prototypes/clip-history-dual-grid-v3.html
  - prototypes/clip-history-dual-grid-v4.html
feedback_applied:
  - feedback/2026-05-04-built-modal-ux-review.md
---

# Clip History UX Review

## What Works

### clip-history-dual-grid-v4.html (selected direction)

The v4 prototype resolves the main failure from the rejected build and archived review: the feature now reads as a transfer from frozen recent history into a committed pattern slot instead of "save the latest capture." The left and right 4x4 matrices have equal visual weight, the footer keeps save disabled until both sides of the transfer are explicit, and the preview copy repeatedly states that audition is temporary and does not mutate the document. That directly supports [[story:2]], [[story:3]], [[story:5]], and [[story:6]].

The surrounding source-editor shell is materially stronger than v3. It keeps the current pattern-slot row, generator-source section, parameter stubs, and generated-notes preview visible enough to show where Clip History enters the app without pretending the whole feature lives on an isolated mock screen. That makes the modal feel attached to the real workflow described in [[story:1]] instead of floating above an underspecified editor.

The empty-history, disabled-save, and occupied-slot fixtures are all reachable without changing the core layout. That matters because the previous review explicitly called out state coverage and layout stability as requirements. The title area also carries the frozen-snapshot cue and minimum-size promise, which is the right UX contract to hand into architecture after the beachball and cropping regressions from the built modal.

### clip-history-dual-grid-v3.html (useful comparison, not selected)

v3 established the corrected interaction model and should be kept as the bridge between the rejected build and the selected direction. It already proved the symmetric source/destination transfer, temporary preview, and overwrite gating.

Its weakness is contextual rather than structural: the generator area is more abstract, the entry point reads as already-open state instead of an app affordance, and the prototype does less to distinguish clip-history audition from the existing generated-notes preview. v4 keeps the same interaction model while grounding it better in the product shell, so it is the better artifact for human approval.

## What Fails Or Needs Follow-Up

### 1. History-cell legibility still needs human judgment

The matrices prove the interaction model, but the tiny note previews inside each history cell are intentionally rough. The human review should focus on whether the combination of relative-time labels, density preview, and per-cell summaries is enough to identify "the musical moment I want" without overloading the modal.

### 2. Length choices need spec confirmation

The prototype offers `1 bar`, `2 bars`, `4 bars`, and `8 steps`. [[story:4]] establishes that length must be adjustable, but it does not lock the allowed set. Human review should confirm whether `8 steps` belongs in the first release or whether the control should stay on bar-based phrases only.

### 3. Naming belongs below the core decision path

The clip-naming chooser is acceptable as a stubbed downstream choice, but it should stay clearly secondary. If future passes make naming feel required before save, the modal risks regressing from the tight source -> destination capture path that this review is approving.

## UX Checklist

| Criterion | Result |
|---|---|
| Modal pattern preserved from prior accepted direction | Pass |
| Source history and destination slots read as symmetrical transfer | Pass |
| Temporary audition stays distinct from committed document state | Pass |
| Save remains gated behind explicit source and destination choice | Pass |
| Occupied-slot overwrite path is visible | Pass |
| Empty / disabled / occupied states are reachable | Pass |
| Prototype is clearly non-production and path-focused | Pass |
| App context is visible enough to judge entry and exit points | Pass |

## User-Story Goal Coverage

| Story | Coverage |
|---|---|
| 1. Capture a good generated moment | Covered by the source-editor entry point and modal framing |
| 2. Review recent generated output | Covered by the frozen 4x4 Recent History matrix |
| 3. Audition history as a predictable clip | Covered by the Virtual Clip Preview and temporary-state copy |
| 4. Adjust the capture length | Covered by the preview length controls; option set needs confirmation |
| 5. Save history to a pattern slot | Covered by the destination matrix and Save footer flow |
| 6. Avoid accidental loss or overwrite | Covered by disabled save, occupied-slot fixture, and overwrite confirmation copy |

## Recommended Direction

Accept `prototypes/clip-history-dual-grid-v4.html` as the prototype to take into human review. It keeps the corrected modal transfer model from the rework brief, restores product context that the earlier prototype pass lacked, and covers the adversarial states that were missing or regressed in the built modal.

Keep `prototypes/clip-history-dual-grid-v3.html` as an archived comparison artifact, not as the handoff target. Its role is to show the interaction-model correction; v4 is the clearer expression of how that model fits the current app shell.

## Human Review Focus

1. Confirm that the history-cell labeling and tiny previews make it easy to pick the intended musical region.
2. Confirm whether the allowed length menu should include `8 steps` in v1.
3. Confirm that the source-editor shell gives enough context without distracting from the modal.
4. Confirm that the occupied-slot confirmation language is strong enough before save unlocks.
