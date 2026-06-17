# Audio Looping PM Loop

- updated: 2026-06-04T11:05Z
- loop: `pm/audio-looping`
- status: locked
- feature: `audio-looping`
- backlog item: 14
- registry manifest: `.meta/multipass/config/loops/pm/audio-looping.yaml`
- runtime root: `.meta/multipass/runtime/loops/pm/audio-looping/`
- authoritative product docs: `docs/roadmap/audio-looping/`
- latest observation:
  `.meta/multipass/runtime/loops/pm/audio-looping/observe/2026-06-04T09-40Z-pm-readiness-observation.md`
- latest orientation:
  `.meta/multipass/runtime/loops/pm/audio-looping/orient/2026-06-04T10-50Z-pm-orientation.md`
- latest PM artifact action:
  `.meta/multipass/runtime/loops/pm/audio-looping/act/2026-06-04T10-06Z-scope-reconciliation.md`
- latest decision:
  `.meta/multipass/runtime/loops/pm/audio-looping/decide/2026-06-04T11-05Z-audio-looping-scope-lock.md`

## Current Interpretation

The Audio Looping PM loop has fresh observation, repeated orientation, and a
bounded PM artifact pass reconciling the lane against landed Input Audio. The
2026-06-04T11:05Z PM decision locked the loop manifest on the single remaining
product-owner scope choice. The lane has useful early PM material, an accepted
prototype, and preliminary dependency reconciliation artifacts, but it is not
builder-ready and is not ready for build-loop promotion.

The lane is trying to clarify a macro live-looping performance page on top of
Input Audio, not reopen the track-level audio input model. That is coherent
with README intent around fast performance setup, capture, loop reuse, and
turning a liked loop toward arrangement. The product fit is strong, but the
first-scope contract is not yet settled.

The authoritative lane README now reports `stage: scope-lock` and
`updated: 2026-06-04`. The accepted prototype/UX review still predates the
landed Input Audio build, so the reconciliation artifacts carry the fresher
dependency interpretation: Input Audio final v1 landed locally at `b00bac9`,
but that v1 is intentionally limited to one audio input track per session,
while Audio Looping stories/prototype assume plural loop-capable tracks and
simultaneous multi-track record.

The open-question and dependency reconciliation layer now exists:
`open-questions.md`, `prototype-approval.md`, and dependency-only
`architecture.md` were added on 2026-06-04. They preserve the accepted plural
prototype as target intent while recording that it is not a literal v1 builder
contract under Input Audio's current one-track limit.

The lowest unmet PM artifact/readiness layer remains a compact product-owner
scope lock: choose whether Audio Looping v1 narrows to a one-capable-track
macro page on top of Input Audio v1, or waits for multiple audio input tracks
and shared input distribution. Recommended default in the artifact is
one-capable-track v1 now, with plural/global-record behavior preserved as
later target intent.

A PM author should not write full architecture, spec, plan, or implementation
handoff before that first-scope choice is answered. The 10:50 orientation
confirms the 10:17 interpretation still holds after current project
orientation: the useful movement is lock handling, not more discovery,
promotion, or implementation routing.

## Existing PM Artifacts

The authoritative product-doc root contains:

- `README.md`: refreshed to `stage: scope-lock` on 2026-06-04.
- `notes.md`: present; records overlap with Input Audio and frames this lane
  as a lower-priority macro live-looping page.
- `user-stories.md`: present; five stories for a macro performance surface:
  open page, arm track, global simultaneous record, playback/silence toggle,
  and clear loop.
- `existing-state.md`: present from 2026-04-29; useful but stale because it
  predates landed Input Audio.
- `prototypes/looping-page-primary.html`: present; single-file interactive
  prototype covering all five stories.
- `ux-review.md`: present and accepted on 2026-04-30, selecting
  `prototypes/looping-page-primary.html`.
- `open-questions.md`: present; records closed Input Audio dependency
  questions and a product-owner scope lock.
- `prototype-approval.md`: present; packages the accepted prototype as target
  intent but not a v1 builder contract.
- `architecture.md`: present as dependency/test guardrails only, not a full
  accepted architecture.
- `feedback/.gitkeep`: present as an empty marker.

Missing builder-facing PM artifacts:

- accepted `spec.md`;
- `plan.md`;
- `implementation-handoff.md`.

## Missing Or Stale Readiness Gates

This lane is missing the PM artifacts required for a builder-ready handoff.
The accepted UX prototype is not enough to promote.

Settled by the 2026-06-04 reconciliation:

- The lane README no longer presents the lane as plain inventory; it now marks
  `stage: scope-lock`.
- The accepted Audio Looping prototype remains target intent, but it is not a
  literal v1 builder contract under the current one-track Input Audio limit.
- Clear loop is recorded as required Audio Looping behavior if the lane
  promotes: it must be an explicit runtime buffer reset, not merely destructive
  re-record/replace.
- The old generic Play/Mute assumption is replaced for v1 by canonical
  Input/Loop monitor mode. Mixer mute must not be overloaded by the looping
  page.
- The page must reflect Input Audio runtime state for arm, monitor mode,
  selected bar length, loop-empty state, loop playback, and failure state.

Still unresolved:

- One-capable-track v1 now versus waiting for plural simultaneous looping.
  This is a product-owner scope choice because accepted prototype intent is
  plural while the landed dependency is single-track.

