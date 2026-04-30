---
verdict: accepted
selected_prototype: prototypes/mixer-busses-variant-a.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/mixer-busses-variant-a.html
feedback_applied: []
---

# Mixer Busses UX Review — 2026-04-30

## Context

One prototype variant was produced for the Mixer Busses feature (roadmap item 5).
Variant A places bus strips as a distinct column section between the track strips area
and the master out column, with darker section header chrome to make the three-zone
hierarchy (tracks | busses | master) immediately legible. The prototype is aligned with
the Variant A layout direction accepted for Mixer Main Out (item 4), which places the
master out as a fixed right-side column. The two features are designed to share a single
mixer surface.

Five interactive states are provided: default, solo-drums-bus, solo-kick-track,
routing-change-in-flight, and empty-bus.

---

## Checklist Results

| Criterion | Result |
|---|---|
| Single-file, no build steps | Pass |
| Monochrome base, semantic color only | Pass |
| Stub regions clearly marked | Pass |
| Real interactions on primary path | Pass |
| Fixture data is adversarial / varied | Pass |
| Interaction budget stated and verified | Pass |
| Reviewer cannot mistake for production | Pass |
| All five user stories reachable in prototype | Pass — see story coverage below |
| Bus section visually distinct from track strips | Pass |
| Solo state covers both tracks and buses | Pass |
| Routing-change-in-flight state present | Pass |
| Empty-bus state present | Pass |
| Insert bypass operable on bus strip | Pass |
| Inline rename operable | Pass |
| Add Bus produces live strip | Pass |
| New bus options added to all track output selectors | Pass |
| Bus output restricted to Master (no dropdown) | Pass — see Q2 note |
| Variants are strategically different, not cosmetic | N/A — single variant |

All primary-path criteria pass. The single-variant submission is acceptable because the
layout question (column placement) was already resolved by the Mixer Main Out review and
no alternative topology was in scope. The prototype covers the additional surface (bus
strips) rather than re-testing the outer shell.

---

## Per-Variant Assessment

### Variant A — Bus Column Section (tracks | busses | master)

