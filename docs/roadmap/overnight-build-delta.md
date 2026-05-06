---
created: 2026-05-05
status: draft
scope: overnight-build-loop
---

# Overnight Build Delta

## Intent

The current roadmap has enough mapped feature intent that the main risk is no
longer "we do not know what to build at all." The risk is that the process
takes so long resolving feature-level questions that momentum dies before the
product shape becomes visible.

This document reframes the next phase around a more aggressive product
development loop:

```text
build broad overnight -> review from several angles -> harvest what worked -> repeat
```

The goal is not to make every overnight build production-ready. The goal is to
learn the holistic shape of the app quickly enough that product judgment stays
alive.

## Source Artifacts

This document links and organizes existing planning state rather than replacing
it.

- [Portfolio plan](portfolio-plan.md): lane grouping and current build-order
  judgment.
- [Next actions](next-actions.md): deterministic per-feature state.
- [Mixer Routing and Sends lane note](lanes/mixer-routing-and-sends.md):
  example of a supervisor-written complexity note.
- [Clip History](clip-history/README.md): active/promoted build lane.
- [Scene Perform](scene-perform/README.md): ready-for-build feature.
- [Modifier Chain Placement](modifier-chain-placement/README.md): important
  track-editor foundation feature.
- [Step Sequencer](step-sequencer/README.md): ready but should follow the
  source/modifier shell.
- [Mixer Main Out](mixer-main-out/README.md), [Mixer Busses](mixer-busses/README.md),
  [Send Effects](send-effects/README.md): mixer lane.
- [Input Audio](input-audio/README.md), [Audio Looping](audio-looping/README.md),
  [Autoslice Algorithm](autoslice-algorithm/README.md): audio capture and
  waveform lane.
- [Track Fill Toggle](track-fill-toggle/README.md), [Note Repeat](note-repeat/README.md),
  [Step Order](step-order/README.md), [Track Perform Multi-Select And Latch](track-perform-multiselect-latch/README.md):
  performance override lane.
- [Phrase Features](phrase-features/README.md), [Song Mode And Phrase Looping](song-mode-phrase-looping/README.md),
  [Scenes In Phrases](scenes-in-phrases/README.md): phrase/scene performance
  lane.

## Product Development Premise

In product-development mode, the danger is not mainly that a bad build reaches
production. The danger is that the system spends too long trying to resolve
questions abstractly, and the human loses interest before the product has a
felt shape.

That changes the cost calculation:

- A wrong overnight branch can still be useful if it reveals product shape,
  interaction friction, missing concepts, or architecture pressure.
- A perfect spec for the wrong abstraction is expensive because it delays the
  moment where the product can be felt.
- Git history is cheap when wrong work stays in harvestable branches or
  worktrees. It becomes expensive when wrong concepts are merged into main,
  tested as intended behavior, and used as context for later agents.

The operating principle should be:

```text
Build broadly in probe space. Merge narrowly into commitment space.
```

## What Is Stopping The Overnight Loop Today

### 1. The scheduler does not yet run lane build leases

The meta cron currently supervises and summarizes. It does not yet grant and
run overnight lane build work end-to-end.

Needed delta:

- lane queue model;
- worktree creation per lane;
- CLI invocation for builders;
- lease limits so lanes do not trample each other;
- morning summary of build outputs, test status, review status, and harvest
  candidates.

### 2. The build unit is still feature-shaped

The artifacts are mostly feature directories. The better overnight unit is a
lane increment:

```text
Lane: Mixer Routing and Sends
Increment: routing model foundation across tracks, busses, sends, and master
Advances: items 4, 5, 6
```

Needed delta:

- lane files for all active lanes;
- lane increment files that state which feature artifacts they consume;
- explicit ownership boundaries for each overnight worktree;
- a rule that broad lane probes do not need feature-level prototype approval
  first.

### 3. There is not yet a holistic UX source of truth

The existing prototypes are feature-specific. That is useful for isolated
review, but less useful for answering whether the whole instrument makes sense.

Needed delta:

- one holistic interactive wireframe that includes the main surfaces together:
  track editor, mixer, phrase/scene performance, audio input/looping, and
  performance overrides;
- fake data and fake engine behavior are acceptable;
- the wireframe should be treated as UX truth, not implementation truth;
- overnight builders can use it to align surface shape before production code
  converges.

### 4. Validation exists, but not as a full overnight matrix

The desired morning state is not merely "code exists." It is:

- tests say what still works;
- adversarial review says what is risky or wrong;
- architecture review says what should not be merged as-is;
- UX review, ideally with Peekaboo screenshots, says whether the shape feels
  coherent;
