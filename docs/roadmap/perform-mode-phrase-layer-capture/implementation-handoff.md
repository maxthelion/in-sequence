---
feature: perform-mode-phrase-layer-capture
status: ready-for-build-loop-promotion
stage: implementation-handoff
updated: 2026-06-18
sources:
  - README.md
  - docs/roadmap/perform-mode-phrase-layer-capture/architecture.md
  - docs/roadmap/perform-mode-phrase-layer-capture/spec.md
  - docs/roadmap/perform-mode-phrase-layer-capture/plan.md
  - docs/roadmap/perform-mode-phrase-layer-capture/reasoning-v3.md
  - docs/roadmap/perform-mode-phrase-layer-capture/prototypes/05-phrase-value-cell-system-v3.html
---

# Perform Mode, Phrase Layers, And Capture Implementation Handoff

## Purpose

This handoff packages the accepted V3 phrase-performance wireframe into
builder-ready scope. The build loop should implement the product/data/UI
contract, not blindly recreate the HTML.

The central outcome is:

> Phrase is the active performance context. Perform edits a temporary phrase
> copy. Capture saves that modified phrase to a chosen phrase matrix
> destination.

## Authoritative Artifacts

| Artifact | Builder Use |
|---|---|
| `spec.md` | Primary pass/fail behavior and acceptance contract. |
| `architecture.md` | Data, engine, ownership, and reuse guardrails. |
| `plan.md` | Suggested implementation sequence and first slice. |
| `reasoning-v3.md` | Rationale behind the V3 IA changes. |
| `prototypes/05-phrase-value-cell-system-v3.html` | Low-fidelity visual reference and interaction intent. |
| `feedback/` | Product-owner corrections that led to V3. |

## Build-Loop Boundary

Implement:

- transport current/next phrase and phrase progress;
- phrase-local shell with Perform, dirty summary, Capture, Discard, and latch
  timing;
- Layers tab with matrix-first layer editing and automation mode;
- Global Apply tab with scoped multi-track matrix actions;
- Scenes tab using the current scene perform A/B/crossfader grammar;
- Capture Phrase destination chooser only;
- phrase baseline versus live perform copy/overlay behavior;
- visual and interaction evidence for the above.

Do not implement:

- performance groups;
- Capture Clip redesign;
- generic Cell Detail page;
- full continuous scene automation;
- cue-output preview;
- unrelated track routing/source redesign.

## First Builder Request

The first builder request should implement or scaffold the backbone only:

- current/next phrase display in transport;
- phrase shell with Perform Off/On;
- live perform copy/overlay state boundary;
- Capture and Discard visible but disabled when Perform is off;
- latch timing controls active only when Latch is selected.

The first slice should include focused tests or characterization checks for the
baseline-versus-perform-copy boundary before extending the feature to every
surface.

## Definition Of Done

The build loop may only declare this feature done when:

- every acceptance criterion in `spec.md` is marked pass or explicitly deferred;
- architecture review confirms a single phrase-resolution path;
- UX/IA review confirms no hybrid of old global controls and new phrase-local
  controls;
- visual review evidence covers transport, phrase shell, Layers, Global Apply,
  Scenes, and Capture Phrase;
- testing review confirms phrase baseline, perform overlay, capture, discard,
  Moment, and Latch behavior are covered at useful seams;
- the anti-hybrid checklist in `spec.md` has no failures.

## Human Escalation

Escalate only if the implementation discovers a product decision not already
covered by the handoff, such as:

- whether perform overlay edits should mark the document dirty before capture;
- whether capture replacing the current phrase needs a confirmation step;
- whether current documents cannot represent phrase value cells without a
  broader migration.

Do not escalate just because the wireframe labels do not map one-to-one to
production controls. Reuse the current app's UI grammar where the intent is
clear.
