---
feature: note-repeat
created: 2026-06-06
status: architecture-accepted
sources:
  - README.md
  - docs/roadmap/note-repeat/notes.md
  - docs/roadmap/note-repeat/artifacts.md
  - docs/roadmap/note-repeat/user-stories.md
  - docs/roadmap/note-repeat/existing-state.md
  - docs/roadmap/note-repeat/ux-review.md
  - docs/roadmap/note-repeat/prototypes/perform-page-toggle.html
  - docs/roadmap/note-repeat/prototypes/layer-interval-and-substep.html
---

# Note Repeat Open Questions

Note Repeat is a track-local live performance override: engage Repeat from the
track perform surface, capture the current quantized step, retrigger that
captured material at the configured interval, and rejoin normal playback cleanly
on release.

This file separates architecture-answerable gaps from product-owner candidates
before spec, plan, handoff, or build promotion.

Acceptance update, 2026-06-06: `architecture.md` accepts the initial
architecture direction and the conservative v1 defaults below. These questions
are resolved enough for `spec.md`; no product-owner lock is needed from this
package.

## Summary

- Architecture-answerable gaps accepted: 6
- Product-owner defaults accepted: 5
- Product-owner lock needed now: no
- Ready for build-loop promotion: no

The accepted UX evidence and accepted architecture are sufficient for the next
spec pass. They are not sufficient for implementation because the current engine
has no live repeat state, no sub-step scheduling primitive, no repeat interval
storage, and no spec-level acceptance criteria for lifecycle and edge-case
semantics.

## Architecture-Answerable Gaps

### A1 - Sub-Step Scheduling

**Accepted architecture decision for spec.**

The current `TickClock` fires once per 1/16 step. Repeat 1/32 and 1/64 require
two or four note triggers inside that step without advancing the main sequencer
step counter.

Accepted direction:

- preserve the main one-tick-equals-one-step sequencer invariant for v1;
- add an engine-owned intra-step repeat scheduler for active Note Repeat tracks;
- schedule repeat note events as offsets from the current step tick rather than
  globally increasing `TickClock` resolution;
- cancel scheduled intra-step repeat events on release, transport stop, track
  deletion, source change, or project close.

Reason:

Changing global clock resolution would touch every step-indexed playback path.
A secondary timer detached from the playback tick risks drift. Anchoring
sub-step repeat events to the current tick keeps the feature scoped to active
repeat playback while preserving normal sequence advancement.

### A2 - Live Repeat State Ownership

**Accepted architecture decision for spec.**

Note Repeat active state is live runtime state, not phrase data and not document
state. It must not mutate phrase cells, selected layer values, clips, or track
source data when the performer engages or releases Repeat.

Accepted direction:

- own active repeat state in the playback session / engine runtime layer;
- expose command-shaped UI APIs such as engage/release/toggle for a track;
- pass UI commands through the existing command queue or state-lock pattern;
- keep an engine-readable snapshot that the playback callback can consume
  without consulting SwiftUI state;
- key active repeat state by track id so multiple tracks can repeat
  independently if the UI allows it.

The runtime state should contain, at minimum: track id, captured quantized step
index, captured notes or events, selected repeat interval, active interaction
mode, and pending scheduled repeat events.

### A3 - Note Capture Source

**Accepted architecture decision for spec.**

The user intent says Repeat captures the quantized step when engaged. The
existing rolling capture buffer is useful precedent, but it was built for
history/capture-to-clip, not for immediate live repeat.

Accepted direction:

- capture from the resolved/prepared note output for the current quantized step;
- capture after phrase, fill, probability, and clip evaluation have produced
  the notes that would actually play for that step;
- do not re-resolve probability on each repeat retrigger;
- do not use the rolling history buffer as the primary source unless
  architecture proves it is current-step exact.

This keeps the audible repeated material aligned with what the performer heard
or was about to hear at engage time.

### A4 - Release, Rapid Re-Engage, And Stuck-Note Safety

**Accepted architecture decision for spec.**

Release must restore normal transport-aligned playback without stuck notes or
doubled notes. Rapid release/re-engage inside the same step must be explicit in
the engine contract.

Accepted direction:

- release cancels pending sub-step repeat events for that track;
- release flushes pending note-offs for repeated MIDI output and performs the
  equivalent cleanup for audio/sample/AU paths;
