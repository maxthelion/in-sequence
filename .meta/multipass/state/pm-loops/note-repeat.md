# Note Repeat PM Loop

- updated: 2026-06-06T09:17Z
- loop: `pm/note-repeat`
- status: active; PM artifact/readiness lane, ready for build-loop promotion
- feature: `note-repeat`
- backlog item: 15
- registry manifest: `.meta/multipass/config/loops/pm/note-repeat.yaml`
- runtime root: `.meta/multipass/runtime/loops/pm/note-repeat/`
- authoritative product docs: `docs/roadmap/note-repeat/`
- latest observation:
  `.meta/multipass/runtime/loops/pm/note-repeat/observe/2026-06-06T08-47Z-pm-readiness-observation.md`
- latest orientation:
  `.meta/multipass/runtime/loops/pm/note-repeat/orient/2026-06-06T09-13Z-pm-orientation.md`
- previous PM orientation:
  `.meta/multipass/runtime/loops/pm/note-repeat/orient/2026-06-06T08-37Z-pm-orientation.md`
- architecture acceptance orientation:
  `.meta/multipass/runtime/loops/pm/note-repeat/orient/2026-06-06T07-49Z-pm-architecture-package-orientation.md`
- latest decision:
  `.meta/multipass/runtime/loops/pm/note-repeat/decide/2026-06-06T09-17Z-pm-no-route-decision.md`
- latest PM act:
  `.meta/multipass/runtime/loops/pm/note-repeat/act/2026-06-06T09-08Z-pm-implementation-handoff.md`
- previous PM act:
  `.meta/multipass/runtime/loops/pm/note-repeat/act/2026-06-06T08-55Z-pm-plan-authoring.md`
- latest PM artifact request acted on:
  `.meta/multipass/runtime/inbox/claimed/2026-06-06T09-07-45-464Z-Author-Note-Repeat-implementation-handoff.md`
- latest project orientation read:
  `.meta/multipass/runtime/loops/project/orient/2026-06-06T08-38Z-project-orientation.md`

## Current Interpretation

Note Repeat is active as a PM artifact/readiness lane on `main`. It is a
track-local live performance override: engage Repeat from the track perform
surface, capture the current quantized step's resolved output, retrigger that
captured material at the configured interval, and release back into normal
transport-aligned playback.

That product shape fits the README: fast performable variation, bounded happy
accidents, changing rules while music is running, and a discardable path back
to authored phrase/scene state. It remains scoped as live performance runtime
behavior, not phrase-cell authoring, generator capture, or a global sequencer
timing rewrite.

The 2026-06-06T08:40Z PM artifact pass accepted the architecture package:

- `docs/roadmap/note-repeat/architecture.md` has status
  `accepted-builder-facing`.
- `docs/roadmap/note-repeat/open-questions.md` has status
  `architecture-accepted`.
- The scheduler hook is an engine-owned repeat scheduler invoked from the
  existing step/tick playback path, with intra-step events anchored to the
  current 1/16 step tick and no global `TickClock` resolution change in v1.
- Active repeat state is owned by the engine playback runtime /
  `EngineController` equivalent, outside document state and undo/redo.
- UI ingress is command-shaped: `engageNoteRepeat(trackID:)` and
  `releaseNoteRepeat(trackID:)` crossing through the existing thread-safe
  command queue or state-lock pattern.
- Capture is current-step exact from resolved/prepared clip-backed output after
  phrase, fill, probability, and clip evaluation; repeats replay captured
  material and do not re-roll probability.
- Release, rapid re-engage, transport stop, source change, track deletion,
  project close, and session rebuild all use an idempotent cleanup contract
  that cancels pending repeat events, flushes note-offs/equivalent output
  cleanup, clears runtime state, and resumes from the live transport position.
- Interval persistence is a per-track layer setting with enum-like values
  `1/16`, `1/32`, and `1/64`; missing values decode to `1/16`; active playback
  snapshots the interval at engagement.
- V1 source scope is clip-backed tracks. Generator-backed tracks are disabled
  or unavailable until generator capture semantics are designed.
- Product defaults are accepted: momentary press/hold, empty-step silence,
  interval changes on next engagement, and interval setup outside perform mode.

The 2026-06-06T08:50Z PM artifact pass created
`docs/roadmap/note-repeat/spec.md`. The spec converts the accepted architecture
into testable acceptance criteria for interaction, command ingress,
current-step capture, engine scheduling, interval persistence,
release/lifecycle cleanup, unsupported states, and safety regressions.

