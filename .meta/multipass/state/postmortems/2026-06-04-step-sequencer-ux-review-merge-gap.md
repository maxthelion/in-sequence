# Step Sequencer UX Review / Merge Gap

## What Happened

Step Sequencer Phase 2 was merged after all configured gates passed for exact
commit `e77e0f7`, then later product-owner review found that the Track Source
clip editor still contradicted important accepted intent: step editing still had
a modal/inspector path, the generic clip grid could not show selected state, and
the Variant D rotary-row interaction was not visible in that surface.

## Why It Got Through

- The final UX/IA pass reviewed a narrow Phase 2-H delta and accepted focused
  `UnifiedStepCell` render evidence because that delta touched coordinator/tests,
  not layout.
- Earlier Phase 2-G evidence did inspect a Track Source target screenshot, but
  the review did not prove that every production surface carrying the Step
  Sequencer grammar matched the accepted prototype and intent.
- The build-loop summary, project decider, and integrator all preserved the
  caveat that visual proof was focused rather than full app-window Peekaboo
  evidence, but treated it as residual risk after green gates.
- The merge decision checked exact-state gate pairing, branch cleanliness, and
  tests, but did not require a final UX intent/surface coverage statement before
  feature-complete integration.

## Systemic Lesson

For UX-oriented features, a phase delta can be reviewed narrowly, but final
feature acceptance must compare the whole intended production surface set
against the raw intent, accepted prototype, and user stories. Otherwise the
system can correctly verify the latest small change while missing that the
feature spirit never arrived in the actual app surface the user cares about.

## Process Tightening

The reusable multipass prompts now require:

- UX/IA reviews to include an Intent / Surface Coverage block.
- Build orientation to preserve UX coverage gaps as missing evidence or
  correction needs, not harmless residual risk.
- Build deciders to block feature-complete merge candidacy when UX coverage is
  partial for core user-facing intent.
- Integrators to stop before merging user-facing candidates that only have
  focused component evidence while intended production surfaces remain
  unchecked.

This should make the same failure much noisier next time without adding a
deterministic state machine.
