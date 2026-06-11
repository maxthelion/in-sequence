# Track Fill Toggle Prototype Approval

- approved: 2026-05-03
- packaged: 2026-06-04
- selected prototype: `prototypes/01-header-toggle.html`
- rejected comparison: `prototypes/02-lane-toolbar-toggle.html`
- source UX review: `ux-review.md`
- decision status: accepted for v1 PM design basis; not yet an implementation handoff

## Approved Direction

Use the header-toggle prototype as the v1 direction for Track Fill Toggle.

The fill preview control belongs in the track editor header area beside the
`Source` / `Modifiers` controls, not inside the clip lane toolbar. This frames
the control as transient playback state for the selected track rather than as a
lane-authoring or phrase-editing mode.

The approved interaction model is:

- default state is preview off for the selected track;
- one click enables fill preview for the selected clip-backed track;
- active state is visually distinct and status copy names that the user is
  hearing the fill lane for this track only;
- switching to another track resets preview to off;
- closing the editor must also reset preview to off;
- generator-backed tracks show the control as unavailable with nearby copy
  explaining that fill preview applies to clip-backed tracks only in v1.

## Why Header Placement Was Accepted

The selected prototype best protects the central product requirement: previewing
fill must not look or behave like writing the phrase `"fill-flag"` layer.

Header placement keeps the toggle near the current track context and editor mode
controls while staying outside the normal/fill lane authoring tabs. That matches
the README intent for performance modifications: quick, bounded changes that can
be tried while listening and discarded without silently changing authored song
state.

The prototype demonstrates the required v1 states:

- inactive clip track hearing the main lane;
- active clip track hearing authored fill lane content;
- track switch reset back to preview off;
- generator-backed track with disabled/unavailable affordance.

## Rejected Comparison

`prototypes/02-lane-toolbar-toggle.html` remains useful as comparison evidence
but should not lead implementation.

The lane-toolbar variant is more immediately discoverable because it places the
control beside `Normal lane` and `Fill lane`, where the user is already editing
clip content. That advantage is outweighed by the mental-model risk: a control
placed beside lane tabs reads too much like authoring state. For this feature,
that ambiguity cuts against the accepted requirement that preview is a runtime
override, not phrase mutation.

Use the lane-toolbar variant only to preserve the rejected tradeoff:

- benefit: strong discoverability near clip lane editing;
- failure: increased risk that users interpret preview as a lane or phrase edit;
- retained lesson: final disabled-state copy should remain close to the
  unavailable control.

## Acceptance Notes To Preserve

Later architecture, spec, and implementation handoff artifacts should preserve
these acceptance notes:

- toggling preview must be audible during playback without a transport restart;
- only the selected/open track is forced to fill preview;
- sibling tracks, including other drum-group parts, are not forced on;
- phrase `"fill-flag"` cells are unchanged by preview;
- the document dirty flag is unchanged by preview alone;
- closing the editor and switching tracks both clear the preview state;
- generator-backed tracks do not fake fill behavior in v1 and must explain the
  limitation near the disabled control.

## Next Artifact Dependencies

This approval package is the design basis for the next PM artifacts. It does
not define runtime ownership, API shape, test plan, or implementation sequence.

The next artifacts should be authored in this order:

1. `architecture.md`: runtime-only override ownership, shadowing of compiled
   fill state, reset lifecycle, dirty-state guardrails, and generator-disabled
   behavior.
2. `spec.md`: user-facing behavior, acceptance criteria, edge cases, and
   verification requirements.
3. `plan.md`: bounded implementation sequence.
4. `implementation-handoff.md`: builder-ready contract once architecture and
   spec are accepted.