The 2026-06-06T08:55Z PM artifact pass created
`docs/roadmap/note-repeat/plan.md`. The plan sequences implementation and
review evidence for the v1 scope: perform-surface momentary control, command
ingress, engine-owned runtime repeat state, current-step capture, intra-step
scheduling without global `TickClock` resolution changes, interval
persistence, release/lifecycle cleanup, unsupported states, and safety
regressions.

The 2026-06-06T09:08Z PM artifact pass created
`docs/roadmap/note-repeat/implementation-handoff.md`. The handoff packages the
accepted architecture, spec, and plan into a bounded builder handoff with exact
scope, non-goals, branch/worktree expectation, implementation sequence,
required tests, review evidence, visual evidence, and promotion-readiness
criteria.

## Existing PM Artifacts

Authoritative product-doc artifacts present under `docs/roadmap/note-repeat/`:

- `README.md`
- `notes.md`
- `artifacts.md`
- `user-stories.md`
- `existing-state.md`
- `ux-review.md`
- `open-questions.md`
- `architecture.md`
- `spec.md`
- `plan.md`
- `implementation-handoff.md`
- `prototypes/perform-page-toggle.html`
- `prototypes/layer-interval-and-substep.html`

Missing downstream PM artifacts:

- None for Note Repeat v1 build-loop promotion.

## Lowest Unmet PM Layer

No unmet PM artifact/readiness layer remains for Note Repeat v1 promotion.

Implementation, build-loop review, visual QA, integration, and merge work
remain future build-loop work. Do not perform them from the PM lane.

## Promotion Readiness

Ready for build-loop promotion.

Note Repeat now has accepted architecture, spec-level acceptance criteria, an
implementation plan, and an implementation handoff. The next useful project
decision, when capacity and roadmap priority allow, is a sparse build-loop
promotion for Note Repeat v1.

The 2026-06-06T09:17Z PM decision intentionally created no new inbox request
and no product-owner lock because no bounded PM artifact gap remains. PM
deciders should continue to avoid routing builders or build-loop promotion
directly from this lane.

A future promotion should create a dedicated build-loop branch/worktree,
expected as `build/note-repeat` and a dedicated worktree such as
`../in-sequence-note-repeat` unless the coordinator assigns a conflict-free
equivalent. The promoted build loop should point builders at
`docs/roadmap/note-repeat/implementation-handoff.md` plus the accepted
architecture/spec/plan.

Do not route implementation, review, integration, merge, rebase, worktree
deletion, product-code edits, or build promotion from this summary alone.

## Product-Owner Attention

No product-owner attention is needed.

The architecture pass accepted the conservative v1 defaults:

- Repeat is momentary press/hold in v1; latch is deferred.
- Clip-backed tracks are supported in v1.
- Generator-backed tracks are disabled in v1.
- Empty-step capture captures silence and does not snap to another step.
- Interval changes apply on next engagement, not mid-repeat.
- Interval setup may remain outside perform mode for v1.
- Active repeat state is engine-owned runtime state, not persisted document
  state.
- The global `TickClock` resolution does not change in v1.

Ask the product owner only if a later PM or build pass finds a direct conflict
between one of those accepted defaults and product intent.

## Routing Boundary

Use `pm/note-repeat` for Note Repeat PM observation, orientation, decisions,
and bounded artifact authoring. Keep PM artifact work on `main` in the root
coordination state and authoritative product-doc directory
`docs/roadmap/note-repeat/`.

The next useful non-PM action is build-loop promotion by a project decider when
capacity and priority allow. PM artifact authoring should not create builder,
reviewer, integrator, merge, rebase, push, or worktree-deletion requests.

## Evidence Freshness

- Latest PM readiness observation:
  `.meta/multipass/runtime/loops/pm/note-repeat/observe/2026-06-06T08-47Z-pm-readiness-observation.md`.
- Latest PM orientation:
  `.meta/multipass/runtime/loops/pm/note-repeat/orient/2026-06-06T09-13Z-pm-orientation.md`.
- Previous PM readiness observation:
  `.meta/multipass/runtime/loops/pm/note-repeat/observe/2026-06-06T06-42Z-pm-readiness-observation.md`.