- harvest notes say what is worth cherry-picking.

Needed delta:

- standard lane result format;
- automated screenshots for changed UI surfaces;
- test command per worktree;
- adversarial review prompt;
- architecture review prompt;
- UX/Peekaboo review prompt;
- morning digest that links outputs rather than asking the user to inspect
  everything.

### 5. There is no harvest policy

"Build it all overnight" is safe only if the morning step distinguishes
learning from commitment.

Needed delta:

- never auto-merge broad overnight probes into main;
- allow agents to prepare cherry-pick candidates;
- require a human or supervisor merge decision for shared product semantics;
- merge small isolated wins automatically only when tests/review are clean and
  the change does not define a new product model.

## Proposed Overnight Build Loop

### Evening setup

The supervisor creates an overnight plan:

- selected lanes and increments;
- feature artifacts each lane should consume;
- files/surfaces each lane may touch;
- explicit non-goals;
- expected morning artifacts.

The user's attention should be limited to approving the mode:

```text
Should tonight run in broad probe mode, where wrong work is acceptable as long
as it stays harvestable and reviewed?
```

### Overnight execution

For each lane, the scheduler creates or reuses a worktree and runs agents in
sequence:

1. **Lane builder:** implement the broadest useful interactive slice.
2. **Test agent:** run relevant tests, add smoke/domain tests for intentional
   behavior, and avoid freezing uncertain UI details.
3. **Adversarial reviewer:** identify bugs, merge risks, bad assumptions, and
   places where code only appears to work.
4. **Architecture reviewer:** identify wrong abstractions, ownership leaks,
   persistence hazards, and conflict risks with other lanes.
5. **UX/Peekaboo reviewer:** inspect screenshots or the running app and judge
   whether the user flow makes sense.
6. **Harvest summarizer:** write what to keep, what to discard, what to ask,
   and what to build next.

### Morning output

The morning digest should not ask the user to read every branch.

It should show:

- which lanes produced a working build;
- screenshots or videos for changed surfaces;
- tests/reviews status;
- harvest candidates;
- one or two decisions whose answers unlock the most flow;
- branches/worktrees safe to delete.

## Lane Delta

### Lane A - Track Editor Foundation

Artifacts:

- [Clip History](clip-history/README.md)
- [Modifier Chain Placement](modifier-chain-placement/README.md)
- [Step Sequencer](step-sequencer/README.md)

Overnight delta:

- settle the source/modifier shell;
- make clip history and step editing coexist in the same track editor shape;
- produce one interactive track-editor build, even if internals are rough.

Validation emphasis:

- architecture review for overlapping SwiftUI ownership;
- UI review for whether the track editor feels coherent;
- tests around selected pattern/source state and non-regression of existing
  clip behavior.

Harvest target:

- keep the source/modifier shell and any clean clip-history implementation;
- discard experiments that only work by coupling unrelated editor state.

### Lane B - Phrase, Scene, and Song Performance

Artifacts:

- [Scene Perform](scene-perform/README.md)
- [Phrase Features](phrase-features/README.md)
- [Song Mode And Phrase Looping](song-mode-phrase-looping/README.md)
- [Scenes In Phrases](scenes-in-phrases/README.md)

Overnight delta:

- create a holistic phrase/scene performance surface;
- make free/song mode, phrase rows, scene rows, basis phrase, and crossfader
  state visible together;
- prefer an interactive wireframe if production integration is too expensive.

Validation emphasis:

- UX/Peekaboo review over implementation completeness;
- adversarial review of confusing or contradictory performance states;
- tests only for stable transport/state contracts.

Harvest target:

- keep the interaction model and screenshots;
- turn unresolved concepts into lane decisions before production merge.

### Lane C - Mixer Routing And Sends

Artifacts:

- [Mixer lane note](lanes/mixer-routing-and-sends.md)
- [Mixer Main Out](mixer-main-out/README.md)
- [Mixer Busses](mixer-busses/README.md)
- [Send Effects](send-effects/README.md)

Overnight delta:

- build or wireframe the routing model across track strips, busses, sends, and
  master;
- use safe defaults from the lane note unless the implementation exposes a
  better option;
- defer polish until the signal-flow model is coherent.

Validation emphasis:

- domain tests for routing state and deletion/rerouting behavior;
- architecture review for audio graph ownership;
- UX review for whether mixer actions are discoverable and reversible.

Harvest target:

- keep routing state model and UI shape if coherent;
- avoid merging anything that locks in wrong signal semantics without review.

### Lane D - Audio Input, Looping, And Autoslice

Artifacts:

