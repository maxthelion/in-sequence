---
verdict: accepted
selected_prototype: 01-mixer-send-knobs.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/01-mixer-send-knobs.html
  - prototypes/02-send-bus-insert-chain.html
  - prototypes/03-signal-flow-overview.html
feedback_applied: []
---

# Send Effects UX Review — 2026-04-30

## Context

Three prototypes were produced for Send Effects (roadmap item 6). They are
complementary rather than competing: each covers a distinct slice of the
feature surface and they share the same adversarial fixture data set (Kick 909
at 75 % Send A, Snare Rim at 25 % Send A, Hi-Hat Closed at 50 % Send B, and
a muted Ağır Bass Synth with full sends). The prototypes are evaluated here both
on their own merits and for cohesion with the accepted Mixer Main Out (item 4,
Variant A) and Mixer Busses (item 5, Variant A) directions.

---

## Checklist Results

| Criterion | P01 Knobs | P02 Chain | P03 Flow |
|---|---|---|---|
| Single-file, no build steps | Pass | Pass | Pass |
| Monochrome base, semantic color only | Pass | Pass | Pass |
| Stub regions clearly marked | Pass | Pass | Pass |
| Real interactions on primary path | Pass | Pass | Pass |
| Fixture data is adversarial / varied | Pass | Pass | Pass |
| Same fixture data across comparable surfaces | Pass | Pass | Pass |
| Interaction budget stated and verified | Pass | Pass | Pass |
| Reviewer cannot mistake for production | Pass | Pass | Pass |
| Send A / B knobs clearly independent per track | Pass | N/A | Pass |
| Non-zero send visually distinguished from zero | Pass | N/A | Pass |
| Send bus column in mixer surface contextually correct | Partial | Pass | Pass |
| Insert chain: add / bypass / remove all operable | N/A | Pass | N/A |
| Empty-chain state present | N/A | Pass | N/A |
| Auto-return label communicates Story 3 without a control | N/A | Pass | Pass |
| Architecture decision (return path) surfaced explicitly | N/A | N/A | Pass |
| Muted-track send behavior surfaced as open question | Pass | N/A | Pass |

All three prototypes pass all criteria applicable to their scope. The single
partial is noted in the per-prototype assessment below.

---

## Per-Prototype Assessment

### Prototype 01 — Per-Track Send Knobs in Mixer

**Scope:** Stories 1 and 4. How send-amount controls sit in the mixer channel
strip and how independent per-track values are communicated.

**What works:**

- The A / B knob pair grouped under a "SENDS" section label with a horizontal
  rule separator from the fader area is immediately legible. The grouping
  correctly maps to the user mental model: "the fader controls my dry level;
  the sends control how much goes to the shared effect."
- Non-zero send values are shown in blue (`#2255cc`) while zero values are grey.
  This color convention is consistent with the accent color used throughout the
  mixer prototype and carries the right semantic: "this send is active." The
  distinction is especially important when scanning many strips — a user can
  see at a glance which tracks are contributing to each send bus.
- The click-to-popover slider mechanism meets the 2-interaction budget (click
  knob, drag slider). The popover label confirms which track and which bus are
  being edited, preventing accidental cross-track edits.