- Previous PM orientation:
  `.meta/multipass/runtime/loops/pm/note-repeat/orient/2026-06-06T08-37Z-pm-orientation.md`.
- Architecture package orientation:
  `.meta/multipass/runtime/loops/pm/note-repeat/orient/2026-06-06T07-49Z-pm-architecture-package-orientation.md`.
- Latest PM decision:
  `.meta/multipass/runtime/loops/pm/note-repeat/decide/2026-06-06T09-17Z-pm-no-route-decision.md`.
- Previous PM decision:
  `.meta/multipass/runtime/loops/pm/note-repeat/decide/2026-06-06T08-45Z-pm-spec-decision.md`.
- Latest PM act:
  `.meta/multipass/runtime/loops/pm/note-repeat/act/2026-06-06T09-08Z-pm-implementation-handoff.md`.
- Previous PM act:
  `.meta/multipass/runtime/loops/pm/note-repeat/act/2026-06-06T08-55Z-pm-plan-authoring.md`.
- Earlier PM acts:
  `.meta/multipass/runtime/loops/pm/note-repeat/act/2026-06-06T08-50Z-pm-spec-authoring.md`
  and
  `.meta/multipass/runtime/loops/pm/note-repeat/act/2026-06-06T08-40Z-pm-architecture-acceptance.md`.
- Request acted on:
  `.meta/multipass/runtime/inbox/claimed/2026-06-06T09-07-45-464Z-Author-Note-Repeat-implementation-handoff.md`.
- Project feature-readiness at 2026-06-06T06:25Z listed `note-repeat` as a
  planning/prototype lane without current builder-ready handoff evidence; this
  durable PM summary is now fresher for Note Repeat PM readiness.
- Project current-work at 2026-06-06T07:19Z reported no ready build-promotion
  candidates and no unpromoted ready candidates; this durable PM summary is now
  fresher for Note Repeat PM readiness.
- Project orientation at 2026-06-06T08:38Z reported ordinary build capacity is
  open, while Note Repeat was still PM-progressed and below builder-ready; this
  handoff closes that PM gap.
- PM feature table at 2026-06-05T01:56Z classified Note Repeat as inventory /
  architecture stage and not ready for build; this durable PM summary is now
  fresher for Note Repeat PM readiness.
- `pm/audio-looping` remains product-owner locked, and
  `build/midi-interfaces` remains hardware locked.
- Coordinator inventory at 2026-06-06T09:13Z reported no pending messages and
  this PM orienter as the only running Note Repeat task; it still emitted known
  Ruby `executable-hooks` / `gem-wrappers` warning noise before useful output.

## Checks Run

- Read the claimed request, README, PM loop manifest, durable PM summary,
  `architecture.md`, `spec.md`, `plan.md`, `open-questions.md`,
  `existing-state.md`, `ux-review.md`, and nearby implementation handoff
  examples for local style.
- Confirmed `docs/roadmap/note-repeat/implementation-handoff.md` was absent
  before authoring.
- Checked `git status --short` before writing and observed broad pre-existing
  coordination/roadmap dirt; left unrelated changes untouched.
- Created `docs/roadmap/note-repeat/implementation-handoff.md`.
- Wrote loop-local PM act evidence at
  `.meta/multipass/runtime/loops/pm/note-repeat/act/2026-06-06T09-08Z-pm-implementation-handoff.md`.
- Refreshed this durable PM summary after the artifact pass.
- Re-read the new handoff, PM act evidence, and this durable PM summary.
- Ran a targeted consistency/readiness check for accepted defaults, handoff
  status, and build-loop promotion readiness across the touched artifacts.
- Wrote loop-local PM orientation at
  `.meta/multipass/runtime/loops/pm/note-repeat/orient/2026-06-06T09-13Z-pm-orientation.md`.
- Refreshed this durable PM summary after orientation.
- Wrote loop-local PM decision at
  `.meta/multipass/runtime/loops/pm/note-repeat/decide/2026-06-06T09-17Z-pm-no-route-decision.md`.
- Refreshed this durable PM summary after the no-route PM decision.
- Ran coordinator inventory; it reported no pending messages, this
  `pm-decider` plus one project orienter as running, and the known Ruby
  `executable-hooks` / `gem-wrappers` warning noise.

No product build, test suite, visual capture, product-code edit, inbox write,
request lifecycle move, build-loop manifest, promotion, implementation route,
review route, integration route, merge, rebase, push, or product-owner request
was performed.