- [Input Audio](input-audio/README.md)
- [Audio Looping](audio-looping/README.md)
- [Autoslice Algorithm](autoslice-algorithm/README.md)

Overnight delta:

- make the waveform/buffer model visible across input, looping, and autoslice;
- fake or stub audio engine behavior where necessary;
- prefer proving the shared model over completing every algorithm.

Validation emphasis:

- architecture review for buffer ownership and lifecycle;
- UX review for recording and loop boundary clarity;
- tests around pure slice/loop calculations only when the behavior is chosen.

Harvest target:

- keep shared buffer/waveform abstractions that survive review;
- discard algorithmic experiments that are not grounded in usable interaction.

### Lane E - Performance Overrides And Pattern Manipulation

Artifacts:

- [Track Fill Toggle](track-fill-toggle/README.md)
- [Note Repeat](note-repeat/README.md)
- [Step Order](step-order/README.md)
- [Track Perform Multi-Select And Latch](track-perform-multiselect-latch/README.md)

Overnight delta:

- build a transient override model that can target one or more tracks;
- make latch/momentary behavior visible and reversible;
- prove that fill, repeat, and step-order can share the same performance layer.

Validation emphasis:

- adversarial review for accidental phrase mutation;
- tests around transient runtime state versus persisted phrase state;
- UX review for target selection clarity.

Harvest target:

- keep the override state model if it remains transient and composable;
- do not merge any approach that mutates source phrases unintentionally.

### Lane F - External Control And Automation

Artifacts:

- [MIDI Interfaces](midi-interfaces/README.md)
- [Observability From Application Logs](observability-log-issues/README.md)

Overnight delta:

- treat observability as independent tooling work;
- hold broad MIDI mapping work until performance surfaces settle;
- use MIDI only where mappings target stable concepts.

Validation emphasis:

- tests and developer ergonomics for observability;
- architecture review for mapping boundaries;
- no heavy UX review unless a user-facing mapping surface changes.

Harvest target:

- keep observability improvements that help future overnight loops;
- defer MIDI surface commitments if target UI is still moving.

## What Human Attention Should Be Directed To

If the goal is overnight holistic building, the user's attention should not go
to feature-by-feature prototype approval.

The useful attention questions are:

1. **Operating mode:** Is it acceptable for agents to run broad probe builds
   overnight if they do not auto-merge shared product semantics?
2. **Source of UX truth:** Should the next major artifact be a holistic
   interactive wireframe of the full instrument?
3. **Harvest policy:** In the morning, should agents prepare cherry-pickable
   commits and discard notes rather than trying to polish every branch?
4. **Merge boundary:** Which classes of changes may auto-merge, if any?
5. **Morning review shape:** Would the user rather see screenshots, a playable
   build, branch summaries, or one recommended harvest plan first?

Recommended default:

```text
Run overnight in broad probe mode, do not auto-merge lane semantics, produce a
morning harvest digest with screenshots, test/review results, and cherry-pick
candidates.
```

## Useful Tests During The Overnight Pass

Tests should protect learning, not prematurely freeze uncertain UI.

Useful overnight tests:

- app launch/smoke tests;
- domain tests for routing, transient override state, buffer lifecycle, and
  transport state;
- regression tests for bugs found during the build;
- contract tests for boundaries shared by several lanes;
- screenshot generation and visual review for changed user surfaces.

Tests to avoid in early probe mode:

- brittle snapshots of unsettled UI layout;
- tests that encode placeholder copy or fake data as product truth;
- broad integration tests whose failures do not localize the problem;
- tests that make it costly to throw away an experiment.

## Merge And Git Policy

Wrong code in git is acceptable when it is clearly contained.

Suggested policy:

- overnight lane work happens in worktrees/branches;
- broad lane probes do not auto-merge to main;
- agents may auto-commit within their branches for traceability;
- morning harvest creates candidate patches or cherry-pick lists;
- isolated fixes may auto-merge only if tests pass, reviews are clean, and the
  change does not define product semantics;
- main remains the commitment line, not the experiment log.

## Minimum Viable Scheduler Delta

To actually run this overnight, meta needs:

- lane queue selection from this document and [portfolio-plan.md](portfolio-plan.md);
- worktree creation and locking per lane;
- CLI builder invocation per lane;
- test/review/architecture/UX reviewer invocations;
- standard lane result files;
- morning digest generation;
- no auto-merge for lane probes by default.

The first version does not need perfect autonomy. It needs enough structure that
the user can say:

```text
Build the broad probe overnight.
```

and wake up to a small number of useful artifacts rather than a pile of
unexplained diffs.
