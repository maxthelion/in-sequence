---
feature: drum-parts-as-group
status: ready-for-build-loop-promotion
stage: implementation-handoff
updated: 2026-06-05
sources:
  - README.md
  - docs/roadmap/drum-parts-as-group/architecture.md
  - docs/roadmap/drum-parts-as-group/spec.md
  - docs/roadmap/drum-parts-as-group/plan.md
  - docs/roadmap/drum-parts-as-group/user-stories.md
  - docs/roadmap/drum-parts-as-group/existing-state.md
  - docs/roadmap/drum-parts-as-group/ux-review.md
  - docs/roadmap/drum-parts-as-group/prototypes/01-part-workspace-header.html
  - docs/roadmap/drum-parts-as-group/prototypes/02-kit-step-matrix.html
  - docs/roadmap/drum-parts-as-group/prototypes/03-group-routing-editor.html
---

# Drum Parts As A Group Implementation Handoff

## Builder Boundary

Implement Drum Parts As A Group v1 as kit-level coordination around the
existing drum-part model. A kit remains an ordered `TrackGroup` of independent
`StepSequenceTrack` members. The build should add:

- sibling navigation from an individual drum-part workspace;
- a pushed kit matrix that shows all member parts and active pattern slots;
- read-legible kit rows with row-tap navigation into normal part editing;
- a standalone post-creation routing editor for shared destination and trigger
  mapping;
- persisted trigger mapping mode, separate note and channel mappings, and
  playback/store resolution for per-note, per-channel, and individual routing.

Do not broaden the build into a new drum-specific track type, a kit-level
pattern object, inline matrix step editing, generator/layer editing from the
matrix, new per-member mute/solo behavior, or unrelated phrase, scene, mixer,
slicer, or melodic-track grammar changes.

## Branch And Worktree Expectations

A future build loop should be created in a feature worktree, not as product-code
dirt on `main`. Unless the decider chooses a different conventional name, use:

- build loop id: `build/drum-parts-as-group`;
- branch: `auto/roadmap-12-drum-parts-as-group`;
- worktree: `.worktrees/roadmap-12-drum-parts-as-group`;
- build-loop evidence root:
  `.meta/multipass/loops/build/drum-parts-as-group/`.

This PM lane does not create the build-loop manifest, branch, worktree, inbox
request, merge, rebase, or push.

## Source Of Truth

Use these PM artifacts in order:

1. `architecture.md` for the model, routing, playback, and UI ownership
   decisions.
2. `spec.md` for observable behavior, acceptance criteria, validation rules,
   edge cases, and v1 exclusions.
3. `plan.md` for the bounded implementation sequence, target seams,
   verification points, and review gates.
4. `ux-review.md` and the accepted prototypes for interaction intent and visual
   evidence, not production styling source.

The settled v1 choices are:

- drum parts remain independent `StepSequenceTrack` values grouped by
  `TrackGroup`;
- `TrackGroup.memberIDs` is the canonical order for header navigation, matrix
  rows, routing rows, and default channel seeding;
- `TrackGroup.triggerMappingMode` is persisted and decodes to `.perNote` for
  older documents;
- `noteMapping` and `channelMapping` are separate maps, so switching modes
  does not delete hidden assignments;
- `noteMapping` stores offsets from `DrumKitNoteMap.baselineNote`, with MIDI
  `60` displayed as `C4` and baseline MIDI `36` displayed as `C2`;
- `channelMapping` stores zero-based MIDI channels while the UI presents
  `1...16`;
- group shared destination edits reuse existing destination write-target
  plumbing;
- the kit matrix is pushed from the part workspace, not shown as a transient
  quick-look overlay;
- matrix cells are read-legible only, and cell taps do not toggle steps;
- matrix row taps navigate to the selected part's normal workspace;
- the routing editor is a standalone post-creation sheet or panel, not
  `AddDrumGroupSheet`;
- duplicate per-channel assignments are allowed with non-blocking warnings;
- matrix display is bounded to 16-step and 32-step v1 behavior, with explicit
  overflow/read-only treatment for longer patterns;
- future kit-pattern selection is a separate extension boundary.

## First Bounded Builder Slice

Start with model, persistence, creation defaults, and normalization only.

The first builder request should:

- add `DrumTriggerMappingMode` with `.perNote`, `.perChannel`, and
  `.individual`;