- The status-bar confirmation message on slider change ("Send A on 'kick': 75%
  — changes are per-track and do not affect other tracks") directly communicates
  Story 4's independence guarantee without requiring documentation.
- Adversarial fixtures are well-chosen: the long Unicode name "Ağır Bass Synth
  (Pad)" tests the truncation path, the muted strip with full sends tests the
  mute–send interaction question, and having four tracks with varied send states
  (75/0, 25/0, 0/50, 100/100) prevents the reviewer from assuming the feature
  only works at symmetric values.
- The send bus columns at the far right of the mixer strips row — separated by a
  dashed border — correctly signal that Send A and Send B are persistent columns
  that live alongside the track strips on the mixer surface, not a separate screen.
  This placement is directly compatible with the three-zone layout accepted for
  Mixer Busses (tracks | busses | master), where Send A and Send B would sit
  between the user busses and the master column.

**What fails or is limited:**

- The send bus columns (Send A, Send B) in P01 are stubs with a hatched fill
  labeled "[stub]." The fader on the send strip is labeled "Return" but it is
  not connected to anything. This is acceptable as a stub treatment, but the
  checklist notes a partial: it is not fully clear from P01 alone whether the
  send columns occupy the same horizontal scroll area as track strips or are
  fixed like the master column. P02 clarifies this (bus selector sidebar),
  but P01's mixer strip layout should confirm the column placement in the spec.
- The rotary knob control depends on click-to-popover interaction. This is
  efficient on desktop but not well-suited for iPad touch-drag, which the
  existing-state notes is a concern. The prototype itself raises the question
  whether a mini horizontal fader would be more touch-friendly. This is an
  open question for spec but does not block the UX direction.
- The zero-value knob and the non-zero knob share the same shape and size. The
  color difference in the value label is the only distinguishing signal. On a
  strip showing a value of 0%, the knob is not visually inert — it looks as
  interactive as an active knob. The prototype annotation raises this question
  correctly. The spec should confirm: zero-value knobs grey out the pointer and
  border, or remain visually identical to active knobs (current behavior).

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Route a track to Send A or B | Covered: A and B knobs per strip, click to adjust |
| 4. Per-track independent send levels | Covered: knob values differ across all four strips; status-bar message confirms independence |
| 3. (partial) Send bus return implied by return fader stub | Partial: fader labeled "Return" but not interactive |
| 2, 5 | Out of scope for this prototype — see P02 and notes |

---

### Prototype 02 — Send Bus Insert Chain Editor

**Scope:** Story 2. How users add, reorder, bypass, and remove insert effects
on Send A and Send B.

**What works:**

- The sidebar navigation (tracks stub → Send A → Send B → master stub) positions
  send buses as first-class mixer sections, not a hidden sub-menu. This is the
  correct information architecture: the user selects a bus by name and its insert
  chain fills the main editing pane. This is consistent with how the existing
  `ScenesWorkspaceView` approaches the master bus insert chain — the pattern is
  already established in the project.
- Send A starts populated (Reverb + Delay, Delay bypassed) and Send B starts
  empty. This gives the reviewer both the "fully operational" and "empty state"
  paths in one file. The empty state message — "No effects. Add one below — all
  tracks routed here will be processed." — correctly communicates the shared-bus
  semantics of sends: any effect added here processes all tracks that route to
  this bus.
- The bypass toggle changes button text to "Bypassed" (yellow) and strikes
  through the insert name while reducing opacity. The visual language is
  consistent with the master bus bypass convention from Mixer Main Out. No new
  pattern is introduced.
- Drag handle (≡) is present but non-functional, which is the correct Balsamiq
  treatment — the affordance is tested before the mechanism is built. The
  reorder interaction can be specified based on the affordance.
- The "→ Master output (auto)" label beside the chain title communicates Story 3
  without requiring a separate control. The user sees that the return is always
  active and always goes to master. No routing toggle is needed, which is correct
  per the user stories assumption.
- The effect picker appears inline below the "+ Add Effect" button. It is closed
  by "Cancel." The 3-interaction budget is met: select bus → click "+ Add Effect"
  → click effect name.
- Send A and Send B badges use blue (`#2255cc`) to distinguish them from the
  greyscale stub items in the sidebar. This is consistent with the send-color
  convention used in P01 (non-zero knob values) and P03 (send tap nodes, return
  arrows).

**What fails or is limited:**

- The sidebar conflates bus selection (for insert chain editing) with the mixer
  channel strip controls (fader, pan, mute, send amounts). In P01 the send knobs
  live on the track strip in the mixer. In P02 the send bus is selected via a
  sidebar. These are two different interaction surfaces for two different tasks,
  which is architecturally correct — but the spec must be explicit that the
  sidebar in P02 is the "bus effect editor" mode, not the mixer level view. The
  Mixer Busses Variant A uses the same sidebar-plus-detail-panel pattern for bus
  insert chains, so this is consistent.
- There is no way to reorder inserts other than via the drag handle, which is not
  implemented. The spec must decide whether arrow-button reorder (as in the
  master bus in Mixer Main Out Variant A) is the implementation, or drag-only.
  Given the existing reorder arrows in the master bus pattern, arrow buttons on
  each insert are the lower-risk path.
- Selecting "[AU Plugin…]" in the effect picker calls `addEffect('[AU Plugin…]')`
  with the same signature as a native effect. There is no AU picker or browser
  shown. This is a correct stub treatment, but the spec must explicitly say "AU
  plugin picker is out of scope for this story or deferred to a separate
  mechanism."
- The "return to master" label is in the chain title area. It says "→ Master
  output (auto)." At this size and position it is easily overlooked. The spec
  should confirm the placement and whether it should be a small indicator, a
  badge, or a labeled indicator similar to the "→ Master" output selector on bus
  strips in Mixer Busses.

**User story coverage:**

| Story | Coverage |
|---|---|
| 2. Add insert effects to a send bus | Covered: add, bypass, remove all operable; drag reorder afforded |
| 3. Hear send bus output in the mix | Covered (informational): "→ Master output (auto)" label |
| 1, 4, 5 | Out of scope for this prototype |

---

### Prototype 03 — Signal Flow Overview

**Scope:** Stories 3 and 4, informational. Signal flow diagram showing the
fan-out tap, send bus boxes, return path, and the open architecture decision
(return to `finalOutputMixer` vs `preMasterMixer`).

**What works:**

- The flow diagram maps directly to the existing-state audio graph topology and
  makes the fan-out concept legible without requiring the user to read
  `existing-state.md`. Track → fan-out (dry to preMasterMixer AND parallel tap
  to Send A/B gain node) → send bus → return → finalOutputMixer is rendered in
  five clear rows.
- The per-track, per-bus send amounts are shown as small clickable nodes ("A:
  75%", "B: 50%") that open an inline level slider. This confirms Story 4:
  independent values per track per bus are visible in one scan.
- Zero-value send taps are rendered as stub boxes (greyed hatching), making the
  inactive paths visually inert. Active taps use the blue send-color, maintaining
  the accent convention.
- The architecture annotation bubble ("Architecture decision needed: send return
  connects to `finalOutputMixer` or `preMasterMixer`") is the correct way to
  surface an unresolved design choice. It does not pretend to resolve the
  question — it flags it as a spec decision with a reference to existing-state
  §3. This prevents the architecture stage from inheriting an assumed answer.
- The muted track is shown as greyed out through all rows of the diagram, and
  the prototype notes raises the open question: does a muted track still send to
  the send buses? This is the correct handling — a muted track with non-zero
  send amounts is the most common confusing edge case in DAW mixing, and it is
  the exact adversarial fixture data used across all three prototypes.
- The legend (track node, send node, master node) and "Key rules" panel make
  this useful as a planning artifact independently of whether it becomes a real
  UI screen.

**What fails or is limited:**

- The signal flow overview is presented as "Mixer — Signal Flow View," implying
  it might be a real screen in the app. The prototype notes correctly question
  whether it belongs as an app screen or is only a planning artifact. The spec
  must resolve this: no other mixer feature (Mixer Main Out, Mixer Busses) has a
  dedicated signal flow screen. This view may be useful for architecture
  documentation but should not be shipped as a UI without a clear user need.
  The per-track send knobs in P01 already surface all per-track information;
  this diagram adds more information than most users need during performance or
  mixing.
- The "↓ & →" notation on track arrows is not conventional. It is explained in
  the notes ("shorthand for the fan-out") but could be misread. A T-junction
  graphic would be clearer. For architecture documentation purposes this is fine;
  for a production screen it would need redesign.
- The return arrows ("↓ auto-return →") lead from the send bus boxes to a
  "return" annotation that points up toward the final output row. The upward
  arrow ("↗ return") in the output row is visually confusing — signal flows
  downward throughout the diagram, then the return path is shown as going upward.
  The layout forces a reversal that is harder to read than a clean left-to-right
  or top-to-bottom return path. This is acceptable as a planning artifact but
  would need redesign if shipped as a screen.

**User story coverage:**

| Story | Coverage |
|---|---|
| 3. Hear send bus output in the mix | Covered: auto-return path shown, no user routing needed |
| 4. Per-track independent send levels | Covered: each track's send-tap node shows its independent value |
| 1, 2, 5 | Out of scope for this prototype |

---

## Cross-Feature Cohesion

### With Mixer Main Out (Item 4, Variant A)

The accepted direction for Mixer Main Out places the master output as a fixed
right-side column with a 2 px border separator. Send Effects P01 places the
send bus columns at the far right of the horizontal mixer strips row, also with
a border separator. The cohesion question is where the send bus columns sit
relative to the track strips, user bus strips (item 5), and the master column.

P01's positioning of send columns as part of the horizontal scrollable area
(dashed border separator, rightmost) is consistent with the three-zone layout
accepted for Mixer Busses (tracks | busses | master). The send buses would
naturally sit inside the "busses" zone or as a fixed sub-section between user
busses and master. The spec must resolve placement, but the prototype does not
conflict with the accepted Mixer Main Out surface.

The insert bypass visual language in P02 (yellow "Bypassed" button, strikethrough
name, opacity reduction) matches the master bus bypass convention in Mixer Main
Out Variant A (filled circle = enabled, hollow circle = bypassed). The spec
should normalize the exact toggle pattern so send bus inserts and master bus
inserts use identical controls. P02 uses a text button while Mixer Main Out
uses a symbol toggle; one pattern must be chosen.

### With Mixer Busses (Item 5, Variant A)

P02's sidebar navigation places Send A and Send B as named items between
"tracks stub" and "master stub." In Mixer Busses, user-added buses are listed
in the bus section of the mixer. The question of whether the insert chain editor
in P02 is the same UI component as the bus insert chain editor in Mixer Busses
is a key extraction question raised in existing-state §2, Story 2: "Cannot
reuse the master chain editor without extraction — same concern as noted for
mixer busses."

The spec for Send Effects should depend on the Mixer Busses spec resolving the
generic insert chain component question. If Mixer Busses extracts a generic
`InsertChainView`, Send Effects should reuse it. If that extraction is deferred,
Send Effects must decide whether to implement its own chain editor (duplication
risk) or wait.

Mixer Busses open question Q4 (global vs. scene-scoped bus inserts) applies
equally to send bus inserts. P02 treats send bus inserts as global (non-scene-
scoped). The spec for both features should use the same answer: if user bus
inserts are global, send bus inserts are also global. If user bus inserts are
scene-scoped, send bus inserts should follow the same model. This cohesion must
be confirmed before either spec is written.

The muted-track-sends question (raised in P01 and P03) also has a parallel in
Mixer Busses: does a muted track route signal to its assigned user bus? The
answer should be consistent across both features. Existing DAW convention is
that mute silences the dry signal and the send tap (so a muted track contributes
nothing to any bus). This should be the default, but it must be confirmed.

---

## Open Questions Surfaced by Prototypes

1. **Send bus placement in the mixer layout.** Where do Send A and Send B
   columns sit relative to track strips, user bus strips (item 5), and the
   master column? Options: (a) fixed columns after user buses, before master;
   (b) part of the user bus section with a type badge; (c) always-visible fixed
   columns at the far right (before master). This is a layout decision for spec.

2. **Muted track and send taps.** Does a muted track contribute signal to Send A
   and Send B? P01 and P03 both surface this as a question without answering it.
   Standard DAW behavior is: mute cuts the send tap as well (mute is applied
   before the fan-out). This must be confirmed before spec.

3. **Return path: `finalOutputMixer` vs `preMasterMixer`.** P03 explicitly
   annotates this as an unresolved architecture decision. Connecting the return
   to `finalOutputMixer` (bypasses master insert chain) vs `preMasterMixer`
   (wet signal passes through master inserts). This is a spec decision with
   product implications: typical DAW behavior is return to post-master (i.e.,
   `finalOutputMixer`), but connecting to `preMasterMixer` is simpler to
   implement. Existing-state §3 details the tradeoffs.

4. **Knob vs. mini fader for send amount control.** P01 uses a rotary knob with
   click-to-popover slider. The prototype notes raise the touch-friendliness
   concern for iPad. The spec should confirm the control type.

5. **Zero-value knob visual treatment.** Should a send knob at 0% look visually
   inert (greyed border, pointer) or identical to an active knob (current P01)?

6. **Send bus insert scope (global vs. scene-scoped).** P02 treats send bus
   inserts as global. Must align with Mixer Busses Q4 decision. If scene-scoped,
   the `SendBusState` model becomes substantially more complex.

7. **Insert reorder mechanism.** Arrow buttons (as in Mixer Main Out) or drag
   handles (as shown in P02)? The existing project convention uses arrow buttons
   in `ScenesWorkspaceView`. P02 provides drag handles but does not implement
   drag. Spec must pick one or both.

8. **Insert bypass toggle style.** P02 uses a text button ("Bypass" / "Bypassed"
   in yellow). Mixer Main Out uses a filled/hollow circle symbol. One pattern
   should be used across all insert chains in the mixer surface.

9. **Signal flow overview as app screen.** P03 raises this question. The spec
   should explicitly decide: this diagram is a planning artifact only, or it
   ships as a "Signal Flow" view in the app. No other mixer feature has a
   dedicated topology view; the default should be "planning artifact only."

10. **Insert component extraction dependency.** If Mixer Busses does not extract
    a generic insert chain component before Send Effects is implemented, Send
    Effects must either wait or build its own chain editor. The implementation
    handoff should capture this sequencing dependency explicitly.

---

## Recommendation

**Accept the three-prototype direction for architecture and spec.** No rework is
needed. The prototypes collectively cover all five user stories, use consistent
adversarial fixture data, apply the established mixer visual language, and
correctly surface the unresolved questions as questions rather than assumptions.

**Selected primary prototype: `01-mixer-send-knobs.html`** as the canoncial
statement of how per-track send controls sit in the mixer surface. P02 and P03
are supporting artifacts for Story 2 (insert chain editor) and Story 3
(return path communication), respectively.

**Elements to carry into architecture:**

- Per-track send section in the mixer channel strip: A and B knob/control pair,
  separated from the fader by a horizontal rule, with "SENDS" section label.
- Non-zero send amount distinguished visually from zero (accent color on value
  display; spec to confirm whether the knob/control itself should also differ).
- Send A and Send B are always-present columns on the mixer surface; no user
  creation or naming is needed.
- Insert chain editor for each send bus: sidebar navigation to select the bus,
  detail panel showing the ordered insert list with add / bypass / remove / reorder.
- "→ Master output (auto)" label communicating automatic return — no user routing
  control needed for the return path.
- Empty insert chain state: descriptive message ("Add an effect — all routed
  tracks will be processed").
- Send bus insert scope must match the Mixer Busses Q4 decision (global or
  scene-scoped) — do not decide independently.
- Return path (`finalOutputMixer` or `preMasterMixer`) is the key architecture
  decision; existing-state §3 has the technical tradeoffs.

**Questions 2, 3, and 6 must be resolved before or during architecture.** All
three affect model and engine scope: muted-track behavior affects the send-tap
wiring point, return path affects where the send bus host connects, and insert
scope affects whether `SendBusState` needs a scene list. Questions 1, 4, 5, 7,
8, 9, and 10 can be resolved during architecture or early spec.

---

## Next Action

Advance to `write-architecture`. The accepted direction is the three-prototype
composite. Architecture should begin by reading existing-state §§3–5, routing
and track-destinations wiki pages, and the decisions reached for Mixer Main Out
and Mixer Busses architecture passes (when available). Open questions 2, 3, and
6 are the highest-priority architecture inputs.