- rapid re-engage runs release cleanup before capturing the next step;
- normal playback resumes from the live transport position, not from the
  captured step.

The later spec must include stuck-note and rapid re-engage acceptance checks.

### A5 - Repeat Interval Storage And Migration

**Accepted architecture decision for spec.**

The raw intent says intervals such as repeat 16, repeat 32, and repeat 64 live
in the layer. The accepted supporting prototype places the segmented interval
control in track layer settings.

Accepted direction:

- model the v1 interval as a stable per-track layer setting, not per-phrase-step
  automation;
- store an explicit enum-like value for 1/16, 1/32, and 1/64;
- default existing projects to 1/16 via `decodeIfPresent` or equivalent
  migration;
- snapshot the interval on Repeat engage so active repeat playback is stable.

If later product direction requires phrase-varying or bar-varying repeat
intervals, that should be a follow-on layer automation feature, not an implicit
v1 requirement.

### A6 - Unsupported Source And Lifecycle Handling

**Accepted architecture decision for spec.**

The feature must define what happens when active repeat state becomes invalid:
track deleted, track source changed, transport stopped, document closed, output
route lost, or interval setting removed.

Accepted direction:

- clear active repeat state when the owning track or playable source becomes
  invalid;
- cancel scheduled repeat events during transport stop and project close;
- surface disabled/unavailable UI states for unsupported track types rather
  than allowing silent partial behavior.

## Product Defaults Accepted

These choices are product-flavored, but PM accepts the recommended conservative
defaults for v1. They should become spec acceptance criteria rather than
product-owner questions unless a later PM pass finds a direct conflict with
product intent.

### Q1 - Latch Versus Momentary Semantics

**Accepted v1 default.**

The raw intent says Repeat keeps playing "until it is released." The UX review
notes that "like Fill" is ambiguous because Fill is not a true live runtime
toggle today.

Use momentary press/hold semantics for Repeat, with release ending the repeat.
Defer latch-on-tap or combined tap/hold semantics unless the product owner
explicitly asks for latch behavior.

Reason:

Momentary behavior best matches "until released" and keeps the first engine API
simple: engage and release. Latch can be added later on top of the same runtime
state if the perform surface needs it.

### Q2 - Generator-Backed Track Behavior

**Accepted v1 default.**

Generator-backed tracks may not have deterministic step material in the same
way clip-backed tracks do, and existing Fill behavior does not apply to
generators today.

Disable or suppress Note Repeat for generator-backed tracks in v1, with a clear
unavailable state. Repeat generator output later only after generator capture
semantics are intentionally designed.

### Q3 - Empty-Step Capture

**Accepted v1 default.**

The accepted prototype only shows Repeat engaging on a step with notes.

Capturing an empty step captures silence and produces no retriggers until
release. Do not snap forward or backward to a nearby populated step.

Reason:

Snapping to another step would surprise the performer and violate the
quantized-step capture model. Capturing silence is predictable and safe.

### Q4 - Interval Changes While Repeat Is Active

**Accepted v1 default.**

The supporting prototype places interval setup outside the perform surface, but
future UI could expose interval changes while Repeat is active.

Snapshot the interval at engage time. Changes to the stored interval take effect
on the next Repeat engagement, not mid-repeat.

Reason:

This avoids jitter and rescheduling edge cases while preserving a clear
pre-performance setup model.

### Q5 - Perform-Mode Access To Interval Setup

**Accepted v1 default.**

The accepted interval prototype uses track layer settings, which likely means
leaving the perform surface to change the interval.

Allow interval setup to remain outside perform mode for v1. The perform page
should show enough active-state feedback to communicate the interval being
used, but it does not need a live interval picker in the first implementation.

Reason:

The primary perform workflow remains one press to engage and one release to
disengage. Live interval picking can be considered later if performance use
shows that changing repeat rate mid-run is central.

## Product-Owner Attention

No immediate product-owner lock is required from this packaging pass.

The architecture acceptance pass has accepted the recommended defaults above
into spec direction. Do not ask the product owner a broad "how should Note
Repeat work?" question; ask only if a later PM pass finds a specific accepted
default conflicts with product intent.

## Next Artifact Dependencies

This file's architecture-answerable questions and product defaults are now
resolved enough for spec. The lane remains not ready for build-loop promotion
until these downstream artifacts exist and are accepted:

- `spec.md`;
- `plan.md`;
- `implementation-handoff.md`.