- add persisted `triggerMappingMode` and `channelMapping` fields to
  `TrackGroup`;
- decode older documents as `.perNote` with empty `channelMapping`;
- keep existing `noteMapping` as semitone offsets from
  `DrumKitNoteMap.baselineNote`;
- normalize `noteMapping` and `channelMapping` to current `memberIDs` during
  project synchronization;
- seed shared MIDI kit note defaults from member tags through `DrumKitNoteMap`;
- seed channel defaults in `memberIDs` order into stored channels `0...15`;
- prove sample/internal kit creation behavior has not changed.

Stop this slice after focused model/document tests and review evidence. Do not
start routing editor UI, matrix UI, or playback-mode branching before the
document contract is reviewed.

## Target Seams

Initial model slice:

- `Sources/Document/TrackGroup.swift`;
- `Sources/Document/Project+DrumGroups.swift`;
- `Sources/Document/Project.swift` or the current synchronization owner for
  `syncPhrasesWithTracks()`;
- existing model tests around `TrackGroup` and drum-group creation.

Subsequent builder slices should inspect and update the current equivalents of:

- `Sources/Document/Project+Destinations.swift`;
- `Sources/Document/SequencerDocumentSession+Mutations.swift`;
- existing `Project.DestinationWriteTarget` plumbing;
- `EngineController.effectiveDestination(for:in:)` or the equivalent
  engine/store destination resolver;
- routing editor draft/view-model support code;
- note-name parser/formatter support near musical mapping code;
- reusable destination picker/editor components;
- `Sources/UI/Track/TrackWorkspaceView.swift`;
- workspace/navigation destination state;
- new `DrumKitMatrixView`;
- store helpers for ordered group members, active pattern slots, and read-only
  step previews.

These paths are starting points from PM evidence. If code has moved, preserve
the same ownership boundaries instead of duplicating policy into views.

## Required Build Sequence

Follow the sequence in `plan.md` unless fresh code inspection proves a lower
risk ordering inside the same boundaries:

1. Model, persistence, creation defaults, and normalization.
2. Project/session mutations, group destination writes, and playback/store
   resolution.
3. Routing editor domain, validation, note parsing, draft apply, and
   non-blocking warnings.
4. Part workspace header and bounded sibling navigation.
5. Pushed kit matrix, pattern badges, mismatch warnings, row navigation, and
   routing-editor launch.
6. End-to-end integration, save/load, playback, focused tests, and visual
   evidence.

Review model and playback behavior before depending on them from UI. Review
the routing editor domain before connecting it to the matrix.

## Acceptance Criteria

The build is not complete until the observable criteria from `spec.md` pass:

- kit-aware part header appears only for tracks with a resolved drum group;
- previous/next controls derive from `TrackGroup.memberIDs`, are bounded at
  first/last parts, and remain available for generator/read-only members;
- `Open Kit View` pushes a kit matrix and Back returns to the originating part;
- matrix row order matches `memberIDs`;
- each matrix row shows part name, active pattern badge, and read-only step
  cells or a clear generator/read-only state;
- matrix cell taps do not mutate steps;
- matrix row taps navigate to the selected part workspace;
- mixed active pattern slots show a compact amber, non-blocking mismatch
  warning and divergent badge treatment;
- 32-step mode keeps part names and pattern badges visible, scrolling only the
  step region when cells would become illegible;
- routing editor Cancel discards draft changes;
- routing editor Apply atomically commits shared destination, mapping mode,
  inherit/own state, note mappings, and channel mappings;
- switching mapping modes preserves hidden note and channel assignments;
- valid note names commit offsets from `DrumKitNoteMap.baselineNote`;
- invalid note names block Apply and preserve previous stored values;
- per-channel mode stores UI channels `1...16` as `0...15`;
- duplicate inherited channels warn but still apply;
- per-channel mode without a MIDI shared destination blocks Apply;
- older documents decode safely with `.perNote` and empty `channelMapping`;
- `TrackGroup` Codable round-trips trigger mode, note mapping, and channel
  mapping;
- removed members are pruned from both mapping dictionaries;
- inherited per-note and per-channel playback resolve through the group shared
  destination correctly;
- own-destination members continue through existing individual destination
  behavior.

## Verification Expectations

Provide focused automated coverage where the current test architecture allows:

- model tests for `TrackGroup` decode defaults and Codable round-trip;
- synchronization tests for stale `noteMapping` and `channelMapping` entries;
- drum-group creation tests for shared MIDI note/channel defaults and unchanged
  sample-backed behavior;
- mutation tests for shared destination, inherit/own state, mapping mode, note
  mapping, channel mapping, and atomic routing-editor draft apply;
- note parser tests for sharps, flats, lowercase input, signed octaves,
  canonical display, MIDI range bounds, empty/partial input, and raw numeric
  rejection;
- channel validation tests for bounds, zero-based storage, duplicate warnings,
  and non-MIDI shared destination blocking;
- playback/store tests for `.perNote`, `.perChannel`, `.individual`, missing
  mappings, nil/non-MIDI shared destinations, and own-destination overrides;
- UI or view-model tests for header bounds, `memberIDs` ordering, matrix row
  order, pattern mismatch warnings, 32-step behavior, row-tap navigation, and
  generator/read-only rows.

Also capture actual built-surface evidence for:

- first, middle, last, and one-member header states;
- long kit and part names;
- six-part mixed-pattern kit matrix;
- coherent and divergent pattern states;
- 16-step and 32-step matrix states;
- at least one generator/read-only row;
- routing editor per-note, per-channel, individual, duplicate-channel warning,
  invalid-note, and non-MIDI destination validation states.

Use the accepted fixture shape from PM evidence where practical: long kit name,
six parts, mixed pattern slots, at least one generator/read-only row, and at
least one own-destination override.

## Review Gates And Evidence Paths

The future build loop should leave compact evidence under
`.meta/multipass/loops/build/drum-parts-as-group/`.

Required review gates:

- architecture/spec-compliance review after model and playback semantics are
  implemented;
- testing review after focused document, mutation, parser, playback, and UI or
  view-model checks run;
- UX/IA review against the accepted prototypes after the header, matrix, and
  routing editor are built;
- visual-economy review for the persistent header, matrix, and routing editor
  surfaces;
- adversarial review only after spec-compliance and code-quality/testing review
  have passed.

Expected evidence:

- builder final evidence for each bounded slice under the build loop `act/`
  area;
- reviewer findings under the build loop `observe/` or reviewer-designated
  evidence area;
- screenshots or visual scenario output for the header, matrix, and routing
  editor states listed above;
- final integration evidence that names test commands, visual checks, save/load
  checks, playback/store checks, known deviations, and residual risks.

## Out Of Scope

- Product-code work on `main`.
- Build-loop promotion by this PM handoff.
- New drum-specific track type.
- Kit-level pattern object, kit pattern selector, or group pattern bank.
- Inline step editing from the kit matrix.
- Matrix editing for generator internals, layered clips, probability rules, or
  phrase-layer rules.
- New per-member mute/solo model.
- Broad visual redesign outside the part header, kit matrix, and routing
  editor surfaces.
- Reusing `AddDrumGroupSheet` as the primary post-creation routing editor.
- Changes to unrelated phrase, scene, mixer, slicer, or melodic-track grammar.

## Residual Risks

- Document compatibility risk is concentrated in `TrackGroup` decoding,
  defaults, and mapping normalization. This is why the first slice stops at the
  model contract.
- Engine/view disagreement is possible if trigger mapping mode is interpreted
  differently by playback, store snapshots, and routing editor draft state.
- Per-channel mode must fail safe for nil or non-MIDI shared destinations; the
  UI should block Apply, but persisted incompatible data must not crash.
- Mode switching must never delete hidden note or channel assignments.
- Navigation state may not currently support a pushed matrix cleanly. If so,
  record architecture evidence instead of downgrading to a transient overlay.
- Matrix cells must remain read-legible and non-mutating; implying a group
  pattern model would violate v1 scope.
- Long names, 32-step rows, generator/read-only rows, and own-destination
  overrides need real visual evidence because they are the main UX stressors.
- Current global readiness summaries may lag this handoff; use this file and
  the durable PM summary as the current PM lane readiness source.

## Product-Owner Attention

No product-owner decision is needed for build-loop promotion. The architecture,
spec, and plan settle the owner-adjacent v1 choices in a conservative direction.
If implementation discovers a concrete contradiction with pushed navigation,
routing safety, or document compatibility, record that as build-loop evidence
for the decider instead of broadening scope silently.