The bus section is placed between the horizontally scrollable track strips and the
stubbed master out column. The bus section header is dark (#555 background, light text)
to distinguish it from the lighter track-section header, giving the three-zone layout a
clear visual hierarchy without color. The separator between track strips and bus strips
is a 2 px border, matching the 2 px separator used between bus strips and master out.
This is consistent with the Mixer Main Out Variant A language.

**What works:**

- The three-zone layout (tracks | busses | master) is immediately legible. Each zone has
  a distinct header weight; the bus zone sits correctly in the middle of the signal chain.
  This maps to the audio graph topology confirmed in existing-state.md: track outputs
  sum to a bus mixer node, bus outputs sum to master.
- The "Add Bus" affordance is provided in two places: the section header button and a
  trailing "+" tile at the end of the bus scroll area. The header button ensures the
  affordance is visible even when no buses exist. The trailing tile provides spatial
  proximity to existing buses. Both invoke the same action. This dual placement is not
  redundant — it covers both "I have no buses yet" and "I want to add another bus
  alongside existing ones" without adding interaction steps.
- Clicking "+ Add Bus" immediately inserts a new bus strip before the trailing tile, adds
  the new bus as an option to every track output selector, and fires a toast confirmation.
  The primary interaction goal (add a bus, route a track to it) is verified in 3
  interactions: click "+ Add Bus" → click track output selector → choose bus. This meets
  the stated budget.
- Strip anatomy is consistent across tracks and buses (output selector / inserts / fader /
  pan / mute+solo / name), reducing cognitive load. The bus strip differs from the track
  strip only in that its output selector is a static label ("→ Master") rather than a
  dropdown. This correctly reflects the user story constraint (one bus output: master).
- The bus strip insert zone shows a working bypass toggle (filled dot = enabled, hollow
  dot = bypassed) with immediate visual feedback on click. Up to three inserts are shown
  on the Drums Bus, with a bypassed insert demonstrating the state visually (opacity
  reduced, dot hollow). The "+ insert" button is present on all strips. This satisfies
  Story 4 at the prototype level.
- Inline rename on double-click works: the name label hides, an input field appears
  pre-populated, focus is set, and Escape or blur restores the label. Enter commits. This
  satisfies Story 5. The prototype correctly stubs the live propagation of a renamed bus
  to all track output selectors, annotating the gap.
- Solo behavior (exclusive model) is implemented for both tracks and buses. Soloing any
  strip dims all other strips. A "SOLO ACTIVE" banner with a "Clear Solo" button appears
  at the top. Soloing a bus dims all other buses and all track strips. Soloing a track
  dims all other tracks and all bus strips. The solo-drums-bus and solo-kick-track states
  are both provided as scene buttons and are visually clear.
- The routing-change-in-flight state shows the Snare strip entering a 600 ms disabled
  state with "Applying…" label replacing the output select, followed by a toast. This
  communicates the engine stop/rewire/restart constraint from existing-state.md (§2,
  Story 2) without over-explaining it.
- The empty-bus state (Leads Bus with no tracks routed) shows a "No tracks routed here"
  badge in the insert area. The bus strip remains fully operable (fader, mute, solo, pan).
  This is consistent with DAW conventions — a bus can exist before tracks are routed.
- Fixture data includes adversarial cases: a long track name ("Pad Lush Strings") that
  overflows and truncates, a bus with three inserts including a bypassed one (Drums Bus),
  a bus with one insert (Synths Bus), and a bus with no inserts (Leads Bus). Cross-track
  routing is varied: three tracks to Drums Bus, two to Synths Bus, one to Leads Bus.
- The prototype header comments and annotation block are explicit about the four open
  spec questions (solo convention, bus output selector scope, routing-change visual, bus
  insert scope/scene-scoping). These are correctly elevated as questions rather than
  resolved by the prototype.
- The master out column is fully stubbed (dashed border, cross-reference to item 4 prototype).
  This correctly keeps the bus feature self-contained while providing spatial context.

**What fails or is limited:**

- The bus output selector is a static label rather than a dropdown, which is correct per
  user stories. However, the label "→ Master" uses the same visual slot as the track
  output dropdown. If bus chaining is introduced later (Q2), the static label would need
  to become a dropdown in the same position, which is straightforward. The current
  treatment is correct given the scoped user stories, but the spec must explicitly call
  out that bus chaining is out of scope so implementers do not leave an accidental
  hook in.
- Inline rename on tracks is also enabled in this prototype (double-click any track name
  to rename). Track strip rename is not in the user stories and no production rename
  pattern exists for tracks today (the `MasterBusScene` rename pattern exists for scenes,
  not tracks). The annotation notes this gap. The spec must decide: does track strip
  rename land as part of this item, or is it deferred? Including it without a decision
  creates scope ambiguity.
- The new-bus default name ("Bus 4", "Bus 5", ...) is a counter-based auto-name. There
  is no user-facing "name this bus now" prompt on creation. The user must double-click
  the name label to rename after the fact. This is a minor discoverability issue for
  Story 5: the user may not realize the bus is renameable, especially if bus names are
  the primary identification mechanism in the track output selectors. Consider whether
  the "Add Bus" action should auto-focus the name field immediately after creation.
- The solo logic is exclusive (one strip at a time) as a prototype choice, but this is
  not confirmed as the product decision. The prototype comment documents this correctly as
  SPEC Q1. The architecture stage will need the product decision before the solo state
  machine is designed — solo exclusivity is a non-trivial engine coordination requirement
  (existing-state.md §3, solo logic complexity).
- When a bus is renamed, the track output selectors are not updated in the prototype
  (annotated as a stub). This propagation requirement (bus name must update all track
  output selector option labels) must be captured in the spec as a first-class behavior,
  not just a "nice to have." It is directly stated in Acceptance Signal 5 of user-stories.md.
- There is no delete-bus affordance shown. The prototype adds buses but does not show how
  to remove one. This is a missing state that must be addressed in the spec: what happens
  when a bus is deleted while tracks are still routed to it? (Re-route to master
  automatically? Warn the user? Block deletion?) This is a required product decision
  before spec.
- The insert chain on bus strips is distinct from the master insert chain (which is
  scene-scoped via `MasterBusScene`). The prototype correctly treats bus inserts as global
  (non-scene-scoped), but this is open question Q4. The spec must confirm the scope
  before implementation: if bus inserts are later made scene-scoped, the data model for
  `MixerBus` becomes substantially more complex (analogous to `MasterBusState` with a
  scene list).
- The bus strip's insert zone height is the same as the track strip insert zone. With
  three inserts on the Drums Bus, the zone is taller than the two-insert and empty
  variants, making bus strips slightly different heights within the same scroll row. The
  prototype handles this by fixing the strip height through the flex layout, but the
  visual difference is visible. The spec should address whether bus strips have a fixed
  insert zone height or grow with content.

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Create a new bus | Covered: "+ Add Bus" header button and trailing tile both work; new strip appears immediately |
| 2. Route a track's output to a bus | Covered: per-strip output selector dropdown with all buses listed; routing-change-in-flight state shown |
| 3. Bus fader, pan, mute, solo | Covered: all four controls present on bus strips; solo dimming shown across all states |
| 4. Insert plugins on a bus | Covered: insert slot list with bypass toggle, "+ insert" button; bypassed insert state shown |
| 5. Name and identify buses | Covered: inline rename on double-click, name persists in prototype; propagation to selectors is stubbed with explicit annotation |

All five user stories are reachable within the prototype and pass the "done when"
observable outcome tests at the interaction level.

---

## Cohesion With Mixer Main Out (Item 4)

The Mixer Main Out review accepted Variant A (right-side master column) as the layout
direction. Mixer Busses Variant A is directly compatible:

- The bus strips use the same strip anatomy (output selector / inserts / fader / pan /
  mute+solo / name from top to bottom) as the track strips in the Mixer Main Out
  prototype. The strip shape is consistent across all three zones.
- The section separators (2 px borders, section headers) use the same visual language.
- The master out column is correctly stubbed in the Mixer Busses prototype as
  "[Master Out strip — see Mixer Main Out prototype (item 4)]," avoiding duplication and
  signaling that the two features share a surface without reimplementing it.
- The signal-flow reading order (tracks → busses → master, left to right) is consistent
  with the top-to-bottom zone order in the Mixer Main Out master column (crossfader →
  inserts → fader → meter).

One cohesion risk: the Mixer Main Out review noted that master inserts are scene-scoped
(per `MasterBusScene`). If bus inserts are decided to be global (non-scene-scoped), the
two halves of the same mixer surface will have conceptually different insert-chain
semantics. This difference should be explicit in the UI — possibly through a label
difference ("Inserts" for buses vs. "Inserts (Scene: X)" for master) — and must be
resolved by the product decision on Q4 before spec.

A second cohesion concern: the Mixer Main Out review asked whether a solo button should
exist at all in its feature scope (master out has no solo in any DAW — you cannot solo
the master). The Mixer Busses prototype adds solo to both tracks and buses but does not
show how soloing a bus interacts with the master out metering in the adjacent column.
The architecture pass should address whether bus solo feeds through to the master level
meter and whether the master out column shows any "solo active" indication.

---

## Open Questions to Carry Forward

1. **Solo convention (Q1).** Exclusive vs. additive solo. Must be confirmed before
   architecture, as the solo state machine design differs substantially between the two
   models.
2. **Bus output scope (Q2).** Bus output is fixed to Master in this item. The spec must
   explicitly defer bus chaining to prevent accidental implementation.
3. **Routing-change visual (Q3).** Brief disabled state shown in prototype. Spec must
   choose: (a) no visual, (b) brief disabled state as shown, (c) toast only, (d) modal.
   The engine stop/rewire/restart must happen on the main thread regardless of choice.
4. **Bus insert scope (Q4).** Global vs. scene-scoped bus inserts. This is the highest-
   impact undecided question: it determines whether `MixerBus` needs a scene list or a
   flat insert list.
5. **Delete bus.** No delete affordance exists in the prototype. What happens when a bus
   is deleted while tracks are routed to it? This is a required product decision before
   spec.
6. **Track strip rename.** The prototype enables inline rename on track strips, which is
   not in the user stories. Confirm: land with this item, defer, or remove from scope.
7. **Auto-focus bus name on creation.** Should "+ Add Bus" auto-focus the new bus name
   field? Relevant to Story 5 discoverability.
8. **Bus insert zone height.** Fixed-height insert area vs. grow-with-content. Affects
   strip height consistency across the bus section.

Questions 1, 4, and 5 block spec. Questions 2, 3, 6, 7, and 8 can be resolved during
architecture or early spec without user escalation.

---

## Recommendation

**Accept Variant A as the direction for architecture and spec.**

The prototype is coherent, covers all five user stories, handles adversarial fixture
data, and is directly compatible with the accepted Mixer Main Out direction. The strip
anatomy and zone layout are consistent across the mixer surface. The four open spec
questions are correctly elevated rather than decided unilaterally.

Before the architecture pass, resolve questions 1 (solo convention), 4 (bus insert
scope), and 5 (delete bus behavior) — these three determine the boundary of the data
model and the engine state machine. If any of them require user input rather than a PM
judgment call, write `open-questions.md` and block the feature before architecture begins.

**Elements to carry into architecture:**

- Three-zone layout: tracks (scrollable) | busses (fixed section) | master out (fixed
  column). Same visual language: 2 px zone separators, distinct section headers.
- Strip anatomy (top to bottom): output selector → insert zone → fader → pan → mute +
  solo → name label.
- Bus output selector: static "→ Master" label (not a dropdown) in this scope.
- Exclusive solo convention (prototype default) pending Q1 confirmation; dimming covers
  all track and bus strips.
- Routing-change-in-flight: brief disabled state + toast while engine rewires.
- Empty-bus state: "No tracks routed here" badge in the insert zone; strip remains operable.
- Add Bus: creates strip, updates all track output selectors, auto-scrolls to new bus.
- Inline rename: double-click to edit; name propagates to all track output selector options.
- Delete bus: requires a product decision before architecture can model the affected track
  re-routing behavior.
- Bus insert chain: global scope (non-scene) per prototype; must be confirmed vs. master's
  scene-scoped model before spec.

---

## Next Action

Resolve open questions 1, 4, and 5 (solo convention, bus insert scope, delete-bus
behavior) — via product judgment or user clarification — then advance to
`write-architecture`. All three affect the data model boundary; none can be assumed away
in the architecture pass.