Input Audio dependency facts now available to PM:

- `.audioInput` track type exists in the accepted PM contract and landed
  feature scope.
- Arm state is runtime-owned by `EngineController` /
  `AudioInputTrackRuntime`, keyed by track ID; both Input Audio and Audio
  Looping should use the same canonical state.
- Recording lengths are 1, 2, 4, and 8 bars, defaulting to 2 bars.
- ARM is bar-quantized, recording auto-stops at selected length, and
  re-recording destructively replaces the previous loop.
- Input mode and Loop mode are distinct monitor states; only one reaches the
  mixer at a time.
- Multiple audio input tracks and shared input distribution are deferred from
  Input Audio v1.

## Next Useful PM Action Kind

The next useful PM action kind is recording the product-owner answer to the
single remaining scope choice, then PM artifact authoring after the answer.

Do not create a build loop or implementation handoff until the lane records
one of these choices:

- proceed with the recommended one-capable-track v1 on top of Input Audio v1;
  or
- wait until plural audio input tracks and shared input distribution are in
  scope.

After the lock is answered, the next PM author can write full architecture,
spec, plan, and implementation handoff for that chosen scope.

The loop manifest now reports `status: locked` with this question. No
`pm-artifact-author` inbox request is useful until the answer exists.

## Product-Owner Decision Needs

Product-owner attention is needed before build-loop promotion.

Decision needed:

- Should Audio Looping v1 narrow to a one-capable-track macro page that sits
  on top of Input Audio v1, or should it wait until multiple audio input tracks
  and shared input distribution are in scope?

Recommended default: one-capable-track v1 now, preserving plural/global-record
behavior as later target intent.

No product-owner attention is needed for clear-loop intent, state ownership,
monitor-mode mechanics, implementation mechanics, build capacity, MIDI
hardware, or Input Audio's landed v1 contract from this PM lane.

## Promotion Readiness

Not ready for build-loop promotion.

The lane has accepted UX prototype evidence, relevant user stories,
open-question reconciliation, target-intent prototype approval, and
dependency/test guardrails. It does not have accepted full architecture, spec,
plan, or implementation handoff, and the first-scope choice remains locked.
Promotion should wait until PM artifacts define the v1 scope and carry that
answer through builder-facing artifacts.

Live build capacity is also full with
`build/track-perform-multiselect-latch` and `build/midi-interfaces`, but
capacity is secondary here. The primary blocker is PM artifact readiness.

## Routing Boundary

Use `pm/audio-looping` for Audio Looping PM artifact observation,
orientation, decisions, and bounded artifact authoring. Keep work on `main` in
the root coordination state and the authoritative product-doc directory
`docs/roadmap/audio-looping/`.

Do not promote a build loop from this observation. Do not route
implementation, review, merge readiness, or integration from the PM lane.

## Evidence Freshness

- PM decision was written at
  `.meta/multipass/runtime/loops/pm/audio-looping/decide/2026-06-04T11-05Z-audio-looping-scope-lock.md`.
- Coordinator inventory at 2026-06-04T11:05Z parsed the updated manifest,
  reports `pm/audio-looping` as `locked`, and reports no pending messages.
  The command produced the known Ruby `executable-hooks` / `gem-wrappers`
  warning noise.
- PM orientation was refreshed at
  `.meta/multipass/runtime/loops/pm/audio-looping/orient/2026-06-04T10-50Z-pm-orientation.md`.
- Previous PM orientation was refreshed at
  `.meta/multipass/runtime/loops/pm/audio-looping/orient/2026-06-04T10-17Z-pm-orientation.md`.
- PM orientation was written at
  `.meta/multipass/runtime/loops/pm/audio-looping/orient/2026-06-04T09-44Z-pm-orientation.md`.
- PM readiness observation was written at
  `.meta/multipass/runtime/loops/pm/audio-looping/observe/2026-06-04T09-40Z-pm-readiness-observation.md`.
- PM artifact action was written at
  `.meta/multipass/runtime/loops/pm/audio-looping/act/2026-06-04T10-06Z-scope-reconciliation.md`.
- The 10:06 PM artifact action is fresher than feature-readiness at 09:15 and
  holistic status at 09:58 where those summaries still describe Audio Looping
  as missing the preliminary open-question, prototype-approval, or architecture
  guardrail layer.
- Fresh project orientation at 2026-06-04T10:34Z confirms Audio Looping PM is
  locked on the one-track-now versus plural/global scope choice, and not
  builder-ready while Track Perform and MIDI occupy build capacity.
- Feature-readiness at 2026-06-04T09:15Z lists `audio-looping` / backlog item
  14 as inventory-stage PM planning with no ready-for-promotion pairing.
- Earlier coordinator inventory at 2026-06-04T10:49Z reported
  `pm/audio-looping` active before this PM decision locked the manifest.
- Checks run: coordinator inventory, targeted `rg --files` and `rg` scans,
  targeted reads of the request, README, PM manifest, latest PM observation,
  prior PM orientation, 10:06 PM artifact action, lane README, user stories,
  open questions, prototype approval, architecture guardrails, current PM
  summary, feature-readiness, current project orientation, work, and holistic
  summaries. Also ran `date -u` and scoped `git status --short`.
